use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail, ensure};
use futures_lite::StreamExt;
use iroh::Endpoint;
use iroh_blobs::{
    ALPN as BLOBS_ALPN, api::remote::GetProgressItem, format::collection::Collection,
    store::fs::FsStore, ticket::BlobTicket,
};
use tokio::fs;
use tokio::sync::mpsc;
use tracing::{instrument, trace};

use crate::protocol::message::{ManifestItem, TransferManifest};
use crate::transfer_flow::receiver::{ExpectedTransferFile, export_downloaded_collection};

use super::send::SenderEvent;
use super::util::ScratchDir;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiverEvent {
    Ready {
        session_id: String,
    },
    Progress {
        session_id: String,
        bytes_received: u64,
        total_bytes: Option<u64>,
    },
    Completed {
        session_id: String,
    },
    Failed {
        session_id: String,
        message: String,
    },
    Cancelled {
        session_id: String,
    },
}

fn emit_receiver_event(
    event_tx: &Option<mpsc::UnboundedSender<ReceiverEvent>>,
    event: ReceiverEvent,
) {
    if let Some(tx) = event_tx {
        let _ = tx.send(event);
    }
}

fn ensure_sender_session_id(expected: &str, event: &SenderEvent) -> Result<()> {
    let actual = match event {
        SenderEvent::Preparing { session_id, .. }
        | SenderEvent::StorePrepared { session_id, .. }
        | SenderEvent::TicketReady { session_id, .. }
        | SenderEvent::Completed { session_id }
        | SenderEvent::Failed { session_id, .. } => session_id.as_str(),
    };
    ensure!(
        expected == actual,
        "sender event session_id mismatch: expected {}, got {}",
        expected,
        actual
    );
    Ok(())
}

/// One-shot receiver entrypoint.
///
/// Consumes sender-side events, connects to the blob provider described by the ticket,
/// downloads the collection into a scratch store, then exports files into `out_dir`.
#[derive(Debug)]
pub struct Receiver {
    endpoint: Endpoint,
}

/// Blob-only downloader that connects to a ticket and exports the fetched collection.
#[derive(Debug)]
pub struct BlobReceiver {
    endpoint: Endpoint,
    session_id: String,
    ticket: BlobTicket,
    out_dir: PathBuf,
    manifest: TransferManifest,
}

struct TempRecvStore {
    store: FsStore,
    root: ScratchDir,
}

impl TempRecvStore {
    async fn open(prefix: &str, session_id: &str) -> Result<Self> {
        let root = ScratchDir::new(prefix, session_id).await?;
        let store = FsStore::load(&root.path)
            .await
            .with_context(|| format!("loading blob store {}", root.path.display()))?;
        Ok(Self { store, root })
    }

    async fn shutdown(self) -> Result<()> {
        self.store
            .shutdown()
            .await
            .context("shutting down blob download store")?;
        drop(self.root);
        Ok(())
    }
}

impl BlobReceiver {
    pub(crate) fn new(
        endpoint: Endpoint,
        session_id: impl Into<String>,
        ticket: BlobTicket,
        out_dir: PathBuf,
        manifest: TransferManifest,
    ) -> Self {
        Self {
            endpoint,
            session_id: session_id.into(),
            ticket,
            out_dir,
            manifest,
        }
    }

