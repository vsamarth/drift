use drift_app::{UserFacingError, UserFacingErrorKind};
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum UserFacingErrorKindData {
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserFacingErrorData {
    pub(crate) kind: UserFacingErrorKindData,
    pub(crate) title: String,
    pub(crate) message: String,
    pub(crate) recovery: Option<String>,
    pub(crate) retryable: bool,
}

#[allow(dead_code)]
impl UserFacingErrorData {
    pub(crate) fn kind(&self) -> UserFacingErrorKindData {
        self.kind
    }

    pub(crate) fn title(&self) -> &str {
        &self.title
    }

    pub(crate) fn message(&self) -> &str {
        &self.message
    }

    pub(crate) fn recovery(&self) -> Option<&str> {
        self.recovery.as_deref()
    }

    pub(crate) fn is_retryable(&self) -> bool {
        self.retryable
    }
}

impl From<UserFacingErrorKind> for UserFacingErrorKindData {
    fn from(kind: UserFacingErrorKind) -> Self {
        match kind {
            UserFacingErrorKind::InvalidInput => Self::InvalidInput,
            UserFacingErrorKind::PairingUnavailable => Self::PairingUnavailable,
            UserFacingErrorKind::PeerDeclined => Self::PeerDeclined,
            UserFacingErrorKind::NetworkUnavailable => Self::NetworkUnavailable,
            UserFacingErrorKind::ConnectionLost => Self::ConnectionLost,
            UserFacingErrorKind::PermissionDenied => Self::PermissionDenied,
            UserFacingErrorKind::FileConflict => Self::FileConflict,
            UserFacingErrorKind::ProtocolIncompatible => Self::ProtocolIncompatible,
            UserFacingErrorKind::Cancelled => Self::Cancelled,
            UserFacingErrorKind::Internal => Self::Internal,
        }
    }
}

impl From<UserFacingError> for UserFacingErrorData {
    fn from(error: UserFacingError) -> Self {
        Self {
            kind: error.kind().into(),
            title: error.title().to_owned(),
            message: error.message().to_owned(),
            recovery: error.recovery().map(str::to_owned),
            retryable: error.is_retryable(),
        }
    }
}

pub(crate) fn map_user_facing_error(error: UserFacingError) -> UserFacingErrorData {
    error.into()
}

pub(crate) fn map_optional_user_facing_error(
    error: Option<UserFacingError>,
) -> Option<UserFacingErrorData> {
    error.map(map_user_facing_error)
}

pub(crate) fn internal_user_facing_error(
    title: impl Into<String>,
    message: impl Into<String>,
) -> UserFacingErrorData {
    UserFacingErrorData::from(UserFacingError::internal(title.into(), message.into()))
}

impl From<UserFacingErrorData> for String {
    fn from(error: UserFacingErrorData) -> Self {
        #[derive(Serialize)]
        struct BridgeErrorPayload<'a> {
            kind: UserFacingErrorKindData,
            title: &'a str,
            message: &'a str,
            recovery: Option<&'a str>,
            retryable: bool,
        }

        serde_json::to_string(&BridgeErrorPayload {
            kind: error.kind,
            title: &error.title,
            message: &error.message,
            recovery: error.recovery.as_deref(),
            retryable: error.retryable,
        })
        .unwrap_or_else(|_| error.message)
    }
}
