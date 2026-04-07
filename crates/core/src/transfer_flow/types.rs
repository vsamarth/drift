use crate::protocol::message::{CancelPhase, TransferRole};

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
