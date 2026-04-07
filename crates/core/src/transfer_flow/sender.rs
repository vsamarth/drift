#![allow(dead_code)]

use anyhow::{Context, Result, anyhow};
use iroh::{
    EndpointAddr, EndpointId,
};
use rand::random;
use tokio::time::{Duration, timeout};
use tokio::{
    io::AsyncWrite,
    sync::{mpsc, oneshot},
    task::JoinHandle,
};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::{debug, info, instrument, warn};

use crate::{
    blobs::send::{BlobRegistration, BlobService, PreparedStore},
    protocol::wire as protocol_wire,
    protocol::{message as protocol_message, send as protocol_sender},
    protocol::ALPN,
};

use super::path::ScratchDir;
use super::types::TransferOutcome;

const CONTROL_STREAM_FINISH_TIMEOUT: Duration = Duration::from_secs(2);

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
    outcome_rx: oneshot::Receiver<Result<TransferOutcome>>,
}

impl SenderRun {
    pub fn into_parts(self) -> (SenderEventStream, oneshot::Receiver<Result<TransferOutcome>>) {
        (self.events, self.outcome_rx)
    }

    pub async fn outcome(self) -> Result<TransferOutcome> {
        self.outcome_rx
            .await
            .context("waiting for sender outcome")?
    }
}


#[derive(Clone, Debug)]
struct SenderEventSink {
    session_id: String,
    event_tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
}

impl SenderEventSink {
    fn new(
        session_id: String,
        event_tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
    ) -> Self {
        Self {
            session_id,
            event_tx,
        }
    }

    fn silent(session_id: String) -> Self {
        Self {
            session_id,
            event_tx: None,
        }
    }

    fn emit(&self, event: SenderEvent) {
        if let Some(tx) = &self.event_tx {
            let _ = tx.send(Ok(event));
        }
    }

    fn fail(&self, error: &anyhow::Error) {
        self.emit(SenderEvent::Failed {
            session_id: self.session_id.clone(),
            message: format!("{error:#}"),
        });
        if let Some(tx) = &self.event_tx {
            let _ = tx.send(Err(anyhow!("{error:#}")));
        }
    }
}

#[derive(Debug)]
struct SenderSession {
    secret_key: iroh::SecretKey,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
    events: SenderEventSink,
}

#[derive(Debug)]
struct SenderControl {
    session_id: String,
    send: iroh::endpoint::SendStream,
    recv: iroh::endpoint::RecvStream,
}

impl SenderControl {
    async fn open(connection: &iroh::endpoint::Connection, session_id: String) -> Result<Self> {
        let (send, recv) = connection
            .open_bi()
            .await
            .context("opening control stream")?;
        Ok(Self {
            session_id,
            send,
            recv,
        })
    }

    async fn start_handshake(
        &mut self,
        identity: protocol_message::Identity,
        manifest: protocol_message::TransferManifest,
        events: &SenderEventSink,
    ) -> Result<(
        protocol_message::Hello,
        protocol_sender::SenderControlOutcome,
    )> {
        let mut handshake = protocol_sender::Sender::new(self.session_id.clone(), identity);
        handshake.send_hello(&mut self.send).await?;
        let peer_hello = handshake.read_peer_hello(&mut self.recv).await?;
        handshake.send_offer(&mut self.send, manifest).await?;
        events.emit(SenderEvent::WaitingForDecision {
            session_id: self.session_id.clone(),
            receiver_device_name: peer_hello.identity.device_name.clone(),
            receiver_endpoint_id: peer_hello.identity.endpoint_id,
        });
        let decision = handshake.await_decision(&mut self.recv).await?;
        Ok((peer_hello, decision))
    }

    async fn send_blob_ticket(&mut self, ticket: String) -> Result<()> {
        protocol_wire::write_sender_message(
            &mut self.send,
            &protocol_message::SenderMessage::BlobTicket(protocol_message::BlobTicketMessage {
                session_id: self.session_id.clone(),
                ticket,
            }),
        )
        .await
        .context("sending blob ticket")
    }

    async fn read_transfer_result(&mut self) -> Result<protocol_message::TransferResult> {
        let completion = match protocol_wire::read_receiver_message(&mut self.recv)
            .await
            .context("waiting for receiver completion")?
        {
            protocol_message::ReceiverMessage::TransferResult(result) => result,
            other => anyhow::bail!("unexpected receiver completion message: {:?}", other),
        };

        if completion.session_id != self.session_id {
            anyhow::bail!(
                "session id mismatch: expected {}, got {}",
                self.session_id,
                completion.session_id
            );
        }

        Ok(completion)
    }

    async fn send_transfer_ack(&mut self) -> Result<()> {
        write_transfer_ack(&mut self.send, &self.session_id).await
    }

    async fn finish(&mut self) -> Result<()> {
        self.send.finish().context("finishing control send")?;
        let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, self.send.stopped()).await;
        Ok(())
    }
}

