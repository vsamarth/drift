use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, anyhow, bail};
use futures_lite::StreamExt;
use iroh::{Endpoint, RelayMode, endpoint::presets, protocol::Router};
use iroh_blobs::{
    ALPN as BLOBS_ALPN, BlobFormat, BlobsProtocol,
    api::{
        TempTag,
        blobs::{AddPathOptions, ExportMode, ExportOptions, ImportMode},
        remote::GetProgressItem,
    },
    format::collection::Collection,
    store::fs::FsStore,
    ticket::BlobTicket,
};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio::time::{Duration, timeout};

use crate::fs_plan::prepare::PreparedFile;
use crate::fs_plan::receive::{ExpectedFile, build_expected_files};
use crate::rendezvous::OfferManifest;
use crate::util::describe_remote;
use crate::wire::{
    ALPN, BlobTicketMessage, ControlMessage, TransferAck, TransferErrorCode, TransferResult,
    TransferStatus, read_message, write_message,
};

const ACK_OK: &[u8] = b"ok";
const DEMO_HELLO: &[u8] = b"hello";
const DEMO_DONE: &[u8] = b"done";
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
        .alpns(vec![ALPN.to_vec()])
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
    _connection: iroh::endpoint::Connection,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    session_id: &str,
    files: &[PreparedFile],
    mut on_progress: F,
) -> Result<()>
where
    F: FnMut(FileSendProgress),
{
    let provider = prepare_blob_provider(session_id, files).await?;
    let ticket = provider.ticket().await?;

    write_message(
        control_send,
        &ControlMessage::BlobTicket(BlobTicketMessage {
            session_id: session_id.to_owned(),
            ticket,
        }),
    )
    .await
    .context("sending blob transfer ticket")?;

    let result = match read_message::<ControlMessage>(control_recv)
        .await
        .context("waiting for final transfer result")?
    {
        ControlMessage::TransferResult(result) => {
            ensure_matching_session_id(&result.session_id, session_id)?;
            if !matches!(result.status, TransferStatus::Ok) {
                Err(anyhow!(
                    "receiver failed transfer: {}",
                    transfer_status_summary(&result.status)
                ))
            } else {
                Ok(())
            }
        }
        other => Err(anyhow!("unexpected final control message: {:?}", other)),
    };

    if result.is_ok() {
        let total_bytes_sent = files.iter().map(|file| file.size).sum();
        on_progress(FileSendProgress {
            total_bytes_sent,
            bytes_sent_in_file: 0,
            file_index: 0,
        });

        send_transfer_ack(control_send, session_id).await?;
        control_send.finish()?;
        let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, control_send.stopped()).await;
    }

    provider.shutdown().await?;
    result
}

pub fn demo_hello_mode_enabled() -> bool {
    matches!(
        std::env::var("DRIFT_DEMO_HELLO").ok().as_deref(),
        Some("1") | Some("true") | Some("TRUE") | Some("yes") | Some("YES")
    )
}

pub async fn send_demo_hello_over_connection(connection: iroh::endpoint::Connection) -> Result<()> {
    let (mut send_stream, mut recv_stream) = connection
        .open_bi()
        .await
        .context("opening demo hello stream")?;

    send_stream
        .write_all(DEMO_HELLO)
        .await
        .context("writing demo hello payload")?;
    send_stream
        .flush()
        .await
        .context("flushing demo hello payload")?;

    let mut ack = [0_u8; ACK_OK.len()];
    recv_stream
        .read_exact(&mut ack)
        .await
        .context("waiting for demo hello ACK")?;
    if ack.as_slice() != ACK_OK {
        bail!("receiver returned unexpected demo ACK");
    }

    send_stream
        .write_all(DEMO_DONE)
        .await
        .context("writing demo done marker")?;
    send_stream
        .flush()
        .await
        .context("flushing demo done marker")?;
    send_stream.finish()?;

    println!(
        "Demo hello payload sent: {}",
        String::from_utf8_lossy(DEMO_HELLO)
    );
    connection.close(0u32.into(), b"done");
    Ok(())
}

pub async fn receive_files_over_connection(
    connection: iroh::endpoint::Connection,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    session_id: &str,
    out_dir: PathBuf,
    manifest: &OfferManifest,
) -> Result<()> {
    let expected_files =
        build_expected_transfer_files(manifest, build_expected_files(manifest, &out_dir).await?)?;
    receive_files_over_connection_with_progress(
        connection,
        control_send,
        control_recv,
        session_id,
        expected_files,
        |_| {},
    )
    .await
}

pub async fn receive_files_over_connection_with_progress<F>(
    _connection: iroh::endpoint::Connection,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    session_id: &str,
    expected_files: Vec<ExpectedTransferFile>,
    mut on_progress: F,
) -> Result<()>
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
                format!("unexpected control message while waiting for blob ticket: {:?}", other),
            );
            send_transfer_result(control_send, session_id, status.clone()).await?;
            bail!(transfer_status_summary(&status));
        }
    };

    let result =
        receive_blob_collection(&ticket_message.ticket, &expected_files, total_bytes_to_receive, &mut on_progress)
            .await;
    match result {
        Ok(()) => {
            send_transfer_result(control_send, session_id, TransferStatus::Ok).await?;
        }
        Err(err) => {
            let status = transfer_error_status(TransferErrorCode::IoError, err.to_string());
            send_transfer_result(control_send, session_id, status.clone()).await?;
            return Err(err);
        }
    }

    match read_message::<ControlMessage>(control_recv)
        .await
        .context("waiting for transfer acknowledgement")?
    {
        ControlMessage::TransferAck(ack) => ensure_matching_session_id(&ack.session_id, session_id)?,
        other => bail!(
            "unexpected control message while waiting for transfer acknowledgement: {:?}",
            other
        ),
    }

    control_send.finish()?;
    let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, control_send.stopped()).await;
    println!("Transfer session finished");
    Ok(())
}

