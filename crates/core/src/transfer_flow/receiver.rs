#![allow(dead_code)]

use anyhow::{Context, Result, anyhow, bail};
use futures_lite::StreamExt;
use iroh::{
    Endpoint,
    endpoint::Connection,
};
use iroh_blobs::{
    ALPN as BLOBS_ALPN,
    api::{remote::GetProgressItem, blobs::ExportMode, blobs::ExportOptions},
    format::collection::Collection,
    store::fs::FsStore,
    ticket::BlobTicket,
};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::fs;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::{debug, info, instrument, warn};

use crate::{
    protocol::wire as protocol_wire,
    protocol::{message as protocol_message, receive as protocol_receiver},
    protocol::ALPN,
    rendezvous::OfferManifest,
};

use super::path::{ScratchDir, ensure_destination_available, resolve_transfer_destination};
use super::types::{TransferCancellation, TransferOutcome};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverRequest {
    pub device_name: String,
    pub device_type: crate::protocol::DeviceType,
    pub out_dir: std::path::PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiverDecision {
    Accept,
    Decline,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverOfferItem {
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverOffer {
    pub session_id: String,
    pub sender_device_name: String,
    pub sender_device_type: crate::protocol::DeviceType,
    pub sender_endpoint_id: iroh::EndpointId,
    pub items: Vec<ReceiverOfferItem>,
    pub file_count: u64,
    pub total_size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiverEvent {
    Listening {
        endpoint_id: iroh::EndpointId,
    },
    OfferReceived {
        session_id: String,
        sender_device_name: String,
        sender_endpoint_id: iroh::EndpointId,
        file_count: u64,
        total_size: u64,
    },
    TransferStarted {
        session_id: String,
        file_count: u64,
        total_bytes: u64,
    },
    TransferProgress {
        session_id: String,
        bytes_received: u64,
        total_bytes: u64,
    },
    Completed {
        session_id: String,
    },
}

pub type ReceiverEventStream = UnboundedReceiverStream<Result<ReceiverEvent>>;

#[derive(Debug)]
pub struct ReceiverControl {
    pub decision_tx: oneshot::Sender<ReceiverDecision>,
    pub cancel_tx: watch::Sender<bool>,
}

#[derive(Debug)]
pub struct ReceiverStart {
    pub events: ReceiverEventStream,
    pub offer_rx: oneshot::Receiver<Result<ReceiverOffer>>,
    pub outcome_rx: oneshot::Receiver<Result<TransferOutcome>>,
    pub control: ReceiverControl,
}

#[derive(Debug)]
pub struct ReceiverSession {
    request: ReceiverRequest,
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

impl ReceiverSession {
    pub fn new(request: ReceiverRequest) -> Self {
        Self { request }
    }

    pub fn start(self, endpoint: Endpoint, connection: Connection) -> ReceiverStart
    where
        Self: Send + 'static,
    {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (offer_tx, offer_rx) = oneshot::channel();
        let (decision_tx, decision_rx) = oneshot::channel();
        let (cancel_tx, cancel_rx) = watch::channel(false);
        let (outcome_tx, outcome_rx) = oneshot::channel();
        let request = self.request.clone();
        tokio::spawn(async move {
            let outcome = run_session(
                endpoint,
                connection,
                request,
                Some(event_tx),
                offer_tx,
                decision_rx,
                cancel_rx,
            )
            .await;
            let _ = outcome_tx.send(outcome);
        });

        ReceiverStart {
            events: UnboundedReceiverStream::new(event_rx),
            offer_rx,
            outcome_rx,
            control: ReceiverControl {
                decision_tx,
                cancel_tx,
            },
        }
    }
}

#[instrument(skip_all, fields(remote = %connection.remote_id()))]
async fn run_session(
    endpoint: Endpoint,
    connection: Connection,
    request: ReceiverRequest,
    event_tx: Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    offer_tx: oneshot::Sender<Result<ReceiverOffer>>,
    decision_rx: oneshot::Receiver<ReceiverDecision>,
    mut cancel_rx: watch::Receiver<bool>,
) -> Result<TransferOutcome> {
    emit_receiver_event(
        &event_tx,
        ReceiverEvent::Listening {
            endpoint_id: endpoint.addr().id,
        },
    );

    let (mut control_send, mut control_recv) = connection
        .accept_bi()
        .await
        .context("waiting for transfer control stream")?;

    let mut handshake = protocol_receiver::Receiver::new(protocol_message::Identity {
        role: protocol_message::TransferRole::Receiver,
        endpoint_id: endpoint.addr().id,
        device_name: request.device_name.clone(),
        device_type: to_protocol_device_type(request.device_type),
    });

    let peer_hello = handshake
        .read_peer_hello(&mut control_recv)
        .await
        .context("reading sender hello")?;
    
    let session_id = peer_hello.session_id.clone();
    tracing::Span::current().record("session_id", &session_id);
    
    handshake
        .send_hello(&mut control_send, &session_id)
        .await
        .context("sending receiver hello")?;

    let offer = handshake
        .read_offer(&mut control_recv, &session_id)
        .await
        .context("reading transfer offer")?;

    let sender_device_name = peer_hello.identity.device_name.clone();
    let sender_device_type = to_local_device_type(peer_hello.identity.device_type);
    let sender_endpoint_id = peer_hello.identity.endpoint_id;
    let manifest = to_offer_manifest(&offer);

    let expected_files = match build_expected_files(&manifest, &request.out_dir).await {
        Ok(expected_files) => expected_files,
        Err(err) => {
            warn!(%session_id, error = %err, "offer rejected due to path validation");
            let _ = handshake
                .decline(&mut control_send, &session_id, err.to_string())
                .await;
            let message = format!("{err:#}");
            let _ = offer_tx.send(Err(anyhow!(message.clone())));
            emit_receiver_error(&event_tx, anyhow!(message.clone()));
            return Err(anyhow!(message));
        }
    };
    let expected_transfer_files = build_expected_transfer_files(&manifest, expected_files)
        .context("building transfer file list")?;

    let offer = ReceiverOffer {
        session_id: session_id.clone(),
        sender_device_name: sender_device_name.clone(),
        sender_device_type,
        sender_endpoint_id,
        items: manifest
            .files
            .iter()
            .map(|item| ReceiverOfferItem {
                path: item.path.clone(),
                size: item.size,
            })
            .collect(),
        file_count: manifest.file_count,
        total_size: manifest.total_size,
    };
    emit_receiver_event(
        &event_tx,
        ReceiverEvent::OfferReceived {
            session_id: offer.session_id.clone(),
            sender_device_name: offer.sender_device_name.clone(),
            sender_endpoint_id: offer.sender_endpoint_id,
            file_count: offer.file_count,
            total_size: offer.total_size,
        },
    );
    let _ = offer_tx.send(Ok(offer.clone()));

    info!(%session_id, %sender_device_name, file_count = offer.file_count, total_size = offer.total_size, "offer received");

    let decision = tokio::select! {
        decision = decision_rx => match decision {
            Ok(decision) => decision,
            Err(error) => {
                let message = format!("{error}");
                emit_receiver_error(&event_tx, anyhow!(message.clone()));
                return Err(anyhow!(message));
            }
        },
        _ = connection.closed() => {
            let message = "sender disconnected before approval".to_owned();
            warn!(%session_id, "{}", message);
            emit_receiver_error(&event_tx, anyhow!(message.clone()));
            return Err(anyhow!(message));
        }
        _ = tokio::time::sleep(std::time::Duration::from_secs(120)) => {
            let message = "offer timed out before approval".to_owned();
            warn!(%session_id, "{}", message);
            emit_receiver_error(&event_tx, anyhow!(message.clone()));
            return Err(anyhow!(message));
        }
    };

    match decision {
        ReceiverDecision::Accept => {
            info!(%session_id, "offer accepted");
            match handshake.accept(&mut control_send, &session_id).await {
                Ok(protocol_receiver::ReceiverControlOutcome::Accepted(sender)) => {
                    debug!(
                        %session_id,
                        sender_device_name = %sender.identity.device_name,
                        sender_endpoint_id = %sender.identity.endpoint_id,
                        "receiver.handshake.accepted"
                    );
                }
                Ok(other) => {
                    return Err(anyhow!(
                        "unexpected receiver control outcome after accept: {:?}",
                        other
                    ));
                }
                Err(error) => return Err(error),
            }

            let ticket_message = match protocol_wire::read_sender_message(&mut control_recv)
                .await
                .context("waiting for blob transfer ticket")?
            {
                protocol_message::SenderMessage::BlobTicket(message) => {
                    ensure_matching_session_id(&message.session_id, &session_id)?;
                    message
                }
                other => {
                    let status = protocol_message::TransferStatus::Error {
                        code: protocol_message::TransferErrorCode::UnexpectedMessage,
                        message: format!(
                            "unexpected control message while waiting for blob ticket: {:?}",
                            other
                        ),
                    };
                    send_transfer_result(&mut control_send, &session_id, status.clone()).await?;
                    bail!("unexpected message while waiting for blob ticket");
                }
            };

            let blob_ticket: BlobTicket = ticket_message
                .ticket
                .parse()
                .context("parsing blob ticket")?;

            debug!(%session_id, hash = %blob_ticket.hash(), "received blob ticket");

            let recv_store = ScratchDir::new("drift-blobs-recv", &session_id).await?;
            let store = FsStore::load(&recv_store.path)
                .await
                .with_context(|| format!("loading blob store {}", recv_store.path.display()))?;

            let blob_connection = endpoint
                .connect(blob_ticket.addr().clone(), BLOBS_ALPN)
                .await
                .context("connecting to blob provider")?;
            let mut stream = store.remote().fetch(blob_connection, blob_ticket.clone()).stream();

            let mut progress_send = connection
                .open_uni()
                .await
                .context("opening progress stream")?;

            let _ = protocol_wire::write_receiver_message(
                &mut progress_send,
                &protocol_message::ReceiverMessage::TransferStarted(
                    protocol_message::TransferStarted {
                        session_id: session_id.clone(),
                        file_count: manifest.file_count,
                        total_bytes: manifest.total_size,
                    },
                ),
            )
            .await;

            emit_receiver_event(
                &event_tx,
                ReceiverEvent::TransferStarted {
                    session_id: session_id.clone(),
                    file_count: manifest.file_count,
                    total_bytes: manifest.total_size,
                },
            );

            info!(%session_id, "transfer started");

            let mut last_progress_report = 0u64;
            let fetch_outcome: Result<Option<TransferCancellation>> = loop {
                tokio::select! {
                    cancel_requested = wait_for_cancel(&mut cancel_rx) => {
                        if cancel_requested {
                            info!(%session_id, "transfer cancelled by local user");
                            let cancellation = local_cancellation(
                                protocol_message::TransferRole::Receiver,
                                protocol_message::CancelPhase::Transferring,
                            );
                            let _ = send_receiver_cancel(
                                &mut control_send,
                                &session_id,
                                cancellation.by,
                                cancellation.phase,
                                cancellation.reason.clone(),
                            ).await;
                            break Ok(Some(cancellation));
                        }
                    }
                    control_message = protocol_wire::read_sender_message(&mut control_recv) => {
                        match control_message.context("waiting for transfer control message")? {
                            protocol_message::SenderMessage::Cancel(cancel) => {
                                info!(%session_id, "transfer cancelled by remote");
                                break Ok(Some(cancellation_from_message(cancel, &session_id)?));
                            }
                            other => {
                                bail!("unexpected message while receiving transfer: {:?}", other);
                            }
                        }
                    }
                    item = stream.next() => {
                        match item {
                            Some(GetProgressItem::Progress(offset)) => {
                                emit_receiver_event(
                                    &event_tx,
                                    ReceiverEvent::TransferProgress {
                                        session_id: session_id.clone(),
                                        bytes_received: offset,
                                        total_bytes: manifest.total_size,
                                    },
                                );

                                // Report to sender occasionally
                                if offset - last_progress_report >= 1024 * 1024 || offset == manifest.total_size {
                                    let _ = protocol_wire::write_receiver_message(
                                        &mut progress_send,
                                        &protocol_message::ReceiverMessage::TransferProgress(
                                            protocol_message::TransferProgress {
                                                session_id: session_id.clone(),
                                                bytes_sent: offset,
                                                total_bytes: manifest.total_size,
                                            }
                                        )
                                    ).await;
                                    last_progress_report = offset;
                                }
                            }
                            Some(GetProgressItem::Done(_)) => break Ok(None),
                            Some(GetProgressItem::Error(err)) => {
                                warn!(%session_id, error = %err, "blob fetch error");
                                break Err(anyhow!(err.to_string()));
                            }
                            None => break Ok(None),
                        }
                    }
                }
            };

            drop(stream);

            let outcome = match fetch_outcome {
                Ok(None) => {
                    info!(%session_id, "transfer data received, exporting files");
                    export_downloaded_collection(&store, blob_ticket.hash(), &expected_transfer_files)
                        .await?;
                    
                    let _ = protocol_wire::write_receiver_message(
                        &mut progress_send,
                        &protocol_message::ReceiverMessage::TransferCompleted(
                            protocol_message::TransferCompleted {
                                session_id: session_id.clone(),
                            }
                        )
                    ).await;

                    emit_receiver_event(
                        &event_tx,
                        ReceiverEvent::Completed {
                            session_id: session_id.clone(),
                        },
                    );
                    send_transfer_result(
                        &mut control_send,
                        &session_id,
                        protocol_message::TransferStatus::Ok,
                    )
                    .await?;
                    info!(%session_id, "transfer completed successfully");
                    TransferOutcome::Completed
                }
                Ok(Some(cancellation)) => {
                    info!(%session_id, reason = %cancellation.reason, "transfer cancelled");
                    TransferOutcome::Cancelled(cancellation)
                }
                Err(error) => {
                    warn!(%session_id, error = %error, "transfer failed");
                    let status = protocol_message::TransferStatus::Error {
                        code: protocol_message::TransferErrorCode::IoError,
                        message: error.to_string(),
                    };
                    send_transfer_result(&mut control_send, &session_id, status).await?;
                    return Err(error);
                }
            };

            if matches!(outcome, TransferOutcome::Completed) {
                match protocol_wire::read_sender_message(&mut control_recv)
                    .await
                    .context("waiting for transfer acknowledgement")?
                {
                    protocol_message::SenderMessage::TransferAck(ack) => {
                        ensure_matching_session_id(&ack.session_id, &session_id)?
                    }
                    other => bail!("unexpected message while waiting for transfer ack: {:?}", other),
                }
                let _ = control_send.finish();
            } else {
                let _ = control_send.finish();
            }

            let _ = store.shutdown().await;
            Ok(outcome)
        }
        ReceiverDecision::Decline => {
            info!(%session_id, "offer declined");
            let _ = handshake
                .decline(
                    &mut control_send,
                    &session_id,
                    "receiver declined the transfer".to_owned(),
                )
                .await
                .context("sending receiver decline")?;
            Ok(TransferOutcome::Declined {
                reason: "receiver declined".to_owned(),
            })
        }
    }
}

pub async fn export_downloaded_collection(
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
        let export_target = if expected.destination.is_absolute() {
            expected.destination.clone()
        } else {
            std::env::current_dir()?.join(&expected.destination)
        };
        store
            .export_with_opts(ExportOptions {
                hash,
                target: export_target,
                mode: ExportMode::Copy,
            })
            .finish()
            .await
            .with_context(|| format!("exporting {}", expected.destination.display()))?;
    }

    Ok(())
}

async fn build_expected_files(
    manifest: &OfferManifest,
    out_dir: &Path,
) -> Result<BTreeMap<String, ExpectedTransferFile>> {
    let mut expected = BTreeMap::new();
    for file in &manifest.files {
        let destination = resolve_transfer_destination(out_dir, &file.path)?;
        ensure_destination_available(out_dir, &destination).await?;

        expected.insert(
            file.path.clone(),
            ExpectedTransferFile {
                path: file.path.clone(),
                size: file.size,
                destination,
            },
        );
    }
    Ok(expected)
}

fn build_expected_transfer_files(
    manifest: &OfferManifest,
    mut expected_files: BTreeMap<String, ExpectedTransferFile>,
) -> Result<Vec<ExpectedTransferFile>> {
    let mut ordered = Vec::with_capacity(manifest.files.len());
    for manifest_file in &manifest.files {
        let expected = expected_files
            .remove(&manifest_file.path)
            .ok_or_else(|| anyhow!("missing expected file entry for {}", manifest_file.path))?;
        ordered.push(expected);
    }
    Ok(ordered)
}

fn to_protocol_device_type(
    device_type: crate::protocol::DeviceType,
) -> protocol_message::DeviceType {
    match device_type {
        crate::protocol::DeviceType::Phone => protocol_message::DeviceType::Phone,
        crate::protocol::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
    }
}

fn to_local_device_type(device_type: protocol_message::DeviceType) -> crate::protocol::DeviceType {
    match device_type {
        protocol_message::DeviceType::Phone => crate::protocol::DeviceType::Phone,
        protocol_message::DeviceType::Laptop => crate::protocol::DeviceType::Laptop,
    }
}

fn to_offer_manifest(offer: &protocol_message::Offer) -> OfferManifest {
    let files = offer
        .manifest
        .items
        .iter()
        .map(|item| match item {
            protocol_message::ManifestItem::File { path, size } => crate::rendezvous::OfferFile {
                path: path.clone(),
                size: *size,
            },
        })
        .collect();
    OfferManifest {
        files,
        file_count: offer.manifest.count() as u64,
        total_size: offer.manifest.total_size(),
    }
}

fn emit_receiver_event(
    event_tx: &Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    event: ReceiverEvent,
) {
    if let Some(tx) = event_tx {
        let _ = tx.send(Ok(event));
    }
}

fn emit_receiver_error(
    event_tx: &Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    error: anyhow::Error,
) {
    if let Some(tx) = event_tx {
        let _ = tx.send(Err(error));
    }
}

fn ensure_matching_session_id(actual: &str, expected: &str) -> Result<()> {
    if actual == expected {
        Ok(())
    } else {
        bail!("session id mismatch: expected {expected}, got {actual}")
    }
}

fn local_cancellation(
    by: protocol_message::TransferRole,
    phase: protocol_message::CancelPhase,
) -> TransferCancellation {
    let reason = match (by, phase) {
        (
            protocol_message::TransferRole::Sender,
            protocol_message::CancelPhase::WaitingForDecision,
        ) => "sender cancelled before approval".to_owned(),
        (protocol_message::TransferRole::Sender, protocol_message::CancelPhase::Transferring) => {
            "sender cancelled transfer".to_owned()
        }
        (
            protocol_message::TransferRole::Receiver,
            protocol_message::CancelPhase::WaitingForDecision,
        ) => "receiver cancelled before approval".to_owned(),
        (protocol_message::TransferRole::Receiver, protocol_message::CancelPhase::Transferring) => {
            "receiver cancelled transfer".to_owned()
        }
    };
    TransferCancellation { by, phase, reason }
}

fn cancellation_from_message(
    cancel: protocol_message::Cancel,
    session_id: &str,
) -> Result<TransferCancellation> {
    ensure_matching_session_id(&cancel.session_id, session_id)?;
    Ok(TransferCancellation {
        by: cancel.by,
        phase: cancel.phase,
        reason: cancel.reason,
    })
}

async fn wait_for_cancel(cancel_rx: &mut watch::Receiver<bool>) -> bool {
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

async fn send_receiver_cancel(
    control_send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    by: protocol_message::TransferRole,
    phase: protocol_message::CancelPhase,
    reason: String,
) -> Result<()> {
    protocol_wire::write_receiver_message(
        control_send,
        &protocol_message::ReceiverMessage::Cancel(protocol_message::Cancel {
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
    status: protocol_message::TransferStatus,
) -> Result<()> {
    protocol_wire::write_receiver_message(
        control_send,
        &protocol_message::ReceiverMessage::TransferResult(protocol_message::TransferResult {
            session_id: session_id.to_owned(),
            status,
        }),
    )
    .await
}

pub async fn bind_endpoint() -> Result<Endpoint> {
    iroh::Endpoint::builder(iroh::endpoint::presets::N0)
        .alpns(vec![ALPN.to_vec(), BLOBS_ALPN.to_vec()])
        .relay_mode(iroh::RelayMode::Default)
        .bind()
        .await
        .context("binding iroh endpoint")
}
