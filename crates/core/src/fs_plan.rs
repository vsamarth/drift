use std::collections::{BTreeMap, HashSet};
use std::path::{Component, Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};
use tokio::fs;

use crate::rendezvous::{OfferFile, OfferManifest};

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

#[derive(Debug, Clone)]
pub struct ExpectedFile {
    pub size: u64,
    pub destination: PathBuf,
}

pub async fn prepare_files(paths: Vec<PathBuf>) -> Result<PreparedFiles> {
    if paths.is_empty() {
        bail!("provide at least one file to send");
    }

    let mut files = Vec::new();
    let mut seen_paths = HashSet::new();

    for path in paths {
        let root_name = input_root_name(&path)?;
        let mut stack = vec![(path, PathBuf::from(root_name))];

        while let Some((source_path, transfer_path)) = stack.pop() {
            let metadata = fs::symlink_metadata(&source_path)
                .await
                .with_context(|| format!("reading metadata for {}", source_path.display()))?;
            let file_type = metadata.file_type();

            if file_type.is_symlink() {
                bail!(
                    "{} is a symbolic link; only regular files are supported",
                    source_path.display()
                );
            }

            if file_type.is_dir() {
                let mut entries = fs::read_dir(&source_path)
                    .await
                    .with_context(|| format!("reading directory {}", source_path.display()))?;
                while let Some(entry) = entries
                    .next_entry()
                    .await
                    .with_context(|| format!("reading directory {}", source_path.display()))?
                {
                    let child_name = entry.file_name();
                    let child_name = child_name.to_str().ok_or_else(|| {
                        anyhow!(
                            "{} contains a path component that is not valid UTF-8",
                            source_path.display()
                        )
                    })?;
                    stack.push((entry.path(), transfer_path.join(child_name)));
                }
                continue;
            }

            if !file_type.is_file() {
                bail!(
                    "{} is not a regular file or directory",
                    source_path.display()
                );
            }

            let transfer_path = normalize_transfer_path(&transfer_path)?;
            if !seen_paths.insert(transfer_path.clone()) {
                bail!("duplicate transfer path {transfer_path}");
            }

            files.push(PreparedFile {
                source_path,
                transfer_path,
                size: metadata.len(),
            });
        }
    }

    if files.is_empty() {
        bail!("no regular files found to send");
    }

    files.sort_by(|left, right| left.transfer_path.cmp(&right.transfer_path));

    let mut manifest_files = Vec::with_capacity(files.len());
    let mut total_size = 0_u64;
    for prepared in &files {
        total_size = total_size
            .checked_add(prepared.size)
            .ok_or_else(|| anyhow!("total transfer size exceeds u64"))?;

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
        },
    })
}

pub async fn build_expected_files(
    manifest: &OfferManifest,
    out_dir: &Path,
) -> Result<BTreeMap<String, ExpectedFile>> {
    if manifest.file_count != manifest.files.len() as u64 {
        bail!("offer manifest file count does not match the file list");
    }

    let mut total_size = 0_u64;
    let mut expected = BTreeMap::new();

    for file in &manifest.files {
        total_size = total_size
            .checked_add(file.size)
            .ok_or_else(|| anyhow!("offer manifest total size exceeds u64"))?;

        let segments = validate_transfer_path(&file.path)?;
        if expected.contains_key(&file.path)
            || expected
                .keys()
                .any(|existing: &String| existing.starts_with(&format!("{}/", file.path)))
        {
            bail!("offer manifest contains a conflicting path {}", file.path);
        }

        for depth in 1..segments.len() {
            let parent = segments[..depth].join("/");
            if expected.contains_key(&parent) {
                bail!("offer manifest contains a conflicting path {}", file.path);
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
        bail!("offer manifest total size does not match the file list");
    }

    Ok(expected)
}

pub fn validate_transfer_path(path: &str) -> Result<Vec<&str>> {
    if path.is_empty() {
        bail!("transfer path must not be empty");
    }

    if path.contains('\\') {
        bail!("transfer path must use '/' separators");
    }

    if Path::new(path).is_absolute() {
        bail!("transfer path must be relative");
    }

    let mut segments = Vec::new();
    for segment in path.split('/') {
        if segment.is_empty() || segment == "." || segment == ".." {
            bail!("transfer path contains an invalid segment");
        }
        segments.push(segment);
    }

    Ok(segments)
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
        bail!("destination already exists: {}", destination.display());
    }

    let mut current = destination.parent();
    while let Some(parent) = current {
        if parent == out_dir {
            break;
        }

        match fs::metadata(parent).await {
            Ok(metadata) => {
                if !metadata.is_dir() {
                    bail!(
                        "destination parent is not a directory: {}",
                        parent.display()
                    );
                }
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                return Err(err).with_context(|| format!("checking {}", parent.display()));
            }
        }

        current = parent.parent();
    }

    Ok(())
}

fn input_root_name(path: &Path) -> Result<String> {
    path.file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| {
            anyhow!(
                "{} does not have a valid UTF-8 final path component",
                path.display()
            )
        })
        .map(|name| name.to_owned())
}

fn normalize_transfer_path(path: &Path) -> Result<String> {
    let mut segments = Vec::new();

    for component in path.components() {
        match component {
            Component::Normal(segment) => {
                let segment = segment.to_str().ok_or_else(|| {
                    anyhow!(
                        "{} contains a path component that is not valid UTF-8",
                        path.display()
                    )
                })?;
                segments.push(segment);
            }
            _ => bail!("transfer path must be relative"),
        }
    }

    if segments.is_empty() {
        bail!("transfer path must not be empty");
    }

    let normalized = segments.join("/");
    validate_transfer_path(&normalized)?;
    Ok(normalized)
}

async fn path_exists(path: &Path) -> Result<bool> {
    match fs::metadata(path).await {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(err).with_context(|| format!("checking {}", path.display())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        async fn new(prefix: &str) -> Result<Self> {
            let unique = format!(
                "{}-{}-{}",
                prefix,
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .expect("system time")
                    .as_nanos(),
                NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed)
            );
            let path = std::env::temp_dir().join(unique);
            fs::create_dir_all(&path).await?;
            Ok(Self { path })
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }

    async fn write_test_file(path: &Path, contents: &str) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).await?;
        }
        fs::write(path, contents).await?;
        Ok(())
    }

    #[tokio::test]
    async fn prepare_files_expands_directories_and_preserves_roots() -> Result<()> {
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
    async fn prepare_files_rejects_duplicate_transfer_paths() -> Result<()> {
        let temp = TestDir::new("drift-duplicates").await?;
        let file = temp.path.join("dup.txt");
        write_test_file(&file, "dup").await?;

        let err = prepare_files(vec![file.clone(), file]).await.unwrap_err();
        assert!(err.to_string().contains("duplicate transfer path"));

        Ok(())
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn prepare_files_rejects_symbolic_links() -> Result<()> {
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

    #[test]
    fn validate_transfer_path_rejects_unsafe_inputs() {
        for invalid in [
            "",
            "/tmp/file",
            "../file",
            "a//b",
            "a/./b",
            "a/../b",
            r"a\b",
        ] {
            assert!(validate_transfer_path(invalid).is_err(), "{invalid}");
        }
    }
}
