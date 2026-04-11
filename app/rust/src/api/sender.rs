use std::path::PathBuf;
use std::sync::{LazyLock, Mutex};

use drift_app::{
    SendConfig, SendDestination, SendDraft, SendEvent as AppSendEvent, SendPhase as AppSendPhase,
    SendSession, SendSessionOutcome,
};
use drift_core::transfer::{TransferPhase, TransferPlan, TransferPlanFile, TransferSnapshot};
use futures_lite::StreamExt;
use tokio::sync::watch;

use super::transfer::{
    TransferPhaseData, TransferPlanData, TransferPlanFileData, TransferSnapshotData,
};
use super::RUNTIME;
use crate::api::error::internal_user_facing_error;
use crate::frb_generated::StreamSink;
use crate::api::error::map_optional_user_facing_error;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";
static ACTIVE_SEND_CANCEL: LazyLock<Mutex<Option<watch::Sender<bool>>>> =
    LazyLock::new(|| Mutex::new(None));

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendTransferPhase {
    Connecting,
    WaitingForDecision,
    Accepted,
    Declined,
    Sending,
    Completed,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone)]
pub struct SendTransferRequest {
    pub code: String,
    pub paths: Vec<String>,
    pub server_url: Option<String>,
    pub device_name: String,
    pub device_type: String,
    pub ticket: Option<String>,
    pub lan_destination_label: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SendTransferEvent {
    pub phase: SendTransferPhase,
    pub destination_label: String,
    pub status_message: String,
    pub item_count: u64,
    pub total_size: u64,
    pub bytes_sent: u64,
    pub plan: Option<TransferPlanData>,
    pub snapshot: Option<TransferSnapshotData>,
    pub remote_device_type: Option<String>,
    pub error: Option<crate::api::error::UserFacingErrorData>,
}

pub fn start_send_transfer(
    request: SendTransferRequest,
    updates: StreamSink<SendTransferEvent>,
) -> Result<(), crate::api::error::UserFacingErrorData> {
    let fallback_destination = fallback_destination_label(&request);

    let draft = SendDraft::new(
        SendConfig {
            device_name: request.device_name,
            device_type: request.device_type,
        },
        request.paths.into_iter().map(PathBuf::from).collect(),
    );

    let destination = match request
        .ticket
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        Some(ticket) => SendDestination::nearby(
            ticket.to_owned(),
            request
                .lan_destination_label
                .unwrap_or_else(|| "Nearby receiver".to_owned()),
        ),
        None => SendDestination::code(
            request.code,
            request.server_url.or(Some(LOCAL_RENDEZVOUS_URL.to_owned())),
        ),
    };

    let session = SendSession::new(draft, destination);
    let (cancel_tx, _cancel_rx) = watch::channel(false);
    if let Ok(mut guard) = ACTIVE_SEND_CANCEL.lock() {
        if let Some(existing) = guard.replace(cancel_tx.clone()) {
            let _ = existing.send(true);
        }
    }

    RUNTIME.spawn(async move {
        let run = session.start();
        let (mut events, outcome_rx) = run.into_parts();

        let event_updates = updates.clone();
        tokio::spawn(async move {
            while let Some(event) = events.next().await {
                let _ = event_updates.add(map_event(event));
            }
        });

        let outcome = outcome_rx.await;

        if let Ok(mut guard) = ACTIVE_SEND_CANCEL.lock() {
            guard.take();
        }

        match outcome {
            Ok(Ok(SendSessionOutcome::Accepted { .. })) => {}
            Ok(Ok(SendSessionOutcome::Declined { .. })) => {}
            Ok(Err(error)) => {
                let _ = updates.add(SendTransferEvent {
                    phase: SendTransferPhase::Failed,
                    destination_label: fallback_destination,
                    status_message: "Transfer failed.".to_owned(),
                    item_count: 0,
                    total_size: 0,
                    bytes_sent: 0,
                    plan: None,
                    snapshot: None,
                    remote_device_type: None,
                    error: Some(internal_user_facing_error(
                        "Transfer failed",
                        error.to_string(),
                    )),
                });
            }
            Err(_) => {}
        }
    });

    Ok(())
}

