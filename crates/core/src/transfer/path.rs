use std::path::{Component, Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use thiserror::Error;
use tokio::fs;

/// Validates a transfer path string: non-empty, relative, `/`-separated, no `.` or `..`.
#[derive(Debug, Error)]
pub enum TransferPathError {
    #[error("transfer path must not be empty")]
    Empty,
    #[error("transfer path must use '/' separators")]
    InvalidSeparator,
    #[error("transfer path must be relative")]
    NotRelative,
    #[error("transfer path contains an invalid segment")]
    InvalidSegment,
    #[error("{path} does not have a valid UTF-8 final path component")]
    InvalidUtf8RootName { path: PathBuf },
    #[error("{path} contains a path component that is not valid UTF-8")]
    InvalidUtf8PathComponent { path: PathBuf },
    #[error("destination already exists: {path}")]
    DestinationExists { path: PathBuf },
    #[error("destination parent is not a directory: {path}")]
    DestinationParentNotDirectory { path: PathBuf },
    #[error("checking {path}")]
    CheckPath {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("resolving current working directory")]
    CurrentDirectory {
        #[source]
        source: std::io::Error,
    },
    #[error("output directory is not absolute: {path}")]
    OutputNotAbsolute { path: PathBuf },
    #[error("system clock before unix epoch")]
    SystemClockBeforeUnixEpoch {
        #[source]
        source: std::time::SystemTimeError,
    },
    #[error("creating temp directory {path}")]
    CreateScratchDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

pub fn validate_transfer_path(path: &str) -> std::result::Result<Vec<&str>, TransferPathError> {
    if path.is_empty() {
        return Err(TransferPathError::Empty);
    }

    if path.contains('\\') {
        return Err(TransferPathError::InvalidSeparator);
    }

    if Path::new(path).is_absolute() {
        return Err(TransferPathError::NotRelative);
    }

    let mut segments = Vec::new();
    for segment in path.split('/') {
        if segment.is_empty() || segment == "." || segment == ".." {
            return Err(TransferPathError::InvalidSegment);
        }
        segments.push(segment);
    }

    Ok(segments)
}

pub fn input_root_name(path: &Path) -> std::result::Result<String, TransferPathError> {
    path.file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(|| TransferPathError::InvalidUtf8RootName {
            path: path.to_path_buf(),
        })
        .map(|name| name.to_owned())
}

pub fn normalize_transfer_path(path: &Path) -> std::result::Result<String, TransferPathError> {
    let mut segments = Vec::new();

    for component in path.components() {
        match component {
            Component::Normal(segment) => {
                let segment = segment.to_str().ok_or_else(|| {
                    TransferPathError::InvalidUtf8PathComponent {
                        path: path.to_path_buf(),
                    }
                })?;
                segments.push(segment);
            }
            _ => return Err(TransferPathError::NotRelative),
        }
    }

    if segments.is_empty() {
        return Err(TransferPathError::Empty);
    }

    let normalized = segments.join("/");
    validate_transfer_path(&normalized)?;
    Ok(normalized)
}

pub fn resolve_transfer_destination(
    out_dir: &Path,
    transfer_path: &str,
) -> std::result::Result<PathBuf, TransferPathError> {
    let segments = validate_transfer_path(transfer_path)?;
    let mut destination = out_dir.to_path_buf();
    for segment in segments {
        destination.push(segment);
    }
    Ok(destination)
}

pub async fn ensure_destination_available(
    out_dir: &Path,
    destination: &Path,
) -> std::result::Result<(), TransferPathError> {
    if path_exists(destination).await? {
        return Err(TransferPathError::DestinationExists {
            path: destination.to_path_buf(),
        });
    }

    let mut current = destination.parent();
    while let Some(parent) = current {
        if parent == out_dir {
            break;
        }

        match fs::metadata(parent).await {
            Ok(metadata) => {
                if !metadata.is_dir() {
                    return Err(TransferPathError::DestinationParentNotDirectory {
                        path: parent.to_path_buf(),
                    });
                }
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                return Err(TransferPathError::CheckPath {
                    path: parent.to_path_buf(),
                    source: err,
                });
            }
        }

        current = parent.parent();
    }

    Ok(())
}

pub fn resolve_output_dir(out_dir: &Path) -> std::result::Result<PathBuf, TransferPathError> {
    let base = if out_dir.is_absolute() {
        out_dir.to_path_buf()
    } else {
        std::env::current_dir()
            .map_err(|source| TransferPathError::CurrentDirectory { source })?
            .join(out_dir)
    };

    let mut resolved = PathBuf::new();
    for component in base.components() {
        match component {
            Component::Prefix(prefix) => resolved.push(prefix.as_os_str()),
            Component::RootDir => resolved.push(component.as_os_str()),
            Component::CurDir => {}
            Component::ParentDir => {
                resolved.pop();
            }
            Component::Normal(segment) => resolved.push(segment),
        }
    }

    if !resolved.is_absolute() {
        return Err(TransferPathError::OutputNotAbsolute { path: resolved });
    }

    Ok(resolved)
}

async fn path_exists(path: &Path) -> std::result::Result<bool, TransferPathError> {
    match fs::metadata(path).await {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(TransferPathError::CheckPath {
            path: path.to_path_buf(),
            source: err,
        }),
    }
}

/// Temporary directory under the process temp dir; deleted on drop.
#[derive(Debug)]
pub struct ScratchDir {
    pub path: PathBuf,
}

impl ScratchDir {
    pub async fn new(prefix: &str, session_id: &str) -> std::result::Result<Self, TransferPathError> {
        let id_digest = blake3::hash(session_id.as_bytes()).to_hex();
        let unique = format!(
            "{prefix}-{id_digest}-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_err(|source| TransferPathError::SystemClockBeforeUnixEpoch { source })?
                .as_nanos()
        );
        let path = std::env::temp_dir().join(unique);
        fs::create_dir_all(&path)
            .await
            .map_err(|source| TransferPathError::CreateScratchDir {
                path: path.clone(),
                source,
            })?;
        Ok(Self { path })
    }
}

impl Drop for ScratchDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::resolve_output_dir;
    use anyhow::Result;
    use std::path::Path;

    #[test]
    fn resolves_relative_output_dir_against_current_dir() -> Result<()> {
        let cwd = std::env::current_dir()?;
        let resolved = resolve_output_dir(Path::new("downloads"))?;
        assert_eq!(resolved, cwd.join("downloads"));
        Ok(())
    }

    #[test]
    fn normalizes_output_dir_lexically() -> Result<()> {
        let cwd = std::env::current_dir()?;
        let resolved = resolve_output_dir(Path::new("./downloads/../downloads/inbox"))?;
        assert_eq!(resolved, cwd.join("downloads/inbox"));
        Ok(())
    }
}
