mod device_name;

pub use device_name::{normalize_hostname_label, process_display_device_name, random_device_name};

use std::io::{self, Write};
use anyhow::{Context, Result};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, TransportAddr};
use serde::{Deserialize, Serialize};

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionPathKind {
    Direct,
    Relay,
    Unknown,
}

pub async fn classify_connection_path(
    endpoint: &iroh::Endpoint,
    remote_id: iroh::EndpointId,
) -> ConnectionPathKind {
    let Some(info) = endpoint.remote_info(remote_id).await else {
        return ConnectionPathKind::Unknown;
    };

    let mut has_ip = false;
    let mut has_relay = false;
    for addr in info.addrs() {
        match addr.addr() {
            TransportAddr::Ip(_) => has_ip = true,
            TransportAddr::Relay(_) => has_relay = true,
            _ => {}
        }
    }

    if has_ip {
        ConnectionPathKind::Direct
    } else if has_relay {
        ConnectionPathKind::Relay
    } else {
        ConnectionPathKind::Unknown
    }
}

pub fn confirm_accept() -> Result<bool> {
    print!("Accept? [y/N]: ");
    io::stdout().flush().context("flushing prompt")?;

    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .context("reading confirmation")?;

    let response = input.trim().to_ascii_lowercase();
    Ok(matches!(response.as_str(), "y" | "yes"))
}

pub fn describe_remote(
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

pub fn human_size(bytes: u64) -> String {
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

pub async fn make_ticket(endpoint: &Endpoint) -> Result<String> {
    endpoint.online().await;
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
