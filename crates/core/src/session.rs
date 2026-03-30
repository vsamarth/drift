use std::cmp::min;
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};
use iroh::{Endpoint, RelayMode};
use tokio::fs::{self, File};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::time::{Duration, Instant};

use crate::fs_plan::prepare::PreparedFile;
use crate::fs_plan::receive::{
    ExpectedFile, ensure_destination_available, resolve_transfer_destination,
};
use crate::util::{describe_remote, human_size};
use crate::wire::{
    ALPN, FileOpen, TRANSFER_CHUNK_SIZE, blake3_from_hex, blake3_to_hex,
    chunk_count_for_transfer_size, read_file_open, write_file_open,
};

const ACK_OK: &[u8] = b"ok";

const STREAM_CTRL_ACK: u8 = 0;
const STREAM_CTRL_NACK: u8 = 1;

const MAX_CHUNK_RETRIES: u32 = 5;

/// Payload progress: emit at most ~5× per second or every 256 KiB to avoid flooding UI.
const PROGRESS_EMIT_INTERVAL: Duration = Duration::from_millis(200);
const PROGRESS_EMIT_MIN_BYTES: u64 = 256 * 1024;

pub async fn bind_endpoint() -> Result<Endpoint> {
    Endpoint::builder()
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .bind()
        .await
        .context("binding iroh endpoint")
}

pub async fn connect_to_ticket(
    endpoint: &Endpoint,
    ticket: iroh::EndpointAddr,
) -> Result<iroh::endpoint::Connection> {
    let connection = endpoint
        .connect(ticket, ALPN)
        .await
        .context("connecting to peer")?;

    println!(
        "Connected to {}",
        describe_remote(
            connection.remote_id(),
            endpoint.remote_info(connection.remote_id()).await.as_ref()
        )
    );

    Ok(connection)
}

