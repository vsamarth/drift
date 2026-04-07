#![allow(dead_code)]

use anyhow::{Context, Result, anyhow, bail};
use iroh::{EndpointAddr, EndpointId, endpoint::Connection};
use rand::random;
use tokio::time::Duration;
use tokio::{
    sync::{mpsc, oneshot, watch},
    task::JoinHandle,
};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::{instrument, warn};

use crate::{
    blobs::send::{BlobRegistration, BlobService, PreparedStore},
    protocol::ALPN,
    protocol::wire as protocol_wire,
    protocol::{message as protocol_message, send as protocol_sender},
};

use super::path::ScratchDir;
use super::types::{TransferOutcome, wait_for_cancel};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendRequest {
    pub peer_endpoint_id: EndpointId,
    pub files: Vec<std::path::PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
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
        message: String,
    },
    TransferStarted {
        session_id: String,
        file_count: u64,
        total_bytes: u64,
    },
    TransferProgress {
        session_id: String,
        bytes_sent: u64,
        total_bytes: u64,
    },
    TransferCompleted {
        session_id: String,
    },
}

pub type SenderEventStream = UnboundedReceiverStream<Result<SenderEvent>>;

#[derive(Debug)]
pub struct SenderRun {
    pub events: SenderEventStream,
    pub cancel_tx: watch::Sender<bool>,
    outcome_rx: oneshot::Receiver<Result<TransferOutcome>>,
}

impl SenderRun {
    pub fn into_parts(
        self,
    ) -> (
        SenderEventStream,
        watch::Sender<bool>,
        oneshot::Receiver<Result<TransferOutcome>>,
    ) {
        (self.events, self.cancel_tx, self.outcome_rx)
    }
    pub async fn outcome(self) -> Result<TransferOutcome> {
        self.outcome_rx.await.context("waiting for outcome")?
    }
}

#[derive(Clone, Debug)]
struct SenderEventSink {
    session_id: String,
    tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
}
impl SenderEventSink {
    fn new(session_id: String, tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>) -> Self {
        Self { session_id, tx }
    }
    fn silent(session_id: String) -> Self {
        Self {
            session_id,
            tx: None,
        }
    }
    fn emit(&self, e: SenderEvent) {
        if let Some(tx) = &self.tx {
            let _ = tx.send(Ok(e));
        }
    }
    fn fail(&self, err: &anyhow::Error) {
        self.emit(SenderEvent::Failed {
            session_id: self.session_id.clone(),
            message: format!("{err:#}"),
        });
        if let Some(tx) = &self.tx {
            let _ = tx.send(Err(anyhow!("{err:#}")));
        }
    }
}

pub struct Sender {
    secret_key: iroh::SecretKey,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
}

