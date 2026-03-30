use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use drift_core::rendezvous::resolve_server_url;
use drift_core::sender::{
    format_code_label, send_files_with_progress, send_files_with_progress_via_lan_ticket,
    SendTransferPhase as CoreSendTransferPhase, SendTransferProgress,
};
use drift_core::wire::DeviceType;

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
    /// `"phone"` or `"laptop"`.
    pub device_type: String,
    /// When set, send via LAN ticket (mDNS); `code` is ignored for rendezvous.
    pub ticket: Option<String>,
    /// Display label for progress when using `ticket` (e.g. `"Quiet River (ABC123)"`).
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
    /// `"phone"` or `"laptop"`.
    pub remote_device_type: Option<String>,
    pub error_message: Option<String>,
}

pub fn start_send_transfer(
    request: SendTransferRequest,
    updates: StreamSink<SendTransferEvent>,
) -> Result<(), String> {
    let local_device_type = parse_device_type(&request.device_type)?;
    let ticket_opt = request
        .ticket
        .as_ref()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string());

    let fallback_destination_label = match &ticket_opt {
        Some(_) => request
            .lan_destination_label
            .clone()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or_else(|| "Nearby receiver".to_owned()),
        None => format_code_label(&request.code),
    };

    let resolved_server_url =
        resolve_server_url(request.server_url.as_deref().or(Some(LOCAL_RENDEZVOUS_URL)));
    log(&format!(
        "starting send transfer: lan={}, code={}, files={}, device={}, server={}",
        ticket_opt.is_some(),
        request.code,
        request.paths.len(),
        request.device_name,
        resolved_server_url
    ));

    let code = request.code.clone();
    let lan_label = request.lan_destination_label.clone();
    let paths: Vec<PathBuf> = request.paths.into_iter().map(PathBuf::from).collect();
    let device_name = request.device_name.clone();

    RUNTIME.block_on(async move {
        struct ProgressState {
            last_event: Option<SendTransferEvent>,
            updates: StreamSink<SendTransferEvent>,
        }

        let state = Arc::new(Mutex::new(ProgressState {
            last_event: None,
            updates,
        }));

        let progress_fn = {
            let state = state.clone();
            move |progress: SendTransferProgress| {
                let event = map_progress(progress);
                log(&format!(
                    "send transfer update: phase={:?}, destination={}, items={}, total_size={}, bytes_sent={}",
                    event.phase,
                    event.destination_label,
                    event.item_count,
                    event.total_size,
                    event.bytes_sent
                ));
                let mut g = state.lock().expect("progress state lock");
                g.last_event = Some(event.clone());
                let _ = g.updates.add(event);
            }
        };

        let result = if let Some(ticket) = ticket_opt {
            let destination_label = lan_label
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| "Nearby receiver".to_owned());
            send_files_with_progress_via_lan_ticket(
                ticket,
                destination_label,
                paths,
                device_name.clone(),
                local_device_type,
                progress_fn,
            )
            .await
        } else {
            send_files_with_progress(
                code,
                paths,
                Some(resolved_server_url.clone()),
                device_name,
                local_device_type,
                progress_fn,
            )
            .await
        };

        let mut g = state.lock().expect("progress state lock");
        let last_event = g.last_event.take();

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
                remote_device_type: None,
                error_message: Some(error_message.clone()),
            });

            let _ = g.updates.add(SendTransferEvent {
                phase: SendTransferPhase::Failed,
                destination_label: failed.destination_label,
                status_message: failed.status_message,
                item_count: failed.item_count,
                total_size: failed.total_size,
                bytes_sent: failed.bytes_sent,
                remote_device_type: failed.remote_device_type,
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
            "Waiting for confirmation.".to_owned(),
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
        remote_device_type: progress
            .remote_device_type
            .map(device_type_to_str),
        error_message: None,
    }
}

fn parse_device_type(value: &str) -> Result<DeviceType, String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "phone" => Ok(DeviceType::Phone),
        "laptop" => Ok(DeviceType::Laptop),
        other => Err(format!(
            "invalid device_type {other:?} (expected \"phone\" or \"laptop\")"
        )),
    }
}

fn device_type_to_str(value: DeviceType) -> String {
    match value {
        DeviceType::Phone => "phone".to_owned(),
        DeviceType::Laptop => "laptop".to_owned(),
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
