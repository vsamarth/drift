use std::borrow::Cow;
use std::error::Error as StdError;
use std::fmt;
use std::io;

use anyhow::Error as AnyhowError;
use drift_core::blobs::BlobError;
use drift_core::discovery::DiscoveryError;
use drift_core::fs_plan::error::FsPlanError;
use drift_core::lan::LanError;
use drift_core::protocol::ProtocolError;
use drift_core::rendezvous::RendezvousError;
use drift_core::transfer::error::TransferError;
use drift_core::transfer::path::TransferPathError;
use drift_core::util::TicketError;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserFacingErrorKind {
    InvalidInput,
    PairingUnavailable,
    PeerDeclined,
    NetworkUnavailable,
    ConnectionLost,
    PermissionDenied,
    FileConflict,
    ProtocolIncompatible,
    Cancelled,
    Internal,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum AppError {
    #[error("receiver setup has not been completed")]
    ReceiverSetupIncomplete,
    #[error("no pending offer")]
    NoPendingOffer,
    #[error("offer is no longer active")]
    OfferNoLongerActive,
    #[error("no active transfer")]
    NoActiveTransfer,
    #[error("unsupported local operation: {operation}")]
    UnsupportedLocalOperation { operation: &'static str },
    #[error("receiver unavailable while {action}")]
    ReceiverUnavailable { action: &'static str },
    #[error("receiver snapshot channel closed")]
    SnapshotChannelClosed,
}

pub type AppResult<T> = std::result::Result<T, AppError>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserFacingError {
    kind: UserFacingErrorKind,
    title: Cow<'static, str>,
    message: Cow<'static, str>,
    recovery: Option<Cow<'static, str>>,
    retryable: bool,
}

impl UserFacingError {
    pub fn new(
        kind: UserFacingErrorKind,
        title: impl Into<Cow<'static, str>>,
        message: impl Into<Cow<'static, str>>,
    ) -> Self {
        Self {
            kind,
            title: title.into(),
            message: message.into(),
            recovery: None,
            retryable: false,
        }
    }

    pub fn with_recovery(
        kind: UserFacingErrorKind,
        title: impl Into<Cow<'static, str>>,
        message: impl Into<Cow<'static, str>>,
        recovery: impl Into<Cow<'static, str>>,
        retryable: bool,
    ) -> Self {
        Self {
            kind,
            title: title.into(),
            message: message.into(),
            recovery: Some(recovery.into()),
            retryable,
        }
    }

    pub fn internal(
        title: impl Into<Cow<'static, str>>,
        message: impl Into<Cow<'static, str>>,
    ) -> Self {
        Self::new(UserFacingErrorKind::Internal, title, message)
    }

    pub fn kind(&self) -> UserFacingErrorKind {
        self.kind
    }

    pub fn title(&self) -> &str {
        &self.title
    }

    pub fn message(&self) -> &str {
        &self.message
    }

    pub fn recovery(&self) -> Option<&str> {
        self.recovery.as_deref()
    }

    pub fn is_retryable(&self) -> bool {
        self.retryable
    }

    fn from_kind(kind: UserFacingErrorKind) -> Self {
        match kind {
            UserFacingErrorKind::InvalidInput => Self::new(
                kind,
                "Invalid input",
                "Check the values you entered and try again.",
            ),
            UserFacingErrorKind::PairingUnavailable => Self::new(
                kind,
                "Pairing unavailable",
                "That pairing code is no longer available.",
            ),
            UserFacingErrorKind::PeerDeclined => Self::new(
                kind,
                "Transfer declined",
                "The other device declined the transfer.",
            ),
            UserFacingErrorKind::NetworkUnavailable => Self::with_recovery(
                kind,
                "Network unavailable",
                "Drift could not reach the other device or server.",
                "Check your connection and try again.",
                true,
            ),
            UserFacingErrorKind::ConnectionLost => Self::with_recovery(
                kind,
                "Connection lost",
                "The connection was interrupted.",
                "Reconnect and try again.",
                true,
            ),
            UserFacingErrorKind::PermissionDenied => Self::new(
                kind,
                "Permission denied",
                "Drift does not have permission to complete that action.",
            ),
            UserFacingErrorKind::FileConflict => Self::new(
                kind,
                "File conflict",
                "A file with the same name already exists.",
            ),
            UserFacingErrorKind::ProtocolIncompatible => Self::with_recovery(
                kind,
                "Protocol mismatch",
                "The devices could not agree on how to complete the transfer.",
                "Update Drift on both devices and try again.",
                false,
            ),
            UserFacingErrorKind::Cancelled => {
                Self::new(kind, "Transfer cancelled", "The transfer was cancelled.")
            }
            UserFacingErrorKind::Internal => {
                Self::internal("Something went wrong", "Please try again.")
            }
        }
    }
}

impl From<AppError> for UserFacingError {
    fn from(error: AppError) -> Self {
        match error {
            AppError::ReceiverSetupIncomplete => UserFacingError::new(
                UserFacingErrorKind::Internal,
                "Receiver not ready",
                "Open the receiver setup before trying that again.",
            ),
            AppError::NoPendingOffer => UserFacingError::new(
                UserFacingErrorKind::Internal,
                "No pending offer",
                "There is no pending offer to respond to.",
            ),
            AppError::OfferNoLongerActive => UserFacingError::new(
                UserFacingErrorKind::Internal,
                "Offer no longer active",
                "That offer is no longer active.",
            ),
            AppError::NoActiveTransfer => UserFacingError::new(
                UserFacingErrorKind::Internal,
                "No active transfer",
                "There is no active transfer to cancel.",
            ),
            AppError::UnsupportedLocalOperation { operation } => UserFacingError::new(
                UserFacingErrorKind::Internal,
                "Unsupported operation",
                format!("Drift does not support {operation} yet."),
            ),
            AppError::ReceiverUnavailable { .. } | AppError::SnapshotChannelClosed => {
                UserFacingError::new(
                    UserFacingErrorKind::Internal,
                    "Receiver unavailable",
                    "The receiver is not available right now.",
                )
            }
        }
    }
}

impl fmt::Display for UserFacingError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.title())
    }
}

