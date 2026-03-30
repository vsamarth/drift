use std::path::PathBuf;

use drift_app::{
    SelectionItem as AppSelectionItem, SelectionPreview as AppSelectionPreview,
    inspect_paths as app_inspect_paths,
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
    let preview = app_inspect_paths(&raw_paths).map_err(|err| err.to_string())?;
    Ok(map_preview(preview))
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