    #[instrument(skip(self, event_tx), fields(session_id = %self.session_id, out_dir = %self.out_dir.display()))]
    pub async fn run(self, event_tx: Option<mpsc::UnboundedSender<ReceiverEvent>>) -> Result<()> {
        let BlobReceiver {
            endpoint,
            session_id,
            ticket,
            out_dir,
            manifest,
        } = self;
        let total_bytes = manifest.total_size();
        let expected_files = expected_files_from_manifest(&manifest, &out_dir);

        fs::create_dir_all(&out_dir)
            .await
            .with_context(|| format!("creating output directory {}", out_dir.display()))?;

        emit_receiver_event(
            &event_tx,
            ReceiverEvent::Ready {
                session_id: session_id.clone(),
            },
        );

        let collection_root_hash = ticket.hash();

        let recv_store = match TempRecvStore::open("drift-one-shot-recv", &session_id).await {
            Ok(v) => v,
            Err(error) => {
                emit_receiver_event(
                    &event_tx,
                    ReceiverEvent::Failed {
                        session_id: session_id.clone(),
                        message: format!("{error:#}"),
                    },
                );
                return Err(error);
            }
        };

        let connection = match endpoint
            .connect(ticket.addr().clone(), BLOBS_ALPN)
            .await
            .context("connecting to blob provider")
        {
            Ok(v) => v,
            Err(error) => {
                emit_receiver_event(
                    &event_tx,
                    ReceiverEvent::Failed {
                        session_id: session_id.clone(),
                        message: format!("{error:#}"),
                    },
                );
                let _ = recv_store.shutdown().await;
                return Err(error);
            }
        };

        let mut stream = recv_store.store.remote().fetch(connection, ticket).stream();

        let fetch_outcome: Result<()> = loop {
            match stream.next().await {
                Some(GetProgressItem::Progress(offset)) => {
                    emit_receiver_event(
                        &event_tx,
                        ReceiverEvent::Progress {
                            session_id: session_id.clone(),
                            bytes_received: offset,
                            total_bytes: Some(total_bytes),
                        },
                    );
                }
                Some(GetProgressItem::Done(_)) => break Ok(()),
                Some(GetProgressItem::Error(err)) => {
                    let error = anyhow!(err.to_string()).context("blob fetch error");
                    emit_receiver_event(
                        &event_tx,
                        ReceiverEvent::Failed {
                            session_id: session_id.clone(),
                            message: format!("{error:#}"),
                        },
                    );
                    break Err(error);
                }
                None => break Ok(()),
            }
        };

        drop(stream);

        if let Err(error) = fetch_outcome {
            let _ = recv_store.shutdown().await;
            return Err(error);
        }

        if let Err(error) =
            export_downloaded_collection(&recv_store.store, collection_root_hash, &expected_files)
                .await
        {
            emit_receiver_event(
                &event_tx,
                ReceiverEvent::Failed {
                    session_id: session_id.clone(),
                    message: format!("{error:#}"),
                },
            );
            let _ = recv_store.shutdown().await;
            return Err(error);
        }

        if let Err(error) = recv_store.shutdown().await {
            emit_receiver_event(
                &event_tx,
                ReceiverEvent::Failed {
                    session_id: session_id.clone(),
                    message: format!("{error:#}"),
                },
            );
            return Err(error);
        }

        emit_receiver_event(&event_tx, ReceiverEvent::Completed { session_id });
        Ok(())
    }
}

fn manifest_from_collection(collection: Collection) -> TransferManifest {
    TransferManifest {
        items: collection
            .into_iter()
            .map(|(path, _hash)| ManifestItem::File { path, size: 0 })
            .collect(),
    }
}

fn expected_files_from_manifest(
    manifest: &TransferManifest,
    out_dir: &Path,
) -> Vec<ExpectedTransferFile> {
    manifest
        .items
        .iter()
        .map(|item| match item {
            ManifestItem::File { path, size } => ExpectedTransferFile {
                path: path.clone(),
                size: *size,
                destination: out_dir.join(path),
            },
        })
        .collect()
}

impl Receiver {
    pub fn new(endpoint: Endpoint) -> Self {
        Self { endpoint }
    }

