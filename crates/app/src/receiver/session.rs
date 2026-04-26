use std::time::Duration;

use drift_core::protocol::DeviceType;
use drift_core::transfer::{
    ReceiverDecision as CoreReceiverDecision, ReceiverEvent as CoreReceiverEvent,
    ReceiverRequest as CoreReceiverRequest, ReceiverSession as CoreReceiverSession,
    ReceiverStart as CoreReceiverStart, TransferOutcome as CoreTransferOutcome, TransferPhase,
    TransferPlan, TransferPlanFile, TransferSnapshot,
};
use drift_core::util::{ConnectionPathKind, classify_connection_path, human_size};
use iroh::Endpoint;
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;
use tokio_stream::StreamExt;

use crate::error::{UserFacingError, UserFacingErrorKind, format_error_chain};
use crate::types::{ConflictPolicy, ReceiverOfferEvent, ReceiverOfferFile, ReceiverOfferPhase};

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
    conflict_policy: ConflictPolicy,
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
        conflict_policy: ConflictPolicy,
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
            conflict_policy,
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
            conflict_policy,
            save_root_label,
            cmd_tx,
        } = self;

        let connection_path_kind =
            classify_connection_path(&endpoint, connection.remote_id()).await;
        let session = CoreReceiverSession::new(build_core_receiver_request(
            device_name.clone(),
            device_type,
            out_dir,
            conflict_policy,
        ));
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
                            String::new(),
                            device_type,
                            "Transfer failed.".to_owned(),
                            UserFacingError::from(error),
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
                            String::new(),
                            device_type,
                            "Transfer failed.".to_owned(),
                            UserFacingError::internal("Transfer failed", format!("{error}")),
                        ),
                    })
                    .await;
                return;
            }
        };

        let sender_label = display_sender_label(&offer.sender_device_name);
        let sender_device_type = offer.sender_device_type;
        let resume_from_bytes = offer.resume_from_bytes;
        let plan = match TransferPlan::try_new(
            offer.session_id.clone(),
            offer
                .items
                .iter()
                .enumerate()
                .map(|(index, file)| TransferPlanFile {
                    id: index as u32,
                    path: file.path.clone(),
                    size: file.size,
                })
                .collect(),
        ) {
            Ok(plan) => plan,
            Err(error) => {
                let _ = cmd_tx
                    .send(ReceiverCommand::OfferFinished {
                        offer_id,
                        final_event: failed_offer_event(
                            &save_root_label,
                            sender_label.clone(),
                            sender_device_type,
                            "Transfer failed.".to_owned(),
                            UserFacingError::internal(
                                "Transfer failed",
                                format_error_chain(&error),
                            ),
                        ),
                    })
                    .await;
                return;
            }
        };
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
                OfferResolution::Decline | OfferResolution::Cancel => CoreReceiverDecision::Decline,
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
            bytes_received: resume_from_bytes,
            plan: Some(plan.clone()),
            snapshot: None,
            connection_path: Some(connection_path_label(connection_path_kind)),
            total_size_label: human_size(offer.total_size),
            files,
            error: None,
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
        let mut last_progress_bytes = resume_from_bytes;
        while let Some(event) = events.next().await {
            match event {
                CoreReceiverEvent::TransferStarted {
                    session_id: _,
                    plan,
                } => {
                    let _ = progress_cmd_tx.try_send(ReceiverCommand::OfferProgress {
                        offer_id,
                        event: build_offer_event(
                            ReceiverOfferPhase::Receiving,
                            sender_label.clone(),
                            save_root_label.clone(),
                            sender_device_type,
                            connection_path_kind,
                            plan.total_files as u64,
                            plan.total_bytes,
                            resume_from_bytes,
                            Some(plan.clone()),
                            None,
                            Vec::new(),
                            None,
                        ),
                    });
                }
                CoreReceiverEvent::TransferProgress {
                    session_id: _,
                    snapshot,
                } => {
                    let now = std::time::Instant::now();
                    let interval_elapsed =
                        now.duration_since(last_progress_emit_at) >= PROGRESS_EVENT_MIN_INTERVAL;
                    let bytes_advanced = snapshot
                        .bytes_transferred
                        .saturating_sub(last_progress_bytes)
                        >= PROGRESS_EVENT_MIN_BYTES;
                    let phase_changed = matches!(snapshot.phase, TransferPhase::Finalizing)
                        || matches!(snapshot.phase, TransferPhase::Completed);
                    let is_complete = snapshot.total_bytes > 0
                        && snapshot.bytes_transferred >= snapshot.total_bytes;
                    if interval_elapsed || bytes_advanced || is_complete || phase_changed {
                        last_progress_emit_at = now;
                        last_progress_bytes = snapshot.bytes_transferred;
                        let _ = progress_cmd_tx.try_send(ReceiverCommand::OfferProgress {
                            offer_id,
                            event: build_offer_event(
                                ReceiverOfferPhase::Receiving,
                                sender_label.clone(),
                                save_root_label.clone(),
                                sender_device_type,
                                connection_path_kind,
                                snapshot.total_files as u64,
                                snapshot.total_bytes,
                                snapshot.bytes_transferred,
                                Some(plan.clone()),
                                Some(snapshot.clone()),
                                Vec::new(),
                                None,
                            ),
                        });
                    }
                }
                CoreReceiverEvent::Listening { .. } => {}
                CoreReceiverEvent::TransferCompleted { .. } => {
                    break;
                }
                CoreReceiverEvent::Completed { .. } => {
                    break;
                }
                CoreReceiverEvent::Failed { error, .. } => {
                    let _ = progress_cmd_tx.try_send(ReceiverCommand::OfferFinished {
                        offer_id,
                        final_event: failed_offer_event(
                            &save_root_label,
                            sender_label.clone(),
                            sender_device_type,
                            "Transfer failed.".to_owned(),
                            UserFacingError::from(error),
                        ),
                    });
                    return;
                }
                CoreReceiverEvent::OfferReceived { .. } => {}
            }
        }

        let final_event = match outcome_rx.await {
            Ok(Ok(outcome)) => match outcome {
                CoreTransferOutcome::Completed => completed_offer_event(
                    sender_label,
                    save_root_label,
                    sender_device_type,
                    connection_path_kind,
                    offer.session_id.clone(),
                    offer.file_count,
                    offer.total_size,
                    plan.clone(),
                ),
                CoreTransferOutcome::Declined { .. } => ReceiverOfferEvent {
                    phase: ReceiverOfferPhase::Declined,
                    sender_name: sender_label.clone(),
                    sender_device_type: device_type_to_str(sender_device_type),
                    destination_label: sender_label,
                    save_root_label,
                    status_message: "Transfer cancelled.".to_owned(),
                    item_count: offer.file_count,
                    total_size_bytes: offer.total_size,
                    bytes_received: 0,
                    plan: Some(plan.clone()),
                    snapshot: None,
                    connection_path: Some(connection_path_label(connection_path_kind)),
                    total_size_label: human_size(offer.total_size),
                    files: Vec::new(),
                    error: None,
                },
                CoreTransferOutcome::Cancelled(cancellation) => ReceiverOfferEvent {
                    phase: ReceiverOfferPhase::Cancelled,
                    sender_name: sender_label.clone(),
                    sender_device_type: device_type_to_str(sender_device_type),
                    destination_label: sender_label,
                    save_root_label,
                    status_message: "Transfer cancelled.".to_owned(),
                    item_count: offer.file_count,
                    total_size_bytes: offer.total_size,
                    bytes_received: last_progress_bytes,
                    plan: Some(plan.clone()),
                    snapshot: None,
                    connection_path: Some(connection_path_label(connection_path_kind)),
                    total_size_label: human_size(offer.total_size),
                    files: Vec::new(),
                    error: Some(UserFacingError::new(
                        UserFacingErrorKind::Cancelled,
                        "Transfer cancelled",
                        cancellation.reason,
                    )),
                },
            },
            Ok(Err(error)) => failed_offer_event(
                &save_root_label,
                sender_label,
                sender_device_type,
                "Transfer failed.".to_owned(),
                UserFacingError::from(error),
            ),
            Err(error) => failed_offer_event(
                &save_root_label,
                sender_label,
                sender_device_type,
                "Transfer failed.".to_owned(),
                UserFacingError::internal("Transfer failed", format!("{error}")),
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

fn build_core_receiver_request(
    device_name: String,
    device_type: DeviceType,
    out_dir: std::path::PathBuf,
    conflict_policy: ConflictPolicy,
) -> CoreReceiverRequest {
    CoreReceiverRequest {
        device_name,
        device_type,
        out_dir,
        conflict_policy,
    }
}

fn completed_offer_event(
    sender_name: String,
    save_root_label: String,
    sender_device_type: DeviceType,
    connection_path_kind: ConnectionPathKind,
    session_id: String,
    item_count: u64,
    total_size: u64,
    plan: TransferPlan,
) -> ReceiverOfferEvent {
    ReceiverOfferEvent {
        phase: ReceiverOfferPhase::Completed,
        sender_name: sender_name.clone(),
        sender_device_type: device_type_to_str(sender_device_type),
        destination_label: save_root_label.clone(),
        save_root_label,
        status_message: "Files saved.".to_owned(),
        item_count,
        total_size_bytes: total_size,
        bytes_received: total_size,
        plan: Some(plan.clone()),
        snapshot: Some(TransferSnapshot {
            session_id,
            phase: TransferPhase::Completed,
            total_files: plan.total_files,
            completed_files: plan.total_files,
            total_bytes: plan.total_bytes,
            bytes_transferred: total_size,
            active_file_id: None,
            active_file_bytes: None,
            bytes_per_sec: None,
            eta_seconds: None,
        }),
        connection_path: Some(connection_path_label(connection_path_kind)),
        total_size_label: human_size(total_size),
        files: Vec::new(),
        error: None,
    }
}

fn build_offer_event(
    phase: ReceiverOfferPhase,
    sender_label: String,
    save_root_label: String,
    sender_device_type: DeviceType,
    connection_path_kind: ConnectionPathKind,
    file_count: u64,
    total_bytes: u64,
    bytes_received: u64,
    plan: Option<TransferPlan>,
    snapshot: Option<TransferSnapshot>,
    files: Vec<ReceiverOfferFile>,
    error: Option<UserFacingError>,
) -> ReceiverOfferEvent {
    ReceiverOfferEvent {
        phase,
        sender_name: sender_label.clone(),
        sender_device_type: device_type_to_str(sender_device_type),
        destination_label: sender_label,
        save_root_label,
        status_message: match phase {
            ReceiverOfferPhase::OfferReady => "Offer ready.".to_owned(),
            ReceiverOfferPhase::Receiving => "Receiving files…".to_owned(),
            ReceiverOfferPhase::Completed => "Files saved.".to_owned(),
            ReceiverOfferPhase::Cancelled => "Transfer cancelled.".to_owned(),
            ReceiverOfferPhase::Failed => "Transfer failed.".to_owned(),
            ReceiverOfferPhase::Declined => "Transfer declined.".to_owned(),
            ReceiverOfferPhase::Connecting => "Connecting...".to_owned(),
        },
        item_count: file_count,
        total_size_bytes: total_bytes,
        bytes_received,
        plan,
        snapshot,
        connection_path: Some(connection_path_label(connection_path_kind)),
        total_size_label: human_size(total_bytes),
        files,
        error,
    }
}

fn failed_offer_event(
    save_root_label: &str,
    sender_name: String,
    sender_device_type: DeviceType,
    status_message: String,
    error: UserFacingError,
) -> ReceiverOfferEvent {
    ReceiverOfferEvent {
        phase: ReceiverOfferPhase::Failed,
        sender_name,
        sender_device_type: device_type_to_str(sender_device_type),
        destination_label: String::new(),
        save_root_label: save_root_label.to_owned(),
        status_message,
        item_count: 0,
        total_size_bytes: 0,
        bytes_received: 0,
        plan: None,
        snapshot: None,
        connection_path: None,
        total_size_label: String::new(),
        files: Vec::new(),
        error: Some(error),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        build_core_receiver_request, build_offer_event, completed_offer_event,
        connection_path_label, failed_offer_event,
    };
    use crate::error::UserFacingErrorKind;
    use crate::types::ConflictPolicy;
    use drift_core::protocol::DeviceType;
    use drift_core::transfer::TransferPlan;
    use drift_core::util::ConnectionPathKind;

    #[test]
    fn core_receiver_request_preserves_configured_conflict_policy() {
        let request = build_core_receiver_request(
            "Receiver".to_owned(),
            DeviceType::Laptop,
            std::path::PathBuf::from("downloads"),
            ConflictPolicy::Reject,
        );

        assert_eq!(request.conflict_policy, ConflictPolicy::Reject);
    }

    #[test]
    fn failed_offer_event_uses_structured_error() {
        let event = failed_offer_event(
            "Downloads",
            "Maya".to_owned(),
            DeviceType::Laptop,
            "Transfer failed.".to_owned(),
            crate::error::UserFacingError::internal("Transfer failed", "boom"),
        );

        assert_eq!(event.sender_name, "Maya");
        let error = event.error.expect("structured error");
        assert_eq!(error.kind(), UserFacingErrorKind::Internal);
        assert_eq!(error.title(), "Transfer failed");
        assert_eq!(error.message(), "boom");
    }

    #[test]
    fn build_offer_event_can_carry_structured_error() {
        let event = build_offer_event(
            super::ReceiverOfferPhase::Failed,
            "Sender".to_owned(),
            "Downloads".to_owned(),
            DeviceType::Laptop,
            ConnectionPathKind::Direct,
            0,
            0,
            0,
            None,
            None,
            Vec::new(),
            Some(crate::error::UserFacingError::internal(
                "Transfer failed",
                "boom",
            )),
        );

        assert_eq!(
            event.connection_path.as_deref(),
            Some(connection_path_label(ConnectionPathKind::Direct).as_str())
        );
        assert_eq!(
            event.error.as_ref().map(|error| error.kind()),
            Some(UserFacingErrorKind::Internal)
        );
    }

    #[test]
    fn completed_offer_event_uses_save_root_as_destination_label() {
        let plan = TransferPlan::try_new(
            "session-1",
            vec![drift_core::transfer::TransferPlanFile {
                id: 0,
                path: "report.pdf".to_owned(),
                size: 1024,
            }],
        )
        .expect("plan");

        let event = completed_offer_event(
            "Maya".to_owned(),
            "Downloads".to_owned(),
            DeviceType::Laptop,
            ConnectionPathKind::Direct,
            "session-1".to_owned(),
            1,
            1024,
            plan,
        );

        assert_eq!(event.destination_label, "Downloads");
        assert_eq!(event.save_root_label, "Downloads");
        assert_eq!(event.sender_name, "Maya");
        assert_eq!(event.phase, super::ReceiverOfferPhase::Completed);
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
