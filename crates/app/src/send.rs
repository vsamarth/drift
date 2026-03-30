use std::path::PathBuf;

use anyhow::{Result, bail};

use crate::error::format_error_chain;
use crate::types::{
    SelectionItem, SelectionPreview, SendEvent, SendPhase, SendRequest, SendTarget,
};
use drift_core::fs_plan::preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview as CoreSelectionPreview,
    inspect_selected_paths,
};
use drift_core::rendezvous::resolve_server_url;
use drift_core::sender::{
    SendTransferPhase as CoreSendTransferPhase, SendTransferProgress, format_code_label,
    send_files_with_progress, send_files_with_progress_via_lan_ticket,
};
use drift_core::wire::DeviceType;

pub fn inspect_paths(paths: &[PathBuf]) -> Result<SelectionPreview> {
    let preview = inspect_selected_paths(paths)?;
    Ok(map_preview(preview))
}

pub async fn send<F>(request: SendRequest, mut on_event: F) -> Result<()>
where
    F: FnMut(SendEvent),
{
    send_impl(request, &mut on_event).await
}

async fn send_impl<F>(request: SendRequest, on_event: &mut F) -> Result<()>
where
    F: FnMut(SendEvent),
{
    let device_type = parse_device_type(&request.device_type)?;
    let fallback_destination_label = match &request.target {
        SendTarget::Code { code, .. } => format_code_label(code),
        SendTarget::Lan {
            destination_label, ..
        } => {
            if destination_label.trim().is_empty() {
                "Nearby receiver".to_owned()
            } else {
                destination_label.clone()
            }
        }
    };

    let result = match request.target {
        SendTarget::Code { code, server_url } => {
            let normalized_server = resolve_server_url(server_url.as_deref());
            send_files_with_progress(
                code,
                request.paths,
                Some(normalized_server),
                request.device_name,
                device_type,
                |progress| on_event(map_progress(progress)),
            )
            .await
        }
        SendTarget::Lan {
            ticket,
            destination_label,
        } => {
            let destination_label = if destination_label.trim().is_empty() {
                "Nearby receiver".to_owned()
            } else {
                destination_label
            };
            send_files_with_progress_via_lan_ticket(
                ticket,
                destination_label,
                request.paths,
                request.device_name,
                device_type,
                |progress| on_event(map_progress(progress)),
            )
            .await
        }
    };

    match result {
        Ok(_) => Ok(()),
        Err(error) => {
            let failed = SendEvent {
                phase: SendPhase::Failed,
                destination_label: fallback_destination_label.clone(),
                status_message: format!("Starting transfer to {fallback_destination_label}."),
                item_count: 0,
                total_size: 0,
                bytes_sent: 0,
                remote_device_type: None,
                error_message: Some(format_error_chain(&error)),
            };
            on_event(failed);
            Err(error)
        }
    }
}

fn map_progress(progress: SendTransferProgress) -> SendEvent {
    let destination_label = display_destination_label(&progress.destination_label);
    let (phase, status_message) = match progress.phase {
        CoreSendTransferPhase::Connecting => (SendPhase::Connecting, "Request sent".to_owned()),
        CoreSendTransferPhase::WaitingForDecision => {
            (SendPhase::WaitingForDecision, "Waiting for confirmation.".to_owned())
        }
        CoreSendTransferPhase::Sending => {
            (SendPhase::Sending, format!("Sending to {destination_label}."))
        }
        CoreSendTransferPhase::Completed => {
            (SendPhase::Completed, "Files sent successfully".to_owned())
        }
    };

    SendEvent {
        phase,
        destination_label,
        status_message,
        item_count: progress.manifest.file_count,
        total_size: progress.manifest.total_size,
        bytes_sent: progress.bytes_sent,
        remote_device_type: progress.remote_device_type.map(device_type_to_str),
        error_message: None,
    }
}

fn map_preview(preview: CoreSelectionPreview) -> SelectionPreview {
    SelectionPreview {
        items: preview.items.into_iter().map(map_item).collect(),
        file_count: preview.file_count,
        total_size: preview.total_size,
    }
}

fn map_item(item: SelectedPathPreview) -> SelectionItem {
    SelectionItem {
        name: item
            .path
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| item.path.display().to_string()),
        path: item.path.display().to_string(),
        is_directory: item.kind == SelectedPathKind::Folder,
        file_count: item.file_count,
        total_size: item.total_size,
    }
}

fn parse_device_type(value: &str) -> Result<DeviceType> {
    match value.trim().to_ascii_lowercase().as_str() {
        "phone" => Ok(DeviceType::Phone),
        "laptop" => Ok(DeviceType::Laptop),
        other => bail!(
            "invalid device_type {other:?} (expected \"phone\" or \"laptop\")"
        ),
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

#[cfg(test)]
mod tests {
    use super::{display_destination_label, map_progress};
    use crate::types::SendPhase;
    use drift_core::rendezvous::{OfferFile, OfferManifest};
    use drift_core::sender::{SendTransferPhase, SendTransferProgress};

    #[test]
    fn destination_label_falls_back_for_unknown_values() {
        assert_eq!(display_destination_label("unknown-device"), "Recipient device");
        assert_eq!(display_destination_label(""), "Recipient device");
    }

    #[test]
    fn send_progress_maps_to_app_event() {
        let event = map_progress(SendTransferProgress {
            phase: SendTransferPhase::Sending,
            destination_label: "quiet_river".to_owned(),
            remote_device_type: None,
            manifest: OfferManifest {
                files: vec![OfferFile {
                    path: "sample.txt".to_owned(),
                    size: 12,
                }],
                file_count: 1,
                total_size: 12,
            },
            bytes_sent: 4,
            current_file_index: Some(0),
            bytes_sent_in_file: 4,
        });
        assert_eq!(event.phase, SendPhase::Sending);
        assert_eq!(event.destination_label, "quiet river");
        assert_eq!(event.total_size, 12);
        assert_eq!(event.bytes_sent, 4);
    }
}
