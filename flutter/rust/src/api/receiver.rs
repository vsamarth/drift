use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Mutex};

use drift_app::{
    ConflictPolicy, OfferDecision, PairingCodeState, ReceiverConfig,
    ReceiverEvent as AppReceiverEvent, ReceiverOfferEvent as AppReceiverOfferEvent,
    ReceiverOfferFile as AppReceiverOfferFile, ReceiverOfferPhase as AppReceiverOfferPhase,
    ReceiverRegistration as AppReceiverRegistration, ReceiverService,
};
use iroh::SecretKey;
use tokio::task::JoinHandle;

use super::RUNTIME;
use crate::frb_generated::StreamSink;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";

static RECEIVER_SECRET_KEY: LazyLock<SecretKey> =
    LazyLock::new(|| SecretKey::from_bytes(&rand::random()));
static RECEIVER_STATE: LazyLock<Mutex<Option<BridgeReceiverState>>> =
    LazyLock::new(|| Mutex::new(None));

#[derive(Clone, Debug, PartialEq, Eq)]
struct BridgeReceiverConfig {
    device_name: String,
    device_type: String,
    download_root: PathBuf,
}

struct BridgeReceiverState {
    config: BridgeReceiverConfig,
    service: Arc<ReceiverService>,
    updates_task: Option<JoinHandle<()>>,
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
    device_name: String,
) -> Result<IdleReceiverRegistration, String> {
    ensure_idle_receiver(server_url, device_name)
}

pub fn ensure_idle_receiver(
    server_url: Option<String>,
    device_name: String,
) -> Result<IdleReceiverRegistration, String> {
    RUNTIME.block_on(async move {
        let service = ensure_receiver_service(BridgeReceiverConfig {
            device_name,
            device_type: "laptop".to_owned(),
            download_root: PathBuf::from("."),
        })
        .await?;

        service
            .ensure_registered(server_url.or(Some(LOCAL_RENDEZVOUS_URL.to_owned())))
            .await
            .map(map_registration)
            .map_err(|e| e.to_string())
    })
}

pub fn current_idle_receiver_registration() -> Option<IdleReceiverRegistration> {
    current_service()
        .and_then(|service| pairing_registration(&service.pairing_code()))
        .map(map_registration)
}

pub fn pause_idle_lan_advertisement() -> Result<(), String> {
    set_discoverable(false)
}

pub fn resume_idle_lan_advertisement() -> Result<(), String> {
    set_discoverable(true)
}

pub fn start_idle_incoming_listener(
    download_root: String,
    device_name: String,
    device_type: String,
    updates: StreamSink<IdleIncomingEvent>,
) -> Result<(), String> {
    RUNTIME.block_on(async move {
        let config = BridgeReceiverConfig {
            device_name,
            device_type,
            download_root: PathBuf::from(download_root),
        };
        let service = ensure_receiver_service(config.clone()).await?;
        service
            .ensure_registered(Some(LOCAL_RENDEZVOUS_URL.to_owned()))
            .await
            .map_err(|e| e.to_string())?;
        service
            .set_discoverable(true)
            .await
            .map_err(|e| e.to_string())?;

        replace_updates_task(config, service, updates);
        Ok(())
    })
}

pub fn respond_idle_incoming_offer(accept: bool) -> Result<(), String> {
    RUNTIME.block_on(async move {
        let Some(service) = current_service() else {
            return Err("receiver is not running".to_owned());
        };
        service
            .respond_to_offer(if accept {
                OfferDecision::Accept
            } else {
                OfferDecision::Decline
            })
            .await
            .map_err(|e| e.to_string())
    })
}

pub(crate) async fn scan_nearby_with_receiver(timeout_secs: u64) -> Result<Vec<crate::api::lan::NearbyReceiverInfo>, String> {
    let service = match current_service() {
        Some(service) => service,
        None => {
            let temp = ReceiverService::start(ReceiverConfig {
                device_name: String::new(),
                device_type: "laptop".to_owned(),
                download_root: PathBuf::from("."),
                conflict_policy: ConflictPolicy::Reject,
                secret_key: RECEIVER_SECRET_KEY.clone(),
            })
            .await
            .map_err(|e| e.to_string())?;
            let receivers = temp
                .scan_nearby(timeout_secs)
                .await
                .map_err(|e| e.to_string())?;
            let _ = temp.shutdown().await;
            return Ok(receivers
                .into_iter()
                .map(crate::api::lan::map_nearby_receiver)
                .collect());
        }
    };

    service
        .scan_nearby(timeout_secs)
        .await
        .map_err(|e| e.to_string())
        .map(|items| items.into_iter().map(crate::api::lan::map_nearby_receiver).collect())
}

