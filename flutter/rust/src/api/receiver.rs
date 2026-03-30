use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use drift_core::receiver::{receiver_finish_after_decision, receiver_run_until_decision};
use drift_core::rendezvous::{resolve_server_url, RegisterPeerResponse, RendezvousClient};
use drift_core::session::bind_endpoint;
use drift_core::transfer::{ReceiverMachine, ReceiverState};
use drift_core::util::human_size;
use drift_core::wire::{make_ticket_now, DeviceType};
use iroh::Endpoint;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use tokio::sync::oneshot;

use super::RUNTIME;
use crate::frb_generated::StreamSink;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";

static IDLE_RECEIVER: Mutex<Option<IdleReceiver>> = Mutex::new(None);
static IDLE_INCOMING_DECISION: Mutex<Option<oneshot::Sender<bool>>> = Mutex::new(None);
static IDLE_INCOMING_STARTED: OnceLock<()> = OnceLock::new();

struct IdleReceiver {
    endpoint: Endpoint,
    server_url: String,
    registration: RegisterPeerResponse,
}

#[derive(Debug, Clone)]
pub struct IdleReceiverRegistration {
    pub code: String,
    pub expires_at: String,
}

#[derive(Clone, Debug)]
pub enum IdleIncomingPhase {
    Connecting,
    OfferReady,
    Receiving,
    Completed,
    Failed,
    Declined,
}

#[derive(Clone, Debug)]
pub struct IdleIncomingFileRow {
    pub path: String,
    pub size: u64,
}

#[derive(Clone, Debug)]
pub struct IdleIncomingEvent {
    pub phase: IdleIncomingPhase,
    pub sender_name: String,
    pub destination_label: String,
    pub save_root_label: String,
    pub status_message: String,
    pub item_count: u64,
    pub total_size_bytes: u64,
    pub total_size_label: String,
    pub files: Vec<IdleIncomingFileRow>,
    pub error_message: Option<String>,
}

pub fn register_idle_receiver(
    server_url: Option<String>,
) -> Result<IdleReceiverRegistration, String> {
    RUNTIME.block_on(async move {
        let resolved_url = resolve_server_url(server_url.as_deref().or(Some(LOCAL_RENDEZVOUS_URL)));
        log(&format!("registering idle receiver against {resolved_url}"));
        replace_idle_receiver(register_new_idle_receiver(resolved_url).await).await
    })
}

pub fn ensure_idle_receiver(
    server_url: Option<String>,
) -> Result<IdleReceiverRegistration, String> {
    RUNTIME.block_on(async move {
        let resolved_url = resolve_server_url(server_url.as_deref().or(Some(LOCAL_RENDEZVOUS_URL)));
        log(&format!("ensuring idle receiver against {resolved_url}"));

        // Never call `take_idle_receiver` unless we are replacing the endpoint.
        // Taking first used to leave `IDLE_RECEIVER` empty during async work so the
        // incoming listener had no endpoint to `accept()` on — CLI sends then time out.
        let snapshot: Option<(String, RegisterPeerResponse)> = {
            let guard = IDLE_RECEIVER.lock().map_err(|e| e.to_string())?;
            guard
                .as_ref()
                .map(|r| (r.server_url.clone(), r.registration.clone()))
        };

        match snapshot {
            None => {
                replace_idle_receiver(register_new_idle_receiver(resolved_url).await).await
            }
            Some((stored_url, registration)) => {
                if stored_url != resolved_url {
                    if let Some(old) = take_idle_receiver()? {
                        old.endpoint.close().await;
                    }
                    replace_idle_receiver(register_new_idle_receiver(resolved_url).await).await
                } else if is_expired(&registration)? {
                    if let Some(old) = take_idle_receiver()? {
                        old.endpoint.close().await;
                    }
                    replace_idle_receiver(register_new_idle_receiver(resolved_url).await).await
                } else {
                    match RendezvousClient::new(stored_url.clone())
                        .pair_status(&registration.code)
                        .await
                        .map_err(|err| err.to_string())?
                    {
                        Some(_) => {
                            log(&format!(
                                "reusing idle receiver code {} on {}",
                                registration.code, stored_url
                            ));
                            Ok(IdleReceiverRegistration {
                                code: registration.code.clone(),
                                expires_at: registration.expires_at.clone(),
                            })
                        }
                        None => {
                            if let Some(old) = take_idle_receiver()? {
                                old.endpoint.close().await;
                            }
                            replace_idle_receiver(register_new_idle_receiver(resolved_url).await)
                                .await
                        }
                    }
                }
            }
        }
    })
}

pub fn current_idle_receiver_registration() -> Option<IdleReceiverRegistration> {
    IDLE_RECEIVER.lock().ok().and_then(|state| {
        state.as_ref().map(|receiver| IdleReceiverRegistration {
            code: receiver.registration.code.clone(),
            expires_at: receiver.registration.expires_at.clone(),
        })
    })
}

