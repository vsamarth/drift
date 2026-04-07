use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use tokio::fs;

/// Validates a transfer path string: non-empty, relative, `/`-separated, no `.` or `..`.
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

pub fn input_root_name(path: &Path) -> Result<String> {
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

pub fn normalize_transfer_path(path: &Path) -> Result<String> {
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

async fn path_exists(path: &Path) -> Result<bool> {
    match fs::metadata(path).await {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(err).with_context(|| format!("checking {}", path.display())),
    }
}

/// Temporary directory under the process temp dir; deleted on drop.
#[derive(Debug)]
pub struct ScratchDir {
    pub path: PathBuf,
}

impl ScratchDir {
    pub async fn new(prefix: &str, session_id: &str) -> Result<Self> {
        let id_digest = blake3::hash(session_id.as_bytes()).to_hex();
        let unique = format!(
            "{prefix}-{id_digest}-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .context("system clock before unix epoch")?
                .as_nanos()
        );
        let path = std::env::temp_dir().join(unique);
        fs::create_dir_all(&path)
            .await
            .with_context(|| format!("creating temp directory {}", path.display()))?;
        Ok(Self { path })
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}
