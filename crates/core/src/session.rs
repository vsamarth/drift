use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use futures_lite::StreamExt;
use iroh::{Endpoint, RelayMode, endpoint::presets, protocol::Router};
use iroh_blobs::{
    ALPN as BLOBS_ALPN, BlobFormat, BlobsProtocol, Hash,
    api::{
        TempTag,
        blobs::{AddPathOptions, ExportMode, ExportOptions, ImportMode},
        remote::GetProgressItem,
    },
    format::collection::Collection,
    provider::events::{EventMask, EventSender, ProviderMessage, RequestMode, RequestUpdate},
    store::fs::FsStore,
    ticket::BlobTicket,
};
use tokio::fs;
use tokio::sync::{mpsc, watch};
use tokio::time::{Duration, timeout};
use tracing::trace;

use crate::fs_plan::ConflictPolicy;
use crate::fs_plan::prepare::PreparedFile;
use crate::fs_plan::receive::{ExpectedFile, build_expected_files};
use crate::rendezvous::OfferManifest;
use crate::transfer::TransferCancellation;
use crate::util::describe_remote;
use crate::wire::{
    ALPN, BlobTicketMessage, Cancel, CancelPhase, ControlMessage, TransferAck, TransferErrorCode,
    TransferResult, TransferRole, TransferStatus, read_message, write_message,
};

const CONTROL_STREAM_FINISH_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Copy)]
pub struct FileSendProgress {
    pub total_bytes_sent: u64,
    pub bytes_sent_in_file: u64,
    pub file_index: usize,
}

#[derive(Debug, Clone)]
pub struct FileReceiveProgress {
    pub total_bytes_received: u64,
    pub total_bytes_to_receive: u64,
    pub bytes_received_in_file: u64,
    pub file_size: u64,
    pub file_path: Arc<str>,
}

#[derive(Debug, Clone)]
pub struct ExpectedTransferFile {
    pub path: String,
    pub size: u64,
    pub destination: PathBuf,
}

struct BlobProvider {
    router: Router,
    root: TempDir,
    _collection_tag: TempTag,
    progress_rx: mpsc::Receiver<FileSendProgress>,
}

struct BlobDownloadStore {
    store: FsStore,
    root: TempDir,
}

struct TempDir {
    path: PathBuf,
}

