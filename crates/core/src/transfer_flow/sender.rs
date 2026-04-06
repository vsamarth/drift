#![allow(dead_code)]

use anyhow::{Context, Result, anyhow};
use iroh::{
    Endpoint, EndpointAddr, EndpointId, RelayMode, SecretKey, address_lookup::MdnsAddressLookup,
    endpoint::presets,
};
use std::path::{Path, PathBuf};
use rand::random;
use tokio::{
    sync::{mpsc, oneshot},
    task::JoinHandle,
};
use tokio::time::{timeout, Duration};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::info;

use crate::{
    blobs::send::{BlobRegistration, BlobService, PreparedStore},
    protocol::{message as protocol_message, send as protocol_sender},
    protocol::wire as protocol_wire,
    wire::ALPN,
};

const CONTROL_STREAM_FINISH_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendRequest {
    pub peer_endpoint_id: EndpointId,
    pub files: Vec<std::path::PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SenderOutcome {
    Accepted {
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
    },
    Declined {
        reason: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SenderEvent {
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
    outcome_rx: oneshot::Receiver<Result<SenderOutcome>>,
}

impl SenderRun {
    pub fn into_parts(self) -> (SenderEventStream, oneshot::Receiver<Result<SenderOutcome>>) {
        (self.events, self.outcome_rx)
    }

    pub async fn outcome(self) -> Result<SenderOutcome> {
        self.outcome_rx
            .await
            .context("waiting for sender outcome")?
    }
}

#[derive(Debug)]
pub struct Sender {
    secret_key: SecretKey,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
}

impl Sender {
    pub fn new(
        device_name: String,
        device_type: crate::wire::DeviceType,
        request: SendRequest,
    ) -> Self {
        let secret_key = SecretKey::from_bytes(&random());
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

    pub async fn run(&self) -> Result<SenderOutcome> {
        self.run_core(None).await
    }

    pub fn run_with_events(self) -> SenderRun
    where
        Self: Send + 'static,
    {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        let (outcome_tx, outcome_rx) = oneshot::channel();
        tokio::spawn(async move {
            let outcome = self.run_core(Some(event_tx.clone())).await;
            if let Err(error) = &outcome {
                emit_sender_error(&Some(event_tx.clone()), anyhow!("{error:#}"));
            }
            let _ = outcome_tx.send(outcome);
        });
        SenderRun {
            events: UnboundedReceiverStream::new(event_rx),
            outcome_rx,
        }
    }

    async fn run_core(&self, event_tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>) -> Result<SenderOutcome> {
        let store_root = TempDir::new(self.session_id.clone())?;
        let prepared_store = PreparedStore::prepare(
            self.session_id.clone(),
            store_root.path(),
            self.request.files.clone(),
        )
        .await
        .context("preparing blob store")?;
        let manifest = prepared_store.manifest();
        let endpoint = bind_endpoint(self.secret_key.clone()).await?;
        info!(
            session_id = %self.session_id,
            peer_endpoint_id = %self.request.peer_endpoint_id,
            local_endpoint_id = %endpoint.addr().id,
            file_count = manifest.count(),
            total_size = manifest.total_size(),
            "demo.send.connecting"
        );

        let connection = endpoint
            .connect(EndpointAddr::new(self.request.peer_endpoint_id), ALPN)
            .await
            .context("connecting to receiver")?;

        let (mut control_send, mut control_recv) = connection
            .open_bi()
            .await
            .context("opening control stream")?;

        let mut handshake = protocol_sender::Sender::new(self.session_id.clone(), self.identity.clone());
        let outcome = handshake
            .run_control(&mut control_send, &mut control_recv, manifest)
            .await?;

        match outcome {
            protocol_sender::SenderControlOutcome::Accepted(peer) => {
                self.handle_accepted(
                    &endpoint,
                    connection.clone(),
                    &mut control_send,
                    &mut control_recv,
                    peer,
                    prepared_store,
                    event_tx,
                )
                .await
            }
            protocol_sender::SenderControlOutcome::Declined(message) => {
                info!(
                    session_id = %self.session_id,
                    reason = %message.reason,
                    "demo.send.declined"
                );
                let _ = control_send.finish();
                endpoint.close().await;
                Ok(SenderOutcome::Declined {
                    reason: message.reason,
                })
            }
        }
    }

    async fn handle_accepted(
        &self,
        endpoint: &Endpoint,
        connection: iroh::endpoint::Connection,
        control_send: &mut iroh::endpoint::SendStream,
        control_recv: &mut iroh::endpoint::RecvStream,
        peer: protocol_sender::SenderPeer,
        prepared_store: PreparedStore,
        event_tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
    ) -> Result<SenderOutcome> {
        let registration = BlobService::new(endpoint.clone())
            .register(prepared_store)
            .await
            .context("registering blob service")?;
        let progress_task = SenderProgressTask::spawn(
            connection,
            self.session_id.clone(),
            event_tx.clone(),
        );
        let blob_task = BlobTransferTask::spawn(registration);
        let result = async {
            let ticket = blob_task.ticket().to_string();
            info!(session_id = %self.session_id, ticket = %ticket, "demo.send.ticket_ready");
            protocol_wire::write_sender_message(
                control_send,
                &protocol_message::SenderMessage::BlobTicket(
                    protocol_message::BlobTicketMessage {
                        session_id: self.session_id.clone(),
                        ticket,
                    },
                ),
            )
            .await
            .context("sending blob ticket")?;

            let completion = self.read_transfer_result(control_recv).await?;
            if !matches!(completion.status, protocol_message::TransferStatus::Ok) {
                anyhow::bail!("receiver reported transfer failure: {:?}", completion.status);
            }

            progress_task.wait().await.context("reading sender progress")?;
            info!(session_id = %self.session_id, "demo.send.completed");
            self.finish_control_stream(control_send).await?;
            info!(
                session_id = %self.session_id,
                receiver_device_name = %peer.identity.device_name,
                receiver_endpoint_id = %peer.identity.endpoint_id,
                "demo.send.accepted"
            );
            endpoint.close().await;
            Ok(SenderOutcome::Accepted {
                receiver_device_name: peer.identity.device_name,
                receiver_endpoint_id: peer.identity.endpoint_id,
            })
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

    async fn read_transfer_result(
        &self,
        control_recv: &mut iroh::endpoint::RecvStream,
    ) -> Result<protocol_message::TransferResult> {
        let completion = match protocol_wire::read_receiver_message(control_recv)
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

    async fn finish_control_stream(
        &self,
        control_send: &mut iroh::endpoint::SendStream,
    ) -> Result<()> {
        control_send.finish().context("finishing control send")?;
        let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, control_send.stopped()).await;
        Ok(())
    }
}

struct SenderProgressTask {
    shutdown: JoinHandle<Result<()>>,
}

impl SenderProgressTask {
    fn spawn(
        connection: iroh::endpoint::Connection,
        session_id: String,
        event_tx: Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
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
                        emit_sender_event(
                            &event_tx,
                            SenderEvent::TransferStarted {
                                session_id: message.session_id,
                                file_count: message.file_count,
                                total_bytes: message.total_bytes,
                            },
                        );
                    }
                    protocol_message::ReceiverMessage::TransferProgress(message) => {
                        ensure_session_id(&message.session_id, &session_id)?;
                        emit_sender_event(
                            &event_tx,
                            SenderEvent::TransferProgress {
                                session_id: message.session_id,
                                bytes_sent: message.bytes_sent,
                                total_bytes: message.total_bytes,
                            },
                        );
                    }
                    protocol_message::ReceiverMessage::TransferCompleted(message) => {
                        ensure_session_id(&message.session_id, &session_id)?;
                        emit_sender_event(
                            &event_tx,
                            SenderEvent::TransferCompleted {
                                session_id: message.session_id,
                            },
                        );
                        break Ok(());
                    }
                    other => {
                        let error = anyhow!(
                            "unexpected sender progress message: {:?}",
                            other
                        );
                        emit_sender_error(&event_tx, anyhow!("{error:#}"));
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

fn emit_sender_event(
    event_tx: &Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
    event: SenderEvent,
) {
    if let Some(tx) = event_tx {
        let _ = tx.send(Ok(event));
    }
}

fn emit_sender_error(
    event_tx: &Option<mpsc::UnboundedSender<Result<SenderEvent>>>,
    error: anyhow::Error,
) {
    if let Some(tx) = event_tx {
        let _ = tx.send(Err(error));
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

#[derive(Debug)]
struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(session_id: String) -> Result<Self> {
        let unique = format!(
            "drift-transfer-flow-sender-{}-{}",
            session_id,
            rand::random::<u64>()
        );
        let path = std::env::temp_dir().join(unique);
        std::fs::create_dir_all(&path)
            .with_context(|| format!("creating temp directory {}", path.display()))?;
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

async fn bind_endpoint(secret_key: SecretKey) -> Result<Endpoint> {
    Endpoint::builder(presets::N0)
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .address_lookup(MdnsAddressLookup::builder())
        .secret_key(secret_key)
        .bind()
        .await
        .context("binding iroh endpoint")
}

fn make_session_id() -> String {
    format!("{:016x}", random::<u64>())
}

fn to_protocol_device_type(
    device_type: crate::wire::DeviceType,
) -> protocol_message::DeviceType {
    match device_type {
        crate::wire::DeviceType::Phone => protocol_message::DeviceType::Phone,
        crate::wire::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
    }
}

#[cfg(test)]
mod tests {
    use super::SendRequest;
    use iroh::SecretKey;

    #[test]
    fn request_keeps_peer_identity() {
        let request = SendRequest {
            peer_endpoint_id: SecretKey::from_bytes(&[1; 32]).public(),
            files: vec![],
        };

        assert_eq!(request.peer_endpoint_id, SecretKey::from_bytes(&[1; 32]).public());
    }
}
