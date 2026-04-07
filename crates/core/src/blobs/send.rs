use std::{
    collections::HashSet,
    path::{Path, PathBuf},
};

use super::receive::ReceiverEvent;
use super::util::import_files;
use anyhow::{Context, Result, anyhow, bail, ensure};
use iroh::{Endpoint, protocol::Router};
use iroh_blobs::{
    ALPN, BlobFormat, BlobsProtocol, api::TempTag, format::collection::Collection,
    store::fs::FsStore, ticket::BlobTicket,
};
use tokio::sync::mpsc;
use tracing::{instrument, trace};

#[derive(Debug)]
pub enum SenderEvent {
    Preparing {
        session_id: String,
        input_count: usize,
    },
    StorePrepared {
        session_id: String,
        root_hash: iroh_blobs::Hash,
        total_bytes: u64,
        collection: Collection,
    },
    TicketReady {
        session_id: String,
        ticket: String,
    },
    Completed {
        session_id: String,
    },
    Failed {
        session_id: String,
        message: String,
    },
}

fn emit_event(event_tx: &Option<mpsc::UnboundedSender<SenderEvent>>, event: SenderEvent) {
    if let Some(tx) = event_tx {
        let _ = tx.send(event);
    }
}

fn ensure_receiver_session_id(expected: &str, event: &ReceiverEvent) -> Result<()> {
    let actual = match event {
        ReceiverEvent::Ready { session_id }
        | ReceiverEvent::Completed { session_id }
        | ReceiverEvent::Cancelled { session_id } => session_id.as_str(),
        ReceiverEvent::Progress { session_id, .. } | ReceiverEvent::Failed { session_id, .. } => {
            session_id.as_str()
        }
    };
    ensure!(
        expected == actual,
        "receiver event session_id mismatch: expected {}, got {}",
        expected,
        actual
    );
    Ok(())
}

#[derive(Debug)]
pub(crate) struct PreparedStore {
    session_id: String,
    store: FsStore,
    collection_tag: TempTag,
    collection: Collection,
    total_bytes: u64,
    files: Vec<PreparedFile>,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedFile {
    pub(crate) path: String,
    pub(crate) size: u64,
}

impl PreparedStore {
    pub(crate) async fn prepare(
        session_id: String,
        root_dir: &Path,
        files: Vec<PathBuf>,
    ) -> Result<Self> {
        let store = FsStore::load(root_dir)
            .await
            .with_context(|| format!("loading blob store at {}", root_dir.display()))?;

        let mut collection = Collection::default();
        let mut seen_transfer_paths = HashSet::new();
        let mut total_bytes = 0_u64;
        let mut files_out = Vec::new();
        for path in files {
            trace!(input_path = %path.display(), "processing import input path");
            let imported = import_files(&store, path).await?;
            for file in imported {
                let transfer_path = file.transfer_path.clone();
                if !seen_transfer_paths.insert(transfer_path.clone()) {
                    bail!("duplicate transfer path in manifest: {}", transfer_path);
                }
                total_bytes = total_bytes
                    .checked_add(file.size_bytes)
                    .ok_or_else(|| anyhow!("total transfer size exceeds u64"))?;
                collection.extend([(transfer_path.clone(), file.temp_tag.hash())]);
                files_out.push(PreparedFile {
                    path: transfer_path,
                    size: file.size_bytes,
                });
            }
        }

        files_out.sort_by(|left, right| left.path.cmp(&right.path));

        let collection_tag = collection.store(store.as_ref()).await?;
        let collection = Collection::load(collection_tag.hash(), store.as_ref())
            .await
            .context("loading collection after store")?;
        trace!(
            collection_hash = %collection_tag.hash(),
            item_count = seen_transfer_paths.len(),
            total_bytes,
            "stored collection in blob store"
        );

        Ok(Self {
            session_id,
            store,
            collection_tag,
            collection,
            total_bytes,
            files: files_out,
        })
    }

    pub(crate) fn session_id(&self) -> &str {
        &self.session_id
    }

    pub(crate) fn store(&self) -> &FsStore {
        &self.store
    }

    pub(crate) fn collection_tag(&self) -> &TempTag {
        &self.collection_tag
    }

    pub(crate) fn collection(&self) -> &Collection {
        &self.collection
    }

