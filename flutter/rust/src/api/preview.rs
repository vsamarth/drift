use std::path::PathBuf;

use drift_core::fs_plan::preview::{
    inspect_selected_paths, SelectedPathKind, SelectedPathPreview,
    SelectionPreview as CoreSelectionPreview,
};

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

pub fn inspect_paths(paths: Vec<String>) -> Result<SelectionPreview, String> {
    let raw_paths = paths.into_iter().map(PathBuf::from).collect::<Vec<_>>();
    let preview = inspect_selected_paths(&raw_paths).map_err(|err| err.to_string())?;
    Ok(map_preview(preview))
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
