use std::{
    collections::HashSet,
    path::{Path, PathBuf},
};

use super::error::{BlobError, BlobTextError, Result};
use super::util::import_files;
use iroh::{Endpoint, protocol::Router};
use iroh_blobs::{
    ALPN, BlobFormat, BlobsProtocol, api::TempTag, format::collection::Collection,
    store::fs::FsStore, ticket::BlobTicket,
};
use tracing::trace;

#[derive(Debug)]
pub(crate) struct PreparedStore {
    store: FsStore,
    collection_tag: TempTag,
    files: Vec<PreparedFile>,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedFile {
    pub(crate) path: String,
    pub(crate) size: u64,
}

impl PreparedStore {
    pub(crate) async fn prepare(root_dir: &Path, files: Vec<PathBuf>) -> Result<Self> {
        let store = FsStore::load(root_dir)
            .await
            .map_err(|source| BlobError::store_load(root_dir.to_path_buf(), source))?;

        let mut collection = Collection::default();
        let mut seen_transfer_paths = HashSet::new();
        let mut files_out = Vec::new();
        for path in files {
            trace!(input_path = %path.display(), "processing import input path");
            let imported = import_files(&store, path.clone()).await.map_err(|source| {
                BlobError::import_files(
                    path.display().to_string(),
                    BlobTextError::new(format!("{source:#}")),
                )
            })?;
            for file in imported {
                let transfer_path = file.transfer_path.clone();
                if !seen_transfer_paths.insert(transfer_path.clone()) {
                    return Err(BlobError::duplicate_transfer_path(transfer_path));
                }
                collection.extend([(transfer_path.clone(), file.temp_tag.hash())]);
                files_out.push(PreparedFile {
                    path: transfer_path,
                    size: file.size_bytes,
                });
            }
        }

        files_out.sort_by(|left, right| left.path.cmp(&right.path));

        let collection_tag = collection
            .store(store.as_ref())
            .await
            .map_err(|source| BlobError::store_collection(source))?;
        trace!(
            collection_hash = %collection_tag.hash(),
            item_count = seen_transfer_paths.len(),
            "stored collection in blob store"
        );

        Ok(Self {
            store,
            collection_tag,
            files: files_out,
        })
    }

    pub(crate) fn store(&self) -> &FsStore {
        &self.store
    }

    pub(crate) fn collection_tag(&self) -> &TempTag {
        &self.collection_tag
    }

    pub(crate) fn manifest(&self) -> crate::protocol::message::TransferManifest {
        crate::protocol::message::TransferManifest {
            items: self
                .files
                .iter()
                .map(|file| crate::protocol::message::ManifestItem::File {
                    path: file.path.clone(),
                    size: file.size,
                })
                .collect(),
        }
    }
}

#[derive(Debug)]
pub(crate) struct BlobService {
    endpoint: Endpoint,
}

#[derive(Debug)]
pub(crate) struct BlobRegistration {
    _prepared: PreparedStore,
    router: Router,
    ticket: BlobTicket,
}

impl BlobService {
    pub(crate) fn new(endpoint: Endpoint) -> Self {
        Self { endpoint }
    }

    pub(crate) async fn register(self, prepared: PreparedStore) -> Result<BlobRegistration> {
        let router = Router::builder(self.endpoint)
            .accept(ALPN, BlobsProtocol::new(prepared.store().as_ref(), None))
            .spawn();

        let ticket = BlobTicket::new(
            router.endpoint().addr(),
            prepared.collection_tag().hash(),
            BlobFormat::HashSeq,
        );

        Ok(BlobRegistration {
            _prepared: prepared,
            router,
            ticket,
        })
    }
}

impl BlobRegistration {
    pub(crate) fn ticket(&self) -> &BlobTicket {
        &self.ticket
    }

    pub(crate) async fn shutdown(self) -> Result<()> {
        self.router
            .shutdown()
            .await
            .map_err(|source| BlobError::store_shutdown("blob registration", source))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::PreparedStore;

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
    async fn prepare_store_rejects_duplicate_transfer_paths() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-duplicate-paths");
        let source = root.join("source");
        let store_root = root.join("store");
        std::fs::create_dir_all(&source)?;
        std::fs::create_dir_all(&store_root)?;
        std::fs::write(source.join("same.txt"), b"same")?;

        let err = PreparedStore::prepare(&store_root, vec![source.clone(), source])
            .await
            .expect_err("expected duplicate transfer path failure");
        let err_text = format!("{err:#}");
        assert!(err_text.contains("duplicate transfer path in manifest: source/same.txt"));

        std::fs::remove_dir_all(&root)?;
        Ok(())
    }
}
