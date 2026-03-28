use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};
use iroh::{Endpoint, RelayMode};
use tokio::fs::{self, File};
use tokio::io::AsyncWriteExt;

use crate::fs_plan::{
    ExpectedFile, PreparedFile, ensure_destination_available, resolve_transfer_destination,
};
use crate::util::{describe_remote, human_size};
use crate::wire::{ALPN, FileHeader, read_header, write_header};

const ACK_OK: &[u8] = b"ok";

pub(crate) async fn bind_endpoint() -> Result<Endpoint> {
    Endpoint::builder()
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .bind()
        .await
        .context("binding iroh endpoint")
}

pub(crate) async fn receive_from_ticket(
    ticket: iroh::EndpointAddr,
    out_dir: PathBuf,
    expected_files: Option<BTreeMap<String, ExpectedFile>>,
) -> Result<()> {
    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let connection = endpoint
        .connect(ticket, ALPN)
        .await
        .context("connecting to sender")?;

    println!(
        "Connected to {}",
        describe_remote(
            connection.remote_id(),
            endpoint.remote_info(connection.remote_id()).await.as_ref()
        )
    );
    receive_files_over_connection(connection, out_dir, expected_files).await?;
    endpoint.close().await;
    Ok(())
}

pub(crate) async fn receive_on_endpoint(
    endpoint: Endpoint,
    out_dir: PathBuf,
    expected_files: Option<BTreeMap<String, ExpectedFile>>,
) -> Result<()> {
    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let incoming = endpoint
        .accept()
        .await
        .context("receiver stopped before a sender connected")?;
    let connection = incoming.await.context("accepting sender connection")?;
    println!(
        "Connected to {}",
        describe_remote(
            connection.remote_id(),
            endpoint.remote_info(connection.remote_id()).await.as_ref()
        )
    );
    receive_files_over_connection(connection, out_dir, expected_files).await
}

pub(crate) async fn send_files_over_connection(
    connection: iroh::endpoint::Connection,
    files: &[PreparedFile],
) -> Result<()> {
    for prepared in files {
        let (mut send_stream, mut recv_stream) = connection
            .open_bi()
            .await
            .with_context(|| {
                format!(
                    "opening transfer stream for {}",
                    prepared.source_path.display()
                )
            })?;

        let header = FileHeader {
            path: prepared.transfer_path.clone(),
            size: prepared.size,
        };
        write_header(&mut send_stream, &header).await?;
        send_file(&mut send_stream, &prepared.source_path).await?;
        send_stream.finish()?;

        let ack = recv_stream
            .read_to_end(64)
            .await
            .with_context(|| {
                format!(
                    "waiting for receiver ack for {}",
                    prepared.source_path.display()
                )
            })?;
        if ack != ACK_OK {
            bail!(
                "receiver returned an unexpected response for {}",
                prepared.source_path.display()
            );
        }

        println!(
            "Sent {} ({})",
            prepared.source_path.display(),
            human_size(prepared.size)
        );
    }

    connection.close(0u32.into(), b"done");
    Ok(())
}

