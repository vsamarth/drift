use std::collections::HashSet;
use std::path::{Path, PathBuf};

use anyhow::{Result, bail};

use crate::error::format_error_chain;
use crate::types::{
    NearbyReceiver, SelectionChange, SelectionItem, SelectionPreview, SendConfig, SendEvent,
    SendPhase,
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendSession {
    config: SendConfig,
    paths: Vec<PathBuf>,
}

impl SendSession {
    pub fn new(config: SendConfig, paths: Vec<PathBuf>) -> Self {
        let mut session = Self {
            config,
            paths: Vec::new(),
        };
        session.replace_paths(paths);
        session
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

    pub async fn send_to_code<F>(
        &self,
        code: String,
        server_url: Option<String>,
        mut on_event: F,
    ) -> Result<()>
    where
        F: FnMut(SendEvent),
    {
        self.send_to_code_impl(code, server_url, &mut on_event)
            .await
    }

    pub async fn send_to_nearby<F>(
        &self,
        ticket: String,
        destination_label: String,
        mut on_event: F,
    ) -> Result<()>
    where
        F: FnMut(SendEvent),
    {
        self.send_to_nearby_impl(ticket, destination_label, &mut on_event)
            .await
    }

    async fn send_to_code_impl<F>(
        &self,
        code: String,
        server_url: Option<String>,
        on_event: &mut F,
    ) -> Result<()>
    where
        F: FnMut(SendEvent),
    {
        let device_type = parse_device_type(&self.config.device_type)?;
        let fallback_destination_label = format_code_label(&code);
        let normalized_server = resolve_server_url(server_url.as_deref());
        let result = send_files_with_progress(
            code,
            self.paths.clone(),
            Some(normalized_server),
            self.config.device_name.clone(),
            device_type,
            |progress| on_event(map_progress(progress)),
        )
        .await;

        match result {
            Ok(_) => Ok(()),
            Err(error) => {
                on_event(failed_event(&fallback_destination_label, &error));
                Err(error)
            }
        }
    }

    async fn send_to_nearby_impl<F>(
        &self,
        ticket: String,
        destination_label: String,
        on_event: &mut F,
    ) -> Result<()>
    where
        F: FnMut(SendEvent),
    {
        let device_type = parse_device_type(&self.config.device_type)?;
        let fallback_destination_label = if destination_label.trim().is_empty() {
            "Nearby receiver".to_owned()
        } else {
            destination_label.clone()
        };
        let result = send_files_with_progress_via_lan_ticket(
            ticket,
            fallback_destination_label.clone(),
            self.paths.clone(),
            self.config.device_name.clone(),
            device_type,
            |progress| on_event(map_progress(progress)),
        )
        .await;

        match result {
            Ok(_) => Ok(()),
            Err(error) => {
                on_event(failed_event(&fallback_destination_label, &error));
                Err(error)
            }
        }
    }
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
        error_message: Some(format_error_chain(error)),
    }
}

fn map_progress(progress: SendTransferProgress) -> SendEvent {
    let destination_label = display_destination_label(&progress.destination_label);
    let (phase, status_message) = match progress.phase {
        CoreSendTransferPhase::Connecting => (SendPhase::Connecting, "Request sent".to_owned()),
        CoreSendTransferPhase::WaitingForDecision => (
            SendPhase::WaitingForDecision,
            "Waiting for confirmation.".to_owned(),
        ),
        CoreSendTransferPhase::Sending => (
            SendPhase::Sending,
            format!("Sending to {destination_label}."),
        ),
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
        other => bail!("invalid device_type {other:?} (expected \"phone\" or \"laptop\")"),
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

fn selection_path_key(path: &Path) -> String {
    path.to_string_lossy().trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::{SendSession, display_destination_label, map_progress};
    use crate::types::{SendConfig, SendPhase};
    use drift_core::rendezvous::{OfferFile, OfferManifest};
    use drift_core::sender::{SendTransferPhase, SendTransferProgress};
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

    #[test]
    fn session_exposes_config_and_paths() {
        let session = SendSession::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("sample.txt")],
        );
        assert_eq!(session.config().device_name, "Laptop");
        assert_eq!(session.paths(), [PathBuf::from("sample.txt")]);
    }

    #[test]
    fn session_constructor_preserves_order_and_dedupes() {
        let session = SendSession::new(
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
            session.paths(),
            [PathBuf::from("a.txt"), PathBuf::from("b.txt")]
        );
    }

    #[test]
    fn add_paths_appends_unique_items_only() {
        let mut session = SendSession::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt")],
        );

        let change = session.add_paths(vec![
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
        assert_eq!(session.paths(), change.paths);
    }

    #[test]
    fn add_paths_is_noop_for_duplicates() {
        let mut session = SendSession::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt")],
        );

        let change = session.add_paths(vec![PathBuf::from("a.txt")]);

        assert!(!change.changed);
        assert_eq!(change.added_count, 0);
        assert_eq!(change.removed_count, 0);
        assert_eq!(session.paths(), [PathBuf::from("a.txt")]);
    }

    #[test]
    fn remove_path_removes_matching_item() {
        let mut session = SendSession::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt"), PathBuf::from("b.txt")],
        );

        let change = session.remove_path(Path::new("a.txt"));

        assert!(change.changed);
        assert_eq!(change.added_count, 0);
        assert_eq!(change.removed_count, 1);
        assert_eq!(session.paths(), [PathBuf::from("b.txt")]);
    }

    #[test]
    fn remove_path_is_noop_when_missing() {
        let mut session = SendSession::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt")],
        );

        let change = session.remove_path(Path::new("missing.txt"));

        assert!(!change.changed);
        assert_eq!(change.removed_count, 0);
        assert_eq!(session.paths(), [PathBuf::from("a.txt")]);
    }

    #[test]
    fn clear_paths_empties_selection() {
        let mut session = SendSession::new(
            SendConfig {
                device_name: "Laptop".to_owned(),
                device_type: "laptop".to_owned(),
            },
            vec![PathBuf::from("a.txt")],
        );

        session.clear_paths();

        assert!(session.is_empty());
        assert!(session.paths().is_empty());
    }
}
