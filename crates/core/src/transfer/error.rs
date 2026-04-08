use std::error::Error as StdError;
use std::fmt;

use thiserror::Error;

use crate::{
    blobs::error::BlobError, protocol::error::ProtocolError, protocol::message::TransferErrorCode,
};

#[derive(Debug, Error)]
pub enum TransferError {
    #[error(transparent)]
    Protocol(#[from] ProtocolError),
    #[error(transparent)]
    Blob(#[from] BlobError),
    #[error("connection closed while {context}")]
    ConnectionClosed { context: &'static str },
    #[error("timed out while {context}")]
    Timeout { context: &'static str },
    #[error("channel closed while {context}")]
    ChannelClosed { context: &'static str },
    #[error("{context}: {source}")]
    Other {
        context: &'static str,
        #[source]
        source: TransferTextError,
    },
}

pub(crate) type Result<T> = std::result::Result<T, TransferError>;

#[derive(Debug)]
pub struct TransferTextError(String);

impl TransferTextError {
    pub(crate) fn new(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

impl fmt::Display for TransferTextError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl StdError for TransferTextError {}

impl TransferError {
    pub(crate) fn connection_closed(context: &'static str) -> Self {
        Self::ConnectionClosed { context }
    }

    pub(crate) fn timeout(context: &'static str) -> Self {
        Self::Timeout { context }
    }

    pub(crate) fn channel_closed(context: &'static str) -> Self {
        Self::ChannelClosed { context }
    }

    pub(crate) fn other(context: &'static str, source: impl Into<String>) -> Self {
        Self::Other {
            context,
            source: TransferTextError::new(source),
        }
    }

    pub(crate) fn code(&self) -> TransferErrorCode {
        match self {
            Self::Protocol(error) => error.code(),
            Self::Blob(error) => match error {
                BlobError::DuplicateTransferPath { .. } => TransferErrorCode::FileConflict,
                BlobError::StoreLoad { .. }
                | BlobError::StoreShutdown { .. }
                | BlobError::StoreStillShared
                | BlobError::Connect { .. }
                | BlobError::Fetch { .. }
                | BlobError::StoreCollection { .. }
                | BlobError::ImportFiles { .. }
                | BlobError::ScratchDirCreate { .. }
                | BlobError::JoinDownloadTask { .. } => TransferErrorCode::IoError,
            },
            Self::ConnectionClosed { .. }
            | Self::Timeout { .. }
            | Self::ChannelClosed { .. }
            | Self::Other { .. } => TransferErrorCode::IoError,
        }
    }
}
