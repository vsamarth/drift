#![allow(dead_code)]

use iroh::{Endpoint, EndpointAddr, EndpointId, endpoint::Connection};
use rand::random;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::Duration;
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::{info, instrument};

use crate::{
    blobs::send::{BlobService, PreparedStore},
    protocol::message::MessageKind,
    protocol::wire as protocol_wire,
    protocol::{ALPN, ProtocolError},
    protocol::{message as protocol_message, send as protocol_sender},
};

use super::error::{Result as TransferResult, TransferError};
use super::path::ScratchDir;
use super::types::{TransferOutcome, TransferPlan, TransferSnapshot, wait_for_cancel};

type Result<T> = TransferResult<T>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendRequest {
    pub peer_endpoint_addr: EndpointAddr,
    pub peer_endpoint_id: EndpointId,
    pub files: Vec<std::path::PathBuf>,
}

#[derive(Debug)]
pub enum SenderEvent {
    Connecting {
        session_id: String,
        peer_endpoint_id: EndpointId,
    },
    WaitingForDecision {
        session_id: String,
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
    },
    Accepted {
        session_id: String,
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
    },
    Declined {
        session_id: String,
        reason: String,
    },
    Failed {
        session_id: String,
        error: TransferError,
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
}

pub type SenderEventStream = UnboundedReceiverStream<SenderEvent>;

#[derive(Debug)]
pub struct SenderRun {
    pub events: SenderEventStream,
    pub cancel_tx: watch::Sender<bool>,
    pub outcome_rx: oneshot::Receiver<TransferResult<TransferOutcome>>,
}

impl SenderRun {
    pub fn into_parts(
        self,
    ) -> (
        SenderEventStream,
        watch::Sender<bool>,
        oneshot::Receiver<TransferResult<TransferOutcome>>,
    ) {
        (self.events, self.cancel_tx, self.outcome_rx)
    }
}

#[derive(Debug, Clone)]
struct SenderEventSink {
    session_id: String,
    tx: Option<mpsc::UnboundedSender<SenderEvent>>,
}

impl SenderEventSink {
    fn new(session_id: String, tx: Option<mpsc::UnboundedSender<SenderEvent>>) -> Self {
        Self { session_id, tx }
    }
    fn emit(&self, e: SenderEvent) {
        if let Some(tx) = &self.tx {
            let _ = tx.send(e);
        }
    }
    fn fail(&self, error: TransferError) {
        self.emit(SenderEvent::Failed {
            session_id: self.session_id.clone(),
            error,
        });
    }
}

pub struct Sender {
    endpoint: Endpoint,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
}

impl Sender {
    pub fn new(
        endpoint: Endpoint,
        identity: protocol_message::Identity,
        request: SendRequest,
    ) -> Self {
        Self {
            endpoint,
            identity,
            session_id: format!("{:016x}", random::<u64>()),
            request,
        }
    }

