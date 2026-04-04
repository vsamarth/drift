use drift_core::error::{DriftError, DriftErrorKind};

pub fn format_error(error: &DriftError) -> String {
    error.to_string()
}

pub fn invalid_device_type(value: &str) -> DriftError {
    DriftError::invalid_input(format!(
        "invalid device_type {value:?} (expected \"phone\" or \"laptop\")"
    ))
}

pub fn receiver_overwrite_policy_unimplemented() -> DriftError {
    DriftError::internal("receiver overwrite policy is not implemented yet")
}

pub fn actor_stopped(action: &str) -> DriftError {
    DriftError::internal(format!("receiver actor stopped before {action}"))
}

pub fn actor_reply_dropped(action: &str) -> DriftError {
    DriftError::internal(format!("receiver actor dropped {action} reply"))
}

pub fn snapshot_channel_closed() -> DriftError {
    DriftError::internal("receiver v2 snapshot channel closed")
}

pub fn receiver_setup_missing() -> DriftError {
    DriftError::internal("receiver setup has not been completed")
}

pub fn no_pending_offer() -> DriftError {
    DriftError::with_reason(DriftErrorKind::ProtocolViolation, "no pending offer")
}

pub fn offer_no_longer_active() -> DriftError {
    DriftError::with_reason(DriftErrorKind::ProtocolViolation, "offer is no longer active")
}

pub fn no_active_transfer() -> DriftError {
    DriftError::internal("no active transfer")
}
