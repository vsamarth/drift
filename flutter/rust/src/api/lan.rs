//! mDNS LAN discovery for Flutter send UI.

use drift_app::{ConflictPolicy, NearbyReceiver, ReceiverConfig, receiver_service};

use super::RUNTIME;

#[derive(Debug, Clone)]
pub struct NearbyReceiverInfo {
    pub fullname: String,
    pub label: String,
    pub code: String,
    pub ticket: String,
}

pub fn scan_nearby_receivers(timeout_secs: u64) -> Result<Vec<NearbyReceiverInfo>, String> {
    RUNTIME.block_on(async move {
        receiver_service(ReceiverConfig {
            device_name: String::new(),
            device_type: "laptop".to_owned(),
            download_root: ".".into(),
            conflict_policy: ConflictPolicy::Reject,
        })
            .scan_nearby(timeout_secs)
            .await
            .map_err(|e| e.to_string())
            .map(|items| items.into_iter().map(map_nearby_receiver).collect())
    })
}

fn map_nearby_receiver(item: NearbyReceiver) -> NearbyReceiverInfo {
    NearbyReceiverInfo {
        fullname: item.fullname,
        label: item.label,
        code: item.code,
        ticket: item.ticket,
    }
}
