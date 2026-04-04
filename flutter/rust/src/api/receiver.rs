use std::path::PathBuf;
use std::sync::{Arc, LazyLock, Mutex};

use drift_app::{
    ConflictPolicy, OfferDecision, PairingCodeState, ReceiverConfig,
    ReceiverEvent as AppReceiverEvent, ReceiverOfferEvent as AppReceiverOfferEvent,
    ReceiverOfferFile as AppReceiverOfferFile, ReceiverOfferPhase as AppReceiverOfferPhase,
    ReceiverRegistration as AppReceiverRegistration, ReceiverService,
};
use iroh::SecretKey;
use tokio::sync::Mutex as AsyncMutex;
use tokio::task::JoinHandle;

use super::RUNTIME;
use crate::api::error::BridgeError;
use crate::frb_generated::StreamSink;
use drift_core::error::DriftError;

static RECEIVER_SECRET_KEY: LazyLock<SecretKey> =
    LazyLock::new(|| SecretKey::from_bytes(&rand::random()));
static RECEIVER_STATE: LazyLock<Mutex<Option<BridgeReceiverState>>> =
    LazyLock::new(|| Mutex::new(None));
static RECEIVER_SERVICE_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));
const ENABLE_DEMO_HELLO_PROTOCOL: bool = false;

#[derive(Clone, Debug, PartialEq, Eq)]
struct BridgeReceiverConfig {
    device_name: String,
    device_type: String,
    download_root: PathBuf,
    server_url: Option<String>,
}

struct BridgeReceiverState {
    config: BridgeReceiverConfig,
    service: Arc<ReceiverService>,
    updates_task: Option<JoinHandle<()>>,
    pairing_task: Option<JoinHandle<()>>,
}

#[derive(Debug, Clone)]
pub struct ReceiverRegistration {
    pub code: String,
    pub expires_at: String,
}

#[derive(Debug, Clone)]
pub struct ReceiverPairingState {
    pub code: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Clone, Debug)]
pub enum ReceiverTransferPhase {
    Connecting,
    OfferReady,
    Receiving,
    Completed,
    Cancelled,
    Failed,
    Declined,
}

#[derive(Clone, Debug)]
pub struct ReceiverTransferFile {
    pub path: String,
    pub size: u64,
}

#[derive(Clone, Debug)]
pub struct ReceiverTransferEvent {
    pub phase: ReceiverTransferPhase,
    pub sender_name: String,
    pub sender_device_type: String,
    pub destination_label: String,
    pub save_root_label: String,
    pub status_message: String,
    pub item_count: u64,
    pub total_size_bytes: u64,
    pub bytes_received: u64,
    pub total_size_label: String,
    pub files: Vec<ReceiverTransferFile>,
    pub error: Option<BridgeError>,
    pub error_message: Option<String>,
}

pub fn register_receiver(
    server_url: Option<String>,
    device_name: String,
) -> Result<ReceiverRegistration, BridgeError> {
    ensure_receiver_registration(server_url, device_name)
}

pub fn ensure_receiver_registration(
    server_url: Option<String>,
    device_name: String,
) -> Result<ReceiverRegistration, BridgeError> {
    RUNTIME.block_on(async move {
        let service = ensure_receiver_service(BridgeReceiverConfig {
            device_name,
            device_type: "laptop".to_owned(),
            download_root: PathBuf::from("."),
            server_url: server_url.clone(),
        })
        .await?;

        service
            .ensure_registered(server_url)
            .await
            .map(map_registration)
            .map_err(Into::into)
    })
}

pub fn current_receiver_registration() -> Option<ReceiverRegistration> {
    current_service()
        .and_then(|service| pairing_registration(&service.pairing_code()))
        .map(map_registration)
}

pub fn watch_receiver_pairing(
    server_url: Option<String>,
    download_root: String,
    device_name: String,
    device_type: String,
    updates: StreamSink<ReceiverPairingState>,
) -> Result<(), BridgeError> {
    RUNTIME.block_on(async move {
        let config = BridgeReceiverConfig {
            device_name,
            device_type,
            download_root: PathBuf::from(download_root),
            server_url: server_url.clone(),
        };
        let service = ensure_receiver_service(config.clone()).await?;
        if let Some(server_url) = config.server_url.clone() {
            if let Err(error) = service.ensure_registered(Some(server_url)).await {
                println!(
                    "[bridge] receiver pairing registration unavailable: {}",
                    error
                );
            }
        }
        service
            .set_discoverable(true)
            .await
            .map_err(BridgeError::from)?;

        replace_pairing_task(config, service, updates);
        Ok(())
    })
}