    pub fn run_with_events(self) -> SenderRun
    where
        Self: Send + 'static,
    {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (outcome_tx, outcome_rx) = oneshot::channel();
        let (cancel_tx, cancel_rx) = watch::channel(false);
        let events = SenderEventSink::new(self.session_id.clone(), Some(event_tx));

        let Sender {
            endpoint,
            session_id,
            identity,
            request,
        } = self;

        tokio::spawn(async move {
            let session = SenderSession {
                endpoint,
                session_id,
                identity,
                request,
                events: events.clone(),
            };
            let outcome = session.run(cancel_rx).await;
            let _ = outcome_tx.send(outcome);
        });

        SenderRun {
            events: UnboundedReceiverStream::new(event_rx),
            cancel_tx,
            outcome_rx,
        }
    }
}

struct SenderSession {
    endpoint: Endpoint,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
    events: SenderEventSink,
}

impl SenderSession {
    #[instrument(skip_all, fields(session_id = %self.session_id, peer = %self.request.peer_endpoint_id))]
    async fn run(self, mut cancel_rx: watch::Receiver<bool>) -> Result<TransferOutcome> {
        let scratch = ScratchDir::new("drift-send", &self.session_id).await?;
        let prepared = PreparedStore::prepare(&scratch.path, self.request.files.clone()).await?;

        info!(
            session_id = %self.session_id,
            collection_hash = %prepared.collection_hash(),
            file_count = prepared.manifest().count(),
            total_size = prepared.manifest().total_size(),
            "prepared manifest"
        );

        self.events.emit(SenderEvent::Connecting {
            session_id: self.session_id.clone(),
            peer_endpoint_id: self.request.peer_endpoint_id,
        });
        let connection = self
            .endpoint
            .connect(self.request.peer_endpoint_addr.clone(), ALPN)
            .await
            .map_err(|source| TransferError::other("connecting to peer", source))?;

        // --- Handshake ---
        let handshake_res = do_handshake(
            &self.session_id,
            &self.identity,
            &prepared,
            &connection,
            &mut cancel_rx,
            &self.events,
        )
        .await?;
        let (mut control_send, mut control_recv, outcome) = match handshake_res {
            HandshakeResult::Ok(s, r, o) => (s, r, o),
            HandshakeResult::Cancelled(outcome) => return Ok(outcome),
        };

        match outcome {
            protocol_sender::SenderControlOutcome::Accepted(peer) => {
                self.events.emit(SenderEvent::Accepted {
                    session_id: self.session_id.clone(),
                    receiver_device_name: peer.identity.device_name.clone(),
                    receiver_endpoint_id: peer.identity.endpoint_id,
                });
            }
            protocol_sender::SenderControlOutcome::Declined(declined) => {
                self.events.emit(SenderEvent::Declined {
                    session_id: self.session_id.clone(),
                    reason: declined.reason,
                });
                return Ok(TransferOutcome::Declined {
                    reason: "receiver declined".to_owned(),
                });
            }
        }

        // --- Data Transfer ---
        let blob_service = BlobService::new(self.endpoint.clone());
        let registration = blob_service.register(prepared).await.map_err(|source| {
            TransferError::other("registering files with blob service", source)
        })?;

        protocol_wire::write_sender_message(
            &mut control_send,
            &protocol_message::SenderMessage::BlobTicket(protocol_message::BlobTicketMessage {
                session_id: self.session_id.clone(),
                ticket: registration.ticket().to_string(),
            }),
        )
        .await?;

        let mut progress_recv = connection
            .accept_uni()
            .await
            .map_err(|source| TransferError::other("accepting progress stream", source))?;

        let outcome = tokio::select! {
            res = do_transfer(&self.session_id, &mut progress_recv, &mut control_recv, &self.events) => res?,
            _ = wait_for_cancel(&mut cancel_rx) => {
                let _ = protocol_wire::write_sender_message(
                    &mut control_send,
                    &protocol_message::SenderMessage::Cancel(protocol_message::Cancel {
                        session_id: self.session_id.clone(),
                        by: protocol_message::TransferRole::Sender,
                        phase: protocol_message::CancelPhase::Transferring,
                        reason: "cancelled by user".to_owned(),
                    }),
                ).await;
                TransferOutcome::local_cancel(protocol_message::TransferRole::Sender, protocol_message::CancelPhase::Transferring)
            }
        };

        // --- Final Acknowledgement ---
        if matches!(outcome, TransferOutcome::Completed) {
            let _ = protocol_wire::write_sender_message(
                &mut control_send,
                &protocol_message::SenderMessage::TransferAck(protocol_message::TransferAck {
                    session_id: self.session_id.clone(),
                }),
            )
            .await;
            finish_control_stream(&mut control_send).await;
        }

        let _ = registration.shutdown().await;
        Ok(outcome)
    }
}

async fn finish_control_stream(send: &mut iroh::endpoint::SendStream) {
    let _ = send.finish();
    let _ = tokio::time::timeout(Duration::from_secs(2), send.stopped()).await;
}

enum HandshakeResult {
    Ok(
        iroh::endpoint::SendStream,
        iroh::endpoint::RecvStream,
        protocol_sender::SenderControlOutcome,
    ),
    Cancelled(TransferOutcome),
}

async fn do_handshake(
    session_id: &str,
    identity: &protocol_message::Identity,
    prepared: &PreparedStore,
    connection: &Connection,
    cancel_rx: &mut watch::Receiver<bool>,
    _events: &SenderEventSink,
) -> Result<HandshakeResult> {
    tokio::select! {
        res = async {
            let (mut send, mut recv) = connection
                .open_bi()
                .await
                .map_err(|source| TransferError::other("opening bi-stream", source))?;

            let mut handler = protocol_sender::Sender::new(
                session_id.to_owned(),
                identity.clone(),
            );

            let outcome = handler
                .run_control(
                    &mut send,
                    &mut recv,
                    prepared.manifest(),
                    prepared.collection_hash(),
                )
                .await?;

            Ok(HandshakeResult::Ok(send, recv, outcome))
        } => res,
        _ = wait_for_cancel(cancel_rx) => {
            Ok(HandshakeResult::Cancelled(TransferOutcome::local_cancel(
                protocol_message::TransferRole::Sender,
                protocol_message::CancelPhase::WaitingForDecision,
            )))
        }
        _ = tokio::time::sleep(Duration::from_secs(30)) => Err(TransferError::timeout("handshake")),
    }
}

async fn do_transfer(
    session_id: &str,
    progress_recv: &mut iroh::endpoint::RecvStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    events: &SenderEventSink,
) -> Result<TransferOutcome> {
    let mut progress_active = true;
    loop {
        tokio::select! {
            msg = protocol_wire::read_receiver_message(progress_recv), if progress_active => {
                match msg {
                    Ok(protocol_message::ReceiverMessage::TransferProgress(p)) => {
                        events.emit(SenderEvent::TransferProgress {
                            session_id: session_id.to_owned(),
                            snapshot: from_wire_snapshot(p.snapshot, session_id),
                        });
                    }
                    Ok(protocol_message::ReceiverMessage::TransferCompleted(c)) => {
                        let snapshot = from_wire_snapshot(c.snapshot, session_id);
                        events.emit(SenderEvent::TransferCompleted {
                            session_id: session_id.to_owned(),
                            snapshot,
                        });
                    }
                    Ok(other) => return Err(ProtocolError::unexpected_message_kind("receiver progress", MessageKind::TransferProgress, other.kind()).into()),
                    Err(_) => {
                        progress_active = false;
                    }
                }
            }
            msg = protocol_wire::read_receiver_message(control_recv) => {
                match msg? {
                    protocol_message::ReceiverMessage::TransferResult(r) => {
                        match r.status {
                            protocol_message::TransferStatus::Ok => return Ok(TransferOutcome::Completed),
                            protocol_message::TransferStatus::Error { code, message } => {
                                return Err(TransferError::other("transfer error from receiver", std::io::Error::other(format!("{code:?}: {message}"))));
                            }
                        }
                    }
                    protocol_message::ReceiverMessage::Cancel(c) => {
                        return Ok(TransferOutcome::from_remote_cancel(c, session_id)?);
                    }
                    other => return Err(ProtocolError::unexpected_message_kind("receiver control", MessageKind::TransferResult, other.kind()).into()),
                }
            }
        }
    }
}

fn from_wire_snapshot(
    snapshot: protocol_message::TransferProgressPayload,
    session_id: &str,
) -> TransferSnapshot {
    TransferSnapshot {
        session_id: session_id.to_owned(),
        phase: snapshot.phase,
        total_files: snapshot.total_files,
        completed_files: snapshot.completed_files,
        total_bytes: snapshot.total_bytes,
        bytes_transferred: snapshot.bytes_transferred,
        active_file_id: snapshot.active_file_id,
        active_file_bytes: snapshot.active_file_bytes,
        bytes_per_sec: None,
        eta_seconds: None,
    }
}
