use std::path::PathBuf;

use thiserror::Error;

use crate::transfer::path::TransferPathError;

#[derive(Debug, Error)]
pub enum FsPlanError {
    #[error("provide at least one file to send")]
    EmptySelection,
    #[error("no regular files found to send")]
    NoRegularFiles,
    #[error("total transfer file count exceeds u64")]
    FileCountOverflow,
    #[error("total transfer size exceeds u64")]
    TotalSizeOverflow,
    #[error("reading metadata for {path}")]
    ReadMetadata {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("reading directory {path}")]
    ReadDirectory {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("{path} is a symbolic link; only regular files are supported")]
    SymbolicLink { path: PathBuf },
    #[error("{path} is not a regular file or directory")]
    UnsupportedFileType { path: PathBuf },
    #[error("{path} contains a path component that is not valid UTF-8")]
    InvalidUtf8PathComponent { path: PathBuf },
    #[error("duplicate transfer path {path}")]
    DuplicateTransferPath { path: String },
    #[error("resolving current directory")]
    CurrentDirectory {
        #[source]
        source: std::io::Error,
    },
    #[error(transparent)]
    TransferPath(#[from] TransferPathError),
}