pub fn set_receiver_discoverable(enabled: bool) -> Result<(), BridgeError> {
    set_discoverable(enabled)
}

pub fn start_receiver_transfer_listener(
    server_url: Option<String>,
    download_root: String,
    device_name: String,
    device_type: String,
    updates: StreamSink<ReceiverTransferEvent>,
) -> Result<(), BridgeError> {
    if ENABLE_DEMO_HELLO_PROTOCOL {
        std::env::set_var("DRIFT_DEMO_HELLO", "1");
        println!("[bridge/receive] demo hello protocol enabled");
    }

    RUNTIME.block_on(async move {
        let config = BridgeReceiverConfig {
            device_name,
            device_type,
            download_root: PathBuf::from(download_root),
            server_url: server_url.clone(),
        };
        let service = ensure_receiver_service(config.clone()).await?;
        if let Some(server_url) = config.server_url.clone() {
            if let Err(error) = service.ensure_registered(Some(server_url)).await {
                println!(
                    "[bridge] receiver transfer listener registration unavailable: {}",
                    error
                );
            }
        }
        service
            .set_discoverable(true)
            .await
            .map_err(BridgeError::from)?;

        replace_updates_task(config, service, updates);
        Ok(())
    })
}

pub fn respond_to_receiver_offer(accept: bool) -> Result<(), BridgeError> {
    RUNTIME.block_on(async move {
        let Some(service) = current_service() else {
            return Err(BridgeError::from(DriftError::internal("receiver is not running")));
        };
        service
            .respond_to_offer(if accept {
                OfferDecision::Accept
            } else {
                OfferDecision::Decline
            })
            .await
            .map_err(BridgeError::from)
    })
}

pub fn cancel_receiver_transfer() -> Result<(), BridgeError> {
    RUNTIME.block_on(async move {
        let Some(service) = current_service() else {
            return Err(BridgeError::from(DriftError::internal("receiver is not running")));
        };
        service.cancel_transfer().await.map_err(BridgeError::from)
    })
}

pub(crate) async fn scan_nearby_with_receiver(
    timeout_secs: u64,
) -> Result<Vec<crate::api::lan::NearbyReceiverInfo>, BridgeError> {
    println!(
        "[bridge] scanning nearby receivers (timeout={}s)",
        timeout_secs
    );
    let service = match current_service() {
        Some(service) => service,
        None => {
            println!("[bridge] starting temporary receiver service for scan");
            let temp = ReceiverService::start(ReceiverConfig {
                device_name: String::new(),
                device_type: "laptop".to_owned(),
                download_root: PathBuf::from("."),
                conflict_policy: ConflictPolicy::Reject,
                secret_key: RECEIVER_SECRET_KEY.clone(),
            })
            .await
            .map_err(BridgeError::from)?;
            let receivers = temp
                .scan_nearby(timeout_secs)
                .await
                .map_err(BridgeError::from)?;
            println!("[bridge] scan found {} receivers", receivers.len());
            for r in &receivers {
                println!(
                    "[bridge]   - found receiver: name='{}' label='{}' code='{}'",
                    r.fullname, r.label, r.code
                );
            }
            let _ = temp.shutdown().await;
            return Ok(receivers
                .into_iter()
                .map(crate::api::lan::map_nearby_receiver)
                .collect());
        }
    };

    let receivers = service
        .scan_nearby(timeout_secs)
        .await
        .map_err(BridgeError::from)?;

    println!("[bridge] scan found {} receivers", receivers.len());
    for r in &receivers {
        println!(
            "[bridge]   - found receiver: name='{}' label='{}' code='{}'",
            r.fullname, r.label, r.code
        );
    }

    Ok(receivers
        .into_iter()
        .map(crate::api::lan::map_nearby_receiver)
        .collect())
}

