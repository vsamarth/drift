use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::fs;

type Result<T> = std::result::Result<T, ConflictError>;

#[derive(Debug, Error)]
pub enum ConflictError {
    #[error("destination already exists: {path}")]
    DestinationExists { path: PathBuf },
    #[error("cannot rename root path")]
    CannotRenameRootPath,
    #[error("invalid file name")]
    InvalidFileName,
    #[error("too many conflicting files for {path}")]
    TooManyConflicts { path: String },
    #[error("checking {path}")]
    CheckPath {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ConflictPolicy {
    Reject,
    Overwrite,
    Rename,
}

impl ConflictPolicy {
    /// Resolves a potential file conflict at the given destination path.
    ///
    /// Returns the final path to use for the file, which may be different
    /// from the input path if the policy is [`ConflictPolicy::Rename`].
    pub async fn resolve(&self, destination: &Path) -> Result<PathBuf> {
        if !path_exists(destination).await? {
            return Ok(destination.to_path_buf());
        }

        match self {
            ConflictPolicy::Reject => Err(ConflictError::DestinationExists {
                path: destination.to_path_buf(),
            }),
            ConflictPolicy::Overwrite => Ok(destination.to_path_buf()),
            ConflictPolicy::Rename => find_available_name(destination).await,
        }
    }
}

async fn find_available_name(path: &Path) -> Result<PathBuf> {
    let parent = path.parent().ok_or(ConflictError::CannotRenameRootPath)?;
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or(ConflictError::InvalidFileName)?;

    let (stem, extension) = match file_name.rfind('.') {
        Some(idx) if idx > 0 => (&file_name[..idx], &file_name[idx..]),
        _ => (file_name, ""),
    };

    let mut counter = 1;
    loop {
        let new_name = format!("{} ({}){}", stem, counter, extension);
        let new_path = parent.join(new_name);

        if !path_exists(&new_path).await? {
            return Ok(new_path);
        }

        counter += 1;
        if counter > 1000 {
            return Err(ConflictError::TooManyConflicts {
                path: file_name.to_owned(),
            });
        }
    }
}

async fn path_exists(path: &Path) -> Result<bool> {
    match fs::metadata(path).await {
        Ok(_) => Ok(true),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(err) => Err(ConflictError::CheckPath {
            path: path.to_path_buf(),
            source: err,
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fs_plan::test_support::{TestDir, write_test_file};
    use std::error::Error as StdError;

    type TestResult<T> = std::result::Result<T, Box<dyn StdError>>;

    #[tokio::test]
    async fn test_policy_reject() -> TestResult<()> {
        let temp = TestDir::new("drift-policy-reject").await?;
        let file = temp.path.join("test.txt");
        write_test_file(&file, "content").await?;

        let policy = ConflictPolicy::Reject;
        let err = policy.resolve(&file).await.unwrap_err();
        assert!(err.to_string().contains("already exists"));

        let non_existent = temp.path.join("new.txt");
        let resolved = policy.resolve(&non_existent).await?;
        assert_eq!(resolved, non_existent);

        Ok(())
    }

    #[tokio::test]
    async fn test_policy_overwrite() -> TestResult<()> {
        let temp = TestDir::new("drift-policy-overwrite").await?;
        let file = temp.path.join("test.txt");
        write_test_file(&file, "content").await?;

        let policy = ConflictPolicy::Overwrite;
        let resolved = policy.resolve(&file).await?;
        assert_eq!(resolved, file);

        Ok(())
    }

    #[tokio::test]
    async fn test_policy_rename() -> TestResult<()> {
        let temp = TestDir::new("drift-policy-rename").await?;
        let file = temp.path.join("test.txt");
        write_test_file(&file, "content").await?;

        let policy = ConflictPolicy::Rename;

        // First rename: test.txt -> test (1).txt
        let resolved = policy.resolve(&file).await?;
        assert_eq!(resolved, temp.path.join("test (1).txt"));

        // Second rename: test.txt exists and test (1).txt exists -> test (2).txt
        write_test_file(&temp.path.join("test (1).txt"), "content").await?;
        let resolved = policy.resolve(&file).await?;
        assert_eq!(resolved, temp.path.join("test (2).txt"));

        Ok(())
    }

    #[tokio::test]
    async fn test_policy_rename_no_extension() -> TestResult<()> {
        let temp = TestDir::new("drift-policy-rename-no-ext").await?;
        let file = temp.path.join("README");
        write_test_file(&file, "content").await?;

        let policy = ConflictPolicy::Rename;
        let resolved = policy.resolve(&file).await?;
        assert_eq!(resolved, temp.path.join("README (1)"));

        Ok(())
    }

    #[tokio::test]
    async fn test_policy_rename_hidden_file() -> TestResult<()> {
        let temp = TestDir::new("drift-policy-rename-hidden").await?;
        let file = temp.path.join(".gitignore");
        write_test_file(&file, "content").await?;

        let policy = ConflictPolicy::Rename;
        let resolved = policy.resolve(&file).await?;
        // For hidden files like .gitignore, rfind('.') returns 0, so we treat it as having no extension
        assert_eq!(resolved, temp.path.join(".gitignore (1)"));

        Ok(())
    }
}
