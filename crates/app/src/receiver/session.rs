use std::time::Duration;

use drift_core::transfer_flow::{
    ReceiverDecision as CoreReceiverDecision, ReceiverEvent as CoreReceiverEvent,
    ReceiverRequest as CoreReceiverRequest, ReceiverSession as CoreReceiverSession,
    ReceiverStart as CoreReceiverStart, TransferOutcome as CoreTransferOutcome,
};
use drift_core::protocol::DeviceType;
use drift_core::util::{ConnectionPathKind, classify_connection_path, human_size};
use iroh::Endpoint;
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;
use tokio_stream::StreamExt;

use crate::error::format_error_chain;
use crate::types::{
    ReceiverOfferEvent, ReceiverOfferFile, ReceiverOfferPhase,
};

use super::actor::ReceiverCommand;
use super::runtime::OfferResolution;

const PROGRESS_EVENT_MIN_INTERVAL: Duration = Duration::from_millis(100);
const PROGRESS_EVENT_MIN_BYTES: u64 = 4 * 1024 * 1024;

#[derive(Debug)]
pub(super) struct ReceiverSession {
    offer_id: u64,
    endpoint: Endpoint,
    connection: iroh::endpoint::Connection,
    out_dir: std::path::PathBuf,
    device_name: String,
    device_type: DeviceType,
    save_root_label: String,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
}

#[derive(Debug)]
pub(super) struct ReceiverRun {
    pub(super) offer_id: u64,
    pub(super) decision_tx: oneshot::Sender<OfferResolution>,
    pub(super) cancel_tx: tokio::sync::watch::Sender<bool>,
}

impl ReceiverSession {
    pub(super) fn new(
        offer_id: u64,
        endpoint: Endpoint,
        connection: iroh::endpoint::Connection,
        out_dir: std::path::PathBuf,
        device_name: String,
        device_type: DeviceType,
        cmd_tx: mpsc::Sender<ReceiverCommand>,
    ) -> Self {
        let save_root_label = save_root_display(&out_dir);
        Self {
            offer_id,
            endpoint,
            connection,
            out_dir,
            device_name,
            device_type,
            save_root_label,
            cmd_tx,
        }
    }

    pub(super) fn spawn(self) -> JoinHandle<()> {
        tokio::spawn(async move {
            self.run().await;
        })
    }

