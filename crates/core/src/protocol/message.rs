#![allow(dead_code)]

use iroh::EndpointId;
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub(crate) const PROTOCOL_VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum DeviceType {
    Phone,
    Laptop,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub(crate) enum TransferRole {
    Sender,
    Receiver,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum MessageKind {
    Hello,
    Offer,
    Accept,
    Decline,
    Cancel,
    TransferStarted,
    TransferProgress,
    TransferCompleted,
    BlobTicket,
    TransferResult,
    TransferAck,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct Identity {
    pub(crate) role: TransferRole,
    pub(crate) endpoint_id: EndpointId,
    pub(crate) device_name: String,
    pub(crate) device_type: DeviceType,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum CancelPhase {
    WaitingForDecision,
    Transferring,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub(crate) enum TransferErrorCode {
    ProtocolViolation,
    UnexpectedMessage,
    FileConflict,
    IoError,
    ChecksumMismatch,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "status", rename_all = "snake_case")]
pub(crate) enum TransferStatus {
    Ok,
    Error {
        code: TransferErrorCode,
        message: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct TransferManifest {
    pub(crate) items: Vec<ManifestItem>,
}

impl TransferManifest {
    pub(crate) fn count(&self) -> usize {
        self.items.len()
    }

    pub(crate) fn total_size(&self) -> u64 {
        self.items
            .iter()
            .map(|item| match item {
                ManifestItem::File { size, .. } => *size,
            })
            .sum()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum ManifestItem {
    File { path: String, size: u64 },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct Hello {
    pub(crate) version: u32,
    pub(crate) session_id: String,
    pub(crate) identity: Identity,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct Offer {
    pub(crate) session_id: String,
    pub(crate) manifest: TransferManifest,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct Accept {
    pub(crate) session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct Decline {
    pub(crate) session_id: String,
    pub(crate) reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct TransferStarted {
    pub(crate) session_id: String,
    pub(crate) file_count: u64,
    pub(crate) total_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct TransferProgress {
    pub(crate) session_id: String,
    pub(crate) bytes_sent: u64,
    pub(crate) total_bytes: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct TransferCompleted {
    pub(crate) session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct Cancel {
    pub(crate) session_id: String,
    pub(crate) by: TransferRole,
    pub(crate) phase: CancelPhase,
    pub(crate) reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct BlobTicketMessage {
    pub(crate) session_id: String,
    pub(crate) ticket: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct TransferResult {
    pub(crate) session_id: String,
    pub(crate) status: TransferStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct TransferAck {
    pub(crate) session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub(crate) struct MessageEnvelope {
    pub(crate) version: u32,
    pub(crate) role: TransferRole,
    pub(crate) kind: MessageKind,
    pub(crate) message: Value,
}

/// Messages the sender can emit on the transfer control channel.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum SenderMessage {
    Hello(Hello),
    Offer(Offer),
    BlobTicket(BlobTicketMessage),
    Cancel(Cancel),
    TransferAck(TransferAck),
}

impl SenderMessage {
    pub(crate) fn kind(&self) -> MessageKind {
        match self {
            Self::Hello(_) => MessageKind::Hello,
            Self::Offer(_) => MessageKind::Offer,
            Self::BlobTicket(_) => MessageKind::BlobTicket,
            Self::Cancel(_) => MessageKind::Cancel,
            Self::TransferAck(_) => MessageKind::TransferAck,
        }
    }

    pub(crate) fn role(&self) -> TransferRole {
        TransferRole::Sender
    }
}

/// Messages the receiver can emit on the transfer control channel.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(crate) enum ReceiverMessage {
    Hello(Hello),
    Accept(Accept),
    Decline(Decline),
    TransferStarted(TransferStarted),
    TransferProgress(TransferProgress),
    TransferCompleted(TransferCompleted),
    Cancel(Cancel),
    TransferResult(TransferResult),
}

impl ReceiverMessage {
    pub(crate) fn kind(&self) -> MessageKind {
        match self {
            Self::Hello(_) => MessageKind::Hello,
            Self::Accept(_) => MessageKind::Accept,
            Self::Decline(_) => MessageKind::Decline,
            Self::TransferStarted(_) => MessageKind::TransferStarted,
            Self::TransferProgress(_) => MessageKind::TransferProgress,
            Self::TransferCompleted(_) => MessageKind::TransferCompleted,
            Self::Cancel(_) => MessageKind::Cancel,
            Self::TransferResult(_) => MessageKind::TransferResult,
        }
    }

    pub(crate) fn role(&self) -> TransferRole {
        TransferRole::Receiver
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use iroh::SecretKey;

    #[test]
    fn sender_message_serializes_with_directional_tag() {
        let message = SenderMessage::Hello(Hello {
            version: PROTOCOL_VERSION,
            session_id: "session-1".to_owned(),
            identity: Identity {
                role: TransferRole::Sender,
                endpoint_id: SecretKey::from_bytes(&[1; 32]).public(),
                device_name: "sam-mac".to_owned(),
                device_type: DeviceType::Laptop,
            },
        });

        let json = serde_json::to_string(&message).unwrap();

        assert!(json.contains("\"type\":\"hello\""));
        assert!(json.contains("\"role\":\"sender\""));
    }

    #[test]
    fn receiver_message_serializes_expected_payloads() {
        let message = ReceiverMessage::TransferResult(TransferResult {
            session_id: "session-1".to_owned(),
            status: TransferStatus::Ok,
        });

        let json = serde_json::to_string(&message).unwrap();

        assert!(json.contains("\"type\":\"transfer_result\""));
        assert!(json.contains("\"status\":\"ok\""));
    }

    #[test]
    fn message_enums_cover_current_transfer_flow() {
        let manifest = TransferManifest {
            items: vec![ManifestItem::File {
                path: "a.txt".to_owned(),
                size: 1,
            }],
        };

        let sender_messages = [
            SenderMessage::Hello(Hello {
                version: PROTOCOL_VERSION,
                session_id: "session-1".to_owned(),
                identity: Identity {
                    role: TransferRole::Sender,
                    endpoint_id: SecretKey::from_bytes(&[1; 32]).public(),
                    device_name: "sam-mac".to_owned(),
                    device_type: DeviceType::Laptop,
                },
            }),
            SenderMessage::Offer(Offer {
                session_id: "session-1".to_owned(),
                manifest: manifest.clone(),
            }),
            SenderMessage::BlobTicket(BlobTicketMessage {
                session_id: "session-1".to_owned(),
                ticket: "ticket".to_owned(),
            }),
            SenderMessage::Cancel(Cancel {
                session_id: "session-1".to_owned(),
                by: TransferRole::Sender,
                phase: CancelPhase::WaitingForDecision,
                reason: "cancelled".to_owned(),
            }),
            SenderMessage::TransferAck(TransferAck {
                session_id: "session-1".to_owned(),
            }),
        ];

        let receiver_messages = [
            ReceiverMessage::Hello(Hello {
                version: PROTOCOL_VERSION,
                session_id: "session-1".to_owned(),
                identity: Identity {
                    role: TransferRole::Receiver,
                    endpoint_id: SecretKey::from_bytes(&[2; 32]).public(),
                    device_name: "phone".to_owned(),
                    device_type: DeviceType::Phone,
                },
            }),
            ReceiverMessage::Accept(Accept {
                session_id: "session-1".to_owned(),
            }),
            ReceiverMessage::Decline(Decline {
                session_id: "session-1".to_owned(),
                reason: "not now".to_owned(),
            }),
            ReceiverMessage::TransferStarted(TransferStarted {
                session_id: "session-1".to_owned(),
                file_count: 1,
                total_bytes: 1,
            }),
            ReceiverMessage::TransferProgress(TransferProgress {
                session_id: "session-1".to_owned(),
                bytes_sent: 1,
                total_bytes: 1,
            }),
            ReceiverMessage::TransferCompleted(TransferCompleted {
                session_id: "session-1".to_owned(),
            }),
            ReceiverMessage::Cancel(Cancel {
                session_id: "session-1".to_owned(),
                by: TransferRole::Receiver,
                phase: CancelPhase::Transferring,
                reason: "cancelled".to_owned(),
            }),
            ReceiverMessage::TransferResult(TransferResult {
                session_id: "session-1".to_owned(),
                status: TransferStatus::Ok,
            }),
        ];

        assert_eq!(sender_messages.len(), 5);
        assert_eq!(receiver_messages.len(), 8);
    }
}
