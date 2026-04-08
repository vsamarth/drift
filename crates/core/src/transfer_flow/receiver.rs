#![allow(dead_code)]

use anyhow::{Context, Result, anyhow, bail};
use futures_lite::StreamExt;
use iroh::{Endpoint, endpoint::Connection};
use iroh_blobs::{
    ALPN as BLOBS_ALPN,
    api::{blobs::ExportMode, blobs::ExportOptions, remote::GetProgressItem},
    format::collection::Collection,
    store::fs::FsStore,
    ticket::BlobTicket,
};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::fs;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::{info, instrument};

use crate::{
    protocol::ALPN, protocol::message as protocol_message, protocol::wire as protocol_wire,
    rendezvous::OfferManifest,
};

use super::progress::ProgressTracker;
use super::path::{
    ScratchDir, ensure_destination_available, resolve_output_dir, resolve_transfer_destination,
};
use super::types::{TransferOutcome, TransferPhase, TransferPlan, TransferSnapshot, wait_for_cancel};

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
        plan: TransferPlan,
    },
    TransferProgress {
        session_id: String,
        snapshot: TransferSnapshot,
    },
    TransferCompleted {
        session_id: String,
        snapshot: TransferSnapshot,
    },
    Failed {
        session_id: String,
        message: String,
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
    mut request: ReceiverRequest,
    event_tx: Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    offer_tx: oneshot::Sender<Result<ReceiverOffer>>,
    decision_rx: oneshot::Receiver<ReceiverDecision>,
    mut cancel_rx: watch::Receiver<bool>,
) -> Result<TransferOutcome> {
    request.out_dir = resolve_output_dir(&request.out_dir)?;

    emit_receiver_event(
        &event_tx,
        ReceiverEvent::Listening {
            endpoint_id: endpoint.addr().id,
        },
    );

    // --- Phase 1: Handshake ---
    let (mut control_send, mut control_recv, peer_hello, offer) =
        match do_handshake(&endpoint, &request, &connection, &mut cancel_rx).await? {
            HandshakeResult::Ok(s, r, h, o) => (s, r, h, o),
            HandshakeResult::Cancelled(outcome) => {
                let _ = offer_tx.send(Err(anyhow!("cancelled during handshake")));
                return Ok(outcome);
            }
        };

    let session_id = peer_hello.session_id.clone();
    tracing::Span::current().record("session_id", &session_id);

    // --- Phase 2: Offer Processing ---
    let manifest = to_offer_manifest(&offer);
    let plan = TransferPlan::from_manifest(session_id.clone(), &offer.manifest)?;
    let expected_files = match build_expected_files(&manifest, &request.out_dir).await {
        Ok(f) => f,
        Err(err) => {
            let _ = send_receiver_decline(&mut control_send, &session_id, err.to_string()).await;
            let _ = offer_tx.send(Err(anyhow!(err.to_string())));
            return Err(err);
        }
    };

    let expected_transfer_files = build_expected_transfer_files(&manifest, expected_files)?;
    let receiver_offer = ReceiverOffer {
        session_id: session_id.clone(),
        sender_device_name: peer_hello.identity.device_name.clone(),
        sender_device_type: to_local_device_type(peer_hello.identity.device_type),
        sender_endpoint_id: peer_hello.identity.endpoint_id,
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
            session_id: session_id.clone(),
            sender_device_name: receiver_offer.sender_device_name.clone(),
            sender_endpoint_id: receiver_offer.sender_endpoint_id,
            file_count: receiver_offer.file_count,
            total_size: receiver_offer.total_size,
        },
    );
    let _ = offer_tx.send(Ok(receiver_offer));

    // --- Phase 3: User Decision ---
    let decision = tokio::select! {
        res = decision_rx => res.map_err(|_| anyhow!("decision channel closed"))?,
        _ = wait_for_cancel(&mut cancel_rx) => return abort_session(&mut control_send, &session_id, protocol_message::CancelPhase::WaitingForDecision).await,
        _ = connection.closed() => bail!("connection closed before decision"),
        _ = tokio::time::sleep(Duration::from_secs(120)) => bail!("offer timed out"),
    };

    if decision == ReceiverDecision::Decline {
        let _ = send_receiver_decline(
            &mut control_send,
            &session_id,
            "declined by user".to_owned(),
        )
        .await;
        return Ok(TransferOutcome::Declined {
            reason: "receiver declined".to_owned(),
        });
    }

    // --- Phase 4: Data Transfer ---
    let _ = protocol_wire::write_receiver_message(
        &mut control_send,
        &protocol_message::ReceiverMessage::Accept(protocol_message::Accept {
            session_id: session_id.clone(),
        }),
    )
    .await?;

    let ticket_message = tokio::select! {
        res = protocol_wire::read_sender_message(&mut control_recv) => match res.context("waiting for ticket")? {
            protocol_message::SenderMessage::BlobTicket(msg) => msg,
            protocol_message::SenderMessage::Cancel(c) => return TransferOutcome::from_remote_cancel(c, &session_id),
            _ => bail!("unexpected message while waiting for ticket"),
        },
        _ = wait_for_cancel(&mut cancel_rx) => return abort_session(&mut control_send, &session_id, protocol_message::CancelPhase::Transferring).await,
        _ = connection.closed() => bail!("connection closed waiting for ticket"),
        _ = tokio::time::sleep(Duration::from_secs(30)) => bail!("timeout waiting for blob ticket"),
    };

    let blob_ticket: BlobTicket = ticket_message
        .ticket
        .parse()
        .context("parsing blob ticket")?;
    let scratch = ScratchDir::new("drift-recv", &session_id).await?;
    let store = FsStore::load(&scratch.path).await?;

    let outcome = async {
        let blob_conn = endpoint.connect(blob_ticket.addr().clone(), BLOBS_ALPN).await?;
        let mut progress_send = connection.open_uni().await?;

        let (transfer_outcome, mut tracker) = do_transfer(
            &session_id,
            &plan,
            store.remote().fetch(blob_conn, blob_ticket.clone()).stream(),
            &mut progress_send,
            &mut control_recv,
            &mut cancel_rx,
            &event_tx,
        ).await?;

        if let TransferOutcome::Cancelled(c) = &transfer_outcome {
            let _ = send_receiver_cancel(&mut control_send, &session_id, c.by, c.phase, c.reason.clone()).await;
            return Ok::<_, anyhow::Error>(transfer_outcome);
        }

        // --- Phase 5: Export & Acknowledgement ---
        info!(%session_id, "exporting files to {}", request.out_dir.display());
        tracker.mark_finalizing(std::time::Instant::now());
        let finalizing_snapshot = tracker.snapshot(std::time::Instant::now());
        emit_receiver_event(&event_tx, ReceiverEvent::TransferProgress {
            session_id: session_id.clone(),
            snapshot: finalizing_snapshot.clone(),
        });
        let _ = protocol_wire::write_receiver_message(
            &mut progress_send,
            &protocol_message::ReceiverMessage::TransferProgress(protocol_message::TransferProgress {
                session_id: session_id.clone(),
                snapshot: to_wire_snapshot(&finalizing_snapshot),
            }),
        ).await;
        let final_snapshot = tokio::select! {
            res = export_downloaded_collection(&store, blob_ticket.hash(), &expected_transfer_files) => {
                res?;
                tracker.mark_completed(std::time::Instant::now());
                tracker.snapshot(std::time::Instant::now())
            },
            _ = wait_for_cancel(&mut cancel_rx) => return abort_session(&mut control_send, &session_id, protocol_message::CancelPhase::Transferring).await,
        };

        let _ = protocol_wire::write_receiver_message(
            &mut progress_send,
            &protocol_message::ReceiverMessage::TransferCompleted(protocol_message::TransferCompleted {
                session_id: session_id.clone(),
                snapshot: to_wire_snapshot(&final_snapshot),
            }),
        ).await;
        let _ = send_transfer_result(&mut control_send, &session_id, protocol_message::TransferStatus::Ok).await;

        // Final wait for Sender to acknowledge our result
        match protocol_wire::read_sender_message(&mut control_recv).await? {
            protocol_message::SenderMessage::TransferAck(_) => {
                let _ = control_send.finish();
                emit_receiver_event(&event_tx, ReceiverEvent::TransferCompleted {
                    session_id: session_id.clone(),
                    snapshot: final_snapshot,
                });
                emit_receiver_event(&event_tx, ReceiverEvent::Completed { session_id: session_id.clone() });
                Ok(TransferOutcome::Completed)
            },
            _ => bail!("missing final transfer ack from sender"),
        }
    }.await;

    if let Err(error) = &outcome {
        emit_receiver_event(
            &event_tx,
            ReceiverEvent::Failed {
                session_id: session_id.clone(),
                message: format!("{error:#}"),
            },
        );
    }
    let _ = store.shutdown().await;
    outcome
}

