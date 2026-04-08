use std::collections::HashSet;
use std::error::Error as StdError;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use drift_core::fs_plan::preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview as CoreSelectionPreview,
    inspect_selected_paths,
};
use drift_core::protocol::DeviceType;
use drift_core::rendezvous::{RendezvousClient, resolve_server_url, validate_code};
use drift_core::transfer::{
    SendRequest, Sender, SenderEvent as CoreSenderEvent, TransferOutcome as CoreTransferOutcome,
    TransferPlan,
};
use drift_core::util::{decode_ticket, format_code_label};
use iroh::{EndpointAddr, EndpointId};
use tokio::sync::{mpsc, oneshot};
use tokio_stream::{StreamExt, wrappers::UnboundedReceiverStream};

use crate::error::{UserFacingError, UserFacingErrorKind, from_anyhow_error, from_error};
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

pub type SendEventStream = UnboundedReceiverStream<SendEvent>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendSession {
    draft: SendDraft,
    destination: SendDestination,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ResolvedDestination {
    destination_label: String,
    peer_endpoint_addr: EndpointAddr,
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
        crate::nearby::scan_nearby_receivers(timeout_secs)
            .await
            .map_err(anyhow::Error::from)
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
                    peer_endpoint_addr: endpoint_addr.clone(),
                    peer_endpoint_id: endpoint_addr.id,
                })
            }
            Self::Nearby { ticket, .. } => {
                let endpoint_addr = decode_ticket(ticket.trim())?;
                Ok(ResolvedDestination {
                    destination_label: self.display_label(),
                    peer_endpoint_addr: endpoint_addr.clone(),
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
        event_tx: mpsc::UnboundedSender<SendEvent>,
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
                plan: None,
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            },
        );

        let resolved = match self.destination.resolve().await {
            Ok(resolved) => resolved,
            Err(error) => {
                emit_send_event(
                    &event_tx,
                    failed_event_from_anyhow(&destination_label, &error),
                );
                return Err(error);
            }
        };
        destination_label = resolved.destination_label;

        let device_type = parse_device_type(&self.draft.config.device_type)?;
        let sender = Sender::new(
            self.draft.config.device_name.clone(),
            device_type,
            SendRequest {
                peer_endpoint_addr: resolved.peer_endpoint_addr.clone(),
                peer_endpoint_id: resolved.peer_endpoint_id,
                files: self.draft.paths.clone(),
            },
        );

        let sender_run = sender.run_with_events();
        let (mut core_events, _cancel_tx, outcome_rx) = sender_run.into_parts();
        let mut current_label = destination_label.clone();
        let mut current_plan: Option<TransferPlan> = None;

        while let Some(core_event) = core_events.next().await {
            let mapped = map_sender_event(
                &mut current_label,
                &preview,
                &mut current_plan,
                core_event,
            );
            emit_send_event(&event_tx, mapped);
        }

        let core_outcome = outcome_rx.await.context("waiting for sender outcome")?;

        match core_outcome {
            Ok(CoreTransferOutcome::Completed) => Ok(SendSessionOutcome::Accepted {
                receiver_device_name: String::new(), // The actor will handle proper naming
                receiver_endpoint_id: resolved.peer_endpoint_id,
            }),
            Ok(CoreTransferOutcome::Declined { reason }) => {
                Ok(SendSessionOutcome::Declined { reason })
            }
            Ok(CoreTransferOutcome::Cancelled(cancellation)) => {
                Err(anyhow::anyhow!(cancellation.reason))
            }
            Err(error) => {
                emit_send_event(&event_tx, failed_event_from_error(&current_label, &error));
                Err(error.into())
            }
        }
    }
}

fn emit_send_event(event_tx: &mpsc::UnboundedSender<SendEvent>, event: SendEvent) {
    let _ = event_tx.send(event);
}

fn failed_event_from_anyhow(destination_label: &str, error: &anyhow::Error) -> SendEvent {
    let user_facing_error = from_anyhow_error(error);
    SendEvent {
        phase: SendPhase::Failed,
        destination_label: destination_label.to_owned(),
        status_message: format!("Starting transfer to {destination_label}."),
        item_count: 0,
        total_size: 0,
        bytes_sent: 0,
        plan: None,
        snapshot: None,
        remote_device_type: None,
        connection_path: None,
        error: Some(user_facing_error),
    }
}