async fn ensure_receiver_service(
    config: BridgeReceiverConfig,
) -> Result<Arc<ReceiverService>, BridgeError> {
    let _lock = RECEIVER_SERVICE_LOCK.lock().await;

    if let Some(service) = existing_service_for_config(&config) {
        return Ok(service);
    }

    println!(
        "[bridge] creating new receiver service: device_name='{}' device_type='{}'",
        config.device_name, config.device_type
    );

    let old_state = {
        let mut guard = RECEIVER_STATE
            .lock()
            .map_err(|_| {
                BridgeError::from(drift_core::error::DriftError::internal(
                    "receiver bridge mutex poisoned",
                ))
            })?;
        guard.take()
    };

    if let Some(old_state) = old_state {
        if let Some(task) = old_state.updates_task {
            task.abort();
        }
        if let Some(task) = old_state.pairing_task {
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
        .await?,
    );

    println!("[bridge] receiver service started");

    let mut guard = RECEIVER_STATE
        .lock()
        .map_err(|_| {
            BridgeError::from(drift_core::error::DriftError::internal(
                "receiver bridge mutex poisoned",
            ))
        })?;
    *guard = Some(BridgeReceiverState {
        config,
        service: service.clone(),
        updates_task: None,
        pairing_task: None,
    });
    Ok(service)
}

fn replace_updates_task(
    config: BridgeReceiverConfig,
    service: Arc<ReceiverService>,
    updates: StreamSink<ReceiverTransferEvent>,
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

fn replace_pairing_task(
    config: BridgeReceiverConfig,
    service: Arc<ReceiverService>,
    updates: StreamSink<ReceiverPairingState>,
) {
    let mut pairing_rx = service.subscribe_pairing_code();
    let task = RUNTIME.spawn(async move {
        let _ = updates.add(map_pairing_state(&pairing_rx.borrow().clone()));
        loop {
            if pairing_rx.changed().await.is_err() {
                break;
            }
            let _ = updates.add(map_pairing_state(&pairing_rx.borrow().clone()));
        }
    });

    if let Ok(mut guard) = RECEIVER_STATE.lock() {
        if let Some(state) = guard.as_mut() {
            if state.config == config && Arc::ptr_eq(&state.service, &service) {
                if let Some(old_task) = state.pairing_task.replace(task) {
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

fn set_discoverable(enabled: bool) -> Result<(), BridgeError> {
    println!("[bridge] setting discoverable: {}", enabled);
    RUNTIME.block_on(async move {
        let Some(service) = current_service() else {
            println!("[bridge] WARNING: set_discoverable called but no service running");
            return Ok(());
        };
        service
            .set_discoverable(enabled)
            .await
            .map_err(Into::into)
    })
}

fn pairing_registration(state: &PairingCodeState) -> Option<AppReceiverRegistration> {
    match state {
        PairingCodeState::Unavailable => None,
        PairingCodeState::Active(registration) => Some(registration.clone()),
    }
}

fn map_registration(value: AppReceiverRegistration) -> ReceiverRegistration {
    ReceiverRegistration {
        code: value.code,
        expires_at: value.expires_at,
    }
}

fn map_pairing_state(state: &PairingCodeState) -> ReceiverPairingState {
    match state {
        PairingCodeState::Unavailable => ReceiverPairingState {
            code: None,
            expires_at: None,
        },
        PairingCodeState::Active(registration) => ReceiverPairingState {
            code: Some(registration.code.clone()),
            expires_at: Some(registration.expires_at.clone()),
        },
    }
}

fn map_event(event: AppReceiverOfferEvent) -> ReceiverTransferEvent {
    ReceiverTransferEvent {
        phase: match event.phase {
            AppReceiverOfferPhase::Connecting => ReceiverTransferPhase::Connecting,
            AppReceiverOfferPhase::OfferReady => ReceiverTransferPhase::OfferReady,
            AppReceiverOfferPhase::Receiving => ReceiverTransferPhase::Receiving,
            AppReceiverOfferPhase::Completed => ReceiverTransferPhase::Completed,
            AppReceiverOfferPhase::Cancelled => ReceiverTransferPhase::Cancelled,
            AppReceiverOfferPhase::Failed => ReceiverTransferPhase::Failed,
            AppReceiverOfferPhase::Declined => ReceiverTransferPhase::Declined,
        },
        sender_name: event.sender_name,
        sender_device_type: event.sender_device_type,
        destination_label: event.destination_label,
        save_root_label: event.save_root_label,
        status_message: event.status_message,
        item_count: event.item_count,
        total_size_bytes: event.total_size_bytes,
        bytes_received: event.bytes_received,
        total_size_label: event.total_size_label,
        files: event.files.into_iter().map(map_file_row).collect(),
        error: event.error.map(Into::into),
        error_message: event.error_message,
    }
}

fn map_file_row(row: AppReceiverOfferFile) -> ReceiverTransferFile {
    ReceiverTransferFile {
        path: row.path,
        size: row.size,
    }
}
