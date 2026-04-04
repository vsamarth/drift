use drift_core::error::{DriftError, DriftErrorKind};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeError {
    pub kind: BridgeErrorKind,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeErrorKind {
    InvalidInput,
    InvalidCode,
    RendezvousUnavailable,
    RendezvousRejected,
    PeerNotFound,
    PeerAlreadyClaimed,
    LanUnavailable,
    NoNearbyReceivers,
    ConnectionFailed,
    ProtocolViolation,
    TransferDeclined,
    TransferCancelled,
    TransferFailed,
    FileConflict,
    FileNotFound,
    PermissionDenied,
    Io,
    Internal,
}

impl From<DriftError> for BridgeError {
    fn from(error: DriftError) -> Self {
        Self {
            kind: error.kind.into(),
            reason: error.reason,
        }
    }
}

impl From<DriftErrorKind> for BridgeErrorKind {
    fn from(kind: DriftErrorKind) -> Self {
        match kind {
            DriftErrorKind::InvalidInput => Self::InvalidInput,
            DriftErrorKind::InvalidCode => Self::InvalidCode,
            DriftErrorKind::RendezvousUnavailable => Self::RendezvousUnavailable,
            DriftErrorKind::RendezvousRejected => Self::RendezvousRejected,
            DriftErrorKind::PeerNotFound => Self::PeerNotFound,
            DriftErrorKind::PeerAlreadyClaimed => Self::PeerAlreadyClaimed,
            DriftErrorKind::LanUnavailable => Self::LanUnavailable,
            DriftErrorKind::NoNearbyReceivers => Self::NoNearbyReceivers,
            DriftErrorKind::ConnectionFailed => Self::ConnectionFailed,
            DriftErrorKind::ProtocolViolation => Self::ProtocolViolation,
            DriftErrorKind::TransferDeclined => Self::TransferDeclined,
            DriftErrorKind::TransferCancelled => Self::TransferCancelled,
            DriftErrorKind::TransferFailed => Self::TransferFailed,
            DriftErrorKind::FileConflict => Self::FileConflict,
            DriftErrorKind::FileNotFound => Self::FileNotFound,
            DriftErrorKind::PermissionDenied => Self::PermissionDenied,
            DriftErrorKind::Io => Self::Io,
            DriftErrorKind::Internal => Self::Internal,
        }
    }
}
