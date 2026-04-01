use std::time::Duration;

use anyhow::{Context, Result};
use drift_core::receiver::{
    ReceiveTransferPhase, ReceiveTransferProgress, receiver_finish_after_decision_with_progress,
    receiver_run_until_decision,
};
use drift_core::transfer::{ReceiverMachine, ReceiverState};
use drift_core::util::human_size;
use drift_core::wire::DeviceType;
use iroh::Endpoint;
use tokio::sync::{broadcast, mpsc, oneshot, watch};
use tokio::task::JoinHandle;
use tokio::time::{MissedTickBehavior, interval, sleep};

use crate::error::format_error_chain;
use crate::types::{
    ConflictPolicy, NearbyReceiver, PairingCodeState, ReceiverOfferEvent, ReceiverOfferFile,
    ReceiverOfferPhase, ReceiverRegistration,
};

use super::runtime::{OfferResolution, ReceiverRuntime};
use super::{OfferDecision, ReceiverEvent, ReceiverLifecycle, ReceiverSnapshot, parse_device_type};

const PENDING_OFFER_TIMEOUT: Duration = Duration::from_secs(120);

#[derive(Debug)]
pub(super) enum ReceiverCommand {
    Setup {
        server_url: Option<String>,
        reply: oneshot::Sender<Result<ReceiverRegistration>>,
    },
    EnsureRegistered {
        server_url: Option<String>,
        reply: oneshot::Sender<Result<ReceiverRegistration>>,
    },
    SetDiscoverable {
        enabled: bool,
        reply: oneshot::Sender<Result<()>>,
    },
    RespondToOffer {
        decision: OfferDecision,
        reply: oneshot::Sender<Result<()>>,
    },
    OfferPrepared {
        offer_id: u64,
        decision_tx: oneshot::Sender<OfferResolution>,
        watch_task: JoinHandle<()>,
        event: ReceiverOfferEvent,
    },
    OfferDisconnected {
        offer_id: u64,
        event: ReceiverOfferEvent,
    },
    OfferExpired {
        offer_id: u64,
        event: ReceiverOfferEvent,
    },
    OfferProgress {
        offer_id: u64,
        event: ReceiverOfferEvent,
    },
    OfferFinished {
        offer_id: u64,
        final_event: ReceiverOfferEvent,
    },
    ScanNearby {
        timeout: Duration,
        reply: oneshot::Sender<Result<Vec<NearbyReceiver>>>,
    },
    Shutdown {
        reply: oneshot::Sender<Result<()>>,
    },
}

pub(super) fn spawn_listener_task(
    endpoint: Endpoint,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
    out_dir: std::path::PathBuf,
    device_name: String,
    device_type: String,
    conflict_policy: ConflictPolicy,
) -> Result<JoinHandle<()>> {
    if matches!(conflict_policy, ConflictPolicy::Overwrite) {
        anyhow::bail!("receiver overwrite policy is not implemented yet");
    }
    let device_type = parse_device_type(&device_type)?;
    Ok(tokio::spawn(async move {
        run_listener_loop(endpoint, cmd_tx, out_dir, device_name, device_type).await;
    }))
}

