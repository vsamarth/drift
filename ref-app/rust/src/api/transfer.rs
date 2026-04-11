#[derive(Debug, Clone)]
pub enum TransferPhaseData {
    Connecting,
    AwaitingAcceptance,
    Transferring,
    Finalizing,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone)]
pub struct TransferPlanFileData {
    pub id: u32,
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone)]
pub struct TransferPlanData {
    pub session_id: String,
    pub total_files: u32,
    pub total_bytes: u64,
    pub files: Vec<TransferPlanFileData>,
}

#[derive(Debug, Clone)]
pub struct TransferSnapshotData {
    pub session_id: String,
    pub phase: TransferPhaseData,
    pub total_files: u32,
    pub completed_files: u32,
    pub total_bytes: u64,
    pub bytes_transferred: u64,
    pub active_file_id: Option<u32>,
    pub active_file_bytes: Option<u64>,
    pub bytes_per_sec: Option<u64>,
    pub eta_seconds: Option<u64>,
}