enum HandshakeResult {
    Ok(
        iroh::endpoint::SendStream,
        iroh::endpoint::RecvStream,
        protocol_message::Hello,
        protocol_message::Offer,
    ),
    Cancelled(TransferOutcome),
}

async fn do_handshake(
    endpoint: &Endpoint,
    request: &ReceiverRequest,
    conn: &Connection,
    cancel_rx: &mut watch::Receiver<bool>,
) -> Result<HandshakeResult> {
    tokio::select! {
        res = async {
            let (mut send, mut recv) = tokio::time::timeout(Duration::from_secs(30), conn.accept_bi())
                .await
                .context("handshake stream timeout")?
                .context("accepting bi-stream")?;
            let hello = match protocol_wire::read_sender_message(&mut recv).await? {
                protocol_message::SenderMessage::Hello(h) => h,
                protocol_message::SenderMessage::Cancel(c) => return Ok(HandshakeResult::Cancelled(TransferOutcome::from_remote_cancel(c, "")?)),
                _ => bail!("expected hello from sender"),
            };
            protocol_wire::write_receiver_message(&mut send, &protocol_message::ReceiverMessage::Hello(protocol_message::Hello {
                version: protocol_message::PROTOCOL_VERSION,
                session_id: hello.session_id.clone(),
                identity: protocol_message::Identity {
                    role: protocol_message::TransferRole::Receiver,
                    endpoint_id: endpoint.addr().id,
                    device_name: request.device_name.clone(),
                    device_type: to_protocol_device_type(request.device_type),
                }
            })).await?;
            let offer = match protocol_wire::read_sender_message(&mut recv).await? {
                protocol_message::SenderMessage::Offer(o) => o,
                protocol_message::SenderMessage::Cancel(c) => return Ok(HandshakeResult::Cancelled(TransferOutcome::from_remote_cancel(c, &hello.session_id)?)),
                _ => bail!("expected offer from sender"),
            };
            Ok(HandshakeResult::Ok(send, recv, hello, offer))
        } => res,
        _ = wait_for_cancel(cancel_rx) => Ok(HandshakeResult::Cancelled(TransferOutcome::local_cancel(protocol_message::TransferRole::Receiver, protocol_message::CancelPhase::WaitingForDecision))),
        _ = tokio::time::sleep(Duration::from_secs(30)) => bail!("handshake timed out"),
        _ = conn.closed() => bail!("connection closed during handshake"),
    }
}

