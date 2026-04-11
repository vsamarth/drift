use std::path::PathBuf;

use drift_app::{
    SelectionItem as AppSelectionItem, SelectionPreview as AppSelectionPreview, SendConfig,
    SendDraft,
};

use crate::api::error::internal_user_facing_error;

#[derive(Debug, Clone)]
pub struct SelectionPreview {
    pub items: Vec<SelectionItem>,
    pub file_count: u64,
    pub total_size: u64,
}

#[derive(Debug, Clone)]
pub struct SelectionItem {
    pub name: String,
    pub path: String,
    pub is_directory: bool,
    pub file_count: u64,
    pub total_size: u64,
}

pub fn inspect_paths(
    paths: Vec<String>,
) -> Result<SelectionPreview, crate::api::error::UserFacingErrorData> {
    let preview = draft_for_paths(paths)
        .inspect()
        .map_err(|err| internal_user_facing_error("Failed to inspect paths", err.to_string()))?;
    Ok(map_preview(preview))
}

pub fn append_paths(
    existing_paths: Vec<String>,
    new_paths: Vec<String>,
) -> Result<SelectionPreview, crate::api::error::UserFacingErrorData> {
    let mut draft = draft_for_paths(existing_paths);
    draft.add_paths(new_paths.into_iter().map(PathBuf::from).collect());
    let preview = draft
        .inspect()
        .map_err(|err| internal_user_facing_error("Failed to inspect paths", err.to_string()))?;
    Ok(map_preview(preview))
}

pub fn remove_path(
    existing_paths: Vec<String>,
    removed_path: String,
) -> Result<SelectionPreview, crate::api::error::UserFacingErrorData> {
    let mut draft = draft_for_paths(existing_paths);
    draft.remove_path(PathBuf::from(removed_path).as_path());
    let preview = draft
        .inspect()
        .map_err(|err| internal_user_facing_error("Failed to inspect paths", err.to_string()))?;
    Ok(map_preview(preview))
}

fn draft_for_paths(paths: Vec<String>) -> SendDraft {
    let raw_paths = paths.into_iter().map(PathBuf::from).collect::<Vec<_>>();
    SendDraft::new(
        SendConfig {
            device_name: String::new(),
            device_type: "laptop".to_owned(),
        },
        raw_paths,
    )
}

fn map_preview(preview: AppSelectionPreview) -> SelectionPreview {
    SelectionPreview {
        items: preview.items.into_iter().map(map_item).collect(),
        file_count: preview.file_count,
        total_size: preview.total_size,
    }
}

fn map_item(item: AppSelectionItem) -> SelectionItem {
    SelectionItem {
        name: item.name,
        path: item.path,
        is_directory: item.is_directory,
        file_count: item.file_count,
        total_size: item.total_size,
    }
}