impl StdError for UserFacingError {}

impl From<RendezvousError> for UserFacingError {
    fn from(error: RendezvousError) -> Self {
        match error {
            RendezvousError::InvalidCode { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
            RendezvousError::Request { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable)
            }
            RendezvousError::ResponseParse { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
            RendezvousError::Api { status, .. } => map_rendezvous_api_status(status.as_u16()),
        }
    }
}

impl From<DiscoveryError> for UserFacingError {
    fn from(error: DiscoveryError) -> Self {
        match error {
            DiscoveryError::Rendezvous(error) => error.into(),
            DiscoveryError::Ticket(error) => error.into(),
            DiscoveryError::NearbyTask { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
            DiscoveryError::NearbyBrowse(error) => error.into(),
        }
    }
}

impl From<TicketError> for UserFacingError {
    fn from(error: TicketError) -> Self {
        match error {
            TicketError::Serialize { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
            TicketError::DecodeBase64 { .. }
            | TicketError::InvalidPayload
            | TicketError::ParseNodeId { .. }
            | TicketError::ParseRelayUrl { .. }
            | TicketError::ParseSocketAddr { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
        }
    }
}

impl From<LanError> for UserFacingError {
    fn from(error: LanError) -> Self {
        match error {
            LanError::NoUsableIpv4Address => {
                UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable)
            }
            LanError::Mdns { source, .. } => map_network_io_error(source.as_ref()),
            LanError::Io { source, .. } => map_network_io_error(&source),
            LanError::SpawnPresenceThread { source } => map_network_io_error(&source),
            LanError::PresenceUnexpectedReply | LanError::PresenceInvalidPong => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
        }
    }
}

impl From<FsPlanError> for UserFacingError {
    fn from(error: FsPlanError) -> Self {
        match error {
            FsPlanError::EmptySelection | FsPlanError::NoRegularFiles => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
            FsPlanError::FileCountOverflow | FsPlanError::TotalSizeOverflow => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
            FsPlanError::ReadMetadata { source, .. }
            | FsPlanError::ReadDirectory { source, .. }
            | FsPlanError::CurrentDirectory { source } => map_local_io_error(&source),
            FsPlanError::SymbolicLink { .. }
            | FsPlanError::UnsupportedFileType { .. }
            | FsPlanError::InvalidUtf8PathComponent { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
            FsPlanError::DuplicateTransferPath { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
            }
            FsPlanError::TransferPath(error) => error.into(),
        }
    }
}

impl From<TransferPathError> for UserFacingError {
    fn from(error: TransferPathError) -> Self {
        match error {
            TransferPathError::Empty
            | TransferPathError::InvalidSeparator
            | TransferPathError::NotRelative
            | TransferPathError::InvalidSegment
            | TransferPathError::InvalidUtf8RootName { .. }
            | TransferPathError::InvalidUtf8PathComponent { .. }
            | TransferPathError::OutputNotAbsolute { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
            TransferPathError::DestinationExists { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
            }
            TransferPathError::DestinationParentNotDirectory { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
            TransferPathError::CheckPath { source, .. }
            | TransferPathError::CurrentDirectory { source }
            | TransferPathError::CreateScratchDir { source, .. } => map_local_io_error(&source),
            TransferPathError::SystemClockBeforeUnixEpoch { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
        }
    }
}

impl From<ProtocolError> for UserFacingError {
    fn from(error: ProtocolError) -> Self {
        match error {
            ProtocolError::UnsupportedVersion { .. } => UserFacingError::with_recovery(
                UserFacingErrorKind::ProtocolIncompatible,
                "Protocol mismatch",
                "This version of Drift cannot complete the transfer.",
                "Update Drift on both devices and try again.",
                false,
            ),
            ProtocolError::UnexpectedRole { .. }
            | ProtocolError::UnexpectedMessageKind { .. }
            | ProtocolError::SessionIdMismatch { .. }
            | ProtocolError::EmptyDeviceName { .. }
            | ProtocolError::InvalidTransition { .. }
            | ProtocolError::MissingPeerIdentity { .. }
            | ProtocolError::MessageTooLarge { .. }
            | ProtocolError::FrameRead { .. }
            | ProtocolError::FrameWrite { .. }
            | ProtocolError::MessageSerialize { .. }
            | ProtocolError::MessageDeserialize { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::ProtocolIncompatible)
            }
        }
    }
}

impl From<TransferError> for UserFacingError {
    fn from(error: TransferError) -> Self {
        match error {
            TransferError::Protocol(error) => error.into(),
            TransferError::Blob(error) => error.into(),
            TransferError::ConnectionClosed { .. } | TransferError::Timeout { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::ConnectionLost)
            }
            TransferError::ChannelClosed { .. } | TransferError::Other { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
        }
    }
}

impl From<BlobError> for UserFacingError {
    fn from(error: BlobError) -> Self {
        match error {
            BlobError::DuplicateTransferPath { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
            }
            BlobError::Connect { source, .. } | BlobError::Fetch { source, .. } => {
                map_network_io_error(source.as_ref())
            }
            BlobError::StoreLoad { source, .. }
            | BlobError::StoreShutdown { source, .. }
            | BlobError::StoreCollection { source }
            | BlobError::ImportFiles { source, .. }
            | BlobError::ScratchDirCreate { source, .. } => map_local_io_error(source.as_ref()),
            BlobError::StoreStillShared | BlobError::JoinDownloadTask { .. } => {
                UserFacingError::from_kind(UserFacingErrorKind::Internal)
            }
        }
    }
}

fn map_rendezvous_api_status(status: u16) -> UserFacingError {
    match status {
        400 => UserFacingError::from_kind(UserFacingErrorKind::InvalidInput),
        401 | 403 => UserFacingError::from_kind(UserFacingErrorKind::PermissionDenied),
        404 | 409 => UserFacingError::from_kind(UserFacingErrorKind::PairingUnavailable),
        429 => UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable),
        500..=599 => UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable),
        401..=499 => UserFacingError::from_kind(UserFacingErrorKind::InvalidInput),
        _ => UserFacingError::from_kind(UserFacingErrorKind::Internal),
    }
}

fn map_network_io_error(error: &(dyn StdError + 'static)) -> UserFacingError {
    if let Some(io_error) = error.downcast_ref::<io::Error>() {
        return map_io_kind(io_error.kind());
    }

    UserFacingError::from_kind(UserFacingErrorKind::Internal)
}

fn map_local_io_error(error: &(dyn StdError + 'static)) -> UserFacingError {
    if let Some(io_error) = error.downcast_ref::<io::Error>() {
        return match io_error.kind() {
            io::ErrorKind::PermissionDenied => {
                UserFacingError::from_kind(UserFacingErrorKind::PermissionDenied)
            }
            io::ErrorKind::NotFound | io::ErrorKind::InvalidInput => {
                UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
            }
            _ => UserFacingError::from_kind(UserFacingErrorKind::Internal),
        };
    }

    UserFacingError::from_kind(UserFacingErrorKind::Internal)
}

fn map_io_kind(kind: io::ErrorKind) -> UserFacingError {
    match kind {
        io::ErrorKind::PermissionDenied => {
            UserFacingError::from_kind(UserFacingErrorKind::PermissionDenied)
        }
        io::ErrorKind::ConnectionAborted
        | io::ErrorKind::ConnectionRefused
        | io::ErrorKind::ConnectionReset
        | io::ErrorKind::BrokenPipe
        | io::ErrorKind::TimedOut
        | io::ErrorKind::UnexpectedEof
        | io::ErrorKind::NotConnected => {
            UserFacingError::from_kind(UserFacingErrorKind::ConnectionLost)
        }
        io::ErrorKind::NotFound | io::ErrorKind::InvalidInput => {
            UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
        }
        _ => UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable),
    }
}

pub fn format_error_chain(error: &anyhow::Error) -> String {
    error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ")
}

pub fn from_anyhow_error(error: &AnyhowError) -> UserFacingError {
    for cause in error.chain() {
        if let Some(app_error) = cause.downcast_ref::<AppError>() {
            return UserFacingError::from(app_error.clone());
        }
        if let Some(core_error) = cause.downcast_ref::<RendezvousError>() {
            return match core_error {
                RendezvousError::InvalidCode { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                }
                RendezvousError::Request { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable)
                }
                RendezvousError::ResponseParse { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
                RendezvousError::Api { status, .. } => map_rendezvous_api_status(status.as_u16()),
            };
        }
        if let Some(core_error) = cause.downcast_ref::<DiscoveryError>() {
            return match core_error {
                DiscoveryError::Rendezvous(error) => match error {
                    RendezvousError::InvalidCode { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                    }
                    RendezvousError::Request { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable)
                    }
                    RendezvousError::ResponseParse { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::Internal)
                    }
                    RendezvousError::Api { status, .. } => {
                        map_rendezvous_api_status(status.as_u16())
                    }
                },
                DiscoveryError::Ticket(error) => match error {
                    TicketError::Serialize { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::Internal)
                    }
                    TicketError::DecodeBase64 { .. }
                    | TicketError::InvalidPayload
                    | TicketError::ParseNodeId { .. }
                    | TicketError::ParseRelayUrl { .. }
                    | TicketError::ParseSocketAddr { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                    }
                },
                DiscoveryError::NearbyTask { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
                DiscoveryError::NearbyBrowse(error) => match error {
                    LanError::NoUsableIpv4Address => {
                        UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable)
                    }
                    LanError::Mdns { source, .. } => map_network_io_error(source.as_ref()),
                    LanError::Io { source, .. } => map_network_io_error(source),
                    LanError::SpawnPresenceThread { source } => map_network_io_error(source),
                    LanError::PresenceUnexpectedReply | LanError::PresenceInvalidPong => {
                        UserFacingError::from_kind(UserFacingErrorKind::Internal)
                    }
                },
            };
        }
        if let Some(core_error) = cause.downcast_ref::<TicketError>() {
            return match core_error {
                TicketError::Serialize { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
                TicketError::DecodeBase64 { .. }
                | TicketError::InvalidPayload
                | TicketError::ParseNodeId { .. }
                | TicketError::ParseRelayUrl { .. }
                | TicketError::ParseSocketAddr { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                }
            };
        }
        if let Some(core_error) = cause.downcast_ref::<LanError>() {
            return match core_error {
                LanError::NoUsableIpv4Address => {
                    UserFacingError::from_kind(UserFacingErrorKind::NetworkUnavailable)
                }
                LanError::Mdns { source, .. } => map_network_io_error(source.as_ref()),
                LanError::Io { source, .. } => map_network_io_error(source),
                LanError::SpawnPresenceThread { source } => map_network_io_error(source),
                LanError::PresenceUnexpectedReply | LanError::PresenceInvalidPong => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
            };
        }
        if let Some(core_error) = cause.downcast_ref::<FsPlanError>() {
            return match core_error {
                FsPlanError::EmptySelection | FsPlanError::NoRegularFiles => {
                    UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                }
                FsPlanError::FileCountOverflow | FsPlanError::TotalSizeOverflow => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
                FsPlanError::ReadMetadata { source, .. }
                | FsPlanError::ReadDirectory { source, .. }
                | FsPlanError::CurrentDirectory { source } => map_local_io_error(source),
                FsPlanError::SymbolicLink { .. }
                | FsPlanError::UnsupportedFileType { .. }
                | FsPlanError::InvalidUtf8PathComponent { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                }
                FsPlanError::DuplicateTransferPath { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
                }
                FsPlanError::TransferPath(error) => match error {
                    TransferPathError::Empty
                    | TransferPathError::InvalidSeparator
                    | TransferPathError::NotRelative
                    | TransferPathError::InvalidSegment
                    | TransferPathError::InvalidUtf8RootName { .. }
                    | TransferPathError::InvalidUtf8PathComponent { .. }
                    | TransferPathError::OutputNotAbsolute { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                    }
                    TransferPathError::DestinationExists { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
                    }
                    TransferPathError::DestinationParentNotDirectory { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                    }
                    TransferPathError::CheckPath { source, .. }
                    | TransferPathError::CurrentDirectory { source }
                    | TransferPathError::CreateScratchDir { source, .. } => {
                        map_local_io_error(source)
                    }
                    TransferPathError::SystemClockBeforeUnixEpoch { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::Internal)
                    }
                },
            };
        }
        if let Some(core_error) = cause.downcast_ref::<TransferPathError>() {
            return match core_error {
                TransferPathError::Empty
                | TransferPathError::InvalidSeparator
                | TransferPathError::NotRelative
                | TransferPathError::InvalidSegment
                | TransferPathError::InvalidUtf8RootName { .. }
                | TransferPathError::InvalidUtf8PathComponent { .. }
                | TransferPathError::OutputNotAbsolute { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                }
                TransferPathError::DestinationExists { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
                }
                TransferPathError::DestinationParentNotDirectory { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::InvalidInput)
                }
                TransferPathError::CheckPath { source, .. }
                | TransferPathError::CurrentDirectory { source }
                | TransferPathError::CreateScratchDir { source, .. } => map_local_io_error(source),
                TransferPathError::SystemClockBeforeUnixEpoch { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
            };
        }
        if let Some(core_error) = cause.downcast_ref::<ProtocolError>() {
            return match core_error {
                ProtocolError::UnsupportedVersion { .. } => UserFacingError::with_recovery(
                    UserFacingErrorKind::ProtocolIncompatible,
                    "Protocol mismatch",
                    "This version of Drift cannot complete the transfer.",
                    "Update Drift on both devices and try again.",
                    false,
                ),
                ProtocolError::UnexpectedRole { .. }
                | ProtocolError::UnexpectedMessageKind { .. }
                | ProtocolError::SessionIdMismatch { .. }
                | ProtocolError::EmptyDeviceName { .. }
                | ProtocolError::InvalidTransition { .. }
                | ProtocolError::MissingPeerIdentity { .. }
                | ProtocolError::MessageTooLarge { .. }
                | ProtocolError::FrameRead { .. }
                | ProtocolError::FrameWrite { .. }
                | ProtocolError::MessageSerialize { .. }
                | ProtocolError::MessageDeserialize { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::ProtocolIncompatible)
                }
            };
        }
        if let Some(core_error) = cause.downcast_ref::<TransferError>() {
            return match core_error {
                TransferError::Protocol(error) => match error {
                    ProtocolError::UnsupportedVersion { .. } => UserFacingError::with_recovery(
                        UserFacingErrorKind::ProtocolIncompatible,
                        "Protocol mismatch",
                        "This version of Drift cannot complete the transfer.",
                        "Update Drift on both devices and try again.",
                        false,
                    ),
                    ProtocolError::UnexpectedRole { .. }
                    | ProtocolError::UnexpectedMessageKind { .. }
                    | ProtocolError::SessionIdMismatch { .. }
                    | ProtocolError::EmptyDeviceName { .. }
                    | ProtocolError::InvalidTransition { .. }
                    | ProtocolError::MissingPeerIdentity { .. }
                    | ProtocolError::MessageTooLarge { .. }
                    | ProtocolError::FrameRead { .. }
                    | ProtocolError::FrameWrite { .. }
                    | ProtocolError::MessageSerialize { .. }
                    | ProtocolError::MessageDeserialize { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::ProtocolIncompatible)
                    }
                },
                TransferError::Blob(error) => match error {
                    BlobError::DuplicateTransferPath { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
                    }
                    BlobError::Connect { source, .. } | BlobError::Fetch { source, .. } => {
                        map_network_io_error(source.as_ref())
                    }
                    BlobError::StoreLoad { source, .. }
                    | BlobError::StoreShutdown { source, .. }
                    | BlobError::StoreCollection { source }
                    | BlobError::ImportFiles { source, .. }
                    | BlobError::ScratchDirCreate { source, .. } => {
                        map_local_io_error(source.as_ref())
                    }
                    BlobError::StoreStillShared | BlobError::JoinDownloadTask { .. } => {
                        UserFacingError::from_kind(UserFacingErrorKind::Internal)
                    }
                },
                TransferError::ConnectionClosed { .. } | TransferError::Timeout { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::ConnectionLost)
                }
                TransferError::ChannelClosed { .. } | TransferError::Other { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
            };
        }
        if let Some(core_error) = cause.downcast_ref::<BlobError>() {
            return match core_error {
                BlobError::DuplicateTransferPath { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::FileConflict)
                }
                BlobError::Connect { source, .. } | BlobError::Fetch { source, .. } => {
                    map_network_io_error(source.as_ref())
                }
                BlobError::StoreLoad { source, .. }
                | BlobError::StoreShutdown { source, .. }
                | BlobError::StoreCollection { source }
                | BlobError::ImportFiles { source, .. }
                | BlobError::ScratchDirCreate { source, .. } => map_local_io_error(source.as_ref()),
                BlobError::StoreStillShared | BlobError::JoinDownloadTask { .. } => {
                    UserFacingError::from_kind(UserFacingErrorKind::Internal)
                }
            };
        }
    }

    UserFacingError::internal("Transfer failed", format_error_chain(error))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io;

    #[test]
    fn constructor_exposes_expected_accessors() {
        let error = UserFacingError::with_recovery(
            UserFacingErrorKind::NetworkUnavailable,
            "Network unavailable",
            "Please check your connection.",
            "Try again once the device is back online.",
            true,
        );

        assert_eq!(error.kind(), UserFacingErrorKind::NetworkUnavailable);
        assert_eq!(error.title(), "Network unavailable");
        assert_eq!(error.message(), "Please check your connection.");
        assert_eq!(
            error.recovery(),
            Some("Try again once the device is back online.")
        );
        assert!(error.is_retryable());
    }

    #[test]
    fn internal_constructor_uses_internal_kind() {
        let error = UserFacingError::internal("Something went wrong", "Please try again.");

        assert_eq!(error.kind(), UserFacingErrorKind::Internal);
        assert_eq!(error.title(), "Something went wrong");
        assert_eq!(error.message(), "Please try again.");
        assert_eq!(error.recovery(), None);
        assert!(!error.is_retryable());
    }

    #[test]
    fn rendezvous_errors_map_to_stable_kinds() {
        assert_eq!(
            UserFacingError::from(RendezvousError::InvalidCode {
                code_length: 6,
                code_alphabet: "ABC",
            })
            .kind(),
            UserFacingErrorKind::InvalidInput
        );

        assert_eq!(
            map_rendezvous_api_status(404).kind(),
            UserFacingErrorKind::PairingUnavailable
        );
        assert_eq!(
            map_rendezvous_api_status(409).kind(),
            UserFacingErrorKind::PairingUnavailable
        );
        assert_eq!(
            map_rendezvous_api_status(503).kind(),
            UserFacingErrorKind::NetworkUnavailable
        );
    }

    #[test]
    fn core_error_mappings_cover_transfer_and_filesystem_categories() {
        assert_eq!(
            UserFacingError::from(ProtocolError::UnsupportedVersion {
                expected: 2,
                actual: 1,
            })
            .kind(),
            UserFacingErrorKind::ProtocolIncompatible
        );

        assert_eq!(
            UserFacingError::from(TransferError::ConnectionClosed { context: "waiting" }).kind(),
            UserFacingErrorKind::ConnectionLost
        );

        assert_eq!(
            UserFacingError::from(FsPlanError::DuplicateTransferPath {
                path: "a.txt".to_owned(),
            })
            .kind(),
            UserFacingErrorKind::FileConflict
        );

        assert_eq!(
            UserFacingError::from(TransferPathError::DestinationExists {
                path: "/tmp/a.txt".into(),
            })
            .kind(),
            UserFacingErrorKind::FileConflict
        );
    }

    #[test]
    fn permission_denied_is_preserved_when_available() {
        let error = FsPlanError::ReadDirectory {
            path: "/tmp".into(),
            source: io::Error::new(io::ErrorKind::PermissionDenied, "permission denied"),
        };

        assert_eq!(
            UserFacingError::from(error).kind(),
            UserFacingErrorKind::PermissionDenied
        );
    }

    #[test]
    fn app_errors_map_to_internal_user_facing_errors() {
        assert_eq!(
            UserFacingError::from(AppError::NoPendingOffer).kind(),
            UserFacingErrorKind::Internal
        );
        assert_eq!(
            UserFacingError::from(AppError::UnsupportedLocalOperation {
                operation: "receiver overwrite policy",
            })
            .kind(),
            UserFacingErrorKind::Internal
        );
    }

    #[test]
    fn anyhow_errors_keep_core_classification_when_available() {
        let error = AnyhowError::new(RendezvousError::Api {
            status: reqwest::StatusCode::NOT_FOUND,
            message: None,
        });

        assert_eq!(
            from_anyhow_error(&error).kind(),
            UserFacingErrorKind::PairingUnavailable
        );
    }
}