fn failed_event_from_error(destination_label: &str, error: &(dyn StdError + 'static)) -> SendEvent {
    let user_facing_error = from_error(error);
    SendEvent {
        phase: SendPhase::Failed,
        destination_label: destination_label.to_owned(),
        status_message: format!("Starting transfer to {destination_label}."),
        item_count: 0,
        total_size: 0,
        bytes_sent: 0,
        plan: None,
        snapshot: None,
        remote_device_type: None,
        connection_path: None,
        error: Some(user_facing_error),
    }
}

fn map_sender_event(
    current_label: &mut String,
    preview: &SelectionPreview,
    current_plan: &mut Option<TransferPlan>,
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
            plan: None,
            snapshot: None,
            remote_device_type: None,
            connection_path: None,
            error: None,
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
                plan: None,
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
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
                plan: None,
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            }
        }
        CoreSenderEvent::Declined { reason, .. } => SendEvent {
            phase: SendPhase::Declined,
            destination_label: current_label.clone(),
            status_message: "Transfer declined.".to_owned(),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            plan: None,
            snapshot: None,
            remote_device_type: None,
            connection_path: None,
            error: Some(UserFacingError::new(
                UserFacingErrorKind::PeerDeclined,
                "Transfer declined",
                reason,
            )),
        },
        CoreSenderEvent::Failed { error, .. } => SendEvent {
            phase: SendPhase::Failed,
            destination_label: current_label.clone(),
            status_message: format!("Starting transfer to {current_label}."),
            item_count: preview.file_count,
            total_size: preview.total_size,
            bytes_sent: 0,
            plan: None,
            snapshot: None,
            remote_device_type: None,
            connection_path: None,
            error: Some(UserFacingError::from(error)),
        },
        CoreSenderEvent::TransferStarted { plan, .. } => {
            *current_plan = Some(plan.clone());
            SendEvent {
                phase: SendPhase::Sending,
                destination_label: current_label.clone(),
                status_message: format!("Sending to {current_label}."),
                item_count: u64::from(plan.total_files),
                total_size: plan.total_bytes,
                bytes_sent: 0,
                plan: Some(plan.clone()),
                snapshot: None,
                remote_device_type: None,
                connection_path: None,
                error: None,
            }
        }
        CoreSenderEvent::TransferProgress { snapshot, .. } => SendEvent {
            phase: SendPhase::Sending,
            destination_label: current_label.clone(),
            status_message: "Sending to ".to_owned() + &current_label,
            item_count: current_plan
                .as_ref()
                .map(|plan| u64::from(plan.total_files))
                .unwrap_or(u64::from(snapshot.total_files)),
            total_size: current_plan
                .as_ref()
                .map(|plan| plan.total_bytes)
                .unwrap_or(snapshot.total_bytes),
            bytes_sent: snapshot.bytes_transferred,
            plan: current_plan.clone(),
            snapshot: Some(snapshot.clone()),
            remote_device_type: None,
            connection_path: None,
            error: None,
        },
        CoreSenderEvent::TransferCompleted { snapshot, .. } => SendEvent {
            phase: SendPhase::Completed,
            destination_label: current_label.clone(),
            status_message: "Files sent successfully".to_owned(),
            item_count: current_plan
                .as_ref()
                .map(|plan| u64::from(plan.total_files))
                .unwrap_or(u64::from(snapshot.total_files)),
            total_size: current_plan
                .as_ref()
                .map(|plan| plan.total_bytes)
                .unwrap_or(snapshot.total_bytes),
            bytes_sent: snapshot.bytes_transferred,
            plan: current_plan.clone(),
            snapshot: Some(snapshot.clone()),
            remote_device_type: None,
            connection_path: None,
            error: None,
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
    use crate::error::UserFacingErrorKind;
    use crate::types::SendConfig;
    use anyhow::anyhow;
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

    #[test]
    fn failed_event_uses_structured_error() {
        let event = super::failed_event("Remote", &anyhow!("boom"));

        let error = event.error.expect("structured error");
        assert_eq!(error.kind(), UserFacingErrorKind::Internal);
        assert_eq!(error.title(), "Transfer failed");
        assert!(error.message().contains("boom"));
    }
}
