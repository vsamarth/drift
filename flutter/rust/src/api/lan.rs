//! mDNS LAN discovery for Flutter send UI.

use super::RUNTIME;
use crate::api::error::BridgeError;
use drift_app::NearbyReceiver;

#[derive(Debug, Clone)]
pub struct NearbyReceiverInfo {
    pub fullname: String,
    pub label: String,
    pub code: String,
    pub ticket: String,
}

pub fn scan_nearby_receivers(timeout_secs: u64) -> Result<Vec<NearbyReceiverInfo>, BridgeError> {
    RUNTIME.block_on(super::receiver::scan_nearby_with_receiver(timeout_secs))
}

pub(crate) fn map_nearby_receiver(item: NearbyReceiver) -> NearbyReceiverInfo {
    NearbyReceiverInfo {
        fullname: item.fullname,
        label: item.label,
        code: item.code,
        ticket: item.ticket,
    }
}
