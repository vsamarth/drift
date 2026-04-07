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
use tokio::sync::{mpsc, oneshot, watch};
use tokio::time::{Duration, MissedTickBehavior, interval};
use tokio_stream::wrappers::UnboundedReceiverStream;
use tracing::info;

use crate::{
    blobs::receive::BlobReceiver,
    fs_plan::receive::build_expected_files,
    protocol::wire as protocol_wire,
    protocol::{message as protocol_message, receive as protocol_receiver},
    protocol::ALPN,
    rendezvous::{OfferFile, OfferManifest},
    session::{
        FileReceiveProgress, build_expected_transfer_files,
        receive_files_over_connection_with_progress,
    },
    transfer::TransferCancellation,
};

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
pub enum ReceiveTransferOutcome {
    Completed,
    Declined,
    Cancelled(TransferCancellation),
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
    pub outcome_rx: oneshot::Receiver<Result<ReceiveTransferOutcome>>,
    pub control: ReceiverControl,
}

#[derive(Debug)]
pub struct ReceiverSession {
    request: ReceiverRequest,
}

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

impl ReceiverSession {
    pub fn new(request: ReceiverRequest) -> Self {
        Self { request }
    }

    pub fn request(&self) -> &ReceiverRequest {
        &self.request
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

async fn run_session(
    endpoint: Endpoint,
    connection: Connection,
    request: ReceiverRequest,
    event_tx: Option<mpsc::UnboundedSender<Result<ReceiverEvent>>>,
    offer_tx: oneshot::Sender<Result<ReceiverOffer>>,
    decision_rx: oneshot::Receiver<ReceiverDecision>,
    cancel_rx: watch::Receiver<bool>,
) -> Result<ReceiveTransferOutcome> {
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
    handshake
        .send_hello(&mut control_send, &peer_hello.session_id)
        .await
        .context("sending receiver hello")?;

    let offer = handshake
        .read_offer(&mut control_recv, &peer_hello.session_id)
        .await
        .context("reading transfer offer")?;

    let session_id = peer_hello.session_id.clone();
    let sender_device_name = peer_hello.identity.device_name.clone();
    let sender_device_type = to_local_device_type(peer_hello.identity.device_type);
    let sender_endpoint_id = peer_hello.identity.endpoint_id;
    let manifest = to_offer_manifest(&offer);

    let expected_files = match build_expected_files(&manifest, &request.out_dir).await {
        Ok(expected_files) => expected_files,
        Err(err) => {
            let _ = handshake
                .decline(&mut control_send, &session_id, err.to_string())
                .await;
            let message = format!("{err:#}");
            let _ = offer_tx.send(Err(anyhow::anyhow!(message.clone())));
            emit_receiver_error(&event_tx, anyhow::anyhow!(message.clone()));
            return Err(anyhow::anyhow!(message));
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

    let decision = match decision_rx.await {
        Ok(decision) => decision,
        Err(error) => {
            let message = format!("{error}");
            emit_receiver_error(&event_tx, anyhow::anyhow!(message.clone()));
            return Err(anyhow::anyhow!(message));
        }
    };

    match decision {
        ReceiverDecision::Accept => {
            match handshake.accept(&mut control_send, &session_id).await {
                Ok(protocol_receiver::ReceiverControlOutcome::Accepted(sender)) => {
                    info!(
                        session_id = %sender.session_id,
                        sender_device_name = %sender.identity.device_name,
                        sender_endpoint_id = %sender.identity.endpoint_id,
                        "demo.receive.accepted"
                    );
                }
                Ok(other) => {
                    return Err(anyhow::anyhow!(
                        "unexpected receiver control outcome after accept: {:?}",
                        other
                    ));
                }
                Err(error) => return Err(error),
            }

            emit_receiver_event(
                &event_tx,
                ReceiverEvent::TransferStarted {
                    session_id: session_id.clone(),
                    file_count: manifest.file_count,
                    total_bytes: manifest.total_size,
                },
            );

            let progress_event_tx = event_tx.clone();
            let progress_session_id = session_id.clone();
            let mut progress_cb = |progress: FileReceiveProgress| {
                let _ = progress_event_tx.as_ref().map(|tx| {
                    tx.send(Ok(ReceiverEvent::TransferProgress {
                        session_id: progress_session_id.clone(),
                        bytes_received: progress.total_bytes_received,
                        total_bytes: progress.total_bytes_to_receive,
                    }))
                });
            };

            let outcome = receive_files_over_connection_with_progress(
                &endpoint,
                &mut control_send,
                &mut control_recv,
                &session_id,
                expected_transfer_files,
                Some(cancel_rx),
                &mut progress_cb,
            )
            .await?;

            if outcome.is_none() {
                emit_receiver_event(
                    &event_tx,
                    ReceiverEvent::Completed {
                        session_id: session_id.clone(),
                    },
                );
                Ok(ReceiveTransferOutcome::Completed)
            } else {
                Ok(ReceiveTransferOutcome::Cancelled(
                    outcome.expect("cancelled transfer has outcome"),
                ))
            }
        }
        ReceiverDecision::Decline => {
            let outcome = handshake
                .decline(
                    &mut control_send,
                    &session_id,
                    "receiver declined the transfer".to_owned(),
                )
                .await
                .context("sending receiver decline")?;
            if let protocol_receiver::ReceiverControlOutcome::Declined(message) = outcome {
                info!(
                    session_id = %message.session_id,
                    reason = %message.reason,
                    "demo.receive.declined"
                );
            }
            Ok(ReceiveTransferOutcome::Declined)
        }
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

        let session_id = pending.session_id().to_owned();
        let sender = pending.sender().clone();
        let manifest = pending.manifest().clone();
        let offer = ReceiverOffer {
            session_id: session_id.clone(),
            sender_device_name: sender.identity.device_name.clone(),
            sender_device_type: to_local_device_type(sender.identity.device_type),
            sender_endpoint_id: sender.identity.endpoint_id,
            items: manifest
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
            file_count: manifest.manifest.count() as u64,
            total_size: manifest.manifest.total_size(),
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
                    .accept(&mut control_send, &session_id)
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

                if ticket_message.session_id != session_id {
                    return Err(AcceptError::from_err(std::io::Error::other(format!(
                        "ticket session mismatch: expected {}, got {}",
                        session_id,
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
                    session_id = %session_id,
                    ticket = %ticket_message.ticket,
                    blob_provider_endpoint_id = %blob_ticket.addr().id,
                    blob_provider_hash = %blob_ticket.hash(),
                    "demo.receive.ticket_received"
                );
                println!("Ticket: {}", ticket_message.ticket);
                let _ = std::io::stdout().flush();

                let blob_receiver = BlobReceiver::new(
                    self.endpoint.clone(),
                    session_id.clone(),
                    blob_ticket,
                    self.out_dir.clone(),
                    to_transfer_manifest(&manifest),
                );

                emit_receiver_event(
                    &self.event_tx,
                    ReceiverEvent::TransferStarted {
                        session_id: session_id.clone(),
                        file_count: manifest.manifest.count() as u64,
                        total_bytes: manifest.manifest.total_size(),
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
                            session_id: session_id.clone(),
                            file_count: manifest.manifest.count() as u64,
                            total_bytes: manifest.manifest.total_size(),
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
                        info!(session_id = %session_id, "demo.receive.completed");
                        protocol_message::TransferResult {
                            session_id: session_id.clone(),
                            status: protocol_message::TransferStatus::Ok,
                        }
                    }
                    Err(error) => {
                        emit_receiver_error(&self.event_tx, error);
                        protocol_message::TransferResult {
                            session_id: session_id.clone(),
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
                        &session_id,
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
        let _ = tokio::time::timeout(
            std::time::Duration::from_secs(2),
            control_send.stopped(),
        )
        .await;
        if let Some(done_tx) = self
            .done_tx
            .lock()
            .expect("receiver done lock")
            .take()
        {
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
            protocol_message::ManifestItem::File { path, size } => OfferFile {
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

fn to_transfer_manifest(manifest: &protocol_message::Offer) -> protocol_message::TransferManifest {
    protocol_message::TransferManifest {
        items: manifest
            .manifest
            .items
            .iter()
            .map(|file| match file {
                protocol_message::ManifestItem::File { path, size } => {
                    protocol_message::ManifestItem::File {
                        path: path.clone(),
                        size: *size,
                    }
                }
            })
            .collect(),
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
