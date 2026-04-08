use crate::protocol::message::{MessageKind, TransferErrorCode, TransferRole, TransferStatus};
use std::error::Error as StdError;
use thiserror::Error;

#[derive(Debug, Error)]
pub(crate) enum ProtocolError {
    #[error("unsupported protocol version {actual} (expected {expected})")]
    UnsupportedVersion { expected: u32, actual: u32 },
    #[error("unexpected message role {actual:?} (expected {expected:?})")]
    UnexpectedRole {
        expected: TransferRole,
        actual: TransferRole,
    },
    #[error("unexpected {context} message kind {actual:?} (expected {expected:?})")]
    UnexpectedMessageKind {
        context: &'static str,
        expected: MessageKind,
        actual: MessageKind,
    },
    #[error("session id mismatch: expected {expected}, got {actual}")]
    SessionIdMismatch { expected: String, actual: String },
    #[error("{role:?} device name must not be empty")]
    EmptyDeviceName { role: TransferRole },
    #[error("invalid {actor} transition: {from} -> {to}")]
    InvalidTransition {
        actor: &'static str,
        from: String,
        to: String,
    },
    #[error("{peer} identity missing after hello")]
    MissingPeerIdentity { peer: &'static str },
    #[error("message length {actual} exceeds maximum {max}")]
    MessageTooLarge { actual: usize, max: usize },
    #[error("{context}: {source}")]
    FrameRead {
        context: &'static str,
        #[source]
        source: Box<dyn StdError + Send + Sync>,
    },
    #[error("{context}: {source}")]
    FrameWrite {
        context: &'static str,
        #[source]
        source: Box<dyn StdError + Send + Sync>,
    },
    #[error("{context}: {source}")]
    MessageSerialize {
        context: &'static str,
        #[source]
        source: Box<dyn StdError + Send + Sync>,
    },
    #[error("{context}: {source}")]
    MessageDeserialize {
        context: &'static str,
        #[source]
        source: Box<dyn StdError + Send + Sync>,
    },
}

pub(crate) type Result<T> = std::result::Result<T, ProtocolError>;

impl ProtocolError {
    pub(crate) fn unsupported_version(expected: u32, actual: u32) -> Self {
        Self::UnsupportedVersion { expected, actual }
    }

    pub(crate) fn unexpected_role(expected: TransferRole, actual: TransferRole) -> Self {
        Self::UnexpectedRole { expected, actual }
    }

    pub(crate) fn unexpected_message_kind(
        context: &'static str,
        expected: MessageKind,
        actual: MessageKind,
    ) -> Self {
        Self::UnexpectedMessageKind {
            context,
            expected,
            actual,
        }
    }

    pub(crate) fn session_id_mismatch(
        expected: impl Into<String>,
        actual: impl Into<String>,
    ) -> Self {
        Self::SessionIdMismatch {
            expected: expected.into(),
            actual: actual.into(),
        }
    }

    pub(crate) fn empty_device_name(role: TransferRole) -> Self {
        Self::EmptyDeviceName { role }
    }

    pub(crate) fn invalid_transition(
        actor: &'static str,
        from: impl Into<String>,
        to: impl Into<String>,
    ) -> Self {
        Self::InvalidTransition {
            actor,
            from: from.into(),
            to: to.into(),
        }
    }

    pub(crate) fn missing_peer_identity(peer: &'static str) -> Self {
        Self::MissingPeerIdentity { peer }
    }

    pub(crate) fn message_too_large(actual: usize, max: usize) -> Self {
        Self::MessageTooLarge { actual, max }
    }

    pub(crate) fn frame_read(
        context: &'static str,
        source: impl StdError + Send + Sync + 'static,
    ) -> Self {
        Self::FrameRead {
            context,
            source: Box::new(source),
        }
    }

    pub(crate) fn frame_write(
        context: &'static str,
        source: impl StdError + Send + Sync + 'static,
    ) -> Self {
        Self::FrameWrite {
            context,
            source: Box::new(source),
        }
    }

    pub(crate) fn message_serialize(
        context: &'static str,
        source: impl StdError + Send + Sync + 'static,
    ) -> Self {
        Self::MessageSerialize {
            context,
            source: Box::new(source),
        }
    }

    pub(crate) fn message_deserialize(
        context: &'static str,
        source: impl StdError + Send + Sync + 'static,
    ) -> Self {
        Self::MessageDeserialize {
            context,
            source: Box::new(source),
        }
    }

    pub(crate) fn code(&self) -> TransferErrorCode {
        match self {
            Self::UnsupportedVersion { .. }
            | Self::UnexpectedRole { .. }
            | Self::UnexpectedMessageKind { .. }
            | Self::SessionIdMismatch { .. }
            | Self::EmptyDeviceName { .. }
            | Self::InvalidTransition { .. }
            | Self::MissingPeerIdentity { .. }
            | Self::MessageTooLarge { .. }
            | Self::FrameRead { .. }
            | Self::FrameWrite { .. }
            | Self::MessageSerialize { .. }
            | Self::MessageDeserialize { .. } => TransferErrorCode::ProtocolViolation,
        }
    }

    pub(crate) fn transfer_status(&self) -> TransferStatus {
        TransferStatus::Error {
            code: self.code(),
            message: self.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ProtocolError;
    use crate::protocol::message::{TransferErrorCode, TransferRole};

    #[test]
    fn maps_all_protocol_errors_to_protocol_violation() {
        let err = ProtocolError::unsupported_version(2, 1);
        assert_eq!(err.code(), TransferErrorCode::ProtocolViolation);
        assert_eq!(
            err.to_string(),
            "unsupported protocol version 1 (expected 2)"
        );
    }

    #[test]
    fn formats_role_specific_messages() {
        let err = ProtocolError::empty_device_name(TransferRole::Receiver);
        assert_eq!(err.to_string(), "Receiver device name must not be empty");
        assert_eq!(err.code(), TransferErrorCode::ProtocolViolation);
    }
}
