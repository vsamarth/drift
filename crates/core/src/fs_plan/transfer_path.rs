use std::path::{Component, Path};

use anyhow::{Result, anyhow, bail};

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

pub(crate) fn input_root_name(path: &Path) -> Result<String> {
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

pub(crate) fn normalize_transfer_path(path: &Path) -> Result<String> {
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

#[cfg(test)]
mod tests {
    use super::validate_transfer_path;

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