/// Spawns a background task that accepts incoming connections on the idle receiver endpoint
/// and streams [IdleIncomingEvent] updates. Safe to call once; later calls are no-ops.
pub fn start_idle_incoming_listener(
    download_root: String,
    device_name: String,
    device_type: String,
    updates: StreamSink<IdleIncomingEvent>,
) -> Result<(), String> {
    if IDLE_INCOMING_STARTED.set(()).is_err() {
        return Ok(());
    }

    let device_type = parse_device_type(&device_type)?;

    RUNTIME.spawn(async move {
        run_idle_incoming_loop(
            PathBuf::from(download_root),
            device_name,
            device_type,
            updates,
        )
        .await;
    });

    Ok(())
}

/// Completes the pending offer decision from the UI. Call after [IdleIncomingPhase::OfferReady].
pub fn respond_idle_incoming_offer(accept: bool) -> Result<(), String> {
    let mut guard = IDLE_INCOMING_DECISION
        .lock()
        .map_err(|_| "incoming decision mutex poisoned".to_owned())?;
    let Some(tx) = guard.take() else {
        return Err("no incoming offer is waiting for a decision".to_owned());
    };
    tx.send(accept)
        .map_err(|_| "failed to send decision (listener may have stopped)".to_owned())?;
    Ok(())
}

async fn run_idle_incoming_loop(
    out_dir: PathBuf,
    device_name: String,
    device_type: DeviceType,
    updates: StreamSink<IdleIncomingEvent>,
) {
    let save_root_label = save_root_display(&out_dir);

    if let Err(err) = tokio::fs::create_dir_all(&out_dir).await {
        log(&format!("create download root: {err}"));
        let _ = updates.add(IdleIncomingEvent {
            phase: IdleIncomingPhase::Failed,
            sender_name: String::new(),
            destination_label: String::new(),
            save_root_label: save_root_label.clone(),
            status_message: "Could not prepare save location.".to_owned(),
            item_count: 0,
            total_size_bytes: 0,
            total_size_label: String::new(),
            files: Vec::new(),
            error_message: Some(err.to_string()),
        });
        return;
    }

    loop {
        let endpoint = IDLE_RECEIVER
            .lock()
            .ok()
            .and_then(|g| g.as_ref().map(|r| r.endpoint.clone()));

        let Some(endpoint) = endpoint else {
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            continue;
        };

        let _ = updates.add(IdleIncomingEvent {
            phase: IdleIncomingPhase::Connecting,
            sender_name: String::new(),
            destination_label: String::new(),
            save_root_label: save_root_label.clone(),
            status_message: "Connecting…".to_owned(),
            item_count: 0,
            total_size_bytes: 0,
            total_size_label: String::new(),
            files: Vec::new(),
            error_message: None,
        });

        let Some(incoming) = endpoint.accept().await else {
            // Registration refresh closes or replaces the endpoint while we are waiting on
            // `accept()`. Exiting the loop would leave no listener — later sends claim a new
            // code but nothing accepts. Rejoin the loop and pick up the current endpoint.
            log("idle endpoint accept closed (replaced or shut down); resuming listen loop");
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
            continue;
        };

        let mut machine = ReceiverMachine::new();
        if machine.transition(ReceiverState::Discoverable).is_err() {
            log("receiver machine: failed to enter discoverable");
            continue;
        }

        if machine.transition(ReceiverState::Connecting).is_err() {
            log("receiver machine: failed to enter connecting");
            continue;
        }

        let connection = match incoming.await {
            Ok(c) => c,
            Err(err) => {
                log(&format!("incoming handshake failed: {err}"));
                let _ = updates.add(IdleIncomingEvent {
                    phase: IdleIncomingPhase::Failed,
                    sender_name: String::new(),
                    destination_label: String::new(),
                    save_root_label: save_root_label.clone(),
                    status_message: "Connection failed.".to_owned(),
                    item_count: 0,
                    total_size_bytes: 0,
                    total_size_label: String::new(),
                    files: Vec::new(),
                    error_message: Some(err.to_string()),
                });
                continue;
            }
        };

        if machine.transition(ReceiverState::Connected).is_err() {
            log("receiver machine: failed to enter connected");
            continue;
        }

        let pending = match receiver_run_until_decision(
            connection,
            out_dir.clone(),
            &device_name,
            device_type,
            &mut machine,
        )
        .await
        {
            Ok(p) => p,
            Err(err) => {
                let msg = format_error_chain(&err);
                log(&format!("receiver negotiation failed: {msg}"));
                let _ = updates.add(IdleIncomingEvent {
                    phase: IdleIncomingPhase::Failed,
                    sender_name: String::new(),
                    destination_label: String::new(),
                    save_root_label: save_root_label.clone(),
                    status_message: "Transfer failed.".to_owned(),
                    item_count: 0,
                    total_size_bytes: 0,
                    total_size_label: String::new(),
                    files: Vec::new(),
                    error_message: Some(msg),
                });
                continue;
            }
        };

        let sender_label = display_sender_label(pending.sender_device_name());
        let manifest = pending.manifest().clone();
        let files: Vec<IdleIncomingFileRow> = manifest
            .files
            .iter()
            .map(|f| IdleIncomingFileRow {
                path: f.path.clone(),
                size: f.size,
            })
            .collect();

        let _ = updates.add(IdleIncomingEvent {
            phase: IdleIncomingPhase::OfferReady,
            sender_name: pending.sender_device_name().to_owned(),
            destination_label: sender_label.clone(),
            save_root_label: save_root_label.clone(),
            status_message: format!("{sender_label} wants to send you files."),
            item_count: manifest.file_count,
            total_size_bytes: manifest.total_size,
            total_size_label: human_size(manifest.total_size),
            files,
            error_message: None,
        });

        let (tx, rx) = oneshot::channel();
        {
            let mut g = IDLE_INCOMING_DECISION
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            *g = Some(tx);
        }

        let approved = rx.await.unwrap_or(false);

        {
            let mut g = IDLE_INCOMING_DECISION
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            *g = None;
        }

        if !approved {
            let _ = receiver_finish_after_decision(pending, &mut machine, false).await;
            let _ = updates.add(IdleIncomingEvent {
                phase: IdleIncomingPhase::Declined,
                sender_name: String::new(),
                destination_label: sender_label.clone(),
                save_root_label: save_root_label.clone(),
                status_message: "Transfer cancelled.".to_owned(),
                item_count: manifest.file_count,
                total_size_bytes: manifest.total_size,
                total_size_label: human_size(manifest.total_size),
                files: Vec::new(),
                error_message: None,
            });
            continue;
        }

        let _ = updates.add(IdleIncomingEvent {
            phase: IdleIncomingPhase::Receiving,
            sender_name: pending.sender_device_name().to_owned(),
            destination_label: sender_label.clone(),
            save_root_label: save_root_label.clone(),
            status_message: "Receiving files…".to_owned(),
            item_count: manifest.file_count,
            total_size_bytes: manifest.total_size,
            total_size_label: human_size(manifest.total_size),
            files: Vec::new(),
            error_message: None,
        });

        match receiver_finish_after_decision(pending, &mut machine, true).await {
            Ok(()) => {
                let _ = updates.add(IdleIncomingEvent {
                    phase: IdleIncomingPhase::Completed,
                    sender_name: String::new(),
                    destination_label: sender_label,
                    save_root_label: save_root_label.clone(),
                    status_message: "Files saved.".to_owned(),
                    item_count: manifest.file_count,
                    total_size_bytes: manifest.total_size,
                    total_size_label: human_size(manifest.total_size),
                    files: Vec::new(),
                    error_message: None,
                });
            }
            Err(err) => {
                let msg = format_error_chain(&err);
                log(&format!("receive payload failed: {msg}"));
                let _ = updates.add(IdleIncomingEvent {
                    phase: IdleIncomingPhase::Failed,
                    sender_name: String::new(),
                    destination_label: String::new(),
                    save_root_label: save_root_label.clone(),
                    status_message: "Transfer failed.".to_owned(),
                    item_count: manifest.file_count,
                    total_size_bytes: manifest.total_size,
                    total_size_label: human_size(manifest.total_size),
                    files: Vec::new(),
                    error_message: Some(msg),
                });
            }
        }
    }
}

