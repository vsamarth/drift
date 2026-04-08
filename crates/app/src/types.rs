use std::path::PathBuf;

pub use drift_core::fs_plan::ConflictPolicy;
pub use drift_core::transfer_flow::{TransferPlan, TransferSnapshot};
use iroh::SecretKey;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendPhase {
    Connecting,
    WaitingForDecision,
    Accepted,
    Declined,
    Sending,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendConfig {
    pub device_name: String,
    pub device_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendEvent {
    pub phase: SendPhase,
    pub destination_label: String,
    pub status_message: String,
    pub item_count: u64,
    pub total_size: u64,
    pub bytes_sent: u64,
    pub plan: Option<TransferPlan>,
    pub snapshot: Option<TransferSnapshot>,
    pub remote_device_type: Option<String>,
    pub connection_path: Option<String>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NearbyReceiver {
    pub fullname: String,
    pub label: String,
    pub code: String,
    pub ticket: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverRegistration {
    pub code: String,
    pub expires_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairingCodeState {
    Unavailable,
    Active(ReceiverRegistration),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReceiverOfferPhase {
    Connecting,
    OfferReady,
    Receiving,
    Completed,
    Cancelled,
    Failed,
    Declined,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverOfferFile {
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverOfferEvent {
    pub phase: ReceiverOfferPhase,
    pub sender_name: String,
    pub sender_device_type: String,
    pub destination_label: String,
    pub save_root_label: String,
    pub status_message: String,
    pub item_count: u64,
    pub total_size_bytes: u64,
    pub bytes_received: u64,
    pub plan: Option<TransferPlan>,
    pub snapshot: Option<TransferSnapshot>,
    pub connection_path: Option<String>,
    pub total_size_label: String,
    pub files: Vec<ReceiverOfferFile>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ReceiverConfig {
    pub device_name: String,
    pub device_type: String,
    pub download_root: PathBuf,
    pub conflict_policy: ConflictPolicy,
    pub secret_key: SecretKey,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionPreview {
    pub items: Vec<SelectionItem>,
    pub file_count: u64,
    pub total_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionChange {
    pub paths: Vec<PathBuf>,
    pub added_count: u64,
    pub removed_count: u64,
    pub changed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionItem {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub file_count: u64,
    pub total_size: u64,
}
