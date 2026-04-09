use std::time::Duration;

use drift_core::protocol::DeviceType;
use iroh::Endpoint;
use tokio::sync::{broadcast, mpsc, oneshot, watch};
use tokio::task::JoinHandle;
use tokio::time::{MissedTickBehavior, interval};

use crate::error::{AppError, AppResult, UserFacingError};
use crate::types::{
    ConflictPolicy, NearbyReceiver, PairingCodeState, ReceiverOfferEvent, ReceiverOfferPhase,
    ReceiverRegistration,
};

use super::runtime::ReceiverRuntime;
use super::session::ReceiverSession;
use super::{OfferDecision, ReceiverEvent, ReceiverLifecycle, ReceiverSnapshot, parse_device_type};

#[derive(Debug)]
pub(super) enum ReceiverCommand {
    Setup {
        server_url: Option<String>,
        reply: oneshot::Sender<AppResult<ReceiverRegistration>>,
    },
    EnsureRegistered {
        server_url: Option<String>,
        reply: oneshot::Sender<AppResult<ReceiverRegistration>>,
    },
    SetDiscoverable {
        enabled: bool,
        reply: oneshot::Sender<AppResult<()>>,
    },
    RespondToOffer {
        decision: OfferDecision,
        reply: oneshot::Sender<AppResult<()>>,
    },
    CancelTransfer {
        reply: oneshot::Sender<AppResult<()>>,
    },
    OfferPrepared {
        run: super::session::ReceiverRun,
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
        reply: oneshot::Sender<AppResult<Vec<NearbyReceiver>>>,
    },
    Shutdown {
        reply: oneshot::Sender<AppResult<()>>,
    },
}

pub(super) fn spawn_listener_task(
    endpoint: Endpoint,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
    out_dir: std::path::PathBuf,
    device_name: String,
    device_type: String,
    conflict_policy: ConflictPolicy,
) -> AppResult<JoinHandle<()>> {
    if matches!(conflict_policy, ConflictPolicy::Overwrite) {
        return Err(AppError::UnsupportedLocalOperation {
            operation: "receiver overwrite policy",
        });
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
                        let result = runtime.set_discoverable(enabled).await;
                        runtime.publish_discoverability_change_if_needed(was_active, &event_tx);
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::RespondToOffer { decision, reply } => {
                        let result = runtime.respond_to_offer(decision);
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::CancelTransfer { reply } => {
                        let result = runtime.cancel_active_transfer();
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                        let _ = reply.send(result);
                    }
                    ReceiverCommand::OfferPrepared { run, event } => {
                        if runtime.handle_offer_prepared(run) {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(event));
                            let _ = runtime
                                .refresh_registration_after_offer(&pairing_tx, &event_tx)
                                .await;
                        }
                        let _ = publish_snapshot(&state_tx, &runtime, ReceiverLifecycle::Ready);
                    }
                    ReceiverCommand::OfferProgress { offer_id, event } => {
                        if runtime.handle_offer_progress(offer_id) {
                            let _ = event_tx.send(ReceiverEvent::OfferUpdated(event));
                        }
                    }
                    ReceiverCommand::OfferFinished { offer_id, final_event } => {
                        if runtime.handle_offer_finished(offer_id)
                            || matches!(
                                final_event.phase,
                                ReceiverOfferPhase::Failed | ReceiverOfferPhase::Declined
                            )
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
                        .map_err(|e| AppError::Internal {
                            message: format!("receiver v2 nearby scan task: {e}"),
                        })
                        .and_then(|result| {
                            result.map_err(|e| AppError::Internal {
                                message: format!("receiver v2 nearby scan error: {e}"),
                            })
                        })
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
) -> AppResult<()> {
    state_tx
        .send(ReceiverSnapshot {
            lifecycle,
            discoverable_requested: runtime.discoverable_requested,
            advertising_active: runtime.advertising_active(),
            has_registration: runtime.has_registration(),
            has_pending_offer: runtime.has_pending_offer(),
        })
        .map_err(|_| AppError::SnapshotChannelClosed)?;
    Ok(())
}

async fn run_listener_loop(
    endpoint: Endpoint,
    cmd_tx: mpsc::Sender<ReceiverCommand>,
    out_dir: std::path::PathBuf,
    device_name: String,
    device_type: DeviceType,
) {
    let save_root_label = super::session::save_root_display(&out_dir);
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
                    bytes_received: 0,
                    plan: None,
                    snapshot: None,
                    connection_path: None,
                    total_size_label: String::new(),
                    files: Vec::new(),
                    error: Some(UserFacingError::internal(
                        "Receiver unavailable",
                        err.to_string(),
                    )),
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
        let endpoint_for_offer = endpoint.clone();
        let session = ReceiverSession::new(
            offer_id,
            endpoint_for_offer,
            connection,
            out_dir_for_offer,
            device_name_for_offer,
            device_type,
            cmd_tx_for_offer,
        );
        let _ = session.spawn();
    }
}
