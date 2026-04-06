use anyhow::{Context, Result};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use iroh::{Endpoint, EndpointAddr, TransportAddr};
use serde::{Deserialize, Serialize};

pub const ALPN: &[u8] = b"drift/transfer/v1";
pub const TRANSFER_PROTOCOL_VERSION: u32 = 1;

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

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use iroh::{RelayUrl, SecretKey};

    use super::*;

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
