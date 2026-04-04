use std::fmt;

pub type Result<T> = std::result::Result<T, DriftError>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DriftError {
    pub kind: DriftErrorKind,
    pub reason: Option<String>,
}

impl DriftError {
    pub fn new(kind: DriftErrorKind) -> Self {
        Self { kind, reason: None }
    }

    pub fn with_reason(kind: DriftErrorKind, reason: impl Into<String>) -> Self {
        Self {
            kind,
            reason: Some(reason.into()),
        }
    }

    pub fn invalid_input(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::InvalidInput, reason)
    }

    pub fn protocol(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::ProtocolViolation, reason)
    }

    pub fn connection(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::ConnectionFailed, reason)
    }

    pub fn internal(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::Internal, reason)
    }

    pub fn transfer_declined(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::TransferDeclined, reason)
    }

    pub fn transfer_cancelled(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::TransferCancelled, reason)
    }

    pub fn lan(reason: impl Into<String>) -> Self {
        Self::with_reason(DriftErrorKind::LanUnavailable, reason)
    }

    pub fn with_prefix(self, prefix: impl Into<String>) -> Self {
        let prefix = prefix.into();
        let detail = self.reason.unwrap_or_else(|| self.kind.default_reason().to_owned());
        Self::with_reason(self.kind, format!("{prefix}: {detail}"))
    }

    pub fn io(reason: impl Into<String>, error: &std::io::Error) -> Self {
        let kind = match error.kind() {
            std::io::ErrorKind::NotFound => DriftErrorKind::FileNotFound,
            std::io::ErrorKind::PermissionDenied => DriftErrorKind::PermissionDenied,
            _ => DriftErrorKind::Io,
        };
        Self::with_reason(kind, format!("{}: {}", reason.into(), error))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DriftErrorKind {
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

impl fmt::Display for DriftError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if let Some(reason) = &self.reason {
            return f.write_str(reason);
        }

        f.write_str(self.kind.default_reason())
    }
}

impl std::error::Error for DriftError {}

impl From<std::io::Error> for DriftError {
    fn from(error: std::io::Error) -> Self {
        DriftError::io("i/o operation failed", &error)
    }
}

impl DriftErrorKind {
    pub fn default_reason(self) -> &'static str {
        match self {
            DriftErrorKind::InvalidInput => "Invalid input",
            DriftErrorKind::InvalidCode => "Invalid pairing code",
            DriftErrorKind::RendezvousUnavailable => "Rendezvous server unavailable",
            DriftErrorKind::RendezvousRejected => "Rendezvous server rejected the request",
            DriftErrorKind::PeerNotFound => "Peer not found",
            DriftErrorKind::PeerAlreadyClaimed => "Peer has already been claimed",
            DriftErrorKind::LanUnavailable => "LAN discovery unavailable",
            DriftErrorKind::NoNearbyReceivers => "No nearby receivers found",
            DriftErrorKind::ConnectionFailed => "Could not connect to peer",
            DriftErrorKind::ProtocolViolation => "Unexpected protocol message",
            DriftErrorKind::TransferDeclined => "Transfer declined",
            DriftErrorKind::TransferCancelled => "Transfer cancelled",
            DriftErrorKind::TransferFailed => "Transfer failed",
            DriftErrorKind::FileConflict => "File conflict",
            DriftErrorKind::FileNotFound => "File not found",
            DriftErrorKind::PermissionDenied => "Permission denied",
            DriftErrorKind::Io => "I/O error",
            DriftErrorKind::Internal => "Internal error",
        }
    }
}
