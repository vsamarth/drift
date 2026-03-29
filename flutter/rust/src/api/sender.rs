use std::path::PathBuf;

use drift_core::rendezvous::resolve_server_url;
use drift_core::sender::{
    format_code_label, send_files_with_progress, SendTransferPhase as CoreSendTransferPhase,
    SendTransferProgress,
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
}

#[derive(Debug, Clone)]
pub struct SendTransferEvent {
    pub phase: SendTransferPhase,
    pub destination_label: String,
    pub status_message: String,
    pub item_count: u64,
    pub total_size: u64,
    pub bytes_sent: u64,
    pub error_message: Option<String>,
}

pub fn start_send_transfer(
    request: SendTransferRequest,
    updates: StreamSink<SendTransferEvent>,
) -> Result<(), String> {
    let fallback_destination_label = format_code_label(&request.code);
    let resolved_server_url =
        resolve_server_url(request.server_url.as_deref().or(Some(LOCAL_RENDEZVOUS_URL)));
    log(&format!(
        "starting send transfer: code={}, files={}, device={}, server={}",
        request.code,
        request.paths.len(),
        request.device_name,
        resolved_server_url
    ));

    RUNTIME.block_on(async move {
        let mut last_event = None::<SendTransferEvent>;
        let result = send_files_with_progress(
            request.code.clone(),
            request.paths.into_iter().map(PathBuf::from).collect(),
            Some(resolved_server_url.clone()),
            request.device_name.clone(),
            |progress| {
                let event = map_progress(progress);
                log(&format!(
                    "send transfer update: phase={:?}, destination={}, items={}, total_size={}, bytes_sent={}",
                    event.phase,
                    event.destination_label,
                    event.item_count,
                    event.total_size,
                    event.bytes_sent
                ));
                last_event = Some(event.clone());
                let _ = updates.add(event);
            },
        )
        .await;

        if let Err(error) = result {
            let error_message = format_error_chain(&error);
            log(&format!("send transfer failed: {}", error_message));
            let failed = last_event.unwrap_or_else(|| SendTransferEvent {
                phase: SendTransferPhase::Failed,
                destination_label: fallback_destination_label.clone(),
                status_message: format!("Starting transfer to {fallback_destination_label}."),
                item_count: 0,
                total_size: 0,
                bytes_sent: 0,
                error_message: Some(error_message.clone()),
            });

            let _ = updates.add(SendTransferEvent {
                phase: SendTransferPhase::Failed,
                destination_label: failed.destination_label,
                status_message: failed.status_message,
                item_count: failed.item_count,
                total_size: failed.total_size,
                bytes_sent: failed.bytes_sent,
                error_message: Some(error_message),
            });
        } else {
            log("send transfer completed");
        }

        Ok(())
    })
}

fn map_progress(progress: SendTransferProgress) -> SendTransferEvent {
    let destination_label = display_destination_label(&progress.destination_label);
    let (phase, status_message) = match progress.phase {
        CoreSendTransferPhase::Connecting => {
            (SendTransferPhase::Connecting, "Request sent".to_owned())
        }
        CoreSendTransferPhase::WaitingForDecision => (
            SendTransferPhase::WaitingForDecision,
            format!("Waiting for {destination_label} to confirm."),
        ),
        CoreSendTransferPhase::Sending => (
            SendTransferPhase::Sending,
            format!("Sending to {destination_label}."),
        ),
        CoreSendTransferPhase::Completed => (
            SendTransferPhase::Completed,
            "Files sent successfully".to_owned(),
        ),
    };

    SendTransferEvent {
        phase,
        destination_label,
        status_message,
        item_count: progress.manifest.file_count,
        total_size: progress.manifest.total_size,
        bytes_sent: progress.bytes_sent,
        error_message: None,
    }
}

fn display_destination_label(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return "Recipient device".to_owned();
    }

    let normalized = trimmed
        .replace(['_', '-'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let lowercase = normalized.to_ascii_lowercase();
    if lowercase.is_empty()
        || lowercase == "unknown device"
        || lowercase == "unknown-device"
        || lowercase == "unknown"
    {
        return "Recipient device".to_owned();
    }

    normalized
}

fn format_error_chain(error: &anyhow::Error) -> String {
    error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ")
}

fn log(message: &str) {
    eprintln!("[drift_bridge::sender] {message}");
}