pub async fn receive_demo_hello_over_connection(
    connection: iroh::endpoint::Connection,
) -> Result<()> {
    let (mut send_stream, mut recv_stream) = connection
        .accept_bi()
        .await
        .context("waiting for demo hello stream")?;

    let mut payload = [0_u8; DEMO_HELLO.len()];
    recv_stream
        .read_exact(&mut payload)
        .await
        .context("reading demo hello payload")?;
    if payload.as_slice() != DEMO_HELLO {
        bail!("unexpected demo hello payload");
    }

    println!(
        "Received demo payload: {}",
        String::from_utf8_lossy(DEMO_HELLO)
    );

    send_stream
        .write_all(ACK_OK)
        .await
        .context("writing demo hello ACK")?;
    send_stream
        .flush()
        .await
        .context("flushing demo hello ACK")?;
    let mut done = [0_u8; DEMO_DONE.len()];
    recv_stream
        .read_exact(&mut done)
        .await
        .context("waiting for demo done marker")?;
    if done.as_slice() != DEMO_DONE {
        bail!("unexpected demo done marker");
    }

    send_stream.finish()?;
    Ok(())
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
        self.router.shutdown().await.context("shutting down blob router")?;
        drop(self.root);
        Ok(())
    }
}

async fn prepare_blob_provider(session_id: &str, files: &[PreparedFile]) -> Result<BlobProvider> {
    let root = TempDir::new("drift-blobs-send", session_id).await?;
    let store = FsStore::load(&root.path)
        .await
        .with_context(|| format!("loading blob store {}", root.path.display()))?;

    let mut collection = Collection::default();
    for prepared in files {
        let tag = store
            .add_path_with_opts(AddPathOptions {
                path: prepared.source_path.clone(),
                mode: ImportMode::TryReference,
                format: BlobFormat::Raw,
            })
            .temp_tag()
            .await
            .with_context(|| format!("importing {}", prepared.source_path.display()))?;
        collection.extend([(prepared.transfer_path.clone(), tag.hash())]);
    }

    let collection_tag = collection.store(store.as_ref()).await?;

    let endpoint = Endpoint::builder(presets::N0)
        .alpns(vec![BLOBS_ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .bind()
        .await
        .context("binding blob provider endpoint")?;
    let router = Router::builder(endpoint)
        .accept(BLOBS_ALPN, BlobsProtocol::new(store.as_ref(), None))
        .spawn();

    Ok(BlobProvider {
        router,
        root,
        _collection_tag: collection_tag,
    })
}

async fn receive_blob_collection<F>(
    ticket: &str,
    expected_files: &[ExpectedTransferFile],
    total_bytes_to_receive: u64,
    on_progress: &mut F,
) -> Result<()>
where
    F: FnMut(FileReceiveProgress),
{
    let blob_ticket: BlobTicket = ticket.parse().context("parsing blob ticket")?;
    let download = BlobDownloadStore::new("drift-blobs-recv", ticket).await?;
    let endpoint = Endpoint::builder(presets::N0)
        .alpns(vec![BLOBS_ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .bind()
        .await
        .context("binding blob receiver endpoint")?;
    let connection = endpoint
        .connect(blob_ticket.addr().clone(), BLOBS_ALPN)
        .await
        .context("connecting to blob provider")?;

    let mut stream = download
        .store
        .remote()
        .fetch(connection, blob_ticket.hash_and_format())
        .stream();

    let result = async {
        while let Some(item) = stream.next().await {
            match item {
                GetProgressItem::Progress(offset) => {
                    on_progress(FileReceiveProgress {
                        total_bytes_received: offset,
                        total_bytes_to_receive,
                        bytes_received_in_file: 0,
                        file_size: 0,
                        file_path: Arc::from(""),
                    });
                }
                GetProgressItem::Done(_) => break,
                GetProgressItem::Error(err) => {
                    return Err(anyhow!(err.to_string()));
                }
            }
        }

        export_downloaded_collection(&download.store, blob_ticket.hash(), expected_files).await?;
        on_progress(FileReceiveProgress {
            total_bytes_received: total_bytes_to_receive,
            total_bytes_to_receive,
            bytes_received_in_file: 0,
            file_size: 0,
            file_path: Arc::from(""),
        });
        Ok(())
    }
    .await;

    endpoint.close().await;
    download.shutdown().await?;
    result
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

fn transfer_status_summary(status: &TransferStatus) -> String {
    match status {
        TransferStatus::Ok => "ok".to_owned(),
        TransferStatus::Error { code, message } => format!("{code:?}: {message}"),
    }
}

fn transfer_error_status(code: TransferErrorCode, message: String) -> TransferStatus {
    TransferStatus::Error { code, message }
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
}