#[derive(Debug)]
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
                device_type: to_protocol_device_type(device_type),
            },
            secret_key,
            session_id: make_session_id(),
            request,
        }
    }

    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    pub fn request(&self) -> &SendRequest {
        &self.request
    }

    pub async fn run(&self) -> Result<TransferOutcome> {
        self.run_core(SenderEventSink::silent(self.session_id.clone()))
            .await
    }

    pub fn run_with_events(self) -> SenderRun
    where
        Self: Send + 'static,
    {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (outcome_tx, outcome_rx) = oneshot::channel();
        let events = SenderEventSink::new(self.session_id.clone(), Some(event_tx));
        tokio::spawn(async move {
            let outcome = self.run_core(events.clone()).await;
            if let Err(error) = &outcome {
                events.fail(error);
            }
            let _ = outcome_tx.send(outcome);
        });
        SenderRun {
            events: UnboundedReceiverStream::new(event_rx),
            outcome_rx,
        }
    }

    async fn run_core(&self, events: SenderEventSink) -> Result<TransferOutcome> {
        SenderSession::new(self, events).run().await
    }
}

impl SenderSession {
    fn new(sender: &Sender, events: SenderEventSink) -> Self {
        Self {
            secret_key: sender.secret_key.clone(),
            session_id: sender.session_id.clone(),
            identity: sender.identity.clone(),
            request: sender.request.clone(),
            events,
        }
    }

    #[instrument(skip_all, fields(session_id = %self.session_id, peer = %self.request.peer_endpoint_id))]
    async fn run(self) -> Result<TransferOutcome> {
        let store_root = ScratchDir::new("drift-flow-sender", &self.session_id).await?;
        let prepared_store = PreparedStore::prepare(
            self.session_id.clone(),
            &store_root.path,
            self.request.files.clone(),
        )
        .await
        .context("preparing blob store")?;
        let manifest = prepared_store.manifest();
        let endpoint = iroh::Endpoint::builder(iroh::endpoint::presets::N0)
            .alpns(vec![ALPN.to_vec()])
            .relay_mode(iroh::RelayMode::Default)
            .secret_key(self.secret_key.clone())
            .bind()
            .await
            .context("binding sender endpoint")?;

        self.events.emit(SenderEvent::Connecting {
            session_id: self.session_id.clone(),
            peer_endpoint_id: self.request.peer_endpoint_id,
        });
        
        info!(
            file_count = manifest.count(),
            total_size = manifest.total_size(),
            "connecting to receiver"
        );

        let connection = endpoint
            .connect(EndpointAddr::new(self.request.peer_endpoint_id), ALPN)
            .await
            .context("connecting to receiver")?;

        let mut control = SenderControl::open(&connection, self.session_id.clone()).await?;
        let (_receiver_hello, outcome) = control
            .start_handshake(self.identity.clone(), manifest, &self.events)
            .await?;

        match outcome {
            protocol_sender::SenderControlOutcome::Accepted(peer) => {
                info!(
                    receiver_device_name = %peer.identity.device_name,
                    receiver_endpoint_id = %peer.identity.endpoint_id,
                    "transfer accepted by receiver"
                );
                self.events.emit(SenderEvent::Accepted {
                    session_id: self.session_id.clone(),
                    receiver_device_name: peer.identity.device_name.clone(),
                    receiver_endpoint_id: peer.identity.endpoint_id,
                });
                self.run_transfer(endpoint, connection, control, prepared_store, peer)
                    .await
            }
            protocol_sender::SenderControlOutcome::Declined(message) => {
                info!(reason = %message.reason, "transfer declined by receiver");
                self.events.emit(SenderEvent::Declined {
                    session_id: self.session_id.clone(),
                    reason: message.reason.clone(),
                });
                let _ = control.finish().await;
                endpoint.close().await;
                Ok(TransferOutcome::Declined {
                    reason: message.reason,
                })
            }
        }
    }

    #[instrument(skip_all, fields(session_id = %self.session_id))]
    async fn run_transfer(
        self,
        endpoint: iroh::Endpoint,
        connection: iroh::endpoint::Connection,
        mut control: SenderControl,
        prepared_store: PreparedStore,
        _peer: protocol_sender::SenderPeer,
    ) -> Result<TransferOutcome> {
        let manifest = prepared_store.manifest();
        let file_count = manifest.count() as u64;
        let total_bytes = prepared_store.total_bytes();
        let registration = BlobService::new(endpoint.clone())
            .register(prepared_store)
            .await
            .context("registering blob service")?;
        let progress_task =
            SenderProgressTask::spawn(connection, self.session_id.clone(), self.events.clone());
        let blob_task = BlobTransferTask::spawn(registration);
        let result = async {
            let ticket = blob_task.ticket().to_string();
            debug!(%ticket, "blob ticket ready");
            control.send_blob_ticket(ticket).await?;

            self.events.emit(SenderEvent::TransferStarted {
                session_id: self.session_id.clone(),
                file_count,
                total_bytes,
            });

            let completion = control.read_transfer_result().await?;
            if !matches!(completion.status, protocol_message::TransferStatus::Ok) {
                warn!(status = ?completion.status, "receiver reported transfer failure");
                anyhow::bail!(
                    "receiver reported transfer failure: {:?}",
                    completion.status
                );
            }

            progress_task
                .wait()
                .await
                .context("reading sender progress")?;

            control.send_transfer_ack().await?;
            self.events.emit(SenderEvent::TransferCompleted {
                session_id: self.session_id.clone(),
            });
            info!("transfer completed successfully");
            control.finish().await?;
            endpoint.close().await;
            Ok(TransferOutcome::Completed)
        }
        .await;

        let stop_result = blob_task.stop().await;
        match result {
            Ok(outcome) => {
                stop_result.context("stopping blob service")?;
                Ok(outcome)
            }
            Err(error) => {
                let _ = stop_result;
                Err(error)
            }
        }
    }
}