    async fn run(self) {
        let ReceiverSession {
            offer_id,
            endpoint,
            connection,
            out_dir,
            device_name,
            device_type,
            save_root_label,
            cmd_tx,
        } = self;

        let connection_path_kind = classify_connection_path(&endpoint, connection.remote_id()).await;
        let session = CoreReceiverSession::new(CoreReceiverRequest {
            device_name: device_name.clone(),
            device_type,
            out_dir,
        });
        let start = session.start(endpoint, connection);
        let CoreReceiverStart {
            mut events,
            offer_rx,
            outcome_rx,
            control,
        } = start;

        let offer = match offer_rx.await {
            Ok(Ok(offer)) => offer,
            Ok(Err(error)) => {
                let _ = cmd_tx
                    .send(ReceiverCommand::OfferFinished {
                        offer_id,
                        final_event: failed_offer_event(
                            &save_root_label,
                            device_type,
                            "Transfer failed.".to_owned(),
                            format_error_chain(&error),
                        ),
                    })
                    .await;
                return;
            }
            Err(error) => {
                let _ = cmd_tx
                    .send(ReceiverCommand::OfferFinished {
                        offer_id,
                        final_event: failed_offer_event(
                            &save_root_label,
                            device_type,
                            "Transfer failed.".to_owned(),
                            format!("{error}"),
                        ),
                    })
                    .await;
                return;
            }
        };

        let sender_label = display_sender_label(&offer.sender_device_name);
        let sender_device_type = offer.sender_device_type;
        let files = offer
            .items
            .iter()
            .map(|file| ReceiverOfferFile {
                path: file.path.clone(),
                size: file.size,
            })
            .collect();

        let (decision_tx, decision_rx) = oneshot::channel();
        let core_decision_tx = control.decision_tx;
        tokio::spawn(async move {
            let decision = match decision_rx.await.unwrap_or(OfferResolution::Cancel) {
                OfferResolution::Accept => CoreReceiverDecision::Accept,
                OfferResolution::Decline | OfferResolution::Cancel => {
                    CoreReceiverDecision::Decline
                }
            };
            let _ = core_decision_tx.send(decision);
        });
        let run = ReceiverRun {
            offer_id,
            decision_tx,
            cancel_tx: control.cancel_tx,
        };
        let prepared_event = ReceiverOfferEvent {
            phase: ReceiverOfferPhase::OfferReady,
            sender_name: offer.sender_device_name.clone(),
            sender_device_type: device_type_to_str(sender_device_type),
            destination_label: sender_label.clone(),
            save_root_label: save_root_label.clone(),
            status_message: format!("{sender_label} wants to send you files."),
            item_count: offer.file_count,
            total_size_bytes: offer.total_size,
            bytes_received: 0,
            connection_path: Some(connection_path_label(connection_path_kind)),
            total_size_label: human_size(offer.total_size),
            files,
            error_message: None,
        };
        if cmd_tx
            .send(ReceiverCommand::OfferPrepared {
                run,
                event: prepared_event,
            })
            .await
            .is_err()
        {
            return;
        }

        let progress_cmd_tx = cmd_tx.clone();
        let mut last_progress_emit_at = std::time::Instant::now()
            .checked_sub(PROGRESS_EVENT_MIN_INTERVAL)
            .unwrap_or_else(std::time::Instant::now);
        let mut last_progress_bytes = 0_u64;
        while let Some(event) = events.next().await {
            match event {
                Ok(CoreReceiverEvent::TransferStarted {
                    session_id: _,
                    file_count,
                    total_bytes,
                }) => {
                    let _ = progress_cmd_tx.try_send(ReceiverCommand::OfferProgress {
                        offer_id,
                        event: build_progress_event(
                            sender_label.clone(),
                            save_root_label.clone(),
                            sender_device_type,
                            connection_path_kind,
                            file_count,
                            total_bytes,
                            0,
                        ),
                    });
                }
                Ok(CoreReceiverEvent::TransferProgress {
                    session_id: _,
                    bytes_received,
                    total_bytes,
                }) => {
                    let now = std::time::Instant::now();
                    let interval_elapsed =
                        now.duration_since(last_progress_emit_at) >= PROGRESS_EVENT_MIN_INTERVAL;
                    let bytes_advanced =
                        bytes_received.saturating_sub(last_progress_bytes) >= PROGRESS_EVENT_MIN_BYTES;
                    let is_complete = total_bytes > 0 && bytes_received >= total_bytes;
                    if interval_elapsed || bytes_advanced || is_complete {
                        last_progress_emit_at = now;
                        last_progress_bytes = bytes_received;
                        let _ = progress_cmd_tx.try_send(ReceiverCommand::OfferProgress {
                            offer_id,
                            event: build_progress_event(
                                sender_label.clone(),
                                save_root_label.clone(),
                                sender_device_type,
                                connection_path_kind,
                                offer.file_count,
                                total_bytes,
                                bytes_received,
                            ),
                        });
                    }
                }
                Ok(CoreReceiverEvent::Listening { .. }) => {}
                Ok(CoreReceiverEvent::Completed { .. }) => {
                    break;
                }
                Ok(CoreReceiverEvent::OfferReceived { .. }) => {}
                Err(error) => {
                    let _ = progress_cmd_tx
                        .try_send(ReceiverCommand::OfferFinished {
                            offer_id,
                            final_event: failed_offer_event(
                                &save_root_label,
                                sender_device_type,
                                "Transfer failed.".to_owned(),
                                format!("{error}"),
                            ),
                        });
                    return;
                }
            }
        }

        let final_event = match outcome_rx.await {
            Ok(Ok(outcome)) => match outcome {
                CoreTransferOutcome::Completed => ReceiverOfferEvent {
                    phase: ReceiverOfferPhase::Completed,
                    sender_name: String::new(),
                    sender_device_type: device_type_to_str(sender_device_type),
                    destination_label: sender_label,
                    save_root_label,
                    status_message: "Files saved.".to_owned(),
                    item_count: offer.file_count,
                    total_size_bytes: offer.total_size,
                    bytes_received: offer.total_size,
                    connection_path: Some(connection_path_label(connection_path_kind)),
                    total_size_label: human_size(offer.total_size),
                    files: Vec::new(),
                    error_message: None,
                },
                CoreTransferOutcome::Declined { .. } => ReceiverOfferEvent {
                    phase: ReceiverOfferPhase::Declined,
                    sender_name: String::new(),
                    sender_device_type: device_type_to_str(sender_device_type),
                    destination_label: sender_label,
                    save_root_label,
                    status_message: "Transfer cancelled.".to_owned(),
                    item_count: offer.file_count,
                    total_size_bytes: offer.total_size,
                    bytes_received: 0,
                    connection_path: Some(connection_path_label(connection_path_kind)),
                    total_size_label: human_size(offer.total_size),
                    files: Vec::new(),
                    error_message: None,
                },
                CoreTransferOutcome::Cancelled(cancellation) => ReceiverOfferEvent {
                    phase: ReceiverOfferPhase::Cancelled,
                    sender_name: String::new(),
                    sender_device_type: device_type_to_str(sender_device_type),
                    destination_label: sender_label,
                    save_root_label,
                    status_message: "Transfer cancelled.".to_owned(),
                    item_count: offer.file_count,
                    total_size_bytes: offer.total_size,
                    bytes_received: last_progress_bytes,
                    connection_path: Some(connection_path_label(connection_path_kind)),
                    total_size_label: human_size(offer.total_size),
                    files: Vec::new(),
                    error_message: Some(cancellation.reason),
                },
            },
            Ok(Err(error)) => failed_offer_event(
                &save_root_label,
                sender_device_type,
                "Transfer failed.".to_owned(),
                format_error_chain(&error),
            ),
            Err(error) => failed_offer_event(
                &save_root_label,
                sender_device_type,
                "Transfer failed.".to_owned(),
                format!("{error}"),
            ),
        };

        let _ = cmd_tx
            .send(ReceiverCommand::OfferFinished {
                offer_id,
                final_event,
            })
            .await;
    }
}

