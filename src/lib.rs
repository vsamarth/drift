use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, RelayMode, TransportAddr, Watcher};
use serde::{Deserialize, Serialize};
use tokio::fs::{self, File};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::signal;
use tokio::time::{MissedTickBehavior, interval};

pub mod rendezvous;
pub mod server;

use rendezvous::{OfferFile, OfferManifest, OfferStatus, RendezvousClient};

pub const ALPN: &[u8] = b"drift/v0";
const ACK_OK: &[u8] = b"ok";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransferTicket {
    node_id: String,
    relay_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct FileHeader {
    name: String,
    size: u64,
}

#[derive(Debug, Clone)]
struct PreparedFile {
    path: PathBuf,
    header: FileHeader,
}

#[derive(Debug, Clone)]
struct ReceiveSetup {
    pub out_dir: PathBuf,
    pub ticket: String,
}

pub async fn send(files: Vec<PathBuf>, server_url: Option<String>) -> Result<()> {
    let prepared = prepare_files(files).await?;
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let ticket = make_ticket(&endpoint).await?;
    let client = RendezvousClient::new(rendezvous::resolve_server_url(server_url.as_deref()));
    let offer = client
        .create_offer(ticket, prepared.manifest.clone())
        .await?;

    println!("Offer ready");
    println!("Code: {}", offer.code);
    println!("Expires: {}", offer.expires_at);
    println!(
        "Files: {} ({})",
        prepared.manifest.file_count,
        human_size(prepared.manifest.total_size)
    );
    println!("Waiting for receiver to accept...");

    let mut accept_future = Box::pin(endpoint.accept());
    let mut poll = interval(Duration::from_secs(2));
    poll.set_missed_tick_behavior(MissedTickBehavior::Delay);
    poll.tick().await;
    let mut ctrl_c = Box::pin(signal::ctrl_c());
    let mut accepted = false;

    loop {
        tokio::select! {
            _ = &mut ctrl_c => {
                endpoint.close().await;
                bail!("transfer interrupted");
            }
            incoming = &mut accept_future => {
                let incoming = incoming.context("sender stopped before a receiver connected")?;
                let connection = incoming.await.context("accepting receiver connection")?;
                println!(
                    "Receiver connected from {}",
                    describe_remote(connection.remote_id(), endpoint.remote_info(connection.remote_id()).await.as_ref())
                );
                send_files_over_connection(connection, &prepared.files).await?;
                endpoint.close().await;
                return Ok(());
            }
            _ = poll.tick() => {
                match client.offer_status(&offer.code).await?.status {
                    OfferStatus::Pending => {}
                    OfferStatus::Accepted => {
                        if !accepted {
                            accepted = true;
                            println!("Offer accepted. Waiting for receiver connection...");
                        }
                    }
                    OfferStatus::Declined => {
                        endpoint.close().await;
                        bail!("receiver declined the offer");
                    }
                    OfferStatus::Expired => {
                        endpoint.close().await;
                        bail!("offer expired before the receiver accepted");
                    }
                }
            }
        }
    }
}

pub async fn receive(code: String, out_dir: PathBuf, server_url: Option<String>) -> Result<()> {
    rendezvous::validate_code(&code)?;

    let client = RendezvousClient::new(rendezvous::resolve_server_url(server_url.as_deref()));
    let preview = client.offer_preview(&code).await?;

    println!("Incoming offer");
    println!("Files: {}", preview.manifest.file_count);
    println!("Total size: {}", human_size(preview.manifest.total_size));
    println!("Expires: {}", preview.expires_at);
    for file in &preview.manifest.files {
        println!("  {} ({})", file.name, human_size(file.size));
    }

    if !confirm_accept()? {
        client.decline_offer(&code).await?;
        println!("Offer declined");
        return Ok(());
    }

    let accepted = client.accept_offer(&code).await?;
    println!("Accepted offer. Connecting to sender...");
    receive_from_ticket(accepted.ticket, out_dir).await
}

pub async fn receive_ticket(out_dir: PathBuf) -> Result<()> {
    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let endpoint = bind_endpoint().await?;
    let ticket = make_ticket(&endpoint).await?;
    let setup = ReceiveSetup { out_dir, ticket };

    println!("Receiver ready");
    println!("Save directory: {}", setup.out_dir.display());
    println!("Ticket:");
    println!("{}", setup.ticket);
    println!("Waiting for a sender...");

    receive_on_endpoint(endpoint, setup.out_dir).await
}

pub async fn send_ticket(ticket: String, files: Vec<PathBuf>) -> Result<()> {
    let prepared = prepare_files(files).await?;
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let addr = decode_ticket(&ticket)?;
    let connection = endpoint
        .connect(addr, ALPN)
        .await
        .context("connecting to receiver")?;

    send_files_over_connection(connection, &prepared.files).await
}

async fn prepare_files(paths: Vec<PathBuf>) -> Result<PreparedFiles> {
    if paths.is_empty() {
        bail!("provide at least one file to send");
    }

    let mut files = Vec::with_capacity(paths.len());
    let mut manifest_files = Vec::with_capacity(paths.len());
    let mut total_size = 0_u64;

    for path in paths {
        let metadata = fs::metadata(&path)
            .await
            .with_context(|| format!("reading metadata for {}", path.display()))?;
        if !metadata.is_file() {
            bail!("{} is not a regular file", path.display());
        }

        let file_name = path
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| anyhow!("{} does not have a valid UTF-8 file name", path.display()))?
            .to_owned();

        total_size = total_size
            .checked_add(metadata.len())
            .ok_or_else(|| anyhow!("total transfer size exceeds u64"))?;

        let header = FileHeader {
            name: file_name.clone(),
            size: metadata.len(),
        };

        manifest_files.push(OfferFile {
            name: file_name,
            size: metadata.len(),
        });
        files.push(PreparedFile { path, header });
    }

    Ok(PreparedFiles {
        files,
        manifest: OfferManifest {
            file_count: manifest_files.len() as u64,
            total_size,
            files: manifest_files,
        },
    })
}