    pub(crate) fn total_bytes(&self) -> u64 {
        self.total_bytes
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
    #[allow(dead_code)]
    prepared: PreparedStore,
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
            prepared,
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
        self.router.shutdown().await?;
        Ok(())
    }
}

#[derive(Debug)]
pub struct Sender {
    endpoint: Endpoint,
}

#[derive(Debug)]
pub struct Manifest {
    files: Vec<PathBuf>,
    root_dir: PathBuf,
    session_id: String,
}

impl Manifest {
    pub fn new(files: Vec<PathBuf>, root_dir: PathBuf, session_id: String) -> Self {
        Self {
            files,
            root_dir,
            session_id,
        }
    }
    pub fn files(&self) -> &[PathBuf] {
        &self.files
    }
    pub fn root_dir(&self) -> &Path {
        &self.root_dir
    }
    pub fn session_id(&self) -> &str {
        &self.session_id
    }
}

impl Sender {
    pub fn new(endpoint: Endpoint) -> Self {
        Self { endpoint }
    }

    #[instrument(skip(self, manifest, event_tx, receiver_event_rx), fields(root_dir = %manifest.root_dir.display(), file_count = manifest.files.len()))]
    pub async fn send(
        &self,
        manifest: Manifest,
        event_tx: Option<mpsc::UnboundedSender<SenderEvent>>,
        receiver_event_rx: &mut mpsc::UnboundedReceiver<ReceiverEvent>,
    ) -> Result<()> {
        let session_id = manifest.session_id.clone();
        emit_event(
            &event_tx,
            SenderEvent::Preparing {
                session_id: session_id.clone(),
                input_count: manifest.files.len(),
            },
        );

        let prepared =
            PreparedStore::prepare(session_id.clone(), &manifest.root_dir, manifest.files)
                .await
                .map_err(|error| {
                    emit_event(
                        &event_tx,
                        SenderEvent::Failed {
                            session_id: session_id.clone(),
                            message: format!("{error:#}"),
                        },
                    );
                    error
                })?;
        self.send_prepared(prepared, event_tx, receiver_event_rx)
            .await
    }

    #[instrument(skip(self, prepared, event_tx, receiver_event_rx), fields(session_id = %prepared.session_id()))]
    pub(crate) async fn send_prepared(
        &self,
        prepared: PreparedStore,
        event_tx: Option<mpsc::UnboundedSender<SenderEvent>>,
        receiver_event_rx: &mut mpsc::UnboundedReceiver<ReceiverEvent>,
    ) -> Result<()> {
        let session_id = prepared.session_id().to_owned();
        emit_event(
            &event_tx,
            SenderEvent::StorePrepared {
                session_id: session_id.clone(),
                root_hash: prepared.collection_tag().hash(),
                total_bytes: prepared.total_bytes(),
                collection: prepared.collection().clone(),
            },
        );

        let registration = BlobService::new(self.endpoint.clone())
            .register(prepared)
            .await
            .context("registering blob service")?;
        let ticket = registration.ticket().to_string();
        trace!(%ticket, "constructed blob ticket for transfer");
        emit_event(
            &event_tx,
            SenderEvent::TicketReady {
                session_id: session_id.clone(),
                ticket,
            },
        );

        let transfer_result: Result<()> = loop {
            let receiver_event = match receiver_event_rx.recv().await {
                Some(event) => event,
                None => {
                    let message = "receiver event channel closed before completion".to_owned();
                    emit_event(
                        &event_tx,
                        SenderEvent::Failed {
                            session_id: session_id.clone(),
                            message: message.clone(),
                        },
                    );
                    break Err(anyhow!(message));
                }
            };

            if let Err(error) = ensure_receiver_session_id(&session_id, &receiver_event) {
                emit_event(
                    &event_tx,
                    SenderEvent::Failed {
                        session_id: session_id.clone(),
                        message: format!("{error:#}"),
                    },
                );
                break Err(error);
            }

            match receiver_event {
                ReceiverEvent::Ready { .. } => {
                    trace!(session_id = %session_id, "receiver acknowledged ticket");
                }
                ReceiverEvent::Progress {
                    bytes_received,
                    total_bytes,
                    ..
                } => {
                    trace!(
                        session_id = %session_id,
                        bytes_received,
                        ?total_bytes,
                        "receiver progress update"
                    );
                }
                ReceiverEvent::Completed { .. } => {
                    emit_event(&event_tx, SenderEvent::Completed { session_id });
                    break Ok(());
                }
                ReceiverEvent::Failed { message, .. } => {
                    emit_event(
                        &event_tx,
                        SenderEvent::Failed {
                            session_id: session_id.clone(),
                            message: message.clone(),
                        },
                    );
                    break Err(anyhow!("receiver reported failure: {message}"));
                }
                ReceiverEvent::Cancelled { .. } => {
                    let message = "receiver cancelled transfer".to_owned();
                    emit_event(
                        &event_tx,
                        SenderEvent::Failed {
                            session_id: session_id.clone(),
                            message: message.clone(),
                        },
                    );
                    break Err(anyhow!(message));
                }
            }
        };

        if let Err(error) = registration.shutdown().await {
            trace!(%error, "failed to shut down sender router");
            if transfer_result.is_ok() {
                return Err(error.into());
            }
        }
        transfer_result
    }
}

#[cfg(test)]
mod tests {
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use crate::session::bind_endpoint;
    use anyhow::Result;
    use tokio::sync::mpsc;

