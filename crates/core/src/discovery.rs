use std::time::Duration;

use anyhow::{Context, Result};
use iroh::{EndpointAddr, EndpointId};
use tracing::debug;

use crate::lan;
use crate::rendezvous::{RendezvousClient, resolve_server_url, validate_code};
use crate::wire::decode_ticket;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NearbyEndpoint {
    pub fullname: String,
    pub label: String,
    pub endpoint_id: EndpointId,
}

impl From<NearbyEndpoint> for EndpointId {
    fn from(value: NearbyEndpoint) -> Self {
        value.endpoint_id
    }
}

impl From<&NearbyEndpoint> for EndpointId {
    fn from(value: &NearbyEndpoint) -> Self {
        value.endpoint_id
    }
}

pub async fn resolve_pairing_code(code: &str, server_url: Option<&str>) -> Result<EndpointId> {
    validate_code(code)?;
    let client = RendezvousClient::new(resolve_server_url(server_url));
    let response = client.claim_peer(code).await?;
    endpoint_id_from_ticket(&response.ticket)
}

pub async fn resolve_nearby(timeout: Duration) -> Result<Vec<NearbyEndpoint>> {
    resolve_nearby_with_exclusion(timeout, None).await
}

pub async fn resolve_nearby_with_exclusion(
    timeout: Duration,
    exclude_endpoint_id: Option<EndpointId>,
) -> Result<Vec<NearbyEndpoint>> {
    let receivers = tokio::task::spawn_blocking(move || {
        lan::browse_nearby_receivers(timeout, exclude_endpoint_id)
    })
    .await
    .context("nearby discovery task")??;

    receivers
        .into_iter()
        .map(nearby_endpoint_from_receiver)
        .collect()
}

pub fn endpoint_id_from_ticket(ticket: &str) -> Result<EndpointId> {
    let addr: EndpointAddr = decode_ticket(ticket.trim())?;
    Ok(addr.id)
}

pub fn nearby_endpoint_from_receiver(receiver: lan::NearbyReceiver) -> Result<NearbyEndpoint> {
    let endpoint_id = endpoint_id_from_ticket(&receiver.ticket)?;
    debug!(
        %endpoint_id,
        fullname = %receiver.fullname,
        label = %receiver.label,
        "resolved nearby endpoint"
    );
    Ok(NearbyEndpoint {
        fullname: receiver.fullname,
        label: receiver.label,
        endpoint_id,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;
    use base64::engine::general_purpose::URL_SAFE_NO_PAD;
    use iroh::SecretKey;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Serialize, Deserialize)]
    struct TestTransferTicket {
        node_id: String,
        addrs: Vec<TestEncodedTransportAddr>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    enum TestEncodedTransportAddr {
        Relay(String),
        Ip(String),
    }

    #[test]
    fn endpoint_id_round_trips_through_ticket() {
        let endpoint_id = SecretKey::from_bytes(&[12; 32]).public();
        let ticket = TestTransferTicket {
            node_id: endpoint_id.to_string(),
            addrs: Vec::new(),
        };
        let encoded =
            URL_SAFE_NO_PAD.encode(bincode::serialize(&ticket).expect("serialize ticket"));

        let endpoint_id = endpoint_id_from_ticket(&encoded).expect("endpoint id");

        assert_eq!(endpoint_id, SecretKey::from_bytes(&[12; 32]).public());
    }

    #[test]
    fn malformed_ticket_is_rejected() {
        assert!(endpoint_id_from_ticket("not-a-ticket").is_err());
    }

    #[test]
    fn nearby_receiver_mapping_rejects_malformed_ticket() {
        let receiver = lan::NearbyReceiver {
            fullname: "recv-1".to_owned(),
            label: "Receiver".to_owned(),
            code: String::new(),
            ticket: "bad-ticket".to_owned(),
        };

        assert!(nearby_endpoint_from_receiver(receiver).is_err());
    }

    #[test]
    fn nearby_endpoint_converts_into_endpoint_id() {
        let endpoint_id = SecretKey::from_bytes(&[13; 32]).public();
        let endpoint = NearbyEndpoint {
            fullname: "recv-1".to_owned(),
            label: "Receiver".to_owned(),
            endpoint_id,
        };

        let converted: EndpointId = endpoint.into();
        assert_eq!(converted, endpoint_id);
    }
}
