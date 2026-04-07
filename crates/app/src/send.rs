use std::collections::HashSet;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use drift_core::fs_plan::preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview as CoreSelectionPreview,
    inspect_selected_paths,
};
use drift_core::rendezvous::{RendezvousClient, resolve_server_url, validate_code};
use drift_core::sender::format_code_label;
use drift_core::transfer_flow::{
    SendRequest, Sender, SenderEvent as CoreSenderEvent, SenderOutcome as CoreSenderOutcome,
};
use drift_core::protocol::DeviceType;
use drift_core::util::decode_ticket;
use iroh::EndpointId;
use tokio::sync::{mpsc, oneshot};
use tokio_stream::{StreamExt, wrappers::UnboundedReceiverStream};

use crate::error::format_error_chain;
use crate::types::{
    NearbyReceiver, SelectionChange, SelectionItem, SelectionPreview, SendConfig, SendEvent,
    SendPhase,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendDraft {
    config: SendConfig,
    paths: Vec<PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendDestination {
    Code {
        code: String,
        server_url: Option<String>,
    },
    Nearby {
        ticket: String,
        destination_label: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendSessionOutcome {
    Accepted {
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
    },
    Declined {
        reason: String,
    },
}

#[derive(Debug)]
pub struct SendRun {
    pub events: SendEventStream,
    outcome_rx: oneshot::Receiver<Result<SendSessionOutcome>>,
}

pub type SendEventStream = UnboundedReceiverStream<Result<SendEvent>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendSession {
    draft: SendDraft,
    destination: SendDestination,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ResolvedDestination {
    destination_label: String,
    peer_endpoint_id: EndpointId,
}

impl SendDraft {
    pub fn new(config: SendConfig, paths: Vec<PathBuf>) -> Self {
        let mut draft = Self {
            config,
            paths: Vec::new(),
        };
        draft.replace_paths(paths);
        draft
    }

    pub fn config(&self) -> &SendConfig {
        &self.config
    }

    pub fn paths(&self) -> &[PathBuf] {
        &self.paths
    }

    pub fn replace_paths(&mut self, paths: Vec<PathBuf>) {
        let mut seen = HashSet::new();
        self.paths = paths
            .into_iter()
            .filter(|path| seen.insert(selection_path_key(path)))
            .collect();
    }

    pub fn add_paths(&mut self, paths: Vec<PathBuf>) -> SelectionChange {
        let before = self.paths.len();
        let mut seen = self
            .paths
            .iter()
            .map(|path| selection_path_key(path))
            .collect::<HashSet<_>>();

        for path in paths {
            if seen.insert(selection_path_key(&path)) {
                self.paths.push(path);
            }
        }

        let added = self.paths.len().saturating_sub(before) as u64;
        SelectionChange {
            paths: self.paths.clone(),
            added_count: added,
            removed_count: 0,
            changed: added > 0,
        }
    }

    pub fn remove_path(&mut self, path: &Path) -> SelectionChange {
        let key = selection_path_key(path);
        let before = self.paths.len();
        self.paths.retain(|item| selection_path_key(item) != key);
        let removed = before.saturating_sub(self.paths.len()) as u64;
        SelectionChange {
            paths: self.paths.clone(),
            added_count: 0,
            removed_count: removed,
            changed: removed > 0,
        }
    }

    pub fn clear_paths(&mut self) {
        self.paths.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.paths.is_empty()
    }

    pub fn inspect(&self) -> Result<SelectionPreview> {
        let preview = inspect_selected_paths(&self.paths)?;
        Ok(map_preview(preview))
    }

    pub async fn scan_nearby(&self, timeout_secs: u64) -> Result<Vec<NearbyReceiver>> {
        crate::nearby::scan_nearby_receivers(timeout_secs).await
    }

    pub fn into_session(self, destination: SendDestination) -> SendSession {
        SendSession::new(self, destination)
    }
}

impl SendDestination {
    pub fn code(code: String, server_url: Option<String>) -> Self {
        Self::Code { code, server_url }
    }

    pub fn nearby(ticket: String, destination_label: String) -> Self {
        Self::Nearby {
            ticket,
            destination_label,
        }
    }

    fn display_label(&self) -> String {
        match self {
            Self::Code { code, .. } => format_code_label(code),
            Self::Nearby {
                destination_label, ..
            } => display_destination_label(destination_label),
        }
    }

    async fn resolve(&self) -> Result<ResolvedDestination> {
        match self {
            Self::Code { code, server_url } => {
                validate_code(code)?;
                let client = RendezvousClient::new(resolve_server_url(server_url.as_deref()));
                let resolved = client.claim_peer(code).await?;
                let endpoint_addr = decode_ticket(&resolved.ticket)?;
                Ok(ResolvedDestination {
                    destination_label: format_code_label(code),
                    peer_endpoint_id: endpoint_addr.id,
                })
            }
            Self::Nearby { ticket, .. } => {
                let endpoint_addr = decode_ticket(ticket.trim())?;
                Ok(ResolvedDestination {
                    destination_label: self.display_label(),
                    peer_endpoint_id: endpoint_addr.id,
                })
            }
        }
    }
}

impl SendRun {
    pub fn into_parts(
        self,
    ) -> (
        SendEventStream,
        oneshot::Receiver<Result<SendSessionOutcome>>,
    ) {
        (self.events, self.outcome_rx)
    }

    pub async fn outcome(self) -> Result<SendSessionOutcome> {
        self.outcome_rx.await.context("waiting for send outcome")?
    }
}

impl SendSession {
    pub fn new(draft: SendDraft, destination: SendDestination) -> Self {
        Self { draft, destination }
    }

    pub fn draft(&self) -> &SendDraft {
        &self.draft
    }

    pub fn destination(&self) -> &SendDestination {
        &self.destination
    }

    pub fn start(self) -> SendRun {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (outcome_tx, outcome_rx) = oneshot::channel();

        tokio::spawn(async move {
            let outcome = self.drive(event_tx).await;
            let _ = outcome_tx.send(outcome);
        });

        SendRun {
            events: UnboundedReceiverStream::new(event_rx),
            outcome_rx,
        }
    }

    async fn drive(
        self,
        event_tx: mpsc::UnboundedSender<Result<SendEvent>>,
    ) -> Result<SendSessionOutcome> {
        let preview = self.draft.inspect().context("inspecting selected paths")?;
        let mut destination_label = self.destination.display_label();

        emit_send_event(
            &event_tx,
            SendEvent {
                phase: SendPhase::Connecting,
                destination_label: destination_label.clone(),
                status_message: "Request sent".to_owned(),
                item_count: preview.file_count,
                total_size: preview.total_size,
                bytes_sent: 0,
                remote_device_type: None,
                connection_path: None,
                error_message: None,
            },
        );

        let resolved = match self.destination.resolve().await {
            Ok(resolved) => resolved,
            Err(error) => {
                emit_failed_event(&event_tx, &destination_label, &error);
                return Err(error);
            }
        };
        destination_label = resolved.destination_label;

        let device_type = parse_device_type(&self.draft.config.device_type)?;
        let sender = Sender::new(
            self.draft.config.device_name.clone(),
            device_type,
            SendRequest {
                peer_endpoint_id: resolved.peer_endpoint_id,
                files: self.draft.paths.clone(),
            },
        );

        let sender_run = sender.run_with_events();
        let (mut core_events, outcome_rx) = sender_run.into_parts();
        let mut current_label = destination_label.clone();

        while let Some(event) = core_events.next().await {
            match event {
                Ok(core_event) => {
                    let mapped = map_sender_event(&mut current_label, &preview, core_event);
                    emit_send_event(&event_tx, mapped);
                }
                Err(error) => {
                    let message = format!("{error:#}");
                    let _ = event_tx.send(Err(anyhow::anyhow!(message.clone())));
                    return Err(anyhow::anyhow!(message));
                }
            }
        }

        let core_outcome = outcome_rx.await.context("waiting for sender outcome")?;

        match core_outcome {
            Ok(CoreSenderOutcome::Accepted {
                receiver_device_name,
                receiver_endpoint_id,
            }) => Ok(SendSessionOutcome::Accepted {
                receiver_device_name,
                receiver_endpoint_id,
            }),
            Ok(CoreSenderOutcome::Declined { reason }) => {
                Ok(SendSessionOutcome::Declined { reason })
            }
            Err(error) => Err(error),
        }
    }
}

fn emit_send_event(event_tx: &mpsc::UnboundedSender<Result<SendEvent>>, event: SendEvent) {
    let _ = event_tx.send(Ok(event));
}

fn emit_failed_event(
    event_tx: &mpsc::UnboundedSender<Result<SendEvent>>,
    destination_label: &str,
    error: &anyhow::Error,
) {
    emit_send_event(event_tx, failed_event(destination_label, error));
    let _ = event_tx.send(Err(anyhow::anyhow!(format!("{error:#}"))));
}

fn failed_event(destination_label: &str, error: &anyhow::Error) -> SendEvent {
    SendEvent {
        phase: SendPhase::Failed,
        destination_label: destination_label.to_owned(),
        status_message: format!("Starting transfer to {destination_label}."),
        item_count: 0,
        total_size: 0,
        bytes_sent: 0,
        remote_device_type: None,
        connection_path: None,
        error_message: Some(format_error_chain(error)),
    }
}

fn map_sender_event(
    current_label: &mut String,
    preview: &SelectionPreview,
    event: CoreSenderEvent,
) -> SendEvent {
    match event {
        CoreSenderEvent::Connecting { .. } => SendEvent {
            phase: SendPhase::Connecting,
            destination_label: current_label.clone(),
            status_message: "Request sent".to_owned(),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            remote_device_type: None,
            connection_path: None,
            error_message: None,
        },
        CoreSenderEvent::WaitingForDecision {
            receiver_device_name,
            receiver_endpoint_id: _,
            ..
        } => {
            *current_label = display_destination_label(&receiver_device_name);
            SendEvent {
                phase: SendPhase::WaitingForDecision,
                destination_label: current_label.clone(),
                status_message: "Waiting for confirmation.".to_owned(),
                item_count: preview.file_count,
                total_size: preview.total_size,
                bytes_sent: 0,
                remote_device_type: None,
                connection_path: None,
                error_message: None,
            }
        }
        CoreSenderEvent::Accepted {
            receiver_device_name,
            receiver_endpoint_id: _,
            ..
        } => {
            *current_label = display_destination_label(&receiver_device_name);
            SendEvent {
                phase: SendPhase::Accepted,
                destination_label: current_label.clone(),
                status_message: format!("Receiver {receiver_device_name} confirmed."),
                item_count: preview.file_count,
                total_size: preview.total_size,
                bytes_sent: 0,
                remote_device_type: None,
                connection_path: None,
                error_message: None,
            }
        }
        CoreSenderEvent::Declined { reason, .. } => SendEvent {
            phase: SendPhase::Declined,
            destination_label: current_label.clone(),
            status_message: "Transfer declined.".to_owned(),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            remote_device_type: None,
            connection_path: None,
            error_message: Some(reason),
        },
        CoreSenderEvent::Failed { message, .. } => SendEvent {
            phase: SendPhase::Failed,
            destination_label: current_label.clone(),
            status_message: format!("Starting transfer to {current_label}."),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            remote_device_type: None,
            connection_path: None,
            error_message: Some(message),
        },
        CoreSenderEvent::TransferStarted {
            file_count,
            total_bytes,
            ..
        } => SendEvent {
            phase: SendPhase::Sending,
            destination_label: current_label.clone(),
            status_message: format!("Sending to {current_label}."),
            item_count: file_count,
            total_size: total_bytes,
            bytes_sent: 0,
            remote_device_type: None,
            connection_path: None,
            error_message: None,
        },
        CoreSenderEvent::TransferProgress {
            bytes_sent,
            total_bytes,
            ..
        } => SendEvent {
            phase: SendPhase::Sending,
            destination_label: current_label.clone(),
            status_message: format!("Sending to {current_label}."),
            item_count: preview.file_count,
            total_size: total_bytes.max(preview.total_size),
            bytes_sent,
            remote_device_type: None,
            connection_path: None,
            error_message: None,
        },
        CoreSenderEvent::TransferCompleted { .. } => SendEvent {
            phase: SendPhase::Completed,
            destination_label: current_label.clone(),
            status_message: "Files sent successfully".to_owned(),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: preview.total_size,
            remote_device_type: None,
            connection_path: None,
            error_message: None,
        },
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
        other => bail!("invalid device_type {other:?} (expected \"phone\" or \"laptop\")"),
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

fn selection_path_key(path: &Path) -> String {
    path.to_string_lossy().trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::{SendDraft, display_destination_label};
    use crate::types::SendConfig;
    use std::path::{Path, PathBuf};

    #[test]
    fn destination_label_falls_back_for_unknown_values() {
        assert_eq!(
            display_destination_label("unknown-device"),
            "Recipient device"
        );
        assert_eq!(display_destination_label(""), "Recipient device");
    }

    #[test]
    fn draft_constructor_preserves_order_and_dedupes() {
        let draft = SendDraft::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![
                PathBuf::from("a.txt"),
                PathBuf::from("b.txt"),
                PathBuf::from("a.txt"),
            ],
        );
        assert_eq!(
            draft.paths(),
            [PathBuf::from("a.txt"), PathBuf::from("b.txt")]
        );
    }

    #[test]
    fn remove_path_removes_matching_item() {
        let mut draft = SendDraft::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt"), PathBuf::from("b.txt")],
        );

        let change = draft.remove_path(Path::new("a.txt"));

        assert!(change.changed);
        assert_eq!(change.added_count, 0);
        assert_eq!(change.removed_count, 1);
        assert_eq!(draft.paths(), [PathBuf::from("b.txt")]);
    }

    #[test]
    fn add_paths_appends_unique_items_only() {
        let mut draft = SendDraft::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt")],
        );

        let change = draft.add_paths(vec![
            PathBuf::from("a.txt"),
            PathBuf::from("b.txt"),
            PathBuf::from("c.txt"),
        ]);

        assert!(change.changed);
        assert_eq!(change.added_count, 2);
        assert_eq!(change.removed_count, 0);
        assert_eq!(
            change.paths,
            vec![
                PathBuf::from("a.txt"),
                PathBuf::from("b.txt"),
                PathBuf::from("c.txt"),
            ]
        );
        assert_eq!(draft.paths(), change.paths);
    }

    #[test]
    fn clear_paths_empties_selection() {
        let mut draft = SendDraft::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt")],
        );

        draft.clear_paths();

        assert!(draft.is_empty());
        assert!(draft.paths().is_empty());
    }
}