async fn receive_from_ticket(ticket: String, out_dir: PathBuf) -> Result<()> {
    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let addr = decode_ticket(&ticket)?;
    let connection = endpoint
        .connect(addr, ALPN)
        .await
        .context("connecting to sender")?;

    println!(
        "Connected to {}",
        describe_remote(
            connection.remote_id(),
            endpoint.remote_info(connection.remote_id()).await.as_ref()
        )
    );
    receive_files_over_connection(connection, out_dir).await?;
    endpoint.close().await;
    Ok(())
}

async fn receive_on_endpoint(endpoint: Endpoint, out_dir: PathBuf) -> Result<()> {
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
    receive_files_over_connection(connection, out_dir).await
}

async fn send_files_over_connection(
    connection: iroh::endpoint::Connection,
    files: &[PreparedFile],
) -> Result<()> {
    for prepared in files {
        let (mut send_stream, mut recv_stream) = connection
            .open_bi()
            .await
            .with_context(|| format!("opening transfer stream for {}", prepared.path.display()))?;

        write_header(&mut send_stream, &prepared.header).await?;
        send_file(&mut send_stream, &prepared.path).await?;
        send_stream.finish()?;

        let ack = recv_stream
            .read_to_end(64)
            .await
            .with_context(|| format!("waiting for receiver ack for {}", prepared.path.display()))?;
        if ack != ACK_OK {
            bail!(
                "receiver returned an unexpected response for {}",
                prepared.path.display()
            );
        }

        println!(
            "Sent {} ({})",
            prepared.path.display(),
            human_size(prepared.header.size)
        );
    }

    connection.close(0u32.into(), b"done");
    Ok(())
}

async fn receive_files_over_connection(
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
) -> Result<()> {
    let mut received_any = false;
    loop {
        match connection.accept_bi().await {
            Ok((mut send_stream, mut recv_stream)) => {
                received_any = true;
                let header = read_header(&mut recv_stream).await?;
                let target_path = unique_destination(&out_dir, &header.name).await?;
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
                if received_any {
                    println!("Transfer session finished");
                    return Ok(());
                }
                return Err(anyhow!(err)).context("connection closed before any file arrived");
            }
        }
    }
}

async fn bind_endpoint() -> Result<Endpoint> {
    Endpoint::builder()
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .bind()
        .await
        .context("binding iroh endpoint")
}

