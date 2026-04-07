pub mod receive;
pub mod send;
mod util;

use std::path::PathBuf;

use crate::fs_plan::prepare::{PreparedFile, PreparedFiles};
use anyhow::{Result, anyhow};
use tokio::sync::watch;

use crate::rendezvous::OfferManifest;
use crate::util::ConnectionPathKind;
use crate::protocol::DeviceType;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendManifestFile {
    pub source_path: PathBuf,
    pub transfer_path: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendManifest {
    pub files: Vec<SendManifestFile>,
    pub file_count: u64,
    pub total_size: u64,
}

impl SendManifest {
    pub fn new(files: Vec<SendManifestFile>) -> Result<Self> {
        if files.is_empty() {
            return Err(anyhow!("provide at least one file to send"));
        }

        let mut total_size = 0_u64;
        for file in &files {
            total_size = total_size
                .checked_add(file.size)
                .ok_or_else(|| anyhow!("total transfer size exceeds u64"))?;
        }

        Ok(Self {
            file_count: files.len() as u64,
            total_size,
            files,
        })
    }
}

impl From<PreparedFiles> for SendManifest {
    fn from(value: PreparedFiles) -> Self {
        let files = value
            .files
            .into_iter()
            .map(|file| SendManifestFile::from(file))
            .collect::<Vec<_>>();

        Self {
            file_count: value.manifest.file_count,
            total_size: value.manifest.total_size,
            files,
        }
    }
}

impl From<PreparedFile> for SendManifestFile {
    fn from(value: PreparedFile) -> Self {
        Self {
            source_path: value.source_path,
            transfer_path: value.transfer_path,
            size: value.size,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerTarget {
    pub destination_label: String,
    pub session_id: String,
    pub remote_device_name: Option<String>,
    pub remote_device_type: Option<DeviceType>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceivePlan {
    pub session_id: String,
    pub out_dir: PathBuf,
    pub manifest: OfferManifest,
}

#[derive(Debug)]
pub struct SendRequest {
    pub peer: PeerTarget,
    pub manifest: SendManifest,
    pub cancel_rx: Option<watch::Receiver<bool>>,
}

#[derive(Debug)]
pub struct ReceiveRequest {
    pub peer: PeerTarget,
    pub plan: ReceivePlan,
    pub cancel_rx: Option<watch::Receiver<bool>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferPhase {
    Starting,
    Handshaking,
    Transferring,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendProgress {
    pub phase: TransferPhase,
    pub destination_label: String,
    pub manifest: SendManifest,
    pub bytes_sent: u64,
    pub current_file_index: Option<u64>,
    pub bytes_sent_in_file: u64,
    pub connection_path_kind: Option<ConnectionPathKind>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveProgress {
    pub phase: TransferPhase,
    pub sender_device_name: String,
    pub sender_device_type: Option<DeviceType>,
    pub manifest: OfferManifest,
    pub bytes_received: u64,
    pub current_file_path: Option<String>,
    pub bytes_received_in_file: u64,
    pub current_file_size: u64,
    pub connection_path_kind: Option<ConnectionPathKind>,
    pub error_message: Option<String>,
}