fn build_progress_event(
    sender_label: String,
    save_root_label: String,
    sender_device_type: DeviceType,
    connection_path_kind: ConnectionPathKind,
    file_count: u64,
    total_bytes: u64,
    bytes_received: u64,
) -> ReceiverOfferEvent {
    ReceiverOfferEvent {
        phase: ReceiverOfferPhase::Receiving,
        sender_name: sender_label.clone(),
        sender_device_type: device_type_to_str(sender_device_type),
        destination_label: sender_label,
        save_root_label,
        status_message: "Receiving files…".to_owned(),
        item_count: file_count,
        total_size_bytes: total_bytes,
        bytes_received,
        connection_path: Some(connection_path_label(connection_path_kind)),
        total_size_label: human_size(total_bytes),
        files: Vec::new(),
        error_message: None,
    }
}

fn failed_offer_event(
    save_root_label: &str,
    sender_device_type: DeviceType,
    status_message: String,
    error_message: String,
) -> ReceiverOfferEvent {
    ReceiverOfferEvent {
        phase: ReceiverOfferPhase::Failed,
        sender_name: String::new(),
        sender_device_type: device_type_to_str(sender_device_type),
        destination_label: String::new(),
        save_root_label: save_root_label.to_owned(),
        status_message,
        item_count: 0,
        total_size_bytes: 0,
        bytes_received: 0,
        connection_path: None,
        total_size_label: String::new(),
        files: Vec::new(),
        error_message: Some(error_message),
    }
}

fn device_type_to_str(value: DeviceType) -> String {
    match value {
        DeviceType::Phone => "phone".to_owned(),
        DeviceType::Laptop => "laptop".to_owned(),
    }
}

fn connection_path_label(kind: ConnectionPathKind) -> String {
    match kind {
        ConnectionPathKind::Direct => "p2p".to_owned(),
        ConnectionPathKind::Relay => "relay".to_owned(),
        ConnectionPathKind::Unknown => "unknown".to_owned(),
    }
}

pub(super) fn save_root_display(path: &std::path::Path) -> String {
    let file_name = path.file_name().and_then(|s| s.to_str());
    let parent_name = path
        .parent()
        .and_then(|parent| parent.file_name())
        .and_then(|s| s.to_str());
    if matches!(file_name, Some("Drift")) && matches!(parent_name, Some("Download" | "Downloads")) {
        return "Downloads".to_owned();
    }
    path.file_name()
        .and_then(|s| s.to_str())
        .map(String::from)
        .unwrap_or_else(|| path.display().to_string())
}

fn display_sender_label(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return "Sender".to_owned();
    }
    let normalized = trimmed
        .replace(['_', '-'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let lowercase = normalized.to_ascii_lowercase();
    if lowercase.is_empty()
        || lowercase == "unknown device"
        || lowercase == "unknown-device"
        || lowercase == "unknown"
    {
        return "Sender".to_owned();
    }
    normalized
}
