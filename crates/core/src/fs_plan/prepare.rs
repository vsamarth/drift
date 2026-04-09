use std::collections::HashSet;
use std::path::PathBuf;

use tokio::fs;

use crate::fs_plan::error::FsPlanError;
use crate::rendezvous::{OfferFile, OfferManifest};
use crate::transfer::path::{input_root_name, normalize_transfer_path};

type Result<T> = std::result::Result<T, FsPlanError>;

#[derive(Debug, Clone)]
pub struct PreparedFile {
    pub source_path: PathBuf,
    pub transfer_path: String,
    pub size: u64,
}

#[derive(Debug, Clone)]
pub struct PreparedFiles {
    pub files: Vec<PreparedFile>,
    pub manifest: OfferManifest,
}

pub async fn prepare_files(paths: Vec<PathBuf>) -> Result<PreparedFiles> {
    if paths.is_empty() {
        return Err(FsPlanError::EmptySelection);
    }

    let mut files = Vec::new();
    let mut seen_paths = HashSet::new();

    for path in paths {
        let root_name = input_root_name(&path)?;
        let mut stack = vec![(path, PathBuf::from(root_name))];

        while let Some((source_path, transfer_path)) = stack.pop() {
            let metadata = fs::symlink_metadata(&source_path).await.map_err(|source| {
                FsPlanError::ReadMetadata {
                    path: source_path.clone(),
                    source,
                }
            })?;
            let file_type = metadata.file_type();

            if file_type.is_symlink() {
                return Err(FsPlanError::SymbolicLink { path: source_path });
            }

            if file_type.is_dir() {
                let mut entries = fs::read_dir(&source_path).await.map_err(|source| {
                    FsPlanError::ReadDirectory {
                        path: source_path.clone(),
                        source,
                    }
                })?;
                while let Some(entry) =
                    entries
                        .next_entry()
                        .await
                        .map_err(|source| FsPlanError::ReadDirectory {
                            path: source_path.clone(),
                            source,
                        })?
                {
                    let child_name = entry.file_name();
                    let child_name = child_name.to_str().ok_or_else(|| {
                        FsPlanError::InvalidUtf8PathComponent {
                            path: source_path.clone(),
                        }
                    })?;
                    stack.push((entry.path(), transfer_path.join(child_name)));
                }
                continue;
            }

            if !file_type.is_file() {
                return Err(FsPlanError::UnsupportedFileType { path: source_path });
            }

            let transfer_path = normalize_transfer_path(&transfer_path)?;
            if !seen_paths.insert(transfer_path.clone()) {
                return Err(FsPlanError::DuplicateTransferPath {
                    path: transfer_path,
                });
            }

            files.push(PreparedFile {
                source_path: absolute_source_path(&source_path)?,
                transfer_path,
                size: metadata.len(),
            });
        }
    }

    if files.is_empty() {
        return Err(FsPlanError::NoRegularFiles);
    }

    files.sort_by(|left, right| left.transfer_path.cmp(&right.transfer_path));

    let mut manifest_files = Vec::with_capacity(files.len());
    let mut total_size = 0_u64;
    for prepared in &files {
        total_size = total_size
            .checked_add(prepared.size)
            .ok_or(FsPlanError::TotalSizeOverflow)?;

        manifest_files.push(OfferFile {
            path: prepared.transfer_path.clone(),
            size: prepared.size,
        });
    }

    Ok(PreparedFiles {
        files,
        manifest: OfferManifest {
            file_count: manifest_files.len() as u64,
            total_size,
            files: manifest_files,
            collection_hash: None,
        },
    })
}

fn absolute_source_path(path: &PathBuf) -> Result<PathBuf> {
    if path.is_absolute() {
        return Ok(path.clone());
    }

    Ok(std::env::current_dir()
        .map_err(|source| FsPlanError::CurrentDirectory { source })?
        .join(path))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs_plan::test_support::{TestDir, write_test_file};

    #[tokio::test]
    async fn prepare_files_expands_directories_and_preserves_roots()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let temp = TestDir::new("drift-prepare").await?;
        let notes = temp.path.join("notes.txt");
        let photos = temp.path.join("photos");
        let backup = temp.path.join("backup");
        write_test_file(&notes, "notes").await?;
        write_test_file(&photos.join("trip/cat.jpg"), "cat").await?;
        write_test_file(&backup.join("a.jpg"), "backup").await?;

        let prepared = prepare_files(vec![photos, notes, backup]).await?;
        let paths: Vec<_> = prepared
            .manifest
            .files
            .iter()
            .map(|file| file.path.as_str())
            .collect();

        assert_eq!(
            paths,
            vec!["backup/a.jpg", "notes.txt", "photos/trip/cat.jpg"]
        );
        assert_eq!(prepared.manifest.file_count, 3);

        Ok(())
    }

    #[tokio::test]
    async fn prepare_files_rejects_duplicate_transfer_paths()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let temp = TestDir::new("drift-duplicates").await?;
        let file = temp.path.join("dup.txt");
        write_test_file(&file, "dup").await?;

        let err = prepare_files(vec![file.clone(), file]).await.unwrap_err();
        assert!(err.to_string().contains("duplicate transfer path"));

        Ok(())
    }

    #[tokio::test]
    async fn prepare_files_normalizes_source_paths_for_imports()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let prepared = prepare_files(vec![PathBuf::from("Cargo.toml")]).await?;
        assert!(prepared.files[0].source_path.is_absolute());

        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn prepare_files_rejects_symbolic_links()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        use std::os::unix::fs::symlink;

        let temp = TestDir::new("drift-symlink").await?;
        let target = temp.path.join("target.txt");
        let link = temp.path.join("link.txt");
        write_test_file(&target, "target").await?;
        symlink(&target, &link)?;

        let err = prepare_files(vec![link]).await.unwrap_err();
        assert!(err.to_string().contains("symbolic link"));

        Ok(())
    }
}