async fn ensure_receiver_service(
    config: BridgeReceiverConfig,
) -> Result<Arc<ReceiverService>, String> {
    if let Some(service) = existing_service_for_config(&config) {
        return Ok(service);
    }

    let old_state = {
        let mut guard = RECEIVER_STATE
            .lock()
            .map_err(|_| "receiver bridge mutex poisoned".to_owned())?;
        guard.take()
    };

    if let Some(old_state) = old_state {
        if let Some(task) = old_state.updates_task {
            task.abort();
        }
        let _ = old_state.service.shutdown().await;
    }

    let service = Arc::new(
        ReceiverService::start(ReceiverConfig {
            device_name: config.device_name.clone(),
            device_type: config.device_type.clone(),
            download_root: config.download_root.clone(),
            conflict_policy: ConflictPolicy::Reject,
            secret_key: RECEIVER_SECRET_KEY.clone(),
        })
        .await
        .map_err(|e| e.to_string())?,
    );

    let mut guard = RECEIVER_STATE
        .lock()
        .map_err(|_| "receiver bridge mutex poisoned".to_owned())?;
    *guard = Some(BridgeReceiverState {
        config,
        service: service.clone(),
        updates_task: None,
    });
    Ok(service)
}

fn replace_updates_task(
    config: BridgeReceiverConfig,
    service: Arc<ReceiverService>,
    updates: StreamSink<IdleIncomingEvent>,
) {
    let mut event_rx = service.subscribe_events();
    let task = RUNTIME.spawn(async move {
        loop {
            match event_rx.recv().await {
                Ok(AppReceiverEvent::OfferUpdated(event)) => {
                    let _ = updates.add(map_event(event));
                }
                Ok(AppReceiverEvent::Shutdown) => break,
                Ok(AppReceiverEvent::RegistrationUpdated(_))
                | Ok(AppReceiverEvent::SetupCompleted(_))
                | Ok(AppReceiverEvent::DiscoverabilityChanged { .. }) => {}
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => {}
            }
        }
    });

    if let Ok(mut guard) = RECEIVER_STATE.lock() {
        if let Some(state) = guard.as_mut() {
            if state.config == config && Arc::ptr_eq(&state.service, &service) {
                if let Some(old_task) = state.updates_task.replace(task) {
                    old_task.abort();
                }
            }
        }
    }
}

fn existing_service_for_config(config: &BridgeReceiverConfig) -> Option<Arc<ReceiverService>> {
    let guard = RECEIVER_STATE.lock().ok()?;
    let state = guard.as_ref()?;
    (state.config == *config).then(|| state.service.clone())
}

fn current_service() -> Option<Arc<ReceiverService>> {
    RECEIVER_STATE
        .lock()
        .ok()
        .and_then(|guard| guard.as_ref().map(|state| state.service.clone()))
}

fn set_discoverable(enabled: bool) -> Result<(), String> {
    RUNTIME.block_on(async move {
        let Some(service) = current_service() else {
            return Ok(());
        };
        service
            .set_discoverable(enabled)
            .await
            .map_err(|e| e.to_string())
    })
}

fn pairing_registration(state: &PairingCodeState) -> Option<AppReceiverRegistration> {
    match state {
        PairingCodeState::Unavailable => None,
        PairingCodeState::Active(registration) => Some(registration.clone()),
    }
}

fn map_registration(value: AppReceiverRegistration) -> IdleReceiverRegistration {
    IdleReceiverRegistration {
        code: value.code,
        expires_at: value.expires_at,
    }
}

fn map_event(event: AppReceiverOfferEvent) -> IdleIncomingEvent {
    IdleIncomingEvent {
        phase: match event.phase {
            AppReceiverOfferPhase::Connecting => IdleIncomingPhase::Connecting,
            AppReceiverOfferPhase::OfferReady => IdleIncomingPhase::OfferReady,
            AppReceiverOfferPhase::Receiving => IdleIncomingPhase::Receiving,
            AppReceiverOfferPhase::Completed => IdleIncomingPhase::Completed,
            AppReceiverOfferPhase::Failed => IdleIncomingPhase::Failed,
            AppReceiverOfferPhase::Declined => IdleIncomingPhase::Declined,
        },
        sender_name: event.sender_name,
        destination_label: event.destination_label,
        save_root_label: event.save_root_label,
        status_message: event.status_message,
        item_count: event.item_count,
        total_size_bytes: event.total_size_bytes,
        total_size_label: event.total_size_label,
        files: event.files.into_iter().map(map_file_row).collect(),
        error_message: event.error_message,
    }
}

fn map_file_row(row: AppReceiverOfferFile) -> IdleIncomingFileRow {
    IdleIncomingFileRow {
        path: row.path,
        size: row.size,
    }
}