fn save_root_display(path: &Path) -> String {
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

fn parse_device_type(value: &str) -> Result<DeviceType, String> {
    match value.trim().to_ascii_lowercase().as_str() {
        "phone" => Ok(DeviceType::Phone),
        "laptop" => Ok(DeviceType::Laptop),
        other => Err(format!(
            "invalid device_type {other:?} (expected \"phone\" or \"laptop\")"
        )),
    }
}

fn format_error_chain(error: &anyhow::Error) -> String {
    error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ")
}

async fn register_new_idle_receiver(server_url: String) -> Result<IdleReceiver, String> {
    let endpoint = bind_endpoint().await.map_err(|err| err.to_string())?;
    let ticket = make_ticket_now(&endpoint).map_err(|err| err.to_string())?;
    let registration = RendezvousClient::new(server_url.clone())
        .register_peer(ticket)
        .await
        .map_err(|err| err.to_string())?;
    log(&format!(
        "registered idle receiver code {} on {}",
        registration.code, server_url
    ));

    Ok(IdleReceiver {
        endpoint,
        server_url,
        registration,
    })
}

fn take_idle_receiver() -> Result<Option<IdleReceiver>, String> {
    let mut state = IDLE_RECEIVER.lock().map_err(|err| err.to_string())?;
    Ok(state.take())
}

async fn replace_idle_receiver(
    receiver: Result<IdleReceiver, String>,
) -> Result<IdleReceiverRegistration, String> {
    let receiver = receiver?;
    let response = IdleReceiverRegistration {
        code: receiver.registration.code.clone(),
        expires_at: receiver.registration.expires_at.clone(),
    };

    let mut state = IDLE_RECEIVER.lock().map_err(|err| err.to_string())?;
    *state = Some(receiver);
    Ok(response)
}

fn is_expired(registration: &RegisterPeerResponse) -> Result<bool, String> {
    let expires_at =
        OffsetDateTime::parse(&registration.expires_at, &Rfc3339).map_err(|err| err.to_string())?;
    Ok(OffsetDateTime::now_utc() >= expires_at)
}

fn log(message: &str) {
    eprintln!("[drift_bridge::receiver] {message}");
}
