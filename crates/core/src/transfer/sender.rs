#![allow(dead_code)]

use iroh::{Endpoint, EndpointAddr, EndpointId, endpoint::Connection};
use rand::random;
use tokio::io::{AsyncRead, AsyncWrite};
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
        prepared_plan: TransferPlan,
    },
    WaitingForDecision {
        session_id: String,
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
        prepared_plan: TransferPlan,
    },
    Accepted {
        session_id: String,
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
        prepared_plan: TransferPlan,
    },
    Declined {
        session_id: String,
        reason: String,
        prepared_plan: TransferPlan,
    },
    Failed {
        session_id: String,
        error: TransferError,
        prepared_plan: TransferPlan,
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
            prepared_plan: TransferPlan {
                session_id: self.session_id.clone(),
                total_files: 0,
                total_bytes: 0,
                files: Vec::new(),
            },
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
        let prepared_plan = build_prepared_plan(&self.session_id, &prepared)?;
        let manifest = prepared.manifest();
        let collection_hash = prepared.collection_hash();

        info!(
            session_id = %self.session_id,
            collection_hash = %collection_hash,
            file_count = manifest.count(),
            total_size = manifest.total_size(),
            "prepared manifest"
        );

        self.events.emit(SenderEvent::Connecting {
            session_id: self.session_id.clone(),
            peer_endpoint_id: self.request.peer_endpoint_id,
            prepared_plan: prepared_plan.clone(),
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
            manifest,
            collection_hash,
            &connection,
            &mut cancel_rx,
            &self.events,
            prepared_plan.clone(),
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
                    prepared_plan: prepared_plan.clone(),
                });
            }
            protocol_sender::SenderControlOutcome::Declined(declined) => {
                self.events.emit(SenderEvent::Declined {
                    session_id: self.session_id.clone(),
                    reason: declined.reason,
                    prepared_plan: prepared_plan.clone(),
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
            res = do_transfer(&self.session_id, &prepared_plan, &mut progress_recv, &mut control_recv, &self.events) => res?,
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
    manifest: protocol_message::TransferManifest,
    collection_hash: iroh_blobs::Hash,
    connection: &Connection,
    cancel_rx: &mut watch::Receiver<bool>,
    events: &SenderEventSink,
    prepared_plan: TransferPlan,
) -> Result<HandshakeResult> {
    tokio::select! {
        res = async {
            let (mut send, mut recv) = connection
                .open_bi()
                .await
                .map_err(|source| TransferError::other("opening bi-stream", source))?;

            let outcome = run_handshake_on_streams(
                session_id,
                identity,
                manifest,
                collection_hash,
                &mut send,
                &mut recv,
                events,
                prepared_plan,
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

async fn run_handshake_on_streams<R, W>(
    session_id: &str,
    identity: &protocol_message::Identity,
    manifest: protocol_message::TransferManifest,
    collection_hash: iroh_blobs::Hash,
    send: &mut W,
    recv: &mut R,
    events: &SenderEventSink,
    prepared_plan: TransferPlan,
) -> Result<protocol_sender::SenderControlOutcome>
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut handler = protocol_sender::Sender::new(session_id.to_owned(), identity.clone());
    handler.send_hello(send).await?;
    let peer_hello = handler.read_peer_hello(recv).await?;
    handler.send_offer(send, manifest, collection_hash).await?;
    events.emit(SenderEvent::WaitingForDecision {
        session_id: session_id.to_owned(),
        receiver_device_name: peer_hello.identity.device_name,
        receiver_endpoint_id: peer_hello.identity.endpoint_id,
        prepared_plan,
    });
    Ok(handler.await_decision(recv).await?)
}

async fn do_transfer<R, C>(
    session_id: &str,
    plan: &TransferPlan,
    progress_recv: &mut R,
    control_recv: &mut C,
    events: &SenderEventSink,
) -> Result<TransferOutcome>
where
    R: AsyncRead + Unpin,
    C: AsyncRead + Unpin,
{
    events.emit(SenderEvent::TransferStarted {
        session_id: session_id.to_owned(),
        plan: plan.clone(),
    });

    let mut progress_active = true;
    let mut control_done = false;
    loop {
        if control_done && !progress_active {
            return Ok(TransferOutcome::Completed);
        }

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
            msg = protocol_wire::read_receiver_message(control_recv), if !control_done => {
                match msg? {
                    protocol_message::ReceiverMessage::TransferResult(r) => {
                        match r.status {
                            protocol_message::TransferStatus::Ok => {
                                control_done = true;
                            },
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

fn build_prepared_plan(
    session_id: &str,
    prepared: &crate::blobs::send::PreparedStore,
) -> Result<TransferPlan> {
    Ok(TransferPlan::from_manifest(
        session_id.to_owned(),
        &prepared.manifest(),
    )?)
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::message::{
        Accept, DeviceType, Hello, Identity, ManifestItem, PROTOCOL_VERSION, ReceiverMessage,
        SenderMessage, TransferCompleted, TransferManifest, TransferProgress,
        TransferProgressPayload, TransferResult as TransferResultMessage, TransferRole,
        TransferStatus,
    };
    use crate::protocol::wire::{read_sender_message, write_receiver_message};
    use crate::transfer::TransferPhase;
    use iroh::SecretKey;
    use tokio::io::{AsyncWriteExt, duplex};
    use tokio::sync::mpsc;
    use tokio::time::{Duration, sleep};

    type TestResult<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

    #[tokio::test]
    async fn handshake_emits_waiting_for_decision_after_offer() -> TestResult<()> {
        let (sender_io, receiver_io) = duplex(4096);
        let (mut sender_read, mut sender_write) = tokio::io::split(sender_io);
        let (mut receiver_read, mut receiver_write) = tokio::io::split(receiver_io);
        let expected_receiver_endpoint_id = SecretKey::from_bytes(&[2; 32]).public();

        let receiver_task = tokio::spawn(async move {
            let hello = match read_sender_message(&mut receiver_read).await? {
                SenderMessage::Hello(hello) => hello,
                other => panic!("expected sender hello, got {:?}", other.kind()),
            };
            write_receiver_message(
                &mut receiver_write,
                &ReceiverMessage::Hello(Hello {
                    version: PROTOCOL_VERSION,
                    session_id: hello.session_id.clone(),
                    identity: Identity {
                        role: TransferRole::Receiver,
                        endpoint_id: expected_receiver_endpoint_id,
                        device_name: "receiver".to_owned(),
                        device_type: DeviceType::Laptop,
                    },
                }),
            )
            .await?;

            match read_sender_message(&mut receiver_read).await? {
                SenderMessage::Offer(_) => {}
                other => panic!("expected sender offer, got {:?}", other.kind()),
            }
            write_receiver_message(
                &mut receiver_write,
                &ReceiverMessage::Accept(Accept {
                    session_id: hello.session_id.clone(),
                }),
            )
            .await?;
            TestResult::Ok(())
        });

        let events = event_sink("session-1");
        let test_manifest = manifest();
        let plan = TransferPlan::from_manifest("session-1".to_owned(), &test_manifest)?;
        let outcome = run_handshake_on_streams(
            "session-1",
            &sender_identity(),
            test_manifest,
            [3u8; 32].into(),
            &mut sender_write,
            &mut sender_read,
            &events.sink,
            plan.clone(),
        )
        .await?;

        assert!(matches!(
            outcome,
            protocol_sender::SenderControlOutcome::Accepted(_)
        ));
        receiver_task.await??;

        let observed = events.collect();
        assert!(matches!(
            observed.as_slice(),
            [SenderEvent::WaitingForDecision {
                session_id,
                receiver_device_name,
                receiver_endpoint_id: endpoint_id,
                prepared_plan,
            }] if session_id == "session-1"
                && receiver_device_name == "receiver"
                && *endpoint_id == expected_receiver_endpoint_id
                && prepared_plan == &plan
        ));

        Ok(())
    }

    #[tokio::test]
    async fn transfer_started_event_precedes_progress_and_carries_plan() -> TestResult<()> {
        let (mut progress_write, mut progress_read) = duplex(4096);
        let (mut control_write, mut control_read) = duplex(4096);
        let plan = TransferPlan::from_manifest("session-1", &manifest())?;

        let receiver_task = tokio::spawn(async move {
            write_receiver_message(
                &mut progress_write,
                &ReceiverMessage::TransferProgress(TransferProgress {
                    session_id: "session-1".to_owned(),
                    snapshot: TransferProgressPayload {
                        phase: TransferPhase::Transferring,
                        completed_files: 1,
                        total_files: 2,
                        bytes_transferred: 5,
                        total_bytes: 11,
                        active_file_id: Some(1),
                        active_file_bytes: Some(0),
                    },
                }),
            )
            .await?;
            write_receiver_message(
                &mut progress_write,
                &ReceiverMessage::TransferCompleted(TransferCompleted {
                    session_id: "session-1".to_owned(),
                    snapshot: TransferProgressPayload {
                        phase: TransferPhase::Completed,
                        completed_files: 2,
                        total_files: 2,
                        bytes_transferred: 11,
                        total_bytes: 11,
                        active_file_id: None,
                        active_file_bytes: None,
                    },
                }),
            )
            .await?;
            progress_write.shutdown().await?;
            sleep(Duration::from_millis(10)).await;

            write_receiver_message(
                &mut control_write,
                &ReceiverMessage::TransferResult(TransferResultMessage {
                    session_id: "session-1".to_owned(),
                    status: TransferStatus::Ok,
                }),
            )
            .await?;
            TestResult::Ok(())
        });

        let events = event_sink("session-1");
        let outcome = do_transfer(
            "session-1",
            &plan,
            &mut progress_read,
            &mut control_read,
            &events.sink,
        )
        .await?;

        assert!(matches!(outcome, TransferOutcome::Completed));
        receiver_task.await??;

        let observed = events.collect();
        assert!(matches!(
            observed.as_slice(),
            [
                SenderEvent::TransferStarted { plan: started_plan, .. },
                SenderEvent::TransferProgress { .. },
                SenderEvent::TransferCompleted { .. },
            ] if started_plan == &plan
        ));
        Ok(())
    }

    struct EventHarness {
        sink: SenderEventSink,
        rx: mpsc::UnboundedReceiver<SenderEvent>,
    }

    impl EventHarness {
        fn collect(mut self) -> Vec<SenderEvent> {
            drop(self.sink);
            let mut observed = Vec::new();
            while let Ok(event) = self.rx.try_recv() {
                observed.push(event);
            }
            observed
        }
    }

    fn event_sink(session_id: &str) -> EventHarness {
        let (tx, rx) = mpsc::unbounded_channel();
        EventHarness {
            sink: SenderEventSink::new(session_id.to_owned(), Some(tx)),
            rx,
        }
    }

    fn sender_identity() -> Identity {
        Identity {
            role: TransferRole::Sender,
            endpoint_id: SecretKey::from_bytes(&[1; 32]).public(),
            device_name: "sender".to_owned(),
            device_type: DeviceType::Laptop,
        }
    }

    fn manifest() -> TransferManifest {
        TransferManifest {
            items: vec![
                ManifestItem::File {
                    path: "album/a.txt".to_owned(),
                    size: 5,
                },
                ManifestItem::File {
                    path: "album/b.txt".to_owned(),
                    size: 6,
                },
            ],
        }
    }
}
