use std::path::PathBuf;

use iroh_blobs::{
    BlobFormat,
    api::{
        Store, TempTag,
        blobs::{AddPathOptions, ImportMode},
    },
};
use tracing::{instrument, trace};

use super::error::{BlobError, BlobTextError, Result as BlobResult};
use crate::{
    fs_plan::FsPlanError,
    transfer::path::{input_root_name, normalize_transfer_path},
};

#[derive(Debug)]
pub(super) struct ImportedFile {
    pub(super) transfer_path: String,
    pub(super) temp_tag: TempTag,
    pub(super) size_bytes: u64,
}

#[instrument(skip_all, fields(input_path = %path.display()))]
pub(crate) fn walk_files(path: PathBuf) -> Result<Vec<(String, PathBuf)>, FsPlanError> {
    let path = absolute_input_path(path)?;
    let metadata =
        std::fs::symlink_metadata(&path).map_err(|source| FsPlanError::ReadMetadata {
            path: path.clone(),
            source,
        })?;
    let file_type = metadata.file_type();

    if file_type.is_symlink() {
        return Err(FsPlanError::SymbolicLink { path });
    }

    let mut discovered = Vec::new();
    let root_name = input_root_name(&path)?;

    if file_type.is_file() {
        discovered.push((root_name, path));
    } else if file_type.is_dir() {
        let mut stack = vec![(path, PathBuf::from(root_name))];
        while let Some((current_path, transfer_path)) = stack.pop() {
            let current_metadata = std::fs::symlink_metadata(&current_path).map_err(|source| {
                FsPlanError::ReadMetadata {
                    path: current_path.clone(),
                    source,
                }
            })?;
            let current_type = current_metadata.file_type();

            if current_type.is_symlink() {
                return Err(FsPlanError::SymbolicLink { path: current_path });
            }

            if current_type.is_file() {
                discovered.push((normalize_transfer_path(&transfer_path)?, current_path));
                continue;
            }

            if !current_type.is_dir() {
                return Err(FsPlanError::UnsupportedFileType { path: current_path });
            }

            let entries =
                std::fs::read_dir(&current_path).map_err(|source| FsPlanError::ReadDirectory {
                    path: current_path.clone(),
                    source,
                })?;

            for entry in entries {
                let entry = entry.map_err(|source| FsPlanError::ReadDirectory {
                    path: current_path.clone(),
                    source,
                })?;
                let child_name = entry
                    .file_name()
                    .into_string()
                    .map_err(|_| FsPlanError::InvalidUtf8PathComponent { path: entry.path() })?;
                stack.push((entry.path(), transfer_path.join(child_name)));
            }
        }
    } else {
        return Err(FsPlanError::UnsupportedFileType { path });
    }

    discovered.sort_by(|(a, _), (b, _)| a.cmp(b));
    trace!(file_count = discovered.len(), "discovered files for import");
    Ok(discovered)
}

fn absolute_input_path(path: PathBuf) -> Result<PathBuf, FsPlanError> {
    if path.is_absolute() {
        return Ok(path);
    }

    Ok(std::env::current_dir()
        .map_err(|source| FsPlanError::CurrentDirectory { source })?
        .join(path))
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
    #[cfg(unix)]
    use std::os::unix::fs::symlink;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use iroh_blobs::{api::Store, store::mem::MemStore};

    use super::{import_files, walk_files};

    type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

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

    #[cfg(unix)]
    #[test]
    fn walk_files_rejects_nested_symbolic_links() -> Result<()> {
        let root = unique_temp_dir("drift-walk-files-symlink");
        let input = root.join("input");
        std::fs::create_dir_all(&input)?;
        std::fs::write(input.join("real.txt"), b"real")?;
        symlink("real.txt", input.join("link.txt"))?;

        let err = walk_files(input).expect_err("expected symlink rejection");
        assert!(err.to_string().contains("symbolic link"));

        let _ = std::fs::remove_dir_all(&root);
        Ok(())
    }
}
