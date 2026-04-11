use std::collections::HashSet;
use std::path::{Path, PathBuf};

use drift_core::fs_plan::preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview as CoreSelectionPreview,
    inspect_selected_paths,
};

use crate::error::{AppError, AppResult};
use crate::types::{SelectionChange, SelectionItem, SelectionPreview, SendConfig};

use super::destination::SendDestination;
use super::session::SendSession;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendDraft {
    config: SendConfig,
    paths: Vec<PathBuf>,
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

    pub fn inspect(&self) -> AppResult<SelectionPreview> {
        let preview = inspect_selected_paths(&self.paths).map_err(|e| AppError::Internal {
            message: e.to_string(),
        })?;
        Ok(map_preview(preview))
    }

    pub async fn scan_nearby(
        &self,
        timeout_secs: u64,
    ) -> AppResult<Vec<crate::types::NearbyReceiver>> {
        crate::nearby::scan_nearby_receivers(timeout_secs).await
    }

    pub fn into_session(self, destination: SendDestination) -> SendSession {
        SendSession::new(self, destination)
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

fn selection_path_key(path: &Path) -> String {
    path.to_string_lossy().trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::SendDraft;
    use crate::error::{AppError, UserFacingErrorKind};
    use crate::types::SendConfig;
    use drift_core::protocol::{CancelPhase, TransferRole};
    use drift_core::transfer::TransferCancellation;
    use std::path::{Path, PathBuf};

    use super::super::destination::display_destination_label;

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
        let error = AppError::Internal {
            message: "boom".to_owned(),
        };
        let event = super::super::session::failed_event_from_error("Remote", error.into());

        let error = event.error.expect("structured error");
        assert_eq!(error.kind(), UserFacingErrorKind::Internal);
        assert_eq!(error.title(), "Something went wrong");
        assert!(error.message().contains("boom"));
    }

    #[test]
    fn receiver_waiting_for_decision_cancel_is_treated_as_decline() {
        let cancellation = TransferCancellation {
            by: TransferRole::Receiver,
            phase: CancelPhase::WaitingForDecision,
            reason: "receiver cancelled before approval".to_owned(),
        };

        assert!(crate::send::destination::is_receiver_decline_cancel(
            &cancellation
        ));
        let sender_cancel = TransferCancellation {
            by: TransferRole::Sender,
            phase: CancelPhase::WaitingForDecision,
            reason: "sender cancelled before approval".to_owned(),
        };
        assert!(!crate::send::destination::is_receiver_decline_cancel(
            &sender_cancel
        ));
    }
}