impl Sender {
    pub fn new(
        device_name: String,
        device_type: crate::protocol::DeviceType,
        request: SendRequest,
    ) -> Self {
        let secret_key = iroh::SecretKey::from_bytes(&random());
        Self {
            identity: protocol_message::Identity {
                role: protocol_message::TransferRole::Sender,
                endpoint_id: secret_key.public(),
                device_name,
                device_type: match device_type {
                    crate::protocol::DeviceType::Phone => protocol_message::DeviceType::Phone,
                    crate::protocol::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
                },
            },
            secret_key,
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

        tokio::spawn(async move {
            let session = SenderSession {
                secret_key: self.secret_key,
                session_id: self.session_id,
                identity: self.identity,
                request: self.request,
                events: events.clone(),
            };
            let outcome = session.run(cancel_rx).await;
            if let Err(e) = &outcome {
                events.fail(e);
            }
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
    secret_key: iroh::SecretKey,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
    events: SenderEventSink,
}

impl SenderSession {
    #[instrument(skip_all, fields(session_id = %self.session_id, peer = %self.request.peer_endpoint_id))]
    async fn run(self, mut cancel_rx: watch::Receiver<bool>) -> Result<TransferOutcome> {
        let scratch = ScratchDir::new("drift-send", &self.session_id).await?;
        let prepared = PreparedStore::prepare(
            self.session_id.clone(),
            &scratch.path,
            self.request.files.clone(),
        )
        .await?;
        let endpoint = iroh::Endpoint::builder(iroh::endpoint::presets::N0)
            .alpns(vec![ALPN.to_vec()])
            .secret_key(self.secret_key.clone())
            .bind()
            .await?;

        self.events.emit(SenderEvent::Connecting {
            session_id: self.session_id.clone(),
            peer_endpoint_id: self.request.peer_endpoint_id,
        });
        let connection = endpoint
            .connect(EndpointAddr::new(self.request.peer_endpoint_id), ALPN)
            .await?;

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
                do_transfer(
                    &self.session_id,
                    endpoint,
                    connection,
                    &mut control_send,
                    &mut control_recv,
                    prepared,
                    &mut cancel_rx,
                    &self.events,
                )
                .await
            }
            protocol_sender::SenderControlOutcome::Declined(msg) => {
                self.events.emit(SenderEvent::Declined {
                    session_id: self.session_id.clone(),
                    reason: msg.reason.clone(),
                });
                let _ = control_send.finish();
                Ok(TransferOutcome::Declined { reason: msg.reason })
            }
        }
    }
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
    conn: &Connection,
    cancel_rx: &mut watch::Receiver<bool>,
    events: &SenderEventSink,
) -> Result<HandshakeResult> {
    tokio::select! {
        res = async {
            let (mut send, mut recv) = conn.open_bi().await.context("opening bi-stream")?;
            protocol_wire::write_sender_message(&mut send, &protocol_message::SenderMessage::Hello(protocol_message::Hello {
                version: protocol_message::PROTOCOL_VERSION,
                session_id: session_id.to_owned(),
                identity: identity.clone(),
            })).await?;

            let peer_hello = match protocol_wire::read_receiver_message(&mut recv).await? {
                protocol_message::ReceiverMessage::Hello(h) => h,
                protocol_message::ReceiverMessage::Cancel(c) => return Ok(HandshakeResult::Cancelled(TransferOutcome::from_remote_cancel(c, session_id)?)),
                _ => bail!("expected hello from receiver"),
            };

            protocol_wire::write_sender_message(&mut send, &protocol_message::SenderMessage::Offer(protocol_message::Offer {
                session_id: session_id.to_owned(),
                manifest: prepared.manifest(),
            })).await?;

            events.emit(SenderEvent::WaitingForDecision {
                session_id: session_id.to_owned(),
                receiver_device_name: peer_hello.identity.device_name.clone(),
                receiver_endpoint_id: peer_hello.identity.endpoint_id,
            });

            let decision = match protocol_wire::read_receiver_message(&mut recv).await? {
                protocol_message::ReceiverMessage::Accept(a) => protocol_sender::SenderControlOutcome::Accepted(protocol_sender::SenderPeer { session_id: a.session_id, identity: peer_hello.identity }),
                protocol_message::ReceiverMessage::Decline(d) => protocol_sender::SenderControlOutcome::Declined(d),
                protocol_message::ReceiverMessage::Cancel(c) => return Ok(HandshakeResult::Cancelled(TransferOutcome::from_remote_cancel(c, session_id)?)),
                _ => bail!("expected decision from receiver"),
            };
            Ok(HandshakeResult::Ok(send, recv, decision))
        } => res,
        _ = wait_for_cancel(cancel_rx) => {
            // Abort handshake locally
            let (mut send, _) = conn.open_bi().await.context("opening bi-stream for abort")?;
            abort_session(&mut send, session_id, protocol_message::CancelPhase::WaitingForDecision).await.map(HandshakeResult::Cancelled)
        },
        _ = conn.closed() => bail!("connection closed during handshake"),
    }
}

async fn do_transfer(
    session_id: &str,
    endpoint: iroh::Endpoint,
    connection: Connection,
    control_send: &mut iroh::endpoint::SendStream,
    control_recv: &mut iroh::endpoint::RecvStream,
    prepared: PreparedStore,
    cancel_rx: &mut watch::Receiver<bool>,
    events: &SenderEventSink,
) -> Result<TransferOutcome> {
    let manifest = prepared.manifest();
    let (file_count, total_bytes) = (manifest.count() as u64, prepared.total_bytes());
    let registration = BlobService::new(endpoint.clone())
        .register(prepared)
        .await?;
    let progress_task =
        SenderProgressTask::spawn(connection, session_id.to_owned(), events.clone());
    let blob_task = BlobTransferTask::spawn(registration);

    let result = async {
        protocol_wire::write_sender_message(control_send, &protocol_message::SenderMessage::BlobTicket(protocol_message::BlobTicketMessage {
            session_id: session_id.to_owned(),
            ticket: blob_task.ticket().to_owned(),
        })).await?;
        events.emit(SenderEvent::TransferStarted { session_id: session_id.to_owned(), file_count, total_bytes });

        loop {
            tokio::select! {
                _ = wait_for_cancel(cancel_rx) => return abort_session(control_send, session_id, protocol_message::CancelPhase::Transferring).await,
                msg = protocol_wire::read_receiver_message(control_recv) => match msg? {
                    protocol_message::ReceiverMessage::Cancel(c) => return TransferOutcome::from_remote_cancel(c, session_id),
                    protocol_message::ReceiverMessage::TransferResult(r) => {
                        if !matches!(r.status, protocol_message::TransferStatus::Ok) { bail!("receiver reported error: {:?}", r.status); }
                        break;
                    }
                    _ => bail!("unexpected message during transfer"),
                }
            }
        }

        let _ = progress_task.wait().await;
        protocol_wire::write_sender_message(control_send, &protocol_message::SenderMessage::TransferAck(protocol_message::TransferAck { session_id: session_id.to_owned() })).await?;
        events.emit(SenderEvent::TransferCompleted { session_id: session_id.to_owned() });
        let _ = control_send.finish();
        Ok(TransferOutcome::Completed)
    }.await;

    let _ = blob_task.stop().await;
    result
}

async fn abort_session(
    send: &mut iroh::endpoint::SendStream,
    session_id: &str,
    phase: protocol_message::CancelPhase,
) -> Result<TransferOutcome> {
    let outcome = TransferOutcome::local_cancel(protocol_message::TransferRole::Sender, phase);
    if let TransferOutcome::Cancelled(c) = &outcome {
        let _ = protocol_wire::write_sender_message(
            send,
            &protocol_message::SenderMessage::Cancel(protocol_message::Cancel {
                session_id: session_id.to_owned(),
                by: c.by,
                phase: c.phase,
                reason: c.reason.clone(),
            }),
        )
        .await;
        let _ = send.finish();
        let _ = tokio::time::timeout(Duration::from_secs(2), send.stopped()).await;
    }
    Ok(outcome)
}

struct SenderProgressTask {
    shutdown: JoinHandle<Result<()>>,
}
impl SenderProgressTask {
    fn spawn(conn: Connection, session_id: String, events: SenderEventSink) -> Self {
        Self {
            shutdown: tokio::spawn(async move {
                let mut recv = tokio::select! {
                    res = conn.accept_uni() => res?,
                    _ = tokio::time::sleep(Duration::from_secs(30)) => { warn!(%session_id, "receiver never opened progress stream"); return Ok(()); }
                };
                loop {
                    match protocol_wire::read_receiver_message(&mut recv).await? {
                        protocol_message::ReceiverMessage::TransferStarted(m) => {
                            events.emit(SenderEvent::TransferStarted {
                                session_id: m.session_id,
                                file_count: m.file_count,
                                total_bytes: m.total_bytes,
                            })
                        }
                        protocol_message::ReceiverMessage::TransferProgress(m) => {
                            events.emit(SenderEvent::TransferProgress {
                                session_id: m.session_id,
                                bytes_sent: m.bytes_sent,
                                total_bytes: m.total_bytes,
                            })
                        }
                        protocol_message::ReceiverMessage::TransferCompleted(_) => break Ok(()),
                        _ => bail!("unexpected progress message from receiver"),
                    }
                }
            }),
        }
    }
    async fn wait(self) -> Result<()> {
        self.shutdown.await?
    }
}

struct BlobTransferTask {
    ticket: String,
    stop_tx: Option<oneshot::Sender<()>>,
    shutdown: JoinHandle<Result<()>>,
}
impl BlobTransferTask {
    fn spawn(reg: BlobRegistration) -> Self {
        let ticket = reg.ticket().to_string();
        let (tx, rx) = oneshot::channel();
        let shutdown = tokio::spawn(async move {
            let _ = rx.await;
            reg.shutdown().await
        });
        Self {
            ticket,
            stop_tx: Some(tx),
            shutdown,
        }
    }
    fn ticket(&self) -> &str {
        &self.ticket
    }
    async fn stop(mut self) -> Result<()> {
        if let Some(tx) = self.stop_tx.take() {
            let _ = tx.send(());
        }
        self.shutdown.await?
    }
}
