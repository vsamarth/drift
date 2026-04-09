use crate::fs_plan::ConflictPolicy;
use crate::protocol::message::TransferManifest;
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum TransferStatus {
    Transferring,
    Paused,
    DataComplete,
    Finalizing,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TransferRecord {
    pub collection_hash: iroh_blobs::Hash,
    pub status: TransferStatus,
    pub output_dir: PathBuf,
    pub conflict_policy: ConflictPolicy,
    pub manifest: TransferManifest,
    pub exported_files: HashSet<String>,
    pub created_at: std::time::SystemTime,
    pub updated_at: std::time::SystemTime,
}

impl TransferRecord {
    pub fn new(
        collection_hash: iroh_blobs::Hash,
        output_dir: PathBuf,
        conflict_policy: ConflictPolicy,
        manifest: TransferManifest,
    ) -> Self {
        let now = std::time::SystemTime::now();
        Self {
            collection_hash,
            status: TransferStatus::Transferring,
            output_dir,
            conflict_policy,
            manifest,
            exported_files: HashSet::new(),
            created_at: now,
            updated_at: now,
        }
    }

    pub fn load(dir: &Path) -> std::io::Result<Self> {
        let path = dir.join("record.json");
        let content = fs::read_to_string(path)?;
        serde_json::from_str(&content)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
    }

    pub fn save(&self, dir: &Path) -> std::io::Result<()> {
        let path = dir.join("record.json");
        let content = serde_json::to_string_pretty(self)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
        fs::write(path, content)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::message::ManifestItem;

    #[test]
    fn record_roundtrips_json() {
        let dir = tempfile::tempdir().unwrap();
        let hash = [1u8; 32].into();
        let record = TransferRecord::new(
            hash,
            PathBuf::from("/tmp/out"),
            ConflictPolicy::Rename,
            TransferManifest {
                items: vec![ManifestItem::File {
                    path: "test.txt".to_owned(),
                    size: 10,
                }],
            },
        );

        record.save(dir.path()).unwrap();
        let loaded = TransferRecord::load(dir.path()).unwrap();
        assert_eq!(record.collection_hash, loaded.collection_hash);
        assert_eq!(record.manifest, loaded.manifest);
        assert_eq!(record.status, loaded.status);
    }
}
