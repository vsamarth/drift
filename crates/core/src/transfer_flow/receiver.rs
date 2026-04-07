#![allow(dead_code)]

use anyhow::{Context, Error, Result};
use iroh::{
    Endpoint, RelayMode, SecretKey,
    address_lookup::MdnsAddressLookup,
    endpoint::Connection,
    endpoint::presets,
    protocol::Router,
    protocol::{AcceptError, ProtocolHandler},
};
use std::io::Write;
use std::sync::Mutex;
use tokio::sync::{mpsc, oneshot};
use tokio::time::{Duration, MissedTickBehavior, interval};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::info;

use crate::{
    blobs::receive::BlobReceiver,
    protocol::wire as protocol_wire,
    protocol::{message as protocol_message, receive as protocol_receiver},
    wire::ALPN,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverRequest {
    pub device_name: String,
    pub device_type: crate::wire::DeviceType,
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

const TRANSFER_PROGRESS_FORWARD_INTERVAL: Duration = Duration::from_millis(100);

#[derive(Debug)]
pub struct Receiver {
    secret_key: SecretKey,
    identity: protocol_message::Identity,
    request: ReceiverRequest,
}

#[derive(Debug)]
struct ReceiverHandler {
    endpoint: Endpoint,
    identity: protocol_message::Identity,
    out_dir: std::path::PathBuf,
    event_tx: Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    offer_tx: Mutex<Option<oneshot::Sender<ReceiverOffer>>>,
    decision_rx: Mutex<Option<oneshot::Receiver<ReceiverDecision>>>,
    done_tx: Mutex<Option<oneshot::Sender<()>>>,
}

impl Receiver {
    pub fn new(request: ReceiverRequest) -> Self {
        let secret_key = SecretKey::from_bytes(&rand::random());
        Self {
            identity: protocol_message::Identity {
                role: protocol_message::TransferRole::Receiver,
                endpoint_id: secret_key.public(),
                device_name: request.device_name.clone(),
                device_type: to_protocol_device_type(request.device_type),
            },
            secret_key,
            request,
        }
    }

    pub(crate) fn identity(&self) -> &protocol_message::Identity {
        &self.identity
    }

    pub fn request(&self) -> &ReceiverRequest {
        &self.request
    }

    pub async fn run<F, Fut>(self, decide: F) -> Result<ReceiverDecision>
    where
        F: FnOnce(ReceiverOffer) -> Fut,
        Fut: std::future::Future<Output = ReceiverDecision>,
    {
        self.run_core(decide, None).await
    }

    pub fn run_with_events<F, Fut>(self, decide: F) -> ReceiverEventStream
    where
        F: FnOnce(ReceiverOffer) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = ReceiverDecision> + Send + 'static,
        Self: Send + 'static,
    {
        let (event_tx, event_rx) = mpsc::unbounded_channel();
        tokio::spawn(async move {
            let _ = self.run_core(decide, Some(event_tx)).await;
        });
        UnboundedReceiverStream::new(event_rx)
    }

    async fn run_core<F, Fut>(
        self,
        decide: F,
        event_tx: Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    ) -> Result<ReceiverDecision>
    where
        F: FnOnce(ReceiverOffer) -> Fut,
        Fut: std::future::Future<Output = ReceiverDecision>,
    {
        let Receiver {
            secret_key,
            identity,
            request,
        } = self;
        let endpoint = bind_endpoint(secret_key).await?;
        info!(endpoint_id = %endpoint.addr().id, "demo.receive.listening");
        emit_receiver_event(
            &event_tx,
            ReceiverEvent::Listening {
                endpoint_id: endpoint.addr().id,
            },
        );

        let (offer_tx, offer_rx) = oneshot::channel();
        let (decision_tx, decision_rx) = oneshot::channel();
        let (done_tx, done_rx) = oneshot::channel();

        let _router = Router::builder(endpoint.clone())
            .accept(
                ALPN,
                ReceiverHandler {
                    endpoint: endpoint.clone(),
                    identity,
                    out_dir: request.out_dir.clone(),
                    event_tx: event_tx.clone(),
                    offer_tx: Mutex::new(Some(offer_tx)),
                    decision_rx: Mutex::new(Some(decision_rx)),
                    done_tx: Mutex::new(Some(done_tx)),
                },
            )
            .spawn();

        let offer = offer_rx.await.context("waiting for incoming offer")?;
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
        let decision = decide(offer).await;
        let _ = decision_tx.send(decision.clone());

        done_rx.await.context("waiting for receiver decision")?;
        endpoint.close().await;
        Ok(decision)
    }
}

impl ProtocolHandler for ReceiverHandler {
    async fn accept(&self, connection: Connection) -> Result<(), AcceptError> {
        let mut handshake = protocol_receiver::Receiver::new(self.identity.clone());
        let (mut control_send, mut control_recv) = connection
            .accept_bi()
            .await
            .map_err(AcceptError::from_err)?;

        let pending = handshake
            .run_control_until_decision(&mut control_send, &mut control_recv)
            .await
            .map_err(|error| {
                AcceptError::from_err(std::io::Error::other(format!(
                    "running receiver handshake: {error:#}"
                )))
            })?;

        let offer = ReceiverOffer {
            session_id: pending.session_id().to_owned(),
            sender_device_name: pending.sender().identity.device_name.clone(),
            sender_endpoint_id: pending.sender().identity.endpoint_id,
            items: pending
                .manifest()
                .manifest
                .items
                .iter()
                .map(|item| match item {
                    protocol_message::ManifestItem::File { path, size } => ReceiverOfferItem {
                        path: path.clone(),
                        size: *size,
                    },
                })
                .collect(),
            file_count: pending.manifest().manifest.items.len() as u64,
            total_size: pending
                .manifest()
                .manifest
                .items
                .iter()
                .map(|item| match item {
                    protocol_message::ManifestItem::File { size, .. } => *size,
                })
                .sum(),
        };

        info!(
            session_id = %offer.session_id,
            sender_device_name = %offer.sender_device_name,
            sender_endpoint_id = %offer.sender_endpoint_id,
            file_count = offer.file_count,
            total_size = offer.total_size,
            "demo.receive.offer_received"
        );

        self.offer_tx
            .lock()
            .expect("receiver offer lock")
            .take()
            .expect("receiver offer sender")
            .send(offer.clone())
            .map_err(|error| {
                AcceptError::from_err(std::io::Error::other(format!(
                    "sending receiver offer to cli: {error:?}"
                )))
            })?;

        let decision_rx = self
            .decision_rx
            .lock()
            .expect("receiver decision lock")
            .take()
            .expect("receiver decision receiver");
        let decision = decision_rx.await.map_err(|error| {
            AcceptError::from_err(std::io::Error::other(format!(
                "waiting for receiver decision: {error}"
            )))
        })?;

        match decision {
            ReceiverDecision::Accept => {
                let outcome = handshake
                    .accept(&mut control_send, pending.session_id())
                    .await
                    .map_err(|error| {
                        AcceptError::from_err(std::io::Error::other(format!(
                            "sending receiver accept: {error:#}"
                        )))
                    })?;
                if let protocol_receiver::ReceiverControlOutcome::Accepted(sender) = outcome {
                    info!(
                        session_id = %sender.session_id,
                        sender_device_name = %sender.identity.device_name,
                        sender_endpoint_id = %sender.identity.endpoint_id,
                        "demo.receive.accepted"
                    );
                }
                let ticket_message = match protocol_wire::read_sender_message(&mut control_recv)
                    .await
                    .map_err(|error| {
                        AcceptError::from_err(std::io::Error::other(format!(
                            "waiting for blob ticket: {error:#}"
                        )))
                    })? {
                    protocol_message::SenderMessage::BlobTicket(message) => message,
                    other => {
                        return Err(AcceptError::from_err(std::io::Error::other(format!(
                            "unexpected sender message while waiting for blob ticket: {:?}",
                            other
                        ))));
                    }
                };

                if ticket_message.session_id != pending.session_id() {
                    return Err(AcceptError::from_err(std::io::Error::other(format!(
                        "ticket session mismatch: expected {}, got {}",
                        pending.session_id(),
                        ticket_message.session_id
                    ))));
                }

                let blob_ticket: iroh_blobs::ticket::BlobTicket =
                    ticket_message.ticket.parse().map_err(|error| {
                        AcceptError::from_err(std::io::Error::other(format!(
                            "parsing blob ticket: {error:#}"
                        )))
                    })?;
                info!(
                    session_id = %pending.session_id(),
                    ticket = %ticket_message.ticket,
                    blob_provider_endpoint_id = %blob_ticket.addr().id,
                    blob_provider_hash = %blob_ticket.hash(),
                    "demo.receive.ticket_received"
                );
                println!("Ticket: {}", ticket_message.ticket);
                let _ = std::io::stdout().flush();

                let blob_receiver = BlobReceiver::new(
                    self.endpoint.clone(),
                    pending.session_id().to_owned(),
                    blob_ticket,
                    self.out_dir.clone(),
                    pending.manifest().manifest.clone(),
                );

                emit_receiver_event(
                    &self.event_tx,
                    ReceiverEvent::TransferStarted {
                        session_id: pending.session_id().to_owned(),
                        file_count: pending.manifest().manifest.count() as u64,
                        total_bytes: pending.manifest().manifest.total_size(),
                    },
                );

                let mut progress_send = connection.open_uni().await.map_err(|error| {
                    AcceptError::from_err(std::io::Error::other(format!(
                        "opening sender progress stream: {error:#}"
                    )))
                })?;

                protocol_wire::write_receiver_message(
                    &mut progress_send,
                    &protocol_message::ReceiverMessage::TransferStarted(
                        protocol_message::TransferStarted {
                            session_id: pending.session_id().to_owned(),
                            file_count: pending.manifest().manifest.count() as u64,
                            total_bytes: pending.manifest().manifest.total_size(),
                        },
                    ),
                )
                .await
                .map_err(|error| {
                    AcceptError::from_err(std::io::Error::other(format!(
                        "sending transfer started progress: {error:#}"
                    )))
                })?;

                let (blob_event_tx, mut blob_event_rx) = mpsc::unbounded_channel();
                let transfer_event_tx = self.event_tx.clone();
                let progress_forwarder = tokio::spawn(async move {
                    let mut progress_send = progress_send;
                    let mut ticker = interval(TRANSFER_PROGRESS_FORWARD_INTERVAL);
                    ticker.set_missed_tick_behavior(MissedTickBehavior::Skip);
                    let _ = ticker.tick().await;
                    let mut pending_progress: Option<(String, u64, u64)> = None;

                    loop {
                        tokio::select! {
                            biased;
                            _ = ticker.tick() => {
                                if let Some((session_id, bytes_received, total_bytes)) = pending_progress.take() {
                                    emit_receiver_event(
                                        &transfer_event_tx,
                                        ReceiverEvent::TransferProgress {
                                            session_id: session_id.clone(),
                                            bytes_received,
                                            total_bytes,
                                        },
                                    );
                                    if let Err(error) = protocol_wire::write_receiver_message(
                                        &mut progress_send,
                                        &protocol_message::ReceiverMessage::TransferProgress(
                                            protocol_message::TransferProgress {
                                                session_id,
                                                bytes_sent: bytes_received,
                                                total_bytes,
                                            },
                                        ),
                                    )
                                    .await
                                    {
                                        emit_receiver_error(&transfer_event_tx, error.into());
                                        break;
                                    }
                                }
                            }
                            event = blob_event_rx.recv() => {
                                match event {
                                    Some(crate::blobs::receive::ReceiverEvent::Progress {
                                        session_id: blob_session_id,
                                        bytes_received,
                                        total_bytes: Some(total_bytes),
                                    }) => {
                                        pending_progress = Some((blob_session_id, bytes_received, total_bytes));
                                    }
                                    Some(crate::blobs::receive::ReceiverEvent::Completed {
                                        session_id: blob_session_id,
                                    }) => {
                                        if let Some((session_id, bytes_received, total_bytes)) = pending_progress.take() {
                                            emit_receiver_event(
                                                &transfer_event_tx,
                                                ReceiverEvent::TransferProgress {
                                                    session_id: session_id.clone(),
                                                    bytes_received,
                                                    total_bytes,
                                                },
                                            );
                                            if let Err(error) = protocol_wire::write_receiver_message(
                                                &mut progress_send,
                                                &protocol_message::ReceiverMessage::TransferProgress(
                                                    protocol_message::TransferProgress {
                                                        session_id,
                                                        bytes_sent: bytes_received,
                                                        total_bytes,
                                                    },
                                                ),
                                            )
                                            .await
                                            {
                                                emit_receiver_error(&transfer_event_tx, error.into());
                                                break;
                                            }
                                        }

                                        emit_receiver_event(
                                            &transfer_event_tx,
                                            ReceiverEvent::Completed {
                                                session_id: blob_session_id.clone(),
                                            },
                                        );
                                        if let Err(error) = protocol_wire::write_receiver_message(
                                            &mut progress_send,
                                            &protocol_message::ReceiverMessage::TransferCompleted(
                                                protocol_message::TransferCompleted {
                                                    session_id: blob_session_id,
                                                },
                                            ),
                                        )
                                        .await
                                        {
                                            emit_receiver_error(&transfer_event_tx, error.into());
                                        }
                                        let _ = progress_send.finish();
                                        break;
                                    }
                                    Some(_) => {}
                                    None => {
                                        if let Some((session_id, bytes_received, total_bytes)) = pending_progress.take() {
                                            emit_receiver_event(
                                                &transfer_event_tx,
                                                ReceiverEvent::TransferProgress {
                                                    session_id: session_id.clone(),
                                                    bytes_received,
                                                    total_bytes,
                                                },
                                            );
                                            if let Err(error) = protocol_wire::write_receiver_message(
                                                &mut progress_send,
                                                &protocol_message::ReceiverMessage::TransferProgress(
                                                    protocol_message::TransferProgress {
                                                        session_id,
                                                        bytes_sent: bytes_received,
                                                        total_bytes,
                                                    },
                                                ),
                                            )
                                            .await
                                            {
                                                emit_receiver_error(&transfer_event_tx, error.into());
                                            }
                                        }
                                        break;
                                    }
                                }
                            }
                        }
                    }
                });

                let completion_result = blob_receiver.run(Some(blob_event_tx.clone())).await;
                drop(blob_event_tx);
                let _ = progress_forwarder.await;
                let completion_message = match completion_result {
                    Ok(()) => {
                        info!(session_id = %pending.session_id(), "demo.receive.completed");
                        protocol_message::TransferResult {
                            session_id: pending.session_id().to_owned(),
                            status: protocol_message::TransferStatus::Ok,
                        }
                    }
                    Err(error) => {
                        emit_receiver_error(&self.event_tx, error);
                        protocol_message::TransferResult {
                            session_id: pending.session_id().to_owned(),
                            status: protocol_message::TransferStatus::Error {
                                code: protocol_message::TransferErrorCode::IoError,
                                message: "blob transfer failed".to_owned(),
                            },
                        }
                    }
                };

                protocol_wire::write_receiver_message(
                    &mut control_send,
                    &protocol_message::ReceiverMessage::TransferResult(completion_message),
                )
                .await
                .map_err(|error| {
                    AcceptError::from_err(std::io::Error::other(format!(
                        "sending receiver completion: {error:#}"
                    )))
                })?;
            }
            ReceiverDecision::Decline => {
                let outcome = handshake
                    .decline(
                        &mut control_send,
                        pending.session_id(),
                        "receiver declined the demo offer".to_owned(),
                    )
                    .await
                    .map_err(|error| {
                        AcceptError::from_err(std::io::Error::other(format!(
                            "sending receiver decline: {error:#}"
                        )))
                    })?;
                if let protocol_receiver::ReceiverControlOutcome::Declined(message) = outcome {
                    info!(
                        session_id = %message.session_id,
                        reason = %message.reason,
                        "demo.receive.declined"
                    );
                }
            }
        }

        control_send.finish()?;
        let _ =
            tokio::time::timeout(std::time::Duration::from_secs(2), control_send.stopped()).await;
        if let Some(done_tx) = self.done_tx.lock().expect("receiver done lock").take() {
            let _ = done_tx.send(());
        }
        Ok(())
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

fn to_protocol_device_type(device_type: crate::wire::DeviceType) -> protocol_message::DeviceType {
    match device_type {
        crate::wire::DeviceType::Phone => protocol_message::DeviceType::Phone,
        crate::wire::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
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
    error: Error,
) {
    if let Some(tx) = event_tx {
        let _ = tx.send(Err(error));
    }
}