async fn receive_files_over_connection(
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    mut expected_files: Option<BTreeMap<String, ExpectedFile>>,
) -> Result<()> {
    let mut received_any = false;
    let mut seen_paths = HashSet::new();
    loop {
        match connection.accept_bi().await {
            Ok((mut send_stream, mut recv_stream)) => {
                received_any = true;
                let header = read_header(&mut recv_stream).await?;
                let target_path = if let Some(expected_files) = expected_files.as_mut() {
                    let expected = expected_files.remove(&header.path).ok_or_else(|| {
                        anyhow!("sender sent unexpected path {}", header.path)
                    })?;
                    if header.size != expected.size {
                        bail!(
                            "sender reported size {} for {}, expected {}",
                            header.size,
                            header.path,
                            expected.size
                        );
                    }
                    expected.destination
                } else {
                    if !seen_paths.insert(header.path.clone()) {
                        bail!("sender sent duplicate path {}", header.path);
                    }
                    let target_path = resolve_transfer_destination(&out_dir, &header.path)?;
                    ensure_destination_available(&out_dir, &target_path).await?;
                    target_path
                };

                if let Some(parent) = target_path.parent() {
                    fs::create_dir_all(parent)
                        .await
                        .with_context(|| format!("creating directory {}", parent.display()))?;
                }
                receive_file(&mut recv_stream, &target_path, header.size).await?;
                send_stream
                    .write_all(ACK_OK)
                    .await
                    .with_context(|| format!("sending ack for {}", target_path.display()))?;
                send_stream.finish()?;

                println!(
                    "Received {} ({})",
                    target_path.display(),
                    human_size(header.size)
                );
            }
            Err(err) => {
                if let Some(expected_files) = expected_files.as_ref() {
                    if !expected_files.is_empty() {
                        bail!(
                            "connection closed before all expected files arrived (missing {})",
                            expected_files.len()
                        );
                    }
                }
                if received_any {
                    println!("Transfer session finished");
                    return Ok(());
                }
                return Err(anyhow!(err)).context("connection closed before any file arrived");
            }
        }
    }
}

async fn send_file(send_stream: &mut iroh::endpoint::SendStream, path: &Path) -> Result<()> {
    let mut file = File::open(path)
        .await
        .with_context(|| format!("opening {}", path.display()))?;
    tokio::io::copy(&mut file, send_stream)
        .await
        .with_context(|| format!("streaming {}", path.display()))?;
    Ok(())
}

async fn receive_file(
    recv_stream: &mut iroh::endpoint::RecvStream,
    destination: &Path,
    expected_size: u64,
) -> Result<()> {
    let mut file = File::create(destination)
        .await
        .with_context(|| format!("creating {}", destination.display()))?;
    let copied = tokio::io::copy(recv_stream, &mut file)
        .await
        .with_context(|| format!("writing {}", destination.display()))?;
    if copied != expected_size {
        bail!(
            "size mismatch for {}: expected {} bytes, received {} bytes",
            destination.display(),
            expected_size,
            copied
        );
    }
    file.flush()
        .await
        .with_context(|| format!("flushing {}", destination.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use anyhow::Context;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{Duration, SystemTime, UNIX_EPOCH};
    use tokio::time::timeout;

    use super::*;
    use crate::transfer::send_ticket;
    use crate::wire::make_ticket;

    static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        async fn new(prefix: &str) -> Result<Self> {
            let unique = format!(
                "{}-{}-{}",
                prefix,
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .expect("system time")
                    .as_nanos(),
                NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed)
            );
            let path = std::env::temp_dir().join(unique);
            fs::create_dir_all(&path).await?;
            Ok(Self { path })
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }

    async fn write_test_file(path: &Path, contents: &str) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).await?;
        }
        fs::write(path, contents).await?;
        Ok(())
    }

    #[ignore = "requires binding local iroh sockets"]
    #[tokio::test]
    async fn send_and_receive_nested_directory_tree() -> Result<()> {
        let temp = TestDir::new("drift-e2e").await?;
        let source_dir = temp.path.join("photos");
        let out_dir = temp.path.join("downloads");
        write_test_file(&source_dir.join("trip/cat.jpg"), "cat").await?;
        write_test_file(&source_dir.join("trip/dog.jpg"), "dog").await?;

        let endpoint = bind_endpoint().await?;
        let ticket = make_ticket(&endpoint).await?;
        let receiver = tokio::spawn(receive_on_endpoint(endpoint, out_dir.clone(), None));

        send_ticket(ticket, vec![source_dir]).await?;
        let receiver_result = timeout(Duration::from_secs(30), receiver)
            .await
            .context("receiver timed out")?;
        receiver_result??;

        let cat = fs::read_to_string(out_dir.join("photos/trip/cat.jpg")).await?;
        let dog = fs::read_to_string(out_dir.join("photos/trip/dog.jpg")).await?;
        assert_eq!(cat, "cat");
        assert_eq!(dog, "dog");

        Ok(())
    }
}
