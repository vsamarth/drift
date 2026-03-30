use drift_app::{
    ConflictPolicy, ReceiverConfig, ReceiverOfferEvent as AppReceiverOfferEvent,
    ReceiverOfferFile as AppReceiverOfferFile, ReceiverOfferPhase as AppReceiverOfferPhase,
    ReceiverRegistration as AppReceiverRegistration,
    ReceiverRegistrationRequest as AppReceiverRegistrationRequest, receiver_service,
};

use super::RUNTIME;
use crate::frb_generated::StreamSink;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";

fn bridge_receiver_service(
    device_name: impl Into<String>,
    device_type: impl Into<String>,
    download_root: impl Into<String>,
) -> drift_app::ReceiverService {
    receiver_service(ReceiverConfig {
        device_name: device_name.into(),
        device_type: device_type.into(),
        download_root: download_root.into().into(),
        conflict_policy: ConflictPolicy::Reject,
    })
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
        bridge_receiver_service(device_name, "laptop", ".")
            .ensure_registered(AppReceiverRegistrationRequest {
            server_url: server_url.or(Some(LOCAL_RENDEZVOUS_URL.to_owned())),
        })
        .await
        .map(map_registration)
        .map_err(|e| e.to_string())
    })
}

pub fn current_idle_receiver_registration() -> Option<IdleReceiverRegistration> {
    bridge_receiver_service("", "laptop", ".")
        .current_registration()
        .map(map_registration)
}

pub fn pause_idle_lan_advertisement() -> Result<(), String> {
    bridge_receiver_service("", "laptop", ".")
        .set_advertising_enabled(false)
        .map_err(|e| e.to_string())
}

pub fn resume_idle_lan_advertisement() -> Result<(), String> {
    bridge_receiver_service("", "laptop", ".")
        .set_advertising_enabled(true)
        .map_err(|e| e.to_string())
}

pub fn start_idle_incoming_listener(
    download_root: String,
    device_name: String,
    device_type: String,
    updates: StreamSink<IdleIncomingEvent>,
) -> Result<(), String> {
    bridge_receiver_service(device_name, device_type, download_root)
        .start_listener(move |event| {
            let _ = updates.add(map_event(event));
        })
        .map_err(|e| e.to_string())
}

pub fn respond_idle_incoming_offer(accept: bool) -> Result<(), String> {
    bridge_receiver_service("", "laptop", ".")
        .respond_to_offer(accept)
        .map_err(|e| e.to_string())
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
