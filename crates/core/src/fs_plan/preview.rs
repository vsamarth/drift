use std::path::{Path, PathBuf};

use crate::fs_plan::error::FsPlanError;

type Result<T> = std::result::Result<T, FsPlanError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectedPathKind {
    File,
    Folder,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectedPathPreview {
    pub path: PathBuf,
    pub kind: SelectedPathKind,
    pub file_count: u64,
    pub total_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionPreview {
    pub items: Vec<SelectedPathPreview>,
    pub file_count: u64,
    pub total_size: u64,
}

pub fn inspect_selected_paths(paths: &[PathBuf]) -> Result<SelectionPreview> {
    if paths.is_empty() {
        return Ok(SelectionPreview {
            items: Vec::new(),
            file_count: 0,
            total_size: 0,
        });
    }

    let mut items = Vec::with_capacity(paths.len());
    let mut total_file_count = 0_u64;
    let mut total_size = 0_u64;

    for path in paths {
        let preview = inspect_selected_path(path)?;
        total_file_count = total_file_count
            .checked_add(preview.file_count)
            .ok_or(FsPlanError::FileCountOverflow)?;
        total_size = total_size
            .checked_add(preview.total_size)
            .ok_or(FsPlanError::TotalSizeOverflow)?;
        items.push(preview);
    }

    if !paths.is_empty() && total_file_count == 0 {
        return Err(FsPlanError::NoRegularFiles);
    }

    Ok(SelectionPreview {
        items,
        file_count: total_file_count,
        total_size,
    })
}

fn inspect_selected_path(path: &Path) -> Result<SelectedPathPreview> {
    let metadata = std::fs::symlink_metadata(path).map_err(|source| FsPlanError::ReadMetadata {
        path: path.to_path_buf(),
        source,
    })?;
    let file_type = metadata.file_type();

    if file_type.is_symlink() {
        return Err(FsPlanError::SymbolicLink {
            path: path.to_path_buf(),
        });
    }

    if file_type.is_file() {
        return Ok(SelectedPathPreview {
            path: path.to_path_buf(),
            kind: SelectedPathKind::File,
            file_count: 1,
            total_size: metadata.len(),
        });
    }

    if file_type.is_dir() {
        let mut file_count = 0_u64;
        let mut total_size = 0_u64;
        let mut stack = vec![path.to_path_buf()];

        while let Some(current) = stack.pop() {
            let entries =
                std::fs::read_dir(&current).map_err(|source| FsPlanError::ReadDirectory {
                    path: current.clone(),
                    source,
                })?;

            for entry in entries {
                let entry = entry.map_err(|source| FsPlanError::ReadDirectory {
                    path: current.clone(),
                    source,
                })?;
                let child_path = entry.path();
                let metadata = entry
                    .metadata()
                    .map_err(|source| FsPlanError::ReadMetadata {
                        path: child_path.clone(),
                        source,
                    })?;
                let child_type = metadata.file_type();

                if child_type.is_symlink() {
                    return Err(FsPlanError::SymbolicLink { path: child_path });
                }

                if child_type.is_dir() {
                    stack.push(child_path);
                    continue;
                }

                if !child_type.is_file() {
                    return Err(FsPlanError::UnsupportedFileType { path: child_path });
                }

                file_count = file_count
                    .checked_add(1)
                    .ok_or(FsPlanError::FileCountOverflow)?;
                total_size = total_size
                    .checked_add(metadata.len())
                    .ok_or(FsPlanError::TotalSizeOverflow)?;
            }
        }

        return Ok(SelectedPathPreview {
            path: path.to_path_buf(),
            kind: SelectedPathKind::Folder,
            file_count,
            total_size,
        });
    }

    Err(FsPlanError::UnsupportedFileType {
        path: path.to_path_buf(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::fs_plan::test_support::{TestDir, write_test_file};

    #[tokio::test]
    async fn inspect_selected_paths_reports_file_counts_and_sizes()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let temp = TestDir::new("drift-inspect").await?;
        let notes = temp.path.join("notes.txt");
        let photos = temp.path.join("photos");
        write_test_file(&notes, "notes").await?;
        write_test_file(&photos.join("trip/cat.jpg"), "cat").await?;
        write_test_file(&photos.join("trip/dog.jpg"), "doggie").await?;

        let preview = inspect_selected_paths(&[notes.clone(), photos.clone()])?;

        assert_eq!(preview.file_count, 3);
        assert_eq!(preview.total_size, 14);
        assert_eq!(preview.items.len(), 2);
        assert_eq!(preview.items[0].kind, SelectedPathKind::File);
        assert_eq!(preview.items[0].file_count, 1);
        assert_eq!(preview.items[0].total_size, 5);
        assert_eq!(preview.items[1].kind, SelectedPathKind::Folder);
        assert_eq!(preview.items[1].file_count, 2);
        assert_eq!(preview.items[1].total_size, 9);

        Ok(())
    }

    #[tokio::test]
    async fn inspect_selected_paths_rejects_empty_directory_only_selection()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let temp = TestDir::new("drift-empty-dir").await?;
        let empty_dir = temp.path.join("empty");
        tokio::fs::create_dir_all(&empty_dir).await?;

        let err = inspect_selected_paths(&[empty_dir]).unwrap_err();
        assert!(err.to_string().contains("no regular files found"));

        Ok(())
    }
}