pub(super) async fn run_receiver_actor(
    mut runtime: ReceiverRuntime,
    mut cmd_rx: mpsc::Receiver<ReceiverCommand>,
    state_tx: watch::Sender<ReceiverSnapshot>,
    pairing_tx: watch::Sender<PairingCodeState>,
    event_tx: broadcast::Sender<ReceiverEvent>,
) {
    let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
    let mut maintenance = interval(Duration::from_secs(15));
    maintenance.set_missed_tick_behavior(MissedTickBehavior::Delay);
    maintenance.tick().await;

    loop {
        tokio::select! {
            _ = maintenance.tick() => {
                if runtime.maintain_registration(&pairing_tx, &event_tx).await.is_err() {
                    let _ = pairing_tx.send(PairingCodeState::Unavailable);
                    let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    let _ = event_tx.send(ReceiverEvent::DiscoverabilityChanged {
                        requested: runtime.discoverable_requested,
                        active: runtime.advertising_active(),
                    });
                } else {
                    let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                }
            }
            maybe_command = cmd_rx.recv() => {
                let Some(command) = maybe_command else {
                    break;
                };
                match command {
                    ReceiverCommand::Setup { server_url, reply } => {
                        let result = runtime.handle_setup(server_url, &pairing_tx, &event_tx).await;
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::EnsureRegistered { server_url, reply } => {
                        let result = runtime.handle_ensure_registered(server_url, &pairing_tx, &event_tx).await;
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::SetDiscoverable { enabled, reply } => {
                        let was_active = runtime.advertising_active();
                        let result = runtime.set_discoverable(enabled);
                        runtime.publish_discoverability_change_if_needed(was_active, &event_tx);
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::RespondToOffer { decision, reply } => {
                        let result = runtime.respond_to_offer(decision);
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::OfferPrepared { offer_id, decision_tx, watch_task, event } => {
                        if runtime.handle_offer_prepared(offer_id, decision_tx, watch_task) {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(event));
                            let _ = runtime
                                .refresh_registration_after_offer(&pairing_tx, &event_tx)
                                .await;
                        }
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    }
                    ReceiverCommand::OfferDisconnected { offer_id, event } => {
                        if runtime.handle_offer_disconnected(offer_id) {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(event));
                        }
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    }
                    ReceiverCommand::OfferExpired { offer_id, event } => {
                        if runtime.handle_offer_expired(offer_id) {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(event));
                        }
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    }
                    ReceiverCommand::OfferProgress { offer_id, event } => {
                        if runtime.handle_offer_progress(offer_id) {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(event));
                        }
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    }
                    ReceiverCommand::OfferFinished { offer_id, final_event } => {
                        if runtime.handle_offer_finished(offer_id)
                            || matches!(final_event.phase, ReceiverOfferPhase::Failed)
                        {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(final_event));
                        }
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    }
                    ReceiverCommand::ScanNearby { timeout, reply } => {
                        let exclude = Some(runtime.endpoint_id());
                        let result = tokio::task::spawn_blocking(move || {
                            drift_core::lan::browse_nearby_receivers(timeout, exclude)
                        })
                        .await
                        .context("receiver v2 nearby scan task")
                        .and_then(|result| result.map_err(Into::into))
                        .map(|receivers| {
                            receivers
                                .into_iter()
                                .map(|receiver| NearbyReceiver {
                                    fullname: receiver.fullname,
                                    label: receiver.label,
                                    code: receiver.code,
                                    ticket: receiver.ticket,
                                })
                                .collect()
                        });
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::Shutdown { reply } => {
                        runtime.clear_advertising();
                        runtime.abort_listener();
                        runtime.close_endpoint().await;
                        let _ = pairing_tx.send(PairingCodeState::Unavailable);
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Stopped);
                        let _ = event_tx.send(ReceiverEvent::Shutdown);
                        let _ = reply.send(Ok(()));
                        break;
                    }
                }
            }
        }
    }
}

fn publish_snapshot(
    state_tx: &watch::Sender<ReceiverSnapshot>,
    runtime: &ReceiverRuntime,
    lifecycle: ReceiverLifecycle,
) -> Result<()> {
    state_tx
        .send(ReceiverSnapshot {
            lifecycle,
            discoverable_requested: runtime.discoverable_requested,
            advertising_active: runtime.advertising_active(),
            has_registration: runtime.has_registration(),
            has_pending_offer: runtime.has_pending_offer(),
        })
        .map_err(|_| anyhow::anyhow!("receiver v2 snapshot channel closed"))?;
    Ok(())
}

async fn run_listener_loop(
    endpoint: Endpoint,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
    out_dir: std::path::PathBuf,
    device_name: String,
    device_type: DeviceType,
) {
    let save_root_label = save_root_display(&out_dir);
    if let Err(err) = tokio::fs::create_dir_all(&out_dir).await {
        let _ = cmd_tx
            .send(ReceiverCommand::OfferFinished {
                offer_id: 0,
                final_event: ReceiverOfferEvent {
                    phase: ReceiverOfferPhase::Failed,
                    sender_name: String::new(),
                    sender_device_type: String::new(),
                    destination_label: String::new(),
                    save_root_label,
                    status_message: "Could not prepare save location.".to_owned(),
                    item_count: 0,
                    total_size_bytes: 0,
                    total_size_label: String::new(),
                    files: Vec::new(),
                    error_message: Some(err.to_string()),
                },
            })
            .await;
        return;
    }

    let mut next_offer_id = 1_u64;
    loop {
        let Some(incoming) = endpoint.accept().await else {
            tokio::time::sleep(Duration::from_millis(50)).await;
            continue;
        };
        let connection = match incoming.await {
            Ok(connection) => connection,
            Err(_) => continue,
        };
        let offer_id = next_offer_id;
        next_offer_id = next_offer_id.saturating_add(1);
        let cmd_tx_for_offer = cmd_tx.clone();
        let out_dir_for_offer = out_dir.clone();
        let device_name_for_offer = device_name.clone();
        let save_root_label_for_offer = save_root_label.clone();
        tokio::spawn(async move {
            handle_incoming_offer(
                offer_id,
                connection,
                out_dir_for_offer,
                device_name_for_offer,
                device_type,
                save_root_label_for_offer,
                cmd_tx_for_offer,
            )
            .await;
        });
    }
}