    #[instrument(skip(self, sender_event_rx, event_tx), fields(out_dir = %out_dir.display()))]
    pub async fn receive(
        &self,
        session_id: &str,
        out_dir: PathBuf,
        sender_event_rx: &mut mpsc::UnboundedReceiver<SenderEvent>,
        event_tx: Option<mpsc::UnboundedSender<ReceiverEvent>>,
    ) -> Result<()> {
        fs::create_dir_all(&out_dir)
            .await
            .with_context(|| format!("creating output directory {}", out_dir.display()))?;

        let session_owned = session_id.to_owned();
        let mut prepared_collection: Option<Collection> = None;
        let mut prepared_total_bytes: Option<u64> = None;
        loop {
            let sender_event = match sender_event_rx.recv().await {
                Some(event) => event,
                None => {
                    let message = "sender event channel closed before ticket".to_owned();
                    emit_receiver_event(
                        &event_tx,
                        ReceiverEvent::Failed {
                            session_id: session_owned.clone(),
                            message: message.clone(),
                        },
                    );
                    bail!("{message}");
                }
            };

            if let Err(error) = ensure_sender_session_id(session_id, &sender_event) {
                emit_receiver_event(
                    &event_tx,
                    ReceiverEvent::Failed {
                        session_id: session_owned.clone(),
                        message: format!("{error:#}"),
                    },
                );
                return Err(error);
            }

            match sender_event {
                SenderEvent::Preparing { .. } => {
                    trace!(%session_id, "waiting for ticket");
                }
                SenderEvent::StorePrepared {
                    collection,
                    total_bytes,
                    ..
                } => {
                    prepared_collection = Some(collection);
                    prepared_total_bytes = Some(total_bytes);
                    trace!(%session_id, "stored collection metadata");
                }
                SenderEvent::TicketReady { ticket, .. } => {
                    let collection = prepared_collection.clone().ok_or_else(|| {
                        anyhow!("sender published ticket before store was prepared")
                    })?;
                    let _total_bytes = prepared_total_bytes.ok_or_else(|| {
                        anyhow!("sender published ticket before total bytes were prepared")
                    })?;
                    let blob_ticket: BlobTicket =
                        match ticket.parse().context("parsing blob ticket") {
                            Ok(v) => v,
                            Err(error) => {
                                emit_receiver_event(
                                    &event_tx,
                                    ReceiverEvent::Failed {
                                        session_id: session_owned.clone(),
                                        message: format!("{error:#}"),
                                    },
                                );
                                return Err(error);
                            }
                        };
                    let blob_receiver = BlobReceiver::new(
                        self.endpoint.clone(),
                        session_owned.clone(),
                        blob_ticket,
                        out_dir,
                        manifest_from_collection(collection),
                    );
                    return blob_receiver.run(event_tx.clone()).await;
                }
                SenderEvent::Failed { message, .. } => {
                    emit_receiver_event(
                        &event_tx,
                        ReceiverEvent::Failed {
                            session_id: session_owned.clone(),
                            message: message.clone(),
                        },
                    );
                    bail!("sender reported failure: {message}");
                }
                SenderEvent::Completed { .. } => {
                    let message = "sender completed before receiver received ticket".to_owned();
                    emit_receiver_event(
                        &event_tx,
                        ReceiverEvent::Failed {
                            session_id: session_owned.clone(),
                            message: message.clone(),
                        },
                    );
                    bail!("{message}");
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use anyhow::{Context, Result};
    use iroh::protocol::Router;
    use iroh_blobs::{
        ALPN as BLOBS_ALPN, BlobFormat, BlobsProtocol, format::collection::Collection,
        store::fs::FsStore, ticket::BlobTicket,
    };
    use tokio::sync::mpsc;

    use crate::blobs::receive::ReceiverEvent;
    use crate::blobs::send::SenderEvent;
    use crate::blobs::util::import_files;
    use crate::transfer_flow::receiver::bind_endpoint;

    use super::Receiver;

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

    async fn bind_endpoint_or_skip(root: &std::path::Path) -> Result<Option<iroh::Endpoint>> {
        match bind_endpoint().await {
            Ok(endpoint) => Ok(Some(endpoint)),
            Err(error) if should_skip_bind_error(&error) => {
                let _ = std::fs::remove_dir_all(root);
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }

    fn collect_receiver_events(
        rx: &mut mpsc::UnboundedReceiver<ReceiverEvent>,
    ) -> Vec<ReceiverEvent> {
        let mut events = Vec::new();
        while let Ok(event) = rx.try_recv() {
            events.push(event);
        }
        events
    }

    fn should_skip_network_error(error: &anyhow::Error) -> bool {
        let text = format!("{error:#}");
        text.contains("No addressing information")
            || text.contains("Failed to resolve TXT")
            || text.contains("Connecting to ourself")
    }

    /// Drives `Receiver` only via `SenderEvent`s. A minimal blob `Router` serves the same store
    /// that produced the ticket (no `Sender::send`).
    #[tokio::test]
    async fn receive_saves_files_from_sender_events() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-recv-sender-events");
        let source_dir = root.join("source");
        let provider_store = root.join("provider_store");
        let out_dir = root.join("out");
        std::fs::create_dir_all(&source_dir)?;
        std::fs::create_dir_all(&provider_store)?;
        std::fs::create_dir_all(&out_dir)?;
        std::fs::write(source_dir.join("hello.txt"), b"sender-events-payload")?;

        let Some(ep_provider) = bind_endpoint_or_skip(&root).await? else {
            return Ok(());
        };
        let Some(ep_recv) = bind_endpoint_or_skip(&root).await? else {
            ep_provider.close().await;
            let _ = std::fs::remove_dir_all(&root);
            return Ok(());
        };

        let store = FsStore::load(&provider_store).await?;
        let imported = import_files(&store, source_dir.clone()).await?;
        let export_relative = imported
            .iter()
            .map(|f| f.transfer_path.clone())
            .min()
            .expect("at least one imported file");
        let mut total_bytes = 0_u64;
        let mut collection = Collection::default();
        for file in imported {
            total_bytes = total_bytes.saturating_add(file.size_bytes);
            collection.extend([(file.transfer_path, file.temp_tag.hash())]);
        }
        let collection_tag = collection.store(store.as_ref()).await?;
        let collection = Collection::load(collection_tag.hash(), store.as_ref())
            .await
            .context("loading collection for ticket event")?;

        let router = Router::builder(ep_provider.clone())
            .accept(BLOBS_ALPN, BlobsProtocol::new(store.as_ref(), None))
            .spawn();

        let ticket = BlobTicket::new(
            router.endpoint().addr(),
            collection_tag.hash(),
            BlobFormat::HashSeq,
        );

        let session_id = "one-shot-sender-events".to_owned();
        let (sender_ev_tx, mut sender_ev_rx) = mpsc::unbounded_channel::<SenderEvent>();

        let recv_handle = {
            let ep = ep_recv.clone();
            let session_id = session_id.clone();
            let out_dir = out_dir.clone();
            tokio::spawn(async move {
                Receiver::new(ep)
                    .receive(&session_id, out_dir, &mut sender_ev_rx, None)
                    .await
            })
        };

        sender_ev_tx
            .send(SenderEvent::Preparing {
                session_id: session_id.clone(),
                input_count: 1,
            })
            .expect("preparing");
        sender_ev_tx
            .send(SenderEvent::StorePrepared {
                session_id: session_id.clone(),
                root_hash: collection_tag.hash(),
                total_bytes,
                collection,
            })
            .expect("store prepared");
        sender_ev_tx
            .send(SenderEvent::TicketReady {
                session_id: session_id.clone(),
                ticket: ticket.to_string(),
            })
            .expect("ticket ready");

        let receive_outcome = recv_handle.await.expect("join receive");

        let shutdown_outcome = router.shutdown().await;
        ep_provider.close().await;
        ep_recv.close().await;

        if let Err(error) = receive_outcome {
            if should_skip_network_error(&error) {
                let _ = std::fs::remove_dir_all(&root);
                return Ok(());
            }
            let _ = shutdown_outcome;
            return Err(error);
        }

        shutdown_outcome?;

        let exported = std::fs::read(out_dir.join(&export_relative))?;
        assert_eq!(exported, b"sender-events-payload");

        let _ = std::fs::remove_dir_all(&root);
        Ok(())
    }

    #[tokio::test]
    async fn receive_fails_on_wrong_sender_session_id() -> Result<()> {
        let (sender_tx, mut sender_rx) = mpsc::unbounded_channel();
        let (event_tx, mut event_rx) = mpsc::unbounded_channel();
        let session_id = "receiver-session-expected".to_owned();

        // Receiver needs an endpoint even when we never open a connection; bind may fail in CI.
        let root = unique_temp_dir("drift-one-shot-recv-sess");
        let Some(ep) = bind_endpoint_or_skip(&root).await? else {
            return Ok(());
        };
        let receiver = Receiver::new(ep.clone());

        sender_tx
            .send(SenderEvent::Preparing {
                session_id: "receiver-session-other".to_owned(),
                input_count: 1,
            })
            .expect("send preparing");

        let err = receiver
            .receive(
                &session_id,
                root.join("out"),
                &mut sender_rx,
                Some(event_tx),
            )
            .await
            .expect_err("expected session mismatch");
        assert!(format!("{err:#}").contains("sender event session_id mismatch"));

        let events = collect_receiver_events(&mut event_rx);
        assert!(matches!(
            events.last(),
            Some(ReceiverEvent::Failed { session_id: got, message })
                if got == "receiver-session-expected"
                    && message.contains("sender event session_id mismatch")
        ));

        ep.close().await;
        let _ = std::fs::remove_dir_all(&root);
        Ok(())
    }

    #[tokio::test]
    async fn receive_fails_on_invalid_ticket() -> Result<()> {
        let root = unique_temp_dir("drift-one-shot-recv-bad-ticket");
        let Some(ep) = bind_endpoint_or_skip(&root).await? else {
            return Ok(());
        };
        let receiver = Receiver::new(ep.clone());
        let (sender_tx, mut sender_rx) = mpsc::unbounded_channel();
        let (event_tx, mut event_rx) = mpsc::unbounded_channel();
        let session_id = "receiver-session-invalid-ticket".to_owned();

        sender_tx
            .send(SenderEvent::StorePrepared {
                session_id: session_id.clone(),
                root_hash: iroh_blobs::Hash::new(b"bad-ticket"),
                total_bytes: 0,
                collection: Collection::default(),
            })
            .expect("send store prepared");
        sender_tx
            .send(SenderEvent::TicketReady {
                session_id: session_id.clone(),
                ticket: "not-a-valid-blob-ticket".to_owned(),
            })
            .expect("send bad ticket");

        let err = receiver
            .receive(
                &session_id,
                root.join("out"),
                &mut sender_rx,
                Some(event_tx),
            )
            .await
            .expect_err("expected ticket parse failure");
        assert!(format!("{err:#}").contains("parsing blob ticket"));

        let events = collect_receiver_events(&mut event_rx);
        assert!(matches!(
            events.last(),
            Some(ReceiverEvent::Failed { session_id: got, message })
                if got == "receiver-session-invalid-ticket"
                    && message.contains("parsing blob ticket")
        ));

        ep.close().await;
        let _ = std::fs::remove_dir_all(&root);
        Ok(())
    }
}