    use super::{Manifest, PreparedStore, Sender, SenderEvent};
    use crate::blobs::receive::ReceiverEvent;

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

    fn should_skip_bind_error(error: &anyhow::Error) -> bool {
        let chain = format!("{error:#}");
        chain.contains("Failed to bind sockets") || chain.contains("Operation not permitted")
    }

    async fn bind_endpoint_or_skip(root: &Path) -> Result<Option<iroh::Endpoint>> {
        match bind_endpoint().await {
            Ok(endpoint) => Ok(Some(endpoint)),
            Err(error) if should_skip_bind_error(&error) => {
                let _ = std::fs::remove_dir_all(root);
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }

    fn collect_sender_events(rx: &mut mpsc::UnboundedReceiver<SenderEvent>) -> Vec<SenderEvent> {
        let mut events = Vec::new();
        while let Ok(event) = rx.try_recv() {
            events.push(event);
        }
        events
    }

    async fn setup_basic_send_case(
        prefix: &str,
        session_id: &str,
    ) -> Result<Option<(PathBuf, iroh::Endpoint, Sender, Manifest)>> {
        let root = unique_temp_dir(prefix);
        let source = root.join("source");
        let store_root = root.join("store");
        std::fs::create_dir_all(&source)?;
        std::fs::create_dir_all(&store_root)?;
        std::fs::write(source.join("a.txt"), b"a")?;

        let endpoint = match bind_endpoint_or_skip(&root).await? {
            Some(endpoint) => endpoint,
            None => return Ok(None),
        };
        let sender = Sender::new(endpoint.clone());
        let manifest = Manifest {
            files: vec![source],
            root_dir: store_root,
            session_id: session_id.to_owned(),
        };
        Ok(Some((root, endpoint, sender, manifest)))
    }

    async fn finish_case(root: &Path, endpoint: iroh::Endpoint) {
        endpoint.close().await;
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn prepare_store_rejects_duplicate_transfer_paths() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-duplicate-paths");
        let source = root.join("source");
        std::fs::create_dir_all(&source)?;
        std::fs::write(source.join("same.txt"), b"same")?;

        let endpoint = match bind_endpoint_or_skip(&root).await? {
            Some(endpoint) => endpoint,
            None => return Ok(()),
        };
        let store_root = root.join("store");
        std::fs::create_dir_all(&store_root)?;
        let sender = Sender::new(endpoint.clone());
        let err = PreparedStore::prepare(
            "session-duplicate-paths".to_owned(),
            &store_root,
            vec![source.clone(), source],
        )
        .await
        .expect_err("expected duplicate transfer path failure");
        let err_text = format!("{err:#}");
        assert!(err_text.contains("duplicate transfer path in manifest: source/same.txt"));

        drop(sender);
        finish_case(&root, endpoint).await;
        Ok(())
    }

    #[tokio::test]
    async fn send_emits_done_path_events() -> Result<()> {
        let (root, endpoint, sender, manifest) =
            match setup_basic_send_case("drift-one-shot-send-events-ok", "session-events-ok")
                .await?
            {
                Some(values) => values,
                None => return Ok(()),
            };
        let (tx, mut rx) = mpsc::unbounded_channel();

        let (receiver_tx, mut receiver_rx) = mpsc::unbounded_channel();
        receiver_tx
            .send(ReceiverEvent::Ready {
                session_id: "session-events-ok".to_owned(),
            })
            .expect("send ready event");
        receiver_tx
            .send(ReceiverEvent::Completed {
                session_id: "session-events-ok".to_owned(),
            })
            .expect("send completed event");
        sender.send(manifest, Some(tx), &mut receiver_rx).await?;

        let events = collect_sender_events(&mut rx);
        assert!(matches!(
            events.first(),
            Some(SenderEvent::Preparing {
                session_id,
                input_count: 1
            }) if session_id == "session-events-ok"
        ));
        assert!(
            events
                .iter()
                .any(|event| matches!(event, SenderEvent::StorePrepared { .. }))
        );
        assert!(
            events
                .iter()
                .any(|event| matches!(event, SenderEvent::TicketReady { .. }))
        );
        assert!(matches!(
            events.last(),
            Some(SenderEvent::Completed { session_id }) if session_id == "session-events-ok"
        ));

        finish_case(&root, endpoint).await;
        Ok(())
    }

    #[tokio::test]
    async fn send_emits_failed_on_prepare_error() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-send-events-fail");
        let source = root.join("source");
        std::fs::create_dir_all(&source)?;
        std::fs::write(source.join("same.txt"), b"same")?;

        let endpoint = match bind_endpoint_or_skip(&root).await? {
            Some(endpoint) => endpoint,
            None => return Ok(()),
        };
        let sender = Sender::new(endpoint.clone());
        let (tx, mut rx) = mpsc::unbounded_channel();
        let manifest = Manifest {
            files: vec![source.clone(), source],
            root_dir: root.join("store"),
            session_id: "session-events-fail".to_owned(),
        };

        let (_receiver_tx, mut receiver_rx) = mpsc::unbounded_channel::<ReceiverEvent>();
        let err = sender
            .send(manifest, Some(tx), &mut receiver_rx)
            .await
            .expect_err("expected duplicate transfer path failure");
        assert!(format!("{err:#}").contains("duplicate transfer path in manifest"));

        let events = collect_sender_events(&mut rx);
        assert!(matches!(
            events.first(),
            Some(SenderEvent::Preparing {
                session_id,
                input_count: 2
            }) if session_id == "session-events-fail"
        ));
        assert!(matches!(
            events.last(),
            Some(SenderEvent::Failed { session_id, message })
                if session_id == "session-events-fail"
                    && message.contains("duplicate transfer path in manifest")
        ));

        finish_case(&root, endpoint).await;
        Ok(())
    }

    #[tokio::test]
    async fn send_emits_failed_on_receiver_failure_event() -> Result<()> {
        let (root, endpoint, sender, manifest) = match setup_basic_send_case(
            "drift-one-shot-send-events-receiver-fail",
            "session-events-receiver-fail",
        )
        .await?
        {
            Some(values) => values,
            None => return Ok(()),
        };
        let (tx, mut rx) = mpsc::unbounded_channel();
        let (receiver_tx, mut receiver_rx) = mpsc::unbounded_channel();

        receiver_tx
            .send(ReceiverEvent::Ready {
                session_id: "session-events-receiver-fail".to_owned(),
            })
            .expect("send ready event");
        receiver_tx
            .send(ReceiverEvent::Failed {
                session_id: "session-events-receiver-fail".to_owned(),
                message: "disk full".to_owned(),
            })
            .expect("send failed event");

        let err = sender
            .send(manifest, Some(tx), &mut receiver_rx)
            .await
            .expect_err("expected receiver failure");
        assert!(format!("{err:#}").contains("receiver reported failure: disk full"));

        let events = collect_sender_events(&mut rx);
        assert!(matches!(
            events.last(),
            Some(SenderEvent::Failed { session_id, message })
                if session_id == "session-events-receiver-fail"
                    && message.contains("disk full")
        ));

        finish_case(&root, endpoint).await;
        Ok(())
    }

    #[tokio::test]
    async fn send_fails_immediately_on_wrong_receiver_session_id() -> Result<()> {
        let (root, endpoint, sender, manifest) = match setup_basic_send_case(
            "drift-one-shot-send-events-wrong-session",
            "session-events-expected",
        )
        .await?
        {
            Some(values) => values,
            None => return Ok(()),
        };
        let (tx, mut rx) = mpsc::unbounded_channel();
        let (receiver_tx, mut receiver_rx) = mpsc::unbounded_channel();

        receiver_tx
            .send(ReceiverEvent::Ready {
                session_id: "session-events-other".to_owned(),
            })
            .expect("send mismatched ready event");

        let err = sender
            .send(manifest, Some(tx), &mut receiver_rx)
            .await
            .expect_err("expected mismatched session_id failure");
        assert!(format!("{err:#}").contains("receiver event session_id mismatch"));

        let events = collect_sender_events(&mut rx);
        assert!(matches!(
            events.last(),
            Some(SenderEvent::Failed { session_id, message })
                if session_id == "session-events-expected"
                    && message.contains("receiver event session_id mismatch")
        ));

        finish_case(&root, endpoint).await;
        Ok(())
    }
}
