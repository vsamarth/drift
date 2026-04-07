use crate::protocol::message::{Cancel, CancelPhase, TransferRole};
use anyhow::{Result, bail};
use tokio::sync::watch;

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
