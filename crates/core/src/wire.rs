use anyhow::{Context, Result};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, TransportAddr, Watcher};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use crate::rendezvous::OfferManifest;

pub const ALPN: &[u8] = b"drift/transfer/v1";
pub const TRANSFER_PROTOCOL_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransferTicket {
    node_id: String,
    relay_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hello {
    pub version: u32,
    pub session_id: String,
    pub role: TransferRole,
    pub device_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum TransferRole {
    Sender,
    Receiver,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Offer {
    pub session_id: String,
    pub manifest: OfferManifest,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Accept {
    pub session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Decline {
    pub session_id: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ControlMessage {
    Hello(Hello),
    Offer(Offer),
    Accept(Accept),
    Decline(Decline),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileHeader {
    pub path: String,
    pub size: u64,
}

pub async fn make_ticket(endpoint: &Endpoint) -> Result<String> {
    endpoint.online().await;
    let addr = endpoint.watch_addr().get();

    let ticket = TransferTicket {
        node_id: addr.id.to_string(),
        relay_url: addr.relay_urls().next().map(|url| url.to_string()),
    };

    let bytes = bincode::serialize(&ticket).context("serializing transfer ticket")?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

pub fn decode_ticket(ticket: &str) -> Result<EndpointAddr> {
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

pub async fn read_message<T: DeserializeOwned>(
    recv_stream: &mut iroh::endpoint::RecvStream,
) -> Result<T> {
    let message_len = recv_stream
        .read_u32()
        .await
        .context("reading message length")? as usize;
    let mut message_buf = vec![0_u8; message_len];
    recv_stream
        .read_exact(&mut message_buf)
        .await
        .context("reading message bytes")?;
    serde_json::from_slice(&message_buf).context("parsing message body")
}

pub async fn write_message<T: Serialize>(
    send_stream: &mut iroh::endpoint::SendStream,
    value: &T,
) -> Result<()> {
    let bytes = serde_json::to_vec(value).context("serializing message body")?;
    send_stream
        .write_u32(bytes.len() as u32)
        .await
        .context("writing message length")?;
    send_stream
        .write_all(&bytes)
        .await
        .context("writing message bytes")?;
    Ok(())
}

pub async fn read_header(recv_stream: &mut iroh::endpoint::RecvStream) -> Result<FileHeader> {
    read_message(recv_stream).await
}

pub async fn write_header(
    send_stream: &mut iroh::endpoint::SendStream,
    header: &FileHeader,
) -> Result<()> {
    write_message(send_stream, header).await
}