impl TempDir {
    async fn new(prefix: &str, session_id: &str) -> Result<Self> {
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

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

pub async fn bind_endpoint() -> Result<Endpoint> {
    Endpoint::builder(presets::N0)
        .alpns(vec![ALPN.to_vec(), BLOBS_ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .bind()
        .await
        .context("binding iroh endpoint")
}

pub async fn connect_to_ticket(
    endpoint: &Endpoint,
    ticket: iroh::EndpointAddr,
) -> Result<iroh::endpoint::Connection> {
    let connection = endpoint
        .connect(ticket, ALPN)
        .await
        .context("connecting to peer")?;

    println!(
        "Connected to {}",
        describe_remote(
            connection.remote_id(),
            endpoint.remote_info(connection.remote_id()).await.as_ref()
        )
    );

    Ok(connection)
}

pub async fn send_files_over_connection<F>(
    endpoint: &Endpoint,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    session_id: &str,
    files: &[PreparedFile],
    mut cancel_rx: Option<watch::Receiver<bool>>,
    mut on_progress: F,
) -> Result<Option<TransferCancellation>>
where
    F: FnMut(FileSendProgress),
{
    let mut provider = prepare_blob_provider(endpoint, session_id, files).await?;
    let ticket = provider.ticket().await?;
    trace!(
        session_id = %session_id,
        blob_provider_ticket = %ticket,
        "prepared blob provider ticket"
    );

    write_message(
        control_send,
        &ControlMessage::BlobTicket(BlobTicketMessage {
            session_id: session_id.to_owned(),
            ticket,
        }),
    )
    .await
    .context("sending blob transfer ticket")?;

    let result = loop {
        tokio::select! {
            maybe_progress = provider.progress_rx.recv() => {
                if let Some(progress) = maybe_progress {
                    on_progress(progress);
                }
            }
            cancel_requested = wait_for_cancel(&mut cancel_rx), if cancel_rx.is_some() => {
                if cancel_requested {
                    let cancellation = local_cancellation(TransferRole::Sender, CancelPhase::Transferring);
                    let _ = send_cancel(
                        control_send,
                        session_id,
                        cancellation.by,
                        cancellation.phase,
                        cancellation.reason.clone(),
                    ).await;
                    break Ok(Some(cancellation));
                }
            }
            control_message = read_message::<ControlMessage>(control_recv) => {
                let outcome = match control_message.context("waiting for final transfer result")? {
                    ControlMessage::TransferResult(result) => {
                        ensure_matching_session_id(&result.session_id, session_id)?;
                        if !matches!(result.status, TransferStatus::Ok) {
                            Err(anyhow!(
                                "receiver failed transfer: {}",
                                transfer_status_summary(&result.status)
                            ))
                        } else {
                            Ok(None)
                        }
                    }
                    ControlMessage::Cancel(cancel) => {
                        Ok(Some(cancellation_from_message(cancel, session_id)?))
                    }
                    other => Err(anyhow!("unexpected final control message: {:?}", other)),
                };
                break outcome;
            }
        }
    };

    let ack_result: Result<()> = if matches!(result, Ok(None)) {
        send_transfer_ack(control_send, session_id).await?;
        control_send.finish()?;
        let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, control_send.stopped()).await;
        Ok(())
    } else {
        let _ = control_send.finish();
        Ok(())
    };

    // Always tear down the blob provider even if ACK/finish fails, to avoid leaking
    // router/store resources on sender-side protocol errors.
    let shutdown_result = provider.shutdown().await;
    shutdown_result?;
    let outcome = result?;
    ack_result?;
    Ok(outcome)
}

pub async fn receive_files_over_connection(
    endpoint: &Endpoint,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    session_id: &str,
    out_dir: PathBuf,
    manifest: &OfferManifest,
    policy: ConflictPolicy,
) -> Result<Option<TransferCancellation>> {
    let expected_files = build_expected_transfer_files(
        manifest,
        build_expected_files(manifest, &out_dir, policy).await?,
    )?;
    receive_files_over_connection_with_progress(
        endpoint,
        control_send,
        control_recv,
        session_id,
        expected_files,
        None,
        |_| {},
    )
    .await
}

pub async fn receive_files_over_connection_with_progress<F>(
    endpoint: &Endpoint,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    session_id: &str,
    expected_files: Vec<ExpectedTransferFile>,
    mut cancel_rx: Option<watch::Receiver<bool>>,
    mut on_progress: F,
) -> Result<Option<TransferCancellation>>
where
    F: FnMut(FileReceiveProgress),
{
    let total_bytes_to_receive = expected_files.iter().map(|file| file.size).sum();
    on_progress(FileReceiveProgress {
        total_bytes_received: 0,
        total_bytes_to_receive,
        bytes_received_in_file: 0,
        file_size: 0,
        file_path: Arc::from(""),
    });

    let ticket_message = match read_message::<ControlMessage>(control_recv)
        .await
        .context("waiting for blob transfer ticket")?
    {
        ControlMessage::BlobTicket(message) => {
            ensure_matching_session_id(&message.session_id, session_id)?;
            message
        }
        other => {
            let status = transfer_error_status(
                TransferErrorCode::UnexpectedMessage,
                format!(
                    "unexpected control message while waiting for blob ticket: {:?}",
                    other
                ),
            );
            send_transfer_result(control_send, session_id, status.clone()).await?;
            bail!(transfer_status_summary(&status));
        }
    };

    let blob_ticket: BlobTicket = ticket_message
        .ticket
        .parse()
        .context("parsing blob ticket")?;
    let download = BlobDownloadStore::new("drift-blobs-recv", session_id).await?;
    let connection = endpoint
        .connect(blob_ticket.addr().clone(), BLOBS_ALPN)
        .await
        .context("connecting to blob provider")?;
    let mut stream = download
        .store
        .remote()
        .fetch(connection, blob_ticket.hash_and_format())
        .stream();

    let result = loop {
        tokio::select! {
            cancel_requested = wait_for_cancel(&mut cancel_rx), if cancel_rx.is_some() => {
                if cancel_requested {
                    let cancellation = local_cancellation(TransferRole::Receiver, CancelPhase::Transferring);
                    let _ = send_cancel(
                        control_send,
                        session_id,
                        cancellation.by,
                        cancellation.phase,
                        cancellation.reason.clone(),
                    ).await;
                    break Ok(Some(cancellation));
                }
            }
            control_message = read_message::<ControlMessage>(control_recv) => {
                match control_message.context("waiting for transfer control message")? {
                    ControlMessage::Cancel(cancel) => {
                        break Ok(Some(cancellation_from_message(cancel, session_id)?));
                    }
                    other => {
                        let status = transfer_error_status(
                            TransferErrorCode::UnexpectedMessage,
                            format!(
                                "unexpected control message while receiving transfer: {:?}",
                                other
                            ),
                        );
                        send_transfer_result(control_send, session_id, status.clone()).await?;
                        break Err(anyhow!(transfer_status_summary(&status)));
                    }
                }
            }
            item = stream.next() => {
                match item {
                    Some(GetProgressItem::Progress(offset)) => {
                        on_progress(FileReceiveProgress {
                            total_bytes_received: offset,
                            total_bytes_to_receive,
                            bytes_received_in_file: 0,
                            file_size: 0,
                            file_path: Arc::from(""),
                        });
                    }
                    Some(GetProgressItem::Done(_)) => break Ok(None),
                    Some(GetProgressItem::Error(err)) => {
                        let error = anyhow!(err.to_string());
                        let status = transfer_error_status(TransferErrorCode::IoError, error.to_string());
                        send_transfer_result(control_send, session_id, status.clone()).await?;
                        break Err(error);
                    }
                    None => break Ok(None),
                }
            }
        }
    };

    let result = match result {
        Ok(None) => {
            export_downloaded_collection(&download.store, blob_ticket.hash(), &expected_files)
                .await?;
            on_progress(FileReceiveProgress {
                total_bytes_received: total_bytes_to_receive,
                total_bytes_to_receive,
                bytes_received_in_file: 0,
                file_size: 0,
                file_path: Arc::from(""),
            });
            send_transfer_result(control_send, session_id, TransferStatus::Ok).await?;
            Ok(None)
        }
        other => other,
    };

    drop(stream);
    let shutdown_result = download.shutdown().await;
    shutdown_result?;
    let outcome = result?;

    if outcome.is_none() {
        match read_message::<ControlMessage>(control_recv)
            .await
            .context("waiting for transfer acknowledgement")?
        {
            ControlMessage::TransferAck(ack) => {
                ensure_matching_session_id(&ack.session_id, session_id)?
            }
            other => bail!(
                "unexpected control message while waiting for transfer acknowledgement: {:?}",
                other
            ),
        }

        control_send.finish()?;
        let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, control_send.stopped()).await;
        println!("Transfer session finished");
    } else {
        let _ = control_send.finish();
    }

    Ok(outcome)
}

pub fn build_expected_transfer_files(
    manifest: &OfferManifest,
    mut expected_files: BTreeMap<String, ExpectedFile>,
) -> Result<Vec<ExpectedTransferFile>> {
    let mut ordered = Vec::with_capacity(manifest.files.len());

    for manifest_file in &manifest.files {
        let expected = expected_files
            .remove(&manifest_file.path)
            .ok_or_else(|| anyhow!("missing expected file entry for {}", manifest_file.path))?;
        if expected.size != manifest_file.size {
            bail!(
                "expected size mismatch for {}: expected {} manifest {}",
                manifest_file.path,
                expected.size,
                manifest_file.size
            );
        }

        ordered.push(ExpectedTransferFile {
            path: manifest_file.path.clone(),
            size: manifest_file.size,
            destination: expected.destination,
        });
    }

    if !expected_files.is_empty() {
        bail!("unexpected extra expected file entries remain");
    }

    Ok(ordered)
}

impl BlobProvider {
    async fn ticket(&self) -> Result<String> {
        self.router.endpoint().online().await;
        let ticket = BlobTicket::new(
            self.router.endpoint().addr(),
            self._collection_tag.hash(),
            BlobFormat::HashSeq,
        );
        Ok(ticket.to_string())
    }

    async fn shutdown(self) -> Result<()> {
        self.router
            .shutdown()
            .await
            .context("shutting down blob router")?;
        drop(self.root);
        Ok(())
    }
}

#[derive(Clone, Copy)]
struct BlobProgressState {
    hash: Hash,
    file_index: usize,
    file_size: u64,
}

async fn prepare_blob_provider(
    endpoint: &Endpoint,
    session_id: &str,
    files: &[PreparedFile],
) -> Result<BlobProvider> {
    let root = TempDir::new("drift-blobs-send", session_id).await?;
    let store = FsStore::load(&root.path)
        .await
        .with_context(|| format!("loading blob store {}", root.path.display()))?;
    let mut file_hashes = BTreeMap::new();

    let mut collection = Collection::default();
    for (file_index, prepared) in files.iter().enumerate() {
        let tag = store
            .add_path_with_opts(AddPathOptions {
                path: prepared.source_path.clone(),
                mode: ImportMode::TryReference,
                format: BlobFormat::Raw,
            })
            .temp_tag()
            .await
            .with_context(|| format!("importing {}", prepared.source_path.display()))?;
        file_hashes.insert(
            tag.hash(),
            BlobProgressState {
                hash: tag.hash(),
                file_index,
                file_size: prepared.size,
            },
        );
        collection.extend([(prepared.transfer_path.clone(), tag.hash())]);
    }

    let collection_tag = collection.store(store.as_ref()).await?;
    let (event_sender, event_rx) = EventSender::channel(
        32,
        EventMask {
            get: RequestMode::NotifyLog,
            get_many: RequestMode::NotifyLog,
            ..EventMask::DEFAULT
        },
    );
    let progress_rx = spawn_blob_progress_forwarder(event_rx, file_hashes);

    let router = Router::builder(endpoint.clone())
        .accept(
            BLOBS_ALPN,
            BlobsProtocol::new(store.as_ref(), Some(event_sender)),
        )
        .spawn();

    Ok(BlobProvider {
        router,
        root,
        _collection_tag: collection_tag,
        progress_rx,
    })
}

fn spawn_blob_progress_forwarder(
    mut event_rx: mpsc::Receiver<ProviderMessage>,
    file_hashes: BTreeMap<Hash, BlobProgressState>,
) -> mpsc::Receiver<FileSendProgress> {
    let (progress_tx, progress_rx) = mpsc::channel(64);
    tokio::spawn(async move {
        while let Some(message) = event_rx.recv().await {
            match message {
                ProviderMessage::GetRequestReceivedNotify(msg) => {
                    tokio::spawn(forward_request_updates(
                        msg.rx,
                        file_hashes.clone(),
                        progress_tx.clone(),
                    ));
                }
                ProviderMessage::GetManyRequestReceivedNotify(msg) => {
                    tokio::spawn(forward_request_updates(
                        msg.rx,
                        file_hashes.clone(),
                        progress_tx.clone(),
                    ));
                }
                _ => {}
            }
        }
    });
    progress_rx
}

async fn forward_request_updates(
    mut updates_rx: irpc::channel::mpsc::Receiver<RequestUpdate>,
    file_hashes: BTreeMap<Hash, BlobProgressState>,
    progress_tx: mpsc::Sender<FileSendProgress>,
) {
    let mut current: Option<BlobProgressState> = None;
    let mut bytes_by_hash = BTreeMap::<Hash, u64>::new();
    let mut total_bytes_sent = 0_u64;

    while let Ok(Some(update)) = updates_rx.recv().await {
        match update {
            RequestUpdate::Started(started) => {
                current = file_hashes.get(&started.hash).copied();
            }
            RequestUpdate::Progress(progress) => {
                if let Some(current_file) = current {
                    let next = progress.end_offset.min(current_file.file_size);
                    let prev = bytes_by_hash.get(&current_file.hash).copied().unwrap_or(0);
                    if next > prev {
                        total_bytes_sent += next - prev;
                        bytes_by_hash.insert(current_file.hash, next);
                        let _ = progress_tx
                            .send(FileSendProgress {
                                total_bytes_sent,
                                bytes_sent_in_file: next,
                                file_index: current_file.file_index,
                            })
                            .await;
                    }
                }
            }
            RequestUpdate::Completed(_) | RequestUpdate::Aborted(_) => {
                current = None;
            }
        }
    }
}

fn make_absolute_path(path: &PathBuf) -> Result<PathBuf> {
    if path.is_absolute() {
        Ok(path.clone())
    } else {
        Ok(std::env::current_dir()
            .context("resolving current directory")?
            .join(path))
    }
}

async fn export_downloaded_collection(
    store: &FsStore,
    root_hash: iroh_blobs::Hash,
    expected_files: &[ExpectedTransferFile],
) -> Result<()> {
    let collection = Collection::load(root_hash, store.as_ref())
        .await
        .context("loading downloaded blob collection")?;
    let hashes_by_path = collection.into_iter().collect::<BTreeMap<_, _>>();

    for expected in expected_files {
        let hash = hashes_by_path
            .get(&expected.path)
            .copied()
            .ok_or_else(|| anyhow!("missing downloaded blob for {}", expected.path))?;
        if let Some(parent) = expected.destination.parent() {
            fs::create_dir_all(parent)
                .await
                .with_context(|| format!("creating directory {}", parent.display()))?;
        }
        let export_target = make_absolute_path(&expected.destination)?;
        store
            .export_with_opts(ExportOptions {
                hash,
                target: export_target,
                mode: ExportMode::Copy,
            })
            .finish()
            .await
            .with_context(|| format!("exporting {}", expected.destination.display()))?;
        println!("Received {}", expected.destination.display());
    }

    Ok(())
}

impl BlobDownloadStore {
    async fn new(prefix: &str, session_id: &str) -> Result<Self> {
        let root = TempDir::new(prefix, session_id).await?;
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

fn ensure_matching_session_id(actual: &str, expected: &str) -> Result<()> {
    if actual == expected {
        Ok(())
    } else {
        bail!("session id mismatch: expected {expected}, got {actual}")
    }
}

fn local_cancellation(by: TransferRole, phase: CancelPhase) -> TransferCancellation {
    let reason = match (by, phase) {
        (TransferRole::Sender, CancelPhase::WaitingForDecision) => {
            "sender cancelled before approval".to_owned()
        }
        (TransferRole::Sender, CancelPhase::Transferring) => "sender cancelled transfer".to_owned(),
        (TransferRole::Receiver, CancelPhase::WaitingForDecision) => {
            "receiver cancelled before approval".to_owned()
        }
        (TransferRole::Receiver, CancelPhase::Transferring) => {
            "receiver cancelled transfer".to_owned()
        }
    };
    TransferCancellation { by, phase, reason }
}

fn cancellation_from_message(cancel: Cancel, session_id: &str) -> Result<TransferCancellation> {
    ensure_matching_session_id(&cancel.session_id, session_id)?;
    Ok(TransferCancellation {
        by: cancel.by,
        phase: cancel.phase,
        reason: cancel.reason,
    })
}

async fn wait_for_cancel(cancel_rx: &mut Option<watch::Receiver<bool>>) -> bool {
    let Some(cancel_rx) = cancel_rx.as_mut() else {
        return false;
    };

    if *cancel_rx.borrow() {
        return true;
    }

    loop {
        if cancel_rx.changed().await.is_err() {
            return *cancel_rx.borrow();
        }
        if *cancel_rx.borrow() {
            return true;
        }
    }
}

fn transfer_status_summary(status: &TransferStatus) -> String {
    match status {
        TransferStatus::Ok => "ok".to_owned(),
        TransferStatus::Error { code, message } => format!("{code:?}: {message}"),
    }
}

fn transfer_error_status(code: TransferErrorCode, message: String) -> TransferStatus {
    TransferStatus::Error { code, message }
}

async fn send_cancel(
    control_send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    by: TransferRole,
    phase: CancelPhase,
    reason: String,
) -> Result<()> {
    write_message(
        control_send,
        &ControlMessage::Cancel(Cancel {
            session_id: session_id.to_owned(),
            by,
            phase,
            reason,
        }),
    )
    .await
}

async fn send_transfer_result(
    control_send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    status: TransferStatus,
) -> Result<()> {
    write_message(
        control_send,
        &ControlMessage::TransferResult(TransferResult {
            session_id: session_id.to_owned(),
            status,
        }),
    )
    .await
}

async fn send_transfer_ack(
    control_send: &mut iroh::endpoint::SendStream,
    session_id: &str,
) -> Result<()> {
    write_message(
        control_send,
        &ControlMessage::TransferAck(TransferAck {
            session_id: session_id.to_owned(),
        }),
    )
    .await
}

#[cfg(test)]
mod transfer_tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};
    use tokio::fs;

    #[tokio::test]
    async fn build_expected_transfer_files_preserves_manifest_order() -> Result<()> {
        let manifest = OfferManifest {
            files: vec![
                crate::rendezvous::OfferFile {
                    path: "b.txt".to_owned(),
                    size: 2,
                },
                crate::rendezvous::OfferFile {
                    path: "a.txt".to_owned(),
                    size: 1,
                },
            ],
            file_count: 2,
            total_size: 3,
        };
        let expected = BTreeMap::from([
            (
                "a.txt".to_owned(),
                ExpectedFile {
                    size: 1,
                    destination: PathBuf::from("/tmp/a.txt"),
                },
            ),
            (
                "b.txt".to_owned(),
                ExpectedFile {
                    size: 2,
                    destination: PathBuf::from("/tmp/b.txt"),
                },
            ),
        ]);

        let ordered = build_expected_transfer_files(&manifest, expected)?;

        assert_eq!(ordered[0].path, "b.txt");
        assert_eq!(ordered[1].path, "a.txt");
        Ok(())
    }

    #[tokio::test]
    #[ignore = "slow: iroh endpoint + blob provider often exceeds 60s in CI"]
    async fn prepare_blob_provider_contains_all_added_files() -> Result<()> {
        static NEXT_TEMP_ID: AtomicU64 = AtomicU64::new(0);
        let unique = format!(
            "drift-session-prepare-provider-{}-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system time")
                .as_nanos(),
            NEXT_TEMP_ID.fetch_add(1, Ordering::Relaxed)
        );
        let temp = std::env::temp_dir().join(unique);
        fs::create_dir_all(&temp).await?;
        let first = temp.join("first.txt");
        let second = temp.join("nested/second.txt");
        if let Some(parent) = second.parent() {
            fs::create_dir_all(parent).await?;
        }
        fs::write(&first, "alpha").await?;
        fs::write(&second, "beta").await?;

        let files = vec![
            PreparedFile {
                source_path: first,
                transfer_path: "first.txt".to_owned(),
                size: 5,
            },
            PreparedFile {
                source_path: second,
                transfer_path: "nested/second.txt".to_owned(),
                size: 4,
            },
        ];

        let endpoint = match bind_endpoint().await {
            Ok(endpoint) => endpoint,
            Err(error) => {
                let chain = format!("{error:#}");
                if chain.contains("Failed to bind sockets")
                    || chain.contains("Operation not permitted")
                {
                    let _ = std::fs::remove_dir_all(temp);
                    return Ok(());
                }
                return Err(error);
            }
        };
        let provider = prepare_blob_provider(&endpoint, "session-test", &files).await?;
        let store = FsStore::load(&provider.root.path)
            .await
            .context("loading provider store for verification")?;
        let collection = Collection::load(provider._collection_tag.hash(), store.as_ref())
            .await
            .context("loading provider collection for verification")?;
        let by_path = collection.into_iter().collect::<BTreeMap<_, _>>();

        assert_eq!(by_path.len(), files.len());
        assert!(by_path.contains_key("first.txt"));
        assert!(by_path.contains_key("nested/second.txt"));

        provider.shutdown().await?;
        endpoint.close().await;
        let _ = std::fs::remove_dir_all(temp);
        Ok(())
    }
}
