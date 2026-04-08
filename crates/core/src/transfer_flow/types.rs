use crate::protocol::message::{Cancel, CancelPhase, ManifestItem, TransferManifest, TransferRole};
use anyhow::{Result, bail};
use serde::{Deserialize, Serialize};
use tokio::sync::watch;

pub type TransferFileId = u32;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransferPlanFile {
    pub id: TransferFileId,
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransferPlan {
    pub session_id: String,
    pub total_files: u32,
    pub total_bytes: u64,
    pub files: Vec<TransferPlanFile>,
}

impl TransferPlan {
    pub fn try_new(session_id: impl Into<String>, files: Vec<TransferPlanFile>) -> Result<Self> {
        let session_id = session_id.into();
        for (expected_id, file) in files.iter().enumerate() {
            let expected_id = u32::try_from(expected_id).map_err(|_| anyhow::anyhow!("too many files"))?;
            if file.id != expected_id {
                bail!(
                    "transfer file ids must be contiguous and ordered from 0..n-1 (expected {}, got {})",
                    expected_id,
                    file.id
                );
            }
        }
        let total_files = u32::try_from(files.len()).map_err(|_| anyhow::anyhow!("too many files"))?;
        let total_bytes = files.iter().try_fold(0_u64, |acc, file| {
            acc.checked_add(file.size)
                .ok_or_else(|| anyhow::anyhow!("total transfer size exceeds u64"))
        })?;
        Ok(Self {
            session_id,
            total_files,
            total_bytes,
            files,
        })
    }

    pub fn from_manifest(session_id: impl Into<String>, manifest: &TransferManifest) -> Result<Self> {
        let files = manifest
            .items
            .iter()
            .enumerate()
            .map(|(index, item)| match item {
                ManifestItem::File { path, size } => {
                    Ok(TransferPlanFile {
                        id: u32::try_from(index).map_err(|_| anyhow::anyhow!("too many files"))?,
                        path: path.clone(),
                        size: *size,
                    })
                }
            })
            .collect::<Result<Vec<_>>>()?;
        Self::try_new(session_id, files)
    }

    pub fn file(&self, id: TransferFileId) -> Option<&TransferPlanFile> {
        self.files.iter().find(|file| file.id == id)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TransferPhase {
    Connecting,
    AwaitingAcceptance,
    Transferring,
    Finalizing,
    Completed,
    Cancelled,
    Failed,
}

impl TransferPhase {
    pub fn is_terminal(self) -> bool {
        matches!(self, Self::Completed | Self::Cancelled | Self::Failed)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransferSnapshot {
    pub session_id: String,
    pub phase: TransferPhase,
    pub total_files: u32,
    pub completed_files: u32,
    pub total_bytes: u64,
    pub bytes_transferred: u64,
    pub active_file_id: Option<TransferFileId>,
    pub active_file_bytes: Option<u64>,
    pub bytes_per_sec: Option<u64>,
    pub eta_seconds: Option<u64>,
}

impl TransferSnapshot {
    pub fn is_terminal(&self) -> bool {
        self.phase.is_terminal()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FileLifecycleState {
    Pending,
    Active,
    Completed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileStateUpdate {
    pub session_id: String,
    pub file_id: TransferFileId,
    pub state: FileLifecycleState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransferCancellation {
    pub by: TransferRole,
    pub phase: CancelPhase,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransferOutcome {
    Completed,
    Declined { reason: String },
    Cancelled(TransferCancellation),
}

impl TransferOutcome {
    pub fn local_cancel(by: TransferRole, phase: CancelPhase) -> Self {
        let reason = match (by, phase) {
            (TransferRole::Sender, CancelPhase::WaitingForDecision) => {
                "sender cancelled before approval".to_owned()
            }
            (TransferRole::Sender, CancelPhase::Transferring) => {
                "sender cancelled transfer".to_owned()
            }
            (TransferRole::Receiver, CancelPhase::WaitingForDecision) => {
                "receiver cancelled before approval".to_owned()
            }
            (TransferRole::Receiver, CancelPhase::Transferring) => {
                "receiver cancelled transfer".to_owned()
            }
        };
        Self::Cancelled(TransferCancellation { by, phase, reason })
    }

    pub fn from_remote_cancel(cancel: Cancel, expected_session_id: &str) -> Result<Self> {
        if !expected_session_id.is_empty() && cancel.session_id != expected_session_id {
            bail!("session id mismatch in cancel message");
        }
        Ok(Self::Cancelled(TransferCancellation {
            by: cancel.by,
            phase: cancel.phase,
            reason: cancel.reason,
        }))
    }
}

pub async fn wait_for_cancel(cancel_rx: &mut watch::Receiver<bool>) {
    if *cancel_rx.borrow() {
        return;
    }
    let _ = cancel_rx.changed().await;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn transfer_plan_rejects_sparse_ids() {
        let err = TransferPlan::try_new(
            "session-1",
            vec![
                TransferPlanFile {
                    id: 0,
                    path: "a.txt".to_owned(),
                    size: 1,
                },
                TransferPlanFile {
                    id: 2,
                    path: "b.txt".to_owned(),
                    size: 1,
                },
            ],
        )
        .unwrap_err();

        assert!(err.to_string().contains("contiguous"));
    }

    #[test]
    fn transfer_plan_accepts_contiguous_ids() {
        let plan = TransferPlan::try_new(
            "session-1",
            vec![
                TransferPlanFile {
                    id: 0,
                    path: "a.txt".to_owned(),
                    size: 1,
                },
                TransferPlanFile {
                    id: 1,
                    path: "b.txt".to_owned(),
                    size: 2,
                },
            ],
        )
        .unwrap();

        assert_eq!(plan.total_files, 2);
        assert_eq!(plan.total_bytes, 3);
        assert_eq!(plan.file(1).map(|file| file.path.as_str()), Some("b.txt"));
    }
}
