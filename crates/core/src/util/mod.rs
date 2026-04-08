mod device_name;

pub use device_name::{normalize_hostname_label, process_display_device_name, random_device_name};

use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, TransportAddr};
use serde::{Deserialize, Serialize};
use std::io::{self, Write};
use thiserror::Error;

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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionPathKind {
    Direct,
    Relay,
    Unknown,
}

#[derive(Debug, Error)]
pub enum TicketError {
    #[error("serializing transfer ticket")]
    Serialize {
        #[source]
        source: Box<bincode::ErrorKind>,
    },
    #[error("decoding ticket from base64")]
    DecodeBase64 {
        #[source]
        source: base64::DecodeError,
    },
    #[error("ticket payload is not a supported drift ticket")]
    InvalidPayload,
    #[error("parsing node id {value}")]
    ParseNodeId {
        value: String,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    #[error("parsing relay url {value}")]
    ParseRelayUrl {
        value: String,
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    #[error("parsing socket addr {value}")]
    ParseSocketAddr {
        value: String,
        #[source]
        source: std::net::AddrParseError,
    },
}

#[derive(Debug, Error)]
pub enum ConfirmAcceptError {
    #[error("flushing prompt")]
    FlushPrompt {
        #[source]
        source: io::Error,
    },
    #[error("reading confirmation")]
    ReadConfirmation {
        #[source]
        source: io::Error,
    },
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

pub fn confirm_accept() -> std::result::Result<bool, ConfirmAcceptError> {
    print!("Accept? [y/N]: ");
    io::stdout()
        .flush()
        .map_err(|source| ConfirmAcceptError::FlushPrompt { source })?;

    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .map_err(|source| ConfirmAcceptError::ReadConfirmation { source })?;

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

pub fn format_code_label(code: &str) -> String {
    let normalized = code.trim().to_ascii_uppercase();
    let chars: Vec<char> = normalized
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric())
        .collect();
    if chars.len() != 6 {
        return "Code".to_owned();
    }

    format!(
        "Code {}{} {}{} {}{}",
        chars[0], chars[1], chars[2], chars[3], chars[4], chars[5]
    )
}

pub async fn make_ticket(endpoint: &Endpoint) -> std::result::Result<String, TicketError> {
    endpoint.online().await;
    make_ticket_from_addr(endpoint.addr())
}

fn make_ticket_from_addr(addr: EndpointAddr) -> std::result::Result<String, TicketError> {
    let ticket = TransferTicket {
        node_id: addr.id.to_string(),
        addrs: addr
            .addrs
            .into_iter()
            .map(EncodedTransportAddr::from)
            .collect(),
    };

    let bytes = bincode::serialize(&ticket).map_err(|source| TicketError::Serialize { source })?;
    Ok(URL_SAFE_NO_PAD.encode(bytes))
}

pub fn decode_ticket(ticket: &str) -> std::result::Result<EndpointAddr, TicketError> {
    let bytes = URL_SAFE_NO_PAD
        .decode(ticket)
        .map_err(|source| TicketError::DecodeBase64 { source })?;
    let ticket = parse_transfer_ticket(&bytes)?;

    let node_id = ticket
        .node_id
        .parse()
        .map_err(|source| TicketError::ParseNodeId {
            value: ticket.node_id.clone(),
            source: Box::new(source),
        })?;

    let addrs = ticket
        .addrs
        .into_iter()
        .map(TryInto::try_into)
        .collect::<std::result::Result<Vec<TransportAddr>, TicketError>>()?;

    Ok(EndpointAddr::new(node_id).with_addrs(addrs))
}

fn parse_transfer_ticket(bytes: &[u8]) -> std::result::Result<TransferTicket, TicketError> {
    bincode::deserialize::<TransferTicket>(bytes).map_err(|_| TicketError::InvalidPayload)
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
    type Error = TicketError;

    fn try_from(value: EncodedTransportAddr) -> std::result::Result<Self, Self::Error> {
        match value {
            EncodedTransportAddr::Relay(url) => {
                Ok(TransportAddr::Relay(url.parse().map_err(|source| {
                    TicketError::ParseRelayUrl {
                        value: url.clone(),
                        source: Box::new(source),
                    }
                })?))
            }
            EncodedTransportAddr::Ip(addr) => {
                Ok(TransportAddr::Ip(addr.parse().map_err(|source| {
                    TicketError::ParseSocketAddr {
                        value: addr.clone(),
                        source,
                    }
                })?))
            }
        }
    }
}