async fn make_ticket(endpoint: &Endpoint) -> Result<String> {
    endpoint.online().await;
    let addr = endpoint.watch_addr().get();

    let ticket = TransferTicket {
        node_id: addr.id.to_string(),
        relay_url: addr.relay_urls().next().map(|url| url.to_string()),
    };

    let bytes = bincode::serialize(&ticket).context("serializing transfer ticket")?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

fn decode_ticket(ticket: &str) -> Result<EndpointAddr> {
    let bytes = URL_SAFE_NO_PAD
        .decode(ticket)
        .context("decoding ticket from base64")?;
    let ticket: TransferTicket = bincode::deserialize(&bytes)
        .or_else(|_| serde_json::from_slice(&bytes))
        .context("parsing ticket payload")?;

    let node_id = ticket
        .node_id
        .parse()
        .with_context(|| format!("parsing node id {}", ticket.node_id))?;

    let mut addr = EndpointAddr::new(node_id);

    if let Some(url) = ticket.relay_url {
        let relay_url = url
            .parse()
            .with_context(|| format!("parsing relay url {url}"))?;
        addr = addr.with_relay_url(relay_url);
    }

    Ok(addr.with_addrs(Vec::<TransportAddr>::new()))
}

async fn read_header(recv_stream: &mut iroh::endpoint::RecvStream) -> Result<FileHeader> {
    let header_len = recv_stream
        .read_u32()
        .await
        .context("reading header length")? as usize;
    let mut header_buf = vec![0_u8; header_len];
    recv_stream
        .read_exact(&mut header_buf)
        .await
        .context("reading header bytes")?;
    serde_json::from_slice(&header_buf).context("parsing file header")
}

async fn write_header(
    send_stream: &mut iroh::endpoint::SendStream,
    header: &FileHeader,
) -> Result<()> {
    let bytes = serde_json::to_vec(header).context("serializing file header")?;
    send_stream
        .write_u32(bytes.len() as u32)
        .await
        .context("writing header length")?;
    send_stream
        .write_all(&bytes)
        .await
        .context("writing header bytes")?;
    Ok(())
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

async fn unique_destination(out_dir: &Path, original_name: &str) -> Result<PathBuf> {
    let safe_name = Path::new(original_name)
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| anyhow!("invalid incoming file name"))?
        .to_owned();

    let candidate = out_dir.join(&safe_name);
    if !path_exists(&candidate).await? {
        return Ok(candidate);
    }

    let stem = Path::new(&safe_name)
        .file_stem()
        .and_then(|stem| stem.to_str())
        .unwrap_or("file");
    let ext = Path::new(&safe_name)
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| format!(".{ext}"))
        .unwrap_or_default();

    for index in 1..10_000 {
        let candidate = out_dir.join(format!("{stem}-{index}{ext}"));
        if !path_exists(&candidate).await? {
            return Ok(candidate);
        }
    }

    bail!("could not find a free destination for {}", safe_name)
}

async fn path_exists(path: &Path) -> Result<bool> {
    match fs::metadata(path).await {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(err).with_context(|| format!("checking {}", path.display())),
    }
}

fn confirm_accept() -> Result<bool> {
    print!("Accept? [y/N]: ");
    io::stdout().flush().context("flushing prompt")?;

    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .context("reading confirmation")?;

    let response = input.trim().to_ascii_lowercase();
    Ok(matches!(response.as_str(), "y" | "yes"))
}

fn describe_remote(
    remote_id: iroh::EndpointId,
    remote: Option<&iroh::endpoint::RemoteInfo>,
) -> String {
    let relay = remote
        .and_then(|info| {
            info.addrs().find_map(|addr| match addr.addr() {
                TransportAddr::Relay(url) => Some(format!(" via relay {url}")),
                TransportAddr::Ip(_) => None,
                _ => None,
            })
        })
        .unwrap_or_default();
    format!("{remote_id}{relay}")
}

fn human_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }

    if unit == 0 {
        format!("{} {}", bytes, UNITS[unit])
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}

#[derive(Debug, Clone)]
struct PreparedFiles {
    files: Vec<PreparedFile>,
    manifest: OfferManifest,
}
