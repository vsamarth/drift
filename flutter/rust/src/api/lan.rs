//! mDNS LAN discovery for Flutter send UI (browse only; publish lives in receiver).

use std::time::Duration;

use super::RUNTIME;
use super::receiver::idle_receiver_endpoint_id_for_lan_filter;

#[derive(Debug, Clone)]
pub struct NearbyReceiverInfo {
    pub fullname: String,
    pub label: String,
    pub code: String,
    pub ticket: String,
}

/// Browse for drift receivers on the LAN (`_drift._udp.local.`).
///
/// Runs the blocking mdns-sd work on a blocking thread pool thread.
pub fn scan_nearby_receivers(timeout_secs: u64) -> Result<Vec<NearbyReceiverInfo>, String> {
    let secs = timeout_secs.max(1);
    RUNTIME.block_on(async move {
        let exclude = idle_receiver_endpoint_id_for_lan_filter();
        tokio::task::spawn_blocking(move || {
            drift_core::lan::browse_nearby_receivers(Duration::from_secs(secs), exclude)
        })
        .await
        .map_err(|e| format!("mDNS scan task failed: {e}"))?
        .map_err(|e| e.to_string())
        .map(|receivers| {
            receivers
                .into_iter()
                .map(|r| NearbyReceiverInfo {
                    fullname: r.fullname,
                    label: r.label,
                    code: r.code,
                    ticket: r.ticket,
                })
                .collect()
        })
    })
}
