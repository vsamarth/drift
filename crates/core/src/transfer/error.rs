use std::error::Error as StdError;
use thiserror::Error;

use crate::{
    blobs::error::BlobError,
    protocol::{error::ProtocolError, message::TransferErrorCode},
    transfer::{path::TransferPathError, types::TransferPlanError},
};

#[derive(Debug, Error)]
pub enum TransferError {
    #[error(transparent)]
    Protocol(#[from] ProtocolError),
    #[error(transparent)]
    Blob(#[from] BlobError),
    #[error(transparent)]
    Path(#[from] TransferPathError),
    #[error(transparent)]
    Plan(#[from] TransferPlanError),
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
        source: Box<dyn StdError + Send + Sync>,
    },
}

pub(crate) type Result<T> = std::result::Result<T, TransferError>;

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

    pub(crate) fn other(
        context: &'static str,
        source: impl StdError + Send + Sync + 'static,
    ) -> Self {
        Self::Other {
            context,
            source: Box::new(source),
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
            Self::Path(error) => match error {
                TransferPathError::DestinationExists { .. } => TransferErrorCode::FileConflict,
                TransferPathError::Empty
                | TransferPathError::InvalidSeparator
                | TransferPathError::NotRelative
                | TransferPathError::InvalidSegment
                | TransferPathError::InvalidUtf8RootName { .. }
                | TransferPathError::InvalidUtf8PathComponent { .. }
                | TransferPathError::DestinationParentNotDirectory { .. }
                | TransferPathError::CheckPath { .. }
                | TransferPathError::CurrentDirectory { .. }
                | TransferPathError::OutputNotAbsolute { .. }
                | TransferPathError::SystemClockBeforeUnixEpoch { .. }
                | TransferPathError::CreateScratchDir { .. } => TransferErrorCode::IoError,
            },
            Self::Plan(_) => TransferErrorCode::IoError,
            Self::ConnectionClosed { .. }
            | Self::Timeout { .. }
            | Self::ChannelClosed { .. }
            | Self::Other { .. } => TransferErrorCode::IoError,
        }
    }
}
