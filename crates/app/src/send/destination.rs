use drift_core::protocol::{DeviceType, TransferRole};
use drift_core::rendezvous::{RendezvousClient, resolve_server_url, validate_code};
use drift_core::transfer::TransferCancellation;
use drift_core::util::{decode_ticket, format_code_label};
use iroh::{EndpointAddr, EndpointId};

use crate::error::{AppError, AppResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendDestination {
    Code {
        code: String,
        server_url: Option<String>,
    },
    Nearby {
        ticket: String,
        destination_label: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ResolvedDestination {
    pub(crate) destination_label: String,
    pub(crate) peer_endpoint_addr: EndpointAddr,
    pub(crate) peer_endpoint_id: EndpointId,
}

impl SendDestination {
    pub fn code(code: String, server_url: Option<String>) -> Self {
        Self::Code { code, server_url }
    }

    pub fn nearby(ticket: String, destination_label: String) -> Self {
        Self::Nearby {
            ticket,
            destination_label,
        }
    }

    pub(crate) fn display_label(&self) -> String {
        match self {
            Self::Code { code, .. } => format_code_label(code),
            Self::Nearby {
                destination_label, ..
            } => display_destination_label(destination_label),
        }
    }

    pub(crate) async fn resolve(&self) -> AppResult<ResolvedDestination> {
        match self {
            Self::Code { code, server_url } => {
                validate_code(code).map_err(|_| AppError::InvalidCode { code: code.clone() })?;
                let client = RendezvousClient::new(resolve_server_url(server_url.as_deref()));
                let resolved = client
                    .claim_peer(code)
                    .await
                    .map_err(|e| AppError::Internal {
                        message: e.to_string(),
                    })?;
                let endpoint_addr =
                    decode_ticket(&resolved.ticket).map_err(|e| AppError::Internal {
                        message: e.to_string(),
                    })?;
                Ok(ResolvedDestination {
                    destination_label: format_code_label(code),
                    peer_endpoint_addr: endpoint_addr.clone(),
                    peer_endpoint_id: endpoint_addr.id,
                })
            }
            Self::Nearby { ticket, .. } => {
                let endpoint_addr =
                    decode_ticket(ticket.trim()).map_err(|e| AppError::Internal {
                        message: e.to_string(),
                    })?;
                Ok(ResolvedDestination {
                    destination_label: self.display_label(),
                    peer_endpoint_addr: endpoint_addr.clone(),
                    peer_endpoint_id: endpoint_addr.id,
                })
            }
        }
    }
}

pub(crate) fn display_destination_label(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return "Recipient device".to_owned();
    }

    let normalized = trimmed
        .replace(['_', '-'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let lowercase = normalized.to_ascii_lowercase();
    if lowercase.is_empty()
        || lowercase == "unknown device"
        || lowercase == "unknown-device"
        || lowercase == "unknown"
    {
        return "Recipient device".to_owned();
    }

    normalized
}

pub(crate) fn parse_device_type(value: &str) -> AppResult<DeviceType> {
    match value.trim().to_ascii_lowercase().as_str() {
        "phone" => Ok(DeviceType::Phone),
        "laptop" => Ok(DeviceType::Laptop),
        other => Err(AppError::InvalidDeviceType {
            value: other.to_owned(),
        }),
    }
}

pub(crate) fn is_receiver_decline_cancel(cancellation: &TransferCancellation) -> bool {
    matches!(cancellation.by, TransferRole::Receiver)
        && matches!(
            cancellation.phase,
            drift_core::protocol::CancelPhase::WaitingForDecision
        )
}

#[cfg(test)]
mod tests {
    use super::display_destination_label;

    #[test]
    fn destination_label_falls_back_for_unknown_values() {
        assert_eq!(
            display_destination_label("unknown-device"),
            "Recipient device"
        );
        assert_eq!(display_destination_label(""), "Recipient device");
    }
}
