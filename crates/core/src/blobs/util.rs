use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use iroh_blobs::{
    BlobFormat,
    api::{
        Store, TempTag,
        blobs::{AddPathOptions, ImportMode},
    },
};
use tokio::fs;
use tracing::{instrument, trace};
use walkdir::WalkDir;

use super::error::{BlobError, BlobTextError, Result as BlobResult};
use crate::transfer::path::normalize_transfer_path;

/// Temporary directory under the process temp dir; deleted on drop.
#[derive(Debug)]
pub(super) struct ScratchDir {
    pub(super) path: PathBuf,
}

impl ScratchDir {
    pub(super) async fn new(prefix: &str, session_id: &str) -> BlobResult<Self> {
        let id_digest = blake3::hash(session_id.as_bytes()).to_hex();
        let clock = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|source| {
                BlobError::scratch_dir_create(
                    std::env::temp_dir(),
                    BlobTextError::new(source.to_string()),
                )
            })?;
        let unique = format!("{prefix}-{id_digest}-{}", clock.as_nanos());
        let path = std::env::temp_dir().join(unique);
        fs::create_dir_all(&path).await.map_err(|source| {
            BlobError::scratch_dir_create(path.clone(), BlobTextError::new(source.to_string()))
        })?;
        Ok(Self { path })
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

#[derive(Debug)]
pub(super) struct ImportedFile {
    pub(super) transfer_path: String,
    pub(super) temp_tag: TempTag,
    pub(super) size_bytes: u64,
}

#[instrument(skip_all, fields(input_path = %path.display()))]
fn walk_files(path: PathBuf) -> BlobResult<Vec<(String, PathBuf)>> {
    let path = path.canonicalize().map_err(|source| {
        BlobError::import_files(
            path.display().to_string(),
            BlobTextError::new(format!("resolving input path {}: {source}", path.display())),
        )
    })?;
    if !path.exists() {
        return Err(BlobError::import_files(
            path.display().to_string(),
            BlobTextError::new(format!("{} does not exist", path.display())),
        ));
    }
    let discovery_root = path.parent().ok_or_else(|| {
        BlobError::import_files(
            path.display().to_string(),
            BlobTextError::new("failed to determine input root directory"),
        )
    })?;

    let mut discovered = WalkDir::new(path.clone())
        .into_iter()
        .filter_map(|entry| match entry {
            Ok(e) if e.file_type().is_file() => Some(Ok(e.into_path())),
            _ => None,
        })
        .map(
            |file_path: std::result::Result<PathBuf, walkdir::Error>| -> BlobResult<(String, PathBuf)> {
                let file_path = file_path.map_err(|source| {
                    BlobError::import_files(
                        path.display().to_string(),
                        BlobTextError::new(source.to_string()),
                    )
                })?;
                let relative = file_path
                    .strip_prefix(discovery_root)
                    .map_err(|source| {
                        BlobError::import_files(
                            path.display().to_string(),
                            BlobTextError::new(format!(
                                "failed to compute relative path for {} using root {}: {source}",
                                file_path.display(),
                                discovery_root.display()
                            )),
                        )
                    })?
                    .to_path_buf();
                let transfer_path = normalize_transfer_path(&relative).map_err(|source| {
                    BlobError::import_files(
                        path.display().to_string(),
                        BlobTextError::new(source.to_string()),
                    )
                })?;
                Ok((transfer_path, file_path))
            },
        )
        .collect::<BlobResult<Vec<(String, PathBuf)>>>()?;
    discovered.sort_by(|(a, _), (b, _)| a.cmp(b));
    trace!(file_count = discovered.len(), "discovered files for import");
    Ok(discovered)
}

#[instrument(skip(store), fields(input_path = %path.display()))]
pub(super) async fn import_files(store: &Store, path: PathBuf) -> BlobResult<Vec<ImportedFile>> {
    let path_display = path.display().to_string();
    let files =
        walk_files(path).map_err(|source| BlobError::import_files(path_display.clone(), source))?;

    let mut imported = Vec::with_capacity(files.len());
    for (transfer_path, local_path) in files {
        trace!(
            transfer_path = %transfer_path,
            local_path = %local_path.display(),
            "importing file into blob store"
        );
        let tag = store
            .add_path_with_opts(AddPathOptions {
                path: local_path.clone(),
                format: BlobFormat::Raw,
                mode: ImportMode::TryReference,
            })
            .temp_tag()
            .await
            .map_err(|source| {
                BlobError::import_files(
                    path_display.clone(),
                    BlobTextError::new(format!("importing {}: {source}", local_path.display())),
                )
            })?;
        imported.push(ImportedFile {
            transfer_path,
            temp_tag: tag,
            size_bytes: std::fs::metadata(&local_path)
                .map_err(|source| {
                    BlobError::import_files(
                        path_display.clone(),
                        BlobTextError::new(format!(
                            "reading metadata for {}: {source}",
                            local_path.display()
                        )),
                    )
                })?
                .len(),
        });
    }
    trace!(imported_count = imported.len(), "finished importing files");
    Ok(imported)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use anyhow::Result;
    use iroh_blobs::{api::Store, store::mem::MemStore};

    use super::import_files;

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);
        let unique = format!(
            "{}-{}-{}",
            prefix,
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time")
                .as_nanos(),
            NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed)
        );
        std::env::temp_dir().join(unique)
    }

    #[tokio::test]
    async fn import_collects_files_in_stable_order_with_sizes() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-import");
        let input = root.join("input");
        let nested = input.join("nested");
        std::fs::create_dir_all(&nested)?;
        std::fs::write(input.join("z.txt"), b"zzz")?;
        std::fs::write(nested.join("a.txt"), b"aaaa")?;
        let store: Store = MemStore::new().into();

        let imported = import_files(&store, input).await?;
        let transfer_paths = imported
            .iter()
            .map(|file| file.transfer_path.clone())
            .collect::<Vec<_>>();
        let total_size = imported.iter().map(|file| file.size_bytes).sum::<u64>();

        assert_eq!(transfer_paths, vec!["input/nested/a.txt", "input/z.txt"]);
        assert_eq!(total_size, 7);
        assert_eq!(imported.len(), 2);

        let _ = std::fs::remove_dir_all(&root);
        Ok(())
    }

    #[tokio::test]
    async fn import_accepts_single_file_path() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-single-file");
        let input_dir = root.join("input");
        std::fs::create_dir_all(&input_dir)?;
        let file_path = input_dir.join("hello.txt");
        std::fs::write(&file_path, b"hello")?;
        let store: Store = MemStore::new().into();

        let imported = import_files(&store, file_path).await?;
        assert_eq!(imported.len(), 1);
        assert_eq!(imported[0].transfer_path, "hello.txt");
        assert_eq!(imported[0].size_bytes, 5);

        let _ = std::fs::remove_dir_all(&root);
        Ok(())
    }
}
