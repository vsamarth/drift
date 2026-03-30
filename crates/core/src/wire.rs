use anyhow::{Context, Result, anyhow, bail};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, TransportAddr};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::rendezvous::OfferManifest;

pub const ALPN: &[u8] = b"drift/transfer/v1";
pub const TRANSFER_PROTOCOL_VERSION: u32 = 1;

/// Maximum payload bytes per chunk on the file transfer stream (4 MiB).
pub const TRANSFER_CHUNK_SIZE: u32 = 4 * 1024 * 1024;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DeviceType {
    Phone,
    Laptop,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TransferTicket {
    node_id: String,
    addrs: Vec<EncodedTransportAddr>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
enum EncodedTransportAddr {
    Relay(String),
    Ip(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LegacyTransferTicket {
    node_id: String,
    relay_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hello {
    pub version: u32,
    pub session_id: String,
    pub role: TransferRole,
    pub device_name: String,
    pub device_type: DeviceType,
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

/// Opens a chunked file transfer on a bidi stream (JSON preamble, then binary chunk frames).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FileOpen {
    pub path: String,
    pub size: u64,
    pub chunk_size: u32,
    pub chunk_count: u32,
    /// Lowercase hex encoding of 32-byte BLAKE3 digest of the full file.
    pub file_blake3: String,
}

pub fn chunk_count_for_transfer_size(size: u64) -> Result<u32> {
    if size == 0 {
        return Ok(1);
    }
    let chunks = size.div_ceil(TRANSFER_CHUNK_SIZE as u64);
    u32::try_from(chunks).map_err(|_| anyhow!("file is too large for chunk protocol"))
}

pub fn blake3_to_hex(digest: &[u8; 32]) -> String {
    digest.iter().map(|b| format!("{:02x}", b)).collect()
}

pub fn blake3_from_hex(s: &str) -> Result<[u8; 32]> {
    if s.len() != 64 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        bail!("file_blake3 must be 64 hex characters");
    }
    let mut out = [0_u8; 32];
    for i in 0..32 {
        let byte = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16)
            .map_err(|_| anyhow!("invalid file_blake3 hex"))?;
        out[i] = byte;
    }
    Ok(out)
}

pub async fn make_ticket(endpoint: &Endpoint) -> Result<String> {
    endpoint.online().await;
    make_ticket_from_addr(endpoint.addr())
}

pub fn make_ticket_now(endpoint: &Endpoint) -> Result<String> {
    make_ticket_from_addr(endpoint.addr())
}

fn make_ticket_from_addr(addr: EndpointAddr) -> Result<String> {
    let ticket = TransferTicket {
        node_id: addr.id.to_string(),
        addrs: addr
            .addrs
            .into_iter()
            .map(EncodedTransportAddr::from)
            .collect(),
    };

    let bytes = bincode::serialize(&ticket).context("serializing transfer ticket")?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

pub fn decode_ticket(ticket: &str) -> Result<EndpointAddr> {
    let bytes = URL_SAFE_NO_PAD
        .decode(ticket)
        .context("decoding ticket from base64")?;
    let ticket = parse_transfer_ticket(&bytes)?;

    let node_id = ticket
        .node_id
        .parse()
        .with_context(|| format!("parsing node id {}", ticket.node_id))?;

    let addrs = ticket
        .addrs
        .into_iter()
        .map(TryInto::try_into)
        .collect::<Result<Vec<TransportAddr>>>()?;

    Ok(EndpointAddr::new(node_id).with_addrs(addrs))
}

fn parse_transfer_ticket(bytes: &[u8]) -> Result<TransferTicket> {
    if let Ok(ticket) = bincode::deserialize::<TransferTicket>(bytes) {
        return Ok(ticket);
    }
    if let Ok(ticket) = bincode::deserialize::<LegacyTransferTicket>(bytes) {
        return Ok(TransferTicket::from(ticket));
    }
    if let Ok(ticket) = serde_json::from_slice::<TransferTicket>(bytes) {
        return Ok(ticket);
    }
    let legacy =
        serde_json::from_slice::<LegacyTransferTicket>(bytes).context("parsing ticket payload")?;
    Ok(TransferTicket::from(legacy))
}

impl From<TransportAddr> for EncodedTransportAddr {
    fn from(value: TransportAddr) -> Self {
        match value {
            TransportAddr::Relay(url) => Self::Relay(url.to_string()),
            TransportAddr::Ip(addr) => Self::Ip(addr.to_string()),
            _ => unreachable!("unsupported transport address variant"),
        }
    }
}

impl TryFrom<EncodedTransportAddr> for TransportAddr {
    type Error = anyhow::Error;

    fn try_from(value: EncodedTransportAddr) -> Result<Self> {
        match value {
            EncodedTransportAddr::Relay(url) => Ok(TransportAddr::Relay(
                url.parse()
                    .with_context(|| format!("parsing relay url {url}"))?,
            )),
            EncodedTransportAddr::Ip(addr) => Ok(TransportAddr::Ip(
                addr.parse()
                    .with_context(|| format!("parsing socket addr {addr}"))?,
            )),
        }
    }
}

impl From<LegacyTransferTicket> for TransferTicket {
    fn from(value: LegacyTransferTicket) -> Self {
        let mut addrs = Vec::new();
        if let Some(url) = value.relay_url {
            addrs.push(EncodedTransportAddr::Relay(url));
        }
        Self {
            node_id: value.node_id,
            addrs,
        }
    }
}

const MAX_JSON_FRAME_BYTES: usize = 16 * 1024 * 1024;

/// Length-prefixed JSON frame (same encoding as control messages), for any async reader.
pub async fn read_json_frame<R: AsyncRead + Unpin, T: DeserializeOwned>(
    reader: &mut R,
) -> Result<T> {
    let message_len = reader.read_u32().await.context("reading message length")? as usize;
    if message_len > MAX_JSON_FRAME_BYTES {
        bail!(
            "message length {} exceeds maximum {}",
            message_len,
            MAX_JSON_FRAME_BYTES
        );
    }
    let mut message_buf = vec![0_u8; message_len];
    reader
        .read_exact(&mut message_buf)
        .await
        .context("reading message bytes")?;
    serde_json::from_slice(&message_buf).context("parsing message body")
}

/// Length-prefixed JSON frame (same encoding as control messages), for any async writer.
pub async fn write_json_frame<W: AsyncWrite + Unpin, T: Serialize>(
    writer: &mut W,
    value: &T,
) -> Result<()> {
    let bytes = serde_json::to_vec(value).context("serializing message body")?;
    writer
        .write_u32(bytes.len() as u32)
        .await
        .context("writing message length")?;
    writer
        .write_all(&bytes)
        .await
        .context("writing message bytes")?;
    writer.flush().await.context("flushing message")?;
    Ok(())
}

pub async fn read_message<T: DeserializeOwned>(
    recv_stream: &mut iroh::endpoint::RecvStream,
) -> Result<T> {
    read_json_frame(recv_stream).await
}

pub async fn write_message<T: Serialize>(
    send_stream: &mut iroh::endpoint::SendStream,
    value: &T,
) -> Result<()> {
    write_json_frame(send_stream, value).await
}

pub async fn read_file_open(recv_stream: &mut iroh::endpoint::RecvStream) -> Result<FileOpen> {
    read_json_frame(recv_stream).await
}

pub async fn write_file_open(
    send_stream: &mut iroh::endpoint::SendStream,
    open: &FileOpen,
) -> Result<()> {
    write_json_frame(send_stream, open).await
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use iroh::{RelayUrl, SecretKey};

    use super::*;

    #[test]
    fn chunk_count_edge_cases() {
        assert_eq!(chunk_count_for_transfer_size(0).unwrap(), 1);
        assert_eq!(chunk_count_for_transfer_size(1).unwrap(), 1);
        assert_eq!(
            chunk_count_for_transfer_size(TRANSFER_CHUNK_SIZE as u64).unwrap(),
            1
        );
        assert_eq!(
            chunk_count_for_transfer_size(TRANSFER_CHUNK_SIZE as u64 + 1).unwrap(),
            2
        );
    }

    #[test]
    fn blake3_hex_roundtrip() {
        let d = *blake3::hash(b"hello").as_bytes();
        let h = blake3_to_hex(&d);
        assert_eq!(blake3_from_hex(&h).unwrap(), d);
    }

    #[test]
    fn ticket_roundtrip_preserves_all_addresses() {
        let relay_url: RelayUrl = "https://example-relay.test./".parse().unwrap();
        let socket_addr = "192.168.1.5:4242".parse().unwrap();
        let endpoint_id = SecretKey::from_bytes(&[7; 32]).public();
        let addr = EndpointAddr::from_parts(
            endpoint_id,
            [
                TransportAddr::Relay(relay_url.clone()),
                TransportAddr::Ip(socket_addr),
            ],
        );

        let ticket = make_ticket_from_addr(addr.clone()).unwrap();
        let decoded = decode_ticket(&ticket).unwrap();

        assert_eq!(decoded.id, addr.id);
        assert_eq!(
            decoded.addrs,
            BTreeSet::from([
                TransportAddr::Relay(relay_url),
                TransportAddr::Ip(socket_addr),
            ])
        );
    }

    #[test]
    fn legacy_ticket_still_decodes() {
        let endpoint_id = SecretKey::from_bytes(&[9; 32]).public();
        let legacy = LegacyTransferTicket {
            node_id: endpoint_id.to_string(),
            relay_url: Some("https://legacy-relay.test./".to_owned()),
        };
        let bytes = bincode::serialize(&legacy).unwrap();
        let encoded = URL_SAFE_NO_PAD.encode(bytes);

        let decoded = decode_ticket(&encoded).unwrap();

        assert_eq!(decoded.id, endpoint_id);
        assert_eq!(
            decoded.relay_urls().next().map(ToString::to_string),
            Some("https://legacy-relay.test./".to_owned())
        );
        assert_eq!(decoded.ip_addrs().count(), 0);
    }
}