async fn handle_incoming_offer(
    offer_id: u64,
    connection: iroh::endpoint::Connection,
    out_dir: std::path::PathBuf,
    device_name: String,
    device_type: DeviceType,
    save_root_label: String,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
) {
    let mut machine = ReceiverMachine::new();
    let _ = machine.transition(ReceiverState::Discoverable);
    let _ = machine.transition(ReceiverState::Connecting);
    let _ = machine.transition(ReceiverState::Connected);

    let pending = match receiver_run_until_decision(
        connection,
        out_dir,
        &device_name,
        device_type,
        &mut machine,
    )
    .await
    {
        Ok(pending) => pending,
        Err(err) => {
            let _ = cmd_tx
                .send(ReceiverCommand::OfferFinished {
                    offer_id,
                    final_event: ReceiverOfferEvent {
                        phase: ReceiverOfferPhase::Failed,
                        sender_name: String::new(),
                        sender_device_type: String::new(),
                        destination_label: String::new(),
                        save_root_label,
                        status_message: "Transfer failed.".to_owned(),
                        item_count: 0,
                        total_size_bytes: 0,
                        total_size_label: String::new(),
                        files: Vec::new(),
                        error_message: Some(format_error_chain(&err)),
                    },
                })
                .await;
            return;
        }
    };

    let sender_label = display_sender_label(pending.sender_device_name());
    let sender_device_type = pending.sender_device_type();
    let manifest = pending.manifest().clone();
    let files = manifest
        .files
        .iter()
        .map(|file| ReceiverOfferFile {
            path: file.path.clone(),
            size: file.size,
        })
        .collect();
    let (decision_tx, decision_rx) = oneshot::channel();
    let watch_task = spawn_pending_offer_watch_task(
        offer_id,
        pending.connection().clone(),
        pending.sender_device_name().to_owned(),
        sender_device_type,
        sender_label.clone(),
        save_root_label.clone(),
        manifest.file_count,
        manifest.total_size,
        cmd_tx.clone(),
    );
    let prepared_event = ReceiverOfferEvent {
        phase: ReceiverOfferPhase::OfferReady,
        sender_name: pending.sender_device_name().to_owned(),
        sender_device_type: device_type_to_str(sender_device_type),
        destination_label: sender_label.clone(),
        save_root_label: save_root_label.clone(),
        status_message: format!("{sender_label} wants to send you files."),
        item_count: manifest.file_count,
        total_size_bytes: manifest.total_size,
        total_size_label: human_size(manifest.total_size),
        files,
        error_message: None,
    };
    if cmd_tx
        .send(ReceiverCommand::OfferPrepared {
            offer_id,
            decision_tx,
            watch_task,
            event: prepared_event,
        })
        .await
        .is_err()
    {
        return;
    }

    let approved = match decision_rx.await {
        Ok(OfferResolution::Accept) => true,
        Ok(OfferResolution::Decline) => false,
        Ok(OfferResolution::Cancel) | Err(_) => return,
    };
    let progress_cmd_tx = cmd_tx.clone();
    let mut progress_cb = |progress: ReceiveTransferProgress| {
        let _ = progress_cmd_tx.try_send(ReceiverCommand::OfferProgress {
            offer_id,
            event: map_receiver_offer_progress(&progress, &sender_label, &save_root_label),
        });
    };
    let final_event = match receiver_finish_after_decision_with_progress(
        pending,
        &mut machine,
        approved,
        &mut progress_cb,
    )
    .await
    {
        Ok(()) => ReceiverOfferEvent {
            phase: if approved {
                ReceiverOfferPhase::Completed
            } else {
                ReceiverOfferPhase::Declined
            },
            sender_name: String::new(),
            sender_device_type: device_type_to_str(sender_device_type),
            destination_label: sender_label,
            save_root_label,
            status_message: if approved {
                "Files saved.".to_owned()
            } else {
                "Transfer cancelled.".to_owned()
            },
            item_count: manifest.file_count,
            total_size_bytes: manifest.total_size,
            total_size_label: human_size(manifest.total_size),
            files: Vec::new(),
            error_message: None,
        },
        Err(err) => ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Failed,
            sender_name: String::new(),
            sender_device_type: device_type_to_str(sender_device_type),
            destination_label: sender_label,
            save_root_label,
            status_message: "Transfer failed.".to_owned(),
            item_count: manifest.file_count,
            total_size_bytes: manifest.total_size,
            total_size_label: human_size(manifest.total_size),
            files: Vec::new(),
            error_message: Some(format_error_chain(&err)),
        },
    };

    let _ = cmd_tx
        .send(ReceiverCommand::OfferFinished {
            offer_id,
            final_event,
        })
        .await;
}

