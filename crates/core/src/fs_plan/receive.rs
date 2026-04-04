use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use tokio::fs;

use crate::error::{DriftError, DriftErrorKind, Result};
use crate::rendezvous::OfferManifest;

use super::transfer_path::validate_transfer_path;

#[derive(Debug, Clone)]
pub struct ExpectedFile {
    pub size: u64,
    pub destination: PathBuf,
}

pub async fn build_expected_files(
    manifest: &OfferManifest,
    out_dir: &Path,
) -> Result<BTreeMap<String, ExpectedFile>> {
    if manifest.file_count != manifest.files.len() as u64 {
        return Err(DriftError::invalid_input(
            "offer manifest file count does not match the file list",
        ));
    }

    let mut total_size = 0_u64;
    let mut expected = BTreeMap::new();

    for file in &manifest.files {
        total_size = total_size
            .checked_add(file.size)
            .ok_or_else(|| {
                DriftError::with_reason(
                    DriftErrorKind::Internal,
                    "offer manifest total size exceeds u64",
                )
            })?;

        let segments = validate_transfer_path(&file.path)?;
        if expected.contains_key(&file.path)
            || expected
                .keys()
                .any(|existing: &String| existing.starts_with(&format!("{}/", file.path)))
        {
            return Err(DriftError::with_reason(
                DriftErrorKind::FileConflict,
                format!("offer manifest contains a conflicting path {}", file.path),
            ));
        }

        for depth in 1..segments.len() {
            let parent = segments[..depth].join("/");
            if expected.contains_key(&parent) {
                return Err(DriftError::with_reason(
                    DriftErrorKind::FileConflict,
                    format!("offer manifest contains a conflicting path {}", file.path),
                ));
            }
        }

        let destination = resolve_transfer_destination(out_dir, &file.path)?;
        ensure_destination_available(out_dir, &destination).await?;

        expected.insert(
            file.path.clone(),
            ExpectedFile {
                size: file.size,
                destination,
            },
        );
    }

    if total_size != manifest.total_size {
        return Err(DriftError::invalid_input(
            "offer manifest total size does not match the file list",
        ));
    }

    Ok(expected)
}

pub fn resolve_transfer_destination(out_dir: &Path, transfer_path: &str) -> Result<PathBuf> {
    let segments = validate_transfer_path(transfer_path)?;
    let mut destination = out_dir.to_path_buf();
    for segment in segments {
        destination.push(segment);
    }
    Ok(destination)
}

pub async fn ensure_destination_available(out_dir: &Path, destination: &Path) -> Result<()> {
    if path_exists(destination).await? {
        return Err(DriftError::with_reason(
            DriftErrorKind::FileConflict,
            format!("destination already exists: {}", destination.display()),
        ));
    }

    let mut current = destination.parent();
    while let Some(parent) = current {
        if parent == out_dir {
            break;
        }

        match fs::metadata(parent).await {
            Ok(metadata) => {
                if !metadata.is_dir() {
                    return Err(DriftError::with_reason(
                        DriftErrorKind::FileConflict,
                        format!(
                        "destination parent is not a directory: {}",
                        parent.display()
                        ),
                    ));
                }
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                return Err(DriftError::io(
                    format!("checking {}", parent.display()),
                    &err,
                ));
            }
        }

        current = parent.parent();
    }

    Ok(())
}

async fn path_exists(path: &Path) -> Result<bool> {
    match fs::metadata(path).await {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(DriftError::io(format!("checking {}", path.display()), &err)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs_plan::test_support::{TestDir, write_test_file};
    use crate::rendezvous::{OfferFile, OfferManifest};

    #[tokio::test]
    async fn build_expected_files_rejects_existing_destinations() -> Result<()> {
        let temp = TestDir::new("drift-expected").await?;
        let out_dir = temp.path.join("downloads");
        fs::create_dir_all(&out_dir).await?;
        write_test_file(&out_dir.join("photos/cat.jpg"), "existing").await?;

        let manifest = OfferManifest {
            files: vec![OfferFile {
                path: "photos/cat.jpg".to_owned(),
                size: 3,
            }],
            file_count: 1,
            total_size: 3,
        };

        let err = build_expected_files(&manifest, &out_dir).await.unwrap_err();
        assert!(err.to_string().contains("destination already exists"));

        Ok(())
    }

    #[tokio::test]
    async fn build_expected_files_rejects_conflicting_incoming_paths() -> Result<()> {
        let temp = TestDir::new("drift-conflicts").await?;
        let out_dir = temp.path.join("downloads");
        fs::create_dir_all(&out_dir).await?;

        let manifest = OfferManifest {
            files: vec![
                OfferFile {
                    path: "photos".to_owned(),
                    size: 3,
                },
                OfferFile {
                    path: "photos/cat.jpg".to_owned(),
                    size: 3,
                },
            ],
            file_count: 2,
            total_size: 6,
        };

        let err = build_expected_files(&manifest, &out_dir).await.unwrap_err();
        assert!(err.to_string().contains("conflicting path"));

        Ok(())
    }
}