struct SenderProgressTask {
    shutdown: JoinHandle<Result<()>>,
}

impl SenderProgressTask {
    fn spawn(
        connection: iroh::endpoint::Connection,
        session_id: String,
        events: SenderEventSink,
    ) -> Self {
        let shutdown = tokio::spawn(async move {
            let mut progress_recv = connection
                .accept_uni()
                .await
                .context("accepting sender progress stream")?;

            loop {
                match protocol_wire::read_receiver_message(&mut progress_recv).await? {
                    protocol_message::ReceiverMessage::TransferStarted(message) => {
                        ensure_session_id(&message.session_id, &session_id)?;
                        events.emit(SenderEvent::TransferStarted {
                            session_id: message.session_id,
                            file_count: message.file_count,
                            total_bytes: message.total_bytes,
                        });
                    }
                    protocol_message::ReceiverMessage::TransferProgress(message) => {
                        ensure_session_id(&message.session_id, &session_id)?;
                        events.emit(SenderEvent::TransferProgress {
                            session_id: message.session_id,
                            bytes_sent: message.bytes_sent,
                            total_bytes: message.total_bytes,
                        });
                    }
                    protocol_message::ReceiverMessage::TransferCompleted(message) => {
                        ensure_session_id(&message.session_id, &session_id)?;
                        events.emit(SenderEvent::TransferCompleted {
                            session_id: message.session_id,
                        });
                        break Ok(());
                    }
                    other => {
                        let error = anyhow!("unexpected sender progress message: {:?}", other);
                        break Err(error);
                    }
                }
            }
        });

        Self { shutdown }
    }

    async fn wait(self) -> Result<()> {
        match self.shutdown.await {
            Ok(result) => result,
            Err(error) => Err(error.into()),
        }
    }
}

fn ensure_session_id(actual: &str, expected: &str) -> Result<()> {
    if actual == expected {
        Ok(())
    } else {
        anyhow::bail!("session id mismatch: expected {expected}, got {actual}")
    }
}

struct BlobTransferTask {
    ticket: String,
    stop_tx: Option<oneshot::Sender<()>>,
    shutdown: JoinHandle<Result<()>>,
}

impl BlobTransferTask {
    fn spawn(registration: BlobRegistration) -> Self {
        let ticket = registration.ticket().to_string();
        let (stop_tx, stop_rx) = oneshot::channel();
        let shutdown = tokio::spawn(async move {
            let _ = stop_rx.await;
            registration.shutdown().await
        });

        Self {
            ticket,
            stop_tx: Some(stop_tx),
            shutdown,
        }
    }

    fn ticket(&self) -> &str {
        &self.ticket
    }

    async fn stop(mut self) -> Result<()> {
        if let Some(stop_tx) = self.stop_tx.take() {
            let _ = stop_tx.send(());
        }

        match self.shutdown.await {
            Ok(result) => result,
            Err(error) => Err(error.into()),
        }
    }
}

fn make_session_id() -> String {
    format!("{:016x}", random::<u64>())
}

fn to_protocol_device_type(device_type: crate::protocol::DeviceType) -> protocol_message::DeviceType {
    match device_type {
        crate::protocol::DeviceType::Phone => protocol_message::DeviceType::Phone,
        crate::protocol::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
    }
}

async fn write_transfer_ack<W>(writer: &mut W, session_id: &str) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    protocol_wire::write_sender_message(
        writer,
        &protocol_message::SenderMessage::TransferAck(protocol_message::TransferAck {
            session_id: session_id.to_owned(),
        }),
    )
    .await
    .context("sending transfer ack")
}

#[cfg(test)]
mod tests {
    use super::write_transfer_ack;
    use crate::protocol::message::{SenderMessage, TransferAck};
    use crate::protocol::wire::read_sender_message;
    use anyhow::Result;
    use tokio::io::duplex;

    #[tokio::test]
    async fn sender_control_sends_transfer_ack() -> Result<()> {
        let (local, remote) = duplex(1024);
        let (_local_read, mut local_write) = tokio::io::split(local);
        let (mut remote_read, _remote_write) = tokio::io::split(remote);

        write_transfer_ack(&mut local_write, "session-1").await?;

        match read_sender_message(&mut remote_read).await? {
            SenderMessage::TransferAck(TransferAck { session_id }) => {
                assert_eq!(session_id, "session-1");
            }
            other => panic!("unexpected sender message: {:?}", other),
        }

        Ok(())
    }
}