pub fn cancel_active_send_transfer() -> Result<(), crate::api::error::UserFacingErrorData> {
    let guard = ACTIVE_SEND_CANCEL
        .lock()
        .map_err(|_| internal_user_facing_error("Send transfer unavailable", "mutex poisoned"))?;
    let Some(cancel_tx) = guard.as_ref() else {
        return Err(internal_user_facing_error(
            "No active send transfer",
            "There is no active send transfer to cancel.",
        ));
    };
    cancel_tx
        .send(true)
        .map_err(|_| {
            internal_user_facing_error(
                "Send transfer unavailable",
                "The active send transfer is no longer available.",
            )
        })
}

fn fallback_destination_label(request: &SendTransferRequest) -> String {
    request
        .lan_destination_label
        .as_deref()
        .map(str::trim)
        .filter(|label| !label.is_empty())
        .map(str::to_owned)
        .or_else(|| format_code_label(&request.code))
        .unwrap_or_else(|| "Nearby receiver".to_owned())
}

fn format_code_label(code: &str) -> Option<String> {
    let normalized = code.trim().to_ascii_uppercase();
    if normalized.len() == 6 {
        Some(format!("Code {} {}", &normalized[..3], &normalized[3..]))
    } else if normalized.is_empty() {
        None
    } else {
        Some(format!("Code {normalized}"))
    }
}

fn map_event(event: AppSendEvent) -> SendTransferEvent {
    SendTransferEvent {
        phase: match event.phase {
            AppSendPhase::Connecting => SendTransferPhase::Connecting,
            AppSendPhase::WaitingForDecision => SendTransferPhase::WaitingForDecision,
            AppSendPhase::Accepted => SendTransferPhase::Accepted,
            AppSendPhase::Declined => SendTransferPhase::Declined,
            AppSendPhase::Sending => SendTransferPhase::Sending,
            AppSendPhase::Completed => SendTransferPhase::Completed,
            AppSendPhase::Cancelled => SendTransferPhase::Cancelled,
            AppSendPhase::Failed => SendTransferPhase::Failed,
        },
        destination_label: event.destination_label,
        status_message: event.status_message,
        item_count: event.item_count,
        total_size: event.total_size,
        bytes_sent: event.bytes_sent,
        plan: event.plan.map(map_plan),
        snapshot: event.snapshot.map(map_snapshot),
        remote_device_type: event.remote_device_type,
        error: map_optional_user_facing_error(event.error),
    }
}

fn map_plan(plan: TransferPlan) -> TransferPlanData {
    TransferPlanData {
        session_id: plan.session_id,
        total_files: plan.total_files,
        total_bytes: plan.total_bytes,
        files: plan.files.into_iter().map(map_plan_file).collect(),
    }
}

fn map_plan_file(file: TransferPlanFile) -> TransferPlanFileData {
    TransferPlanFileData {
        id: file.id,
        path: file.path,
        size: file.size,
    }
}

fn map_snapshot(snapshot: TransferSnapshot) -> TransferSnapshotData {
    TransferSnapshotData {
        session_id: snapshot.session_id,
        phase: map_phase(snapshot.phase),
        total_files: snapshot.total_files,
        completed_files: snapshot.completed_files,
        total_bytes: snapshot.total_bytes,
        bytes_transferred: snapshot.bytes_transferred,
        active_file_id: snapshot.active_file_id,
        active_file_bytes: snapshot.active_file_bytes,
        bytes_per_sec: snapshot.bytes_per_sec,
        eta_seconds: snapshot.eta_seconds,
    }
}

fn map_phase(phase: TransferPhase) -> TransferPhaseData {
    match phase {
        TransferPhase::Connecting => TransferPhaseData::Connecting,
        TransferPhase::AwaitingAcceptance => TransferPhaseData::AwaitingAcceptance,
        TransferPhase::Transferring => TransferPhaseData::Transferring,
        TransferPhase::Finalizing => TransferPhaseData::Finalizing,
        TransferPhase::Completed => TransferPhaseData::Completed,
        TransferPhase::Cancelled => TransferPhaseData::Cancelled,
        TransferPhase::Failed => TransferPhaseData::Failed,
    }
}
