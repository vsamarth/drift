use std::path::PathBuf;

use drift_app::{
    SendConfig, SendEvent as AppSendEvent, SendPhase as AppSendPhase, SendSession,
};

use super::RUNTIME;
use crate::frb_generated::StreamSink;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendTransferPhase {
    Connecting,
    WaitingForDecision,
    Sending,
    Completed,
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
    pub error_message: Option<String>,
}

pub fn start_send_transfer(
    request: SendTransferRequest,
    updates: StreamSink<SendTransferEvent>,
) -> Result<(), String> {
    let session = SendSession::new(
        SendConfig {
            device_name: request.device_name,
            device_type: request.device_type,
        },
        request.paths.into_iter().map(PathBuf::from).collect(),
    );

    RUNTIME.block_on(async move {
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
                        |event| {
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
                        |event| {
                            let _ = updates.add(map_event(event));
                        },
                    )
                    .await
            }
        };

        result.map(|_| ()).map_err(|e| e.to_string())
    })
}

fn map_event(event: AppSendEvent) -> SendTransferEvent {
    SendTransferEvent {
        phase: match event.phase {
            AppSendPhase::Connecting => SendTransferPhase::Connecting,
            AppSendPhase::WaitingForDecision => SendTransferPhase::WaitingForDecision,
            AppSendPhase::Sending => SendTransferPhase::Sending,
            AppSendPhase::Completed => SendTransferPhase::Completed,
            AppSendPhase::Failed => SendTransferPhase::Failed,
        },
        destination_label: event.destination_label,
        status_message: event.status_message,
        item_count: event.item_count,
        total_size: event.total_size,
        bytes_sent: event.bytes_sent,
        remote_device_type: event.remote_device_type,
        error_message: event.error_message,
    }
}
