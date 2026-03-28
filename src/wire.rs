use anyhow::{Context, Result};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, TransportAddr, Watcher};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub(crate) const ALPN: &[u8] = b"drift/v0";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransferTicket {
    node_id: String,
    relay_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct FileHeader {
    pub(crate) path: String,
    pub(crate) size: u64,
}

pub(crate) async fn make_ticket(endpoint: &Endpoint) -> Result<String> {
    endpoint.online().await;
    let addr = endpoint.watch_addr().get();

    let ticket = TransferTicket {
        node_id: addr.id.to_string(),
        relay_url: addr.relay_urls().next().map(|url| url.to_string()),
    };

    let bytes = bincode::serialize(&ticket).context("serializing transfer ticket")?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

pub(crate) fn decode_ticket(ticket: &str) -> Result<EndpointAddr> {
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

pub(crate) async fn read_header(recv_stream: &mut iroh::endpoint::RecvStream) -> Result<FileHeader> {
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

pub(crate) async fn write_header(
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
