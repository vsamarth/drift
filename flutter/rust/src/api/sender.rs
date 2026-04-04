use std::path::PathBuf;
use std::sync::{LazyLock, Mutex};

use drift_app::{
    SendConfig, SendEvent as AppSendEvent, SendPhase as AppSendPhase, SendSession,
    SendSessionOutcome,
};
use tokio::sync::watch;

use super::RUNTIME;
use crate::api::error::BridgeError;
use crate::frb_generated::StreamSink;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";
const ENABLE_DEMO_HELLO_PROTOCOL: bool = false;
static ACTIVE_SEND_CANCEL: LazyLock<Mutex<Option<watch::Sender<bool>>>> =
    LazyLock::new(|| Mutex::new(None));

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendTransferPhase {
    Connecting,
    WaitingForDecision,
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
    pub remote_device_type: Option<String>,
    pub error: Option<BridgeError>,
    pub error_message: Option<String>,
}

pub fn start_send_transfer(
    request: SendTransferRequest,
    updates: StreamSink<SendTransferEvent>,
) -> Result<(), BridgeError> {
    if ENABLE_DEMO_HELLO_PROTOCOL {
        std::env::set_var("DRIFT_DEMO_HELLO", "1");
        println!("[bridge/send] demo hello protocol enabled");
    }

    let fallback_destination = fallback_destination_label(&request);
    let session = SendSession::new(
        SendConfig {
            device_name: request.device_name,
            device_type: request.device_type,
        },
        request.paths.into_iter().map(PathBuf::from).collect(),
    );
    let (cancel_tx, cancel_rx) = watch::channel(false);
    if let Ok(mut guard) = ACTIVE_SEND_CANCEL.lock() {
        if let Some(existing) = guard.replace(cancel_tx.clone()) {
            let _ = existing.send(true);
        }
    }

    RUNTIME.block_on(async move {
        let mut emitted_failed_event = false;
        let mut emitted_cancelled_event = false;
        let result = match request
            .ticket
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
        {
            Some(ticket) => {
                session
                    .send_to_nearby(
                        ticket.to_owned(),
                        request
                            .lan_destination_label
                            .unwrap_or_else(|| "Nearby receiver".to_owned()),
                        Some(cancel_rx.clone()),
                        |event| {
                            if matches!(event.phase, AppSendPhase::Failed) {
                                emitted_failed_event = true;
                            }
                            if matches!(event.phase, AppSendPhase::Cancelled) {
                                emitted_cancelled_event = true;
                            }
                            let _ = updates.add(map_event(event));
                        },
                    )
                    .await
            }
            None => {
                session
                    .send_to_code(
                        request.code,
                        request.server_url.or(Some(LOCAL_RENDEZVOUS_URL.to_owned())),
                        Some(cancel_rx),
                        |event| {
                            if matches!(event.phase, AppSendPhase::Failed) {
                                emitted_failed_event = true;
                            }
                            if matches!(event.phase, AppSendPhase::Cancelled) {
                                emitted_cancelled_event = true;
                            }
                            let _ = updates.add(map_event(event));
                        },
                    )
                    .await
            }
        };

        if let Ok(mut guard) = ACTIVE_SEND_CANCEL.lock() {
            guard.take();
        }

        match result {
            Ok(SendSessionOutcome::Completed | SendSessionOutcome::Cancelled) => Ok(()),
            Err(error) => {
                if !emitted_failed_event && !emitted_cancelled_event {
                    let bridge_error: BridgeError = error.clone().into();
                    let error_message = bridge_error
                        .reason
                        .clone()
                        .unwrap_or_else(|| error.to_string());
                    let _ = updates.add(SendTransferEvent {
                        phase: SendTransferPhase::Failed,
                        destination_label: fallback_destination,
                        status_message: "Transfer failed.".to_owned(),
                        item_count: 0,
                        total_size: 0,
                        bytes_sent: 0,
                        remote_device_type: None,
                        error: Some(bridge_error),
                        error_message: Some(error_message),
                    });
                }
                Err(error.into())
            }
        }
    })
}

pub fn cancel_active_send_transfer() -> Result<(), BridgeError> {
    let guard = ACTIVE_SEND_CANCEL
        .lock()
        .map_err(|_| BridgeError::from(drift_core::error::DriftError::internal("send transfer mutex poisoned")))?;
    let Some(cancel_tx) = guard.as_ref() else {
        return Err(BridgeError::from(drift_core::error::DriftError::internal(
            "no active send transfer",
        )));
    };
    cancel_tx
        .send(true)
        .map_err(|_| {
            BridgeError::from(drift_core::error::DriftError::protocol(
                "send transfer is no longer active",
            ))
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
        remote_device_type: event.remote_device_type,
        error: event.error.map(Into::into),
        error_message: event.error_message,
    }
}