pub async fn send_files_over_connection<F>(
    connection: iroh::endpoint::Connection,
    files: &[PreparedFile],
    mut on_progress: F,
) -> Result<()>
where
    F: FnMut(u64),
{
    let mut cumulative = 0_u64;
    let mut last_emit = Instant::now();
    let mut bytes_since_emit = 0_u64;

    for prepared in files {
        let (mut send_stream, mut recv_stream) = connection.open_bi().await.with_context(|| {
            format!(
                "opening transfer stream for {}",
                prepared.source_path.display()
            )
        })?;

        let chunk_count = chunk_count_for_transfer_size(prepared.size)?;
        let open = FileOpen {
            path: prepared.transfer_path.clone(),
            size: prepared.size,
            chunk_size: TRANSFER_CHUNK_SIZE,
            chunk_count,
            file_blake3: blake3_to_hex(&prepared.file_blake3),
        };
        write_file_open(&mut send_stream, &open).await?;

        send_file_chunked(
            &mut send_stream,
            &mut recv_stream,
            &prepared.source_path,
            prepared.size,
            chunk_count,
            &mut cumulative,
            &mut last_emit,
            &mut bytes_since_emit,
            &mut on_progress,
        )
        .await?;

        send_stream.finish()?;

        let ack = recv_stream.read_to_end(64).await.with_context(|| {
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

pub async fn receive_files_over_connection(
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
                let open = read_file_open(&mut recv_stream).await?;
                if open.chunk_size != TRANSFER_CHUNK_SIZE {
                    bail!(
                        "sender used unsupported chunk_size {} (expected {})",
                        open.chunk_size,
                        TRANSFER_CHUNK_SIZE
                    );
                }
                let expected_count = chunk_count_for_transfer_size(open.size)?;
                if open.chunk_count != expected_count {
                    bail!(
                        "chunk_count {} does not match size {} (expected {})",
                        open.chunk_count,
                        open.size,
                        expected_count
                    );
                }
                let file_digest = blake3_from_hex(&open.file_blake3)
                    .context("parsing file_blake3 from sender")?;

                let target_path = if let Some(expected_files) = expected_files.as_mut() {
                    let expected = expected_files
                        .remove(&open.path)
                        .ok_or_else(|| anyhow!("sender sent unexpected path {}", open.path))?;
                    if open.size != expected.size {
                        bail!(
                            "sender reported size {} for {}, expected {}",
                            open.size,
                            open.path,
                            expected.size
                        );
                    }
                    expected.destination
                } else {
                    if !seen_paths.insert(open.path.clone()) {
                        bail!("sender sent duplicate path {}", open.path);
                    }
                    let target_path = resolve_transfer_destination(&out_dir, &open.path)?;
                    ensure_destination_available(&out_dir, &target_path).await?;
                    target_path
                };

                if let Some(parent) = target_path.parent() {
                    fs::create_dir_all(parent)
                        .await
                        .with_context(|| format!("creating directory {}", parent.display()))?;
                }

                receive_file_chunked(
                    &mut recv_stream,
                    &mut send_stream,
                    &target_path,
                    &open,
                    &file_digest,
                )
                .await?;

                send_stream
                    .write_all(ACK_OK)
                    .await
                    .with_context(|| format!("sending ack for {}", target_path.display()))?;
                send_stream.finish()?;

                println!(
                    "Received {} ({})",
                    target_path.display(),
                    human_size(open.size)
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

async fn read_stream_ctrl<R: AsyncRead + Unpin>(recv_stream: &mut R) -> Result<(u8, u32)> {
    let tag = recv_stream
        .read_u8()
        .await
        .context("reading stream control tag")?;
    let index = recv_stream
        .read_u32()
        .await
        .context("reading stream control chunk index")?;
    Ok((tag, index))
}

async fn write_stream_ctrl<W: AsyncWrite + Unpin>(
    send_stream: &mut W,
    tag: u8,
    chunk_index: u32,
) -> Result<()> {
    send_stream
        .write_u8(tag)
        .await
        .context("writing stream control tag")?;
    send_stream
        .write_u32(chunk_index)
        .await
        .context("writing stream control chunk index")?;
    send_stream
        .flush()
        .await
        .context("flushing stream control")?;
    Ok(())
}

async fn write_chunk_frame<W: AsyncWrite + Unpin>(
    send_stream: &mut W,
    chunk_index: u32,
    payload: &[u8],
) -> Result<()> {
    if payload.len() > TRANSFER_CHUNK_SIZE as usize {
        bail!("chunk payload exceeds TRANSFER_CHUNK_SIZE");
    }
    let hash = *blake3::hash(payload).as_bytes();
    send_stream
        .write_u32(chunk_index)
        .await
        .context("writing chunk index")?;
    send_stream
        .write_u32(payload.len() as u32)
        .await
        .context("writing chunk length")?;
    send_stream
        .write_all(payload)
        .await
        .context("writing chunk payload")?;
    send_stream
        .write_all(&hash)
        .await
        .context("writing chunk blake3")?;
    send_stream.flush().await.context("flushing chunk frame")?;
    Ok(())
}

async fn read_chunk_frame<R: AsyncRead + Unpin>(
    recv_stream: &mut R,
) -> Result<(u32, Vec<u8>, [u8; 32])> {
    let chunk_index = recv_stream
        .read_u32()
        .await
        .context("reading chunk index")?;
    let len = recv_stream
        .read_u32()
        .await
        .context("reading chunk payload length")? as usize;
    if len > TRANSFER_CHUNK_SIZE as usize {
        bail!(
            "chunk payload length {} exceeds maximum {}",
            len,
            TRANSFER_CHUNK_SIZE
        );
    }
    let mut payload = vec![0_u8; len];
    recv_stream
        .read_exact(&mut payload)
        .await
        .context("reading chunk payload")?;
    let mut hash = [0_u8; 32];
    recv_stream
        .read_exact(&mut hash)
        .await
        .context("reading chunk blake3")?;
    Ok((chunk_index, payload, hash))
}

async fn send_file_chunked<W, R, F>(
    chunk_out: &mut W,
    ctrl_in: &mut R,
    path: &Path,
    size: u64,
    chunk_count: u32,
    cumulative: &mut u64,
    last_emit: &mut Instant,
    bytes_since_emit: &mut u64,
    on_progress: &mut F,
) -> Result<()>
where
    W: AsyncWrite + Unpin,
    R: AsyncRead + Unpin,
    F: FnMut(u64),
{
    let mut file = File::open(path)
        .await
        .with_context(|| format!("opening {}", path.display()))?;

    let mut offset = 0_u64;
    for chunk_index in 0..chunk_count {
        let remaining = size.saturating_sub(offset);
        let this_len = min(TRANSFER_CHUNK_SIZE as u64, remaining) as usize;
        let mut payload = vec![0_u8; this_len];
        if this_len > 0 {
            file.read_exact(&mut payload)
                .await
                .with_context(|| format!("reading {}", path.display()))?;
        }

        let mut retries = 0_u32;
        loop {
            write_chunk_frame(chunk_out, chunk_index, &payload)
                .await
                .with_context(|| format!("sending chunk {chunk_index} of {}", path.display()))?;

            match read_stream_ctrl(ctrl_in).await.with_context(|| {
                format!(
                    "waiting for chunk {chunk_index} control message for {}",
                    path.display()
                )
            })? {
                (STREAM_CTRL_ACK, i) if i == chunk_index => break,
                (STREAM_CTRL_NACK, i) if i == chunk_index => {
                    retries += 1;
                    if retries > MAX_CHUNK_RETRIES {
                        bail!(
                            "exceeded chunk retry limit for {} chunk {}",
                            path.display(),
                            chunk_index
                        );
                    }
                    continue;
                }
                (tag, i) => {
                    bail!(
                        "unexpected stream control for {}: tag={tag} chunk_index={i} (expected ack for chunk {chunk_index})",
                        path.display()
                    );
                }
            }
        }

        offset += this_len as u64;
        *cumulative += this_len as u64;
        *bytes_since_emit += this_len as u64;
        if last_emit.elapsed() >= PROGRESS_EMIT_INTERVAL
            || *bytes_since_emit >= PROGRESS_EMIT_MIN_BYTES
        {
            on_progress(*cumulative);
            *last_emit = Instant::now();
            *bytes_since_emit = 0;
        }
    }

    on_progress(*cumulative);
    *last_emit = Instant::now();
    *bytes_since_emit = 0;
    Ok(())
}

async fn receive_file_chunked<R, W>(
    chunk_in: &mut R,
    ctrl_out: &mut W,
    destination: &Path,
    open: &FileOpen,
    expected_digest: &[u8; 32],
) -> Result<()>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut file = File::create(destination)
        .await
        .with_context(|| format!("creating {}", destination.display()))?;
    let mut hasher = blake3::Hasher::new();
    let mut next_index: u32 = 0;

    while next_index < open.chunk_count {
        let (chunk_index, payload, claimed_hash) = read_chunk_frame(chunk_in)
            .await
            .with_context(|| format!("reading chunk {next_index} for {}", destination.display()))?;

        if chunk_index != next_index {
            bail!(
                "unexpected chunk index {} for {} (expected {})",
                chunk_index,
                destination.display(),
                next_index
            );
        }

        let actual = *blake3::hash(&payload).as_bytes();
        if actual != claimed_hash {
            write_stream_ctrl(ctrl_out, STREAM_CTRL_NACK, chunk_index)
                .await
                .with_context(|| format!("sending NACK for chunk {chunk_index}"))?;
            continue;
        }

        file.write_all(&payload)
            .await
            .with_context(|| format!("writing {}", destination.display()))?;
        hasher.update(&payload);

        write_stream_ctrl(ctrl_out, STREAM_CTRL_ACK, chunk_index)
            .await
            .with_context(|| format!("sending ACK for chunk {chunk_index}"))?;

        next_index += 1;
    }

    if hasher.finalize().as_bytes() != expected_digest {
        bail!(
            "BLAKE3 mismatch for {} after receiving all chunks",
            destination.display()
        );
    }

    file.flush()
        .await
        .with_context(|| format!("flushing {}", destination.display()))?;
    Ok(())
}

#[cfg(test)]
mod transfer_tests {
    use super::*;
    use crate::wire::{
        FileOpen, TRANSFER_CHUNK_SIZE, blake3_from_hex, blake3_to_hex,
        chunk_count_for_transfer_size, read_json_frame, write_json_frame,
    };
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

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

    async fn assert_transfer_roundtrip(payload: Vec<u8>) -> Result<()> {
        let temp = TestDir::new("drift-xfer").await?;
        let src = temp.path.join("in.bin");
        let dst = temp.path.join("out.bin");
        fs::write(&src, &payload).await?;

        let digest = *blake3::hash(&payload).as_bytes();
        let size = payload.len() as u64;
        let chunk_count = chunk_count_for_transfer_size(size)?;
        let transfer_path = "xfer/doc.dat".to_owned();
        let open = FileOpen {
            path: transfer_path.clone(),
            size,
            chunk_size: TRANSFER_CHUNK_SIZE,
            chunk_count,
            file_blake3: blake3_to_hex(&digest),
        };

        let (mut chunk_tx, mut chunk_rx) = tokio::io::duplex(32 * 1024 * 1024);
        let (mut ctrl_tx, mut ctrl_rx) = tokio::io::duplex(64 * 1024);

        let src_clone = src.clone();
        let open_clone = open.clone();
        let mut cumulative = 0_u64;
        let mut last_emit = Instant::now();
        let mut bytes_since_emit = 0_u64;

        let send_task = tokio::spawn(async move {
            write_json_frame(&mut chunk_tx, &open_clone)
                .await
                .context("writing FileOpen")?;
            send_file_chunked(
                &mut chunk_tx,
                &mut ctrl_rx,
                &src_clone,
                size,
                chunk_count,
                &mut cumulative,
                &mut last_emit,
                &mut bytes_since_emit,
                &mut |_| {},
            )
            .await
            .context("send_file_chunked")?;
            let mut ok = [0_u8; ACK_OK.len()];
            ctrl_rx
                .read_exact(&mut ok)
                .await
                .context("reading final ACK_OK")?;
            if ok.as_slice() != ACK_OK {
                bail!("expected ACK_OK, got {:?}", ok);
            }
            Ok::<(), anyhow::Error>(())
        });

        let dst_clone = dst.clone();
        let recv_task = tokio::spawn(async move {
            let open_r: FileOpen = read_json_frame(&mut chunk_rx)
                .await
                .context("reading FileOpen")?;
            assert_eq!(open_r, open);
            let file_digest = blake3_from_hex(&open_r.file_blake3)?;
            receive_file_chunked(
                &mut chunk_rx,
                &mut ctrl_tx,
                &dst_clone,
                &open_r,
                &file_digest,
            )
            .await
            .context("receive_file_chunked")?;
            ctrl_tx.write_all(ACK_OK).await.context("writing ACK_OK")?;
            ctrl_tx.flush().await.context("flush ACK_OK")?;
            Ok::<(), anyhow::Error>(())
        });

        send_task.await??;
        recv_task.await??;

        let got = fs::read(&dst).await?;
        if got != payload {
            bail!("output mismatch: len {} vs {}", got.len(), payload.len());
        }
        Ok(())
    }

    #[tokio::test]
    async fn duplex_transfers_small_file() -> Result<()> {
        assert_transfer_roundtrip(b"hello chunked transfer".to_vec()).await
    }

    #[tokio::test]
    async fn duplex_transfers_empty_file() -> Result<()> {
        assert_transfer_roundtrip(Vec::new()).await
    }

    #[tokio::test]
    async fn duplex_transfers_multi_chunk() -> Result<()> {
        let len = TRANSFER_CHUNK_SIZE as usize + 1024;
        let payload: Vec<u8> = (0_u8..=255).cycle().take(len).collect();
        assert_transfer_roundtrip(payload).await
    }
}