fn spawn_pending_offer_watch_task(
    offer_id: u64,
    connection: iroh::endpoint::Connection,
    sender_name: String,
    sender_device_type: DeviceType,
    destination_label: String,
    save_root_label: String,
    item_count: u64,
    total_size_bytes: u64,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let disconnected_event = ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Failed,
            sender_name: sender_name.clone(),
            sender_device_type: device_type_to_str(sender_device_type),
            destination_label: destination_label.clone(),
            save_root_label: save_root_label.clone(),
            status_message: "Sender disconnected before you responded.".to_owned(),
            item_count,
            total_size_bytes,
            total_size_label: human_size(total_size_bytes),
            files: Vec::new(),
            error_message: Some("sender disconnected before approval".to_owned()),
        };
        let expired_event = ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Failed,
            sender_name,
            sender_device_type: device_type_to_str(sender_device_type),
            destination_label,
            save_root_label,
            status_message: "Offer expired before you responded.".to_owned(),
            item_count,
            total_size_bytes,
            total_size_label: human_size(total_size_bytes),
            files: Vec::new(),
            error_message: Some("offer timed out before approval".to_owned()),
        };

        tokio::select! {
            _ = connection.closed() => {
                let _ = cmd_tx.send(ReceiverCommand::OfferDisconnected { offer_id, event: disconnected_event }).await;
            }
            _ = sleep(PENDING_OFFER_TIMEOUT) => {
                let _ = cmd_tx.send(ReceiverCommand::OfferExpired { offer_id, event: expired_event }).await;
            }
        }
    })
}

fn map_receiver_offer_progress(
    progress: &ReceiveTransferProgress,
    sender_label: &str,
    save_root_label: &str,
) -> ReceiverOfferEvent {
    let phase = match progress.phase {
        ReceiveTransferPhase::WaitingForDecision => ReceiverOfferPhase::Receiving,
        ReceiveTransferPhase::Receiving => ReceiverOfferPhase::Receiving,
        ReceiveTransferPhase::Completed => ReceiverOfferPhase::Completed,
        ReceiveTransferPhase::Declined => ReceiverOfferPhase::Declined,
        ReceiveTransferPhase::Failed => ReceiverOfferPhase::Failed,
    };
    let total_size_bytes = match progress.phase {
        ReceiveTransferPhase::Receiving => progress.bytes_received,
        _ => progress.total_bytes,
    };
    ReceiverOfferEvent {
        phase,
        sender_name: progress.sender_device_name.clone(),
        sender_device_type: device_type_to_str(progress.sender_device_type),
        destination_label: sender_label.to_owned(),
        save_root_label: save_root_label.to_owned(),
        status_message: match progress.phase {
            ReceiveTransferPhase::WaitingForDecision | ReceiveTransferPhase::Receiving => {
                "Receiving files…".to_owned()
            }
            ReceiveTransferPhase::Completed => "Files saved.".to_owned(),
            ReceiveTransferPhase::Declined => "Transfer cancelled.".to_owned(),
            ReceiveTransferPhase::Failed => "Transfer failed.".to_owned(),
        },
        item_count: progress.file_count,
        total_size_bytes,
        total_size_label: human_size(total_size_bytes),
        files: Vec::new(),
        error_message: progress.error_message.clone(),
    }
}

fn device_type_to_str(value: DeviceType) -> String {
    match value {
        DeviceType::Phone => "phone".to_owned(),
        DeviceType::Laptop => "laptop".to_owned(),
    }
}

fn save_root_display(path: &std::path::Path) -> String {
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