async fn do_transfer(
    session_id: &str,
    plan: &TransferPlan,
    mut stream: impl futures_lite::Stream<Item = GetProgressItem> + Unpin,
    progress_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    cancel_rx: &mut watch::Receiver<bool>,
    event_tx: &Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
) -> Result<(TransferOutcome, ProgressTracker)> {
    let mut tracker = ProgressTracker::new(plan.clone());
    tracker.set_phase(TransferPhase::Transferring, std::time::Instant::now());
    emit_receiver_event(
        event_tx,
        ReceiverEvent::TransferStarted {
            session_id: session_id.to_owned(),
            plan: plan.clone(),
        },
    );

    loop {
        tokio::select! {
            item = stream.next() => match item {
                Some(GetProgressItem::Progress(offset)) => {
                    let now = std::time::Instant::now();
                    tracker.set_bytes_transferred(offset, now);
                    let snapshot = tracker.snapshot(now);
                    emit_receiver_event(event_tx, ReceiverEvent::TransferProgress {
                        session_id: session_id.to_owned(),
                        snapshot: snapshot.clone(),
                    });
                    let _ = protocol_wire::write_receiver_message(
                        progress_send,
                        &protocol_message::ReceiverMessage::TransferProgress(protocol_message::TransferProgress {
                            session_id: session_id.to_owned(),
                            snapshot: to_wire_snapshot(&snapshot),
                        }),
                    ).await;
                }
                Some(GetProgressItem::Done(_)) | None => {
                    return Ok((TransferOutcome::Completed, tracker));
                },
                Some(GetProgressItem::Error(e)) => bail!("blob fetch error: {e}"),
            },
            msg = protocol_wire::read_sender_message(control_recv) => match msg? {
                protocol_message::SenderMessage::Cancel(c) => {
                    return TransferOutcome::from_remote_cancel(c, session_id)
                        .map(|outcome| (outcome, tracker));
                }
                _ => bail!("unexpected control message during transfer"),
            },
            _ = wait_for_cancel(cancel_rx) => {
                return Ok((
                    TransferOutcome::local_cancel(
                        protocol_message::TransferRole::Receiver,
                        protocol_message::CancelPhase::Transferring,
                    ),
                    tracker,
                ))
            },
        }
    }
}

async fn abort_session(
    send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    phase: protocol_message::CancelPhase,
) -> Result<TransferOutcome> {
    let outcome = TransferOutcome::local_cancel(protocol_message::TransferRole::Receiver, phase);
    if let TransferOutcome::Cancelled(c) = &outcome {
        let _ = send_receiver_cancel(send, session_id, c.by, c.phase, c.reason.clone()).await;
        let _ = send.finish();
        let _ = tokio::time::timeout(Duration::from_secs(2), send.stopped()).await;
    }
    Ok(outcome)
}

pub async fn export_downloaded_collection(
    store: &FsStore,
    root_hash: iroh_blobs::Hash,
    expected_files: &[ExpectedTransferFile],
) -> Result<()> {
    let collection = Collection::load(root_hash, store.as_ref()).await?;
    let hashes: BTreeMap<_, _> = collection.into_iter().collect();
    for exp in expected_files {
        let hash = *hashes
            .get(&exp.path)
            .ok_or_else(|| anyhow!("missing file in collection: {}", exp.path))?;
        if let Some(p) = exp.destination.parent() {
            fs::create_dir_all(p).await?;
        }
        store
            .export_with_opts(ExportOptions {
                hash,
                target: exp.destination.clone(),
                mode: ExportMode::Copy,
            })
            .finish()
            .await?;
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
    manifest
        .files
        .iter()
        .map(|f| {
            expected_files
                .remove(&f.path)
                .ok_or_else(|| anyhow!("missing expected file for {}", f.path))
        })
        .collect()
}

fn to_protocol_device_type(dt: crate::protocol::DeviceType) -> protocol_message::DeviceType {
    match dt {
        crate::protocol::DeviceType::Phone => protocol_message::DeviceType::Phone,
        crate::protocol::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
    }
}

fn to_local_device_type(dt: protocol_message::DeviceType) -> crate::protocol::DeviceType {
    match dt {
        protocol_message::DeviceType::Phone => crate::protocol::DeviceType::Phone,
        protocol_message::DeviceType::Laptop => crate::protocol::DeviceType::Laptop,
    }
}

fn to_offer_manifest(offer: &protocol_message::Offer) -> OfferManifest {
    OfferManifest {
        files: offer
            .manifest
            .items
            .iter()
            .map(|item| match item {
                protocol_message::ManifestItem::File { path, size } => {
                    crate::rendezvous::OfferFile {
                        path: path.clone(),
                        size: *size,
                    }
                }
            })
            .collect(),
        file_count: offer.manifest.count() as u64,
        total_size: offer.manifest.total_size(),
    }
}

fn to_wire_snapshot(snapshot: &TransferSnapshot) -> protocol_message::TransferProgressPayload {
    protocol_message::TransferProgressPayload {
        phase: snapshot.phase,
        completed_files: snapshot.completed_files,
        total_files: snapshot.total_files,
        bytes_transferred: snapshot.bytes_transferred,
        total_bytes: snapshot.total_bytes,
        active_file_id: snapshot.active_file_id,
        active_file_bytes: snapshot.active_file_bytes,
    }
}

fn emit_receiver_event(
    tx: &Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    event: ReceiverEvent,
) {
    if let Some(tx) = tx {
        let _ = tx.send(Ok(event));
    }
}

async fn send_receiver_cancel(
    send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    by: protocol_message::TransferRole,
    phase: protocol_message::CancelPhase,
    reason: String,
) -> Result<()> {
    protocol_wire::write_receiver_message(
        send,
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
    send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    status: protocol_message::TransferStatus,
) -> Result<()> {
    protocol_wire::write_receiver_message(
        send,
        &protocol_message::ReceiverMessage::TransferResult(protocol_message::TransferResult {
            session_id: session_id.to_owned(),
            status,
        }),
    )
    .await
}

async fn send_receiver_decline(
    send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    reason: String,
) -> Result<()> {
    protocol_wire::write_receiver_message(
        send,
        &protocol_message::ReceiverMessage::Decline(protocol_message::Decline {
            session_id: session_id.to_owned(),
            reason,
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
