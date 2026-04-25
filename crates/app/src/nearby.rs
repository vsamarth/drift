use std::collections::BTreeMap;
use std::time::Duration;

use crate::error::{AppError, AppResult};
use crate::types::NearbyReceiver;

pub async fn scan_nearby_receivers(timeout_secs: u64) -> AppResult<Vec<NearbyReceiver>> {
    let secs = timeout_secs.max(1);
    let receivers = tokio::task::spawn_blocking(move || {
        drift_core::lan::browse_nearby_receivers(Duration::from_secs(secs), None)
    })
    .await
    .map_err(|_| AppError::DiscoveryFailed)?
    .map_err(|_| AppError::DiscoveryFailed)?;

    let mut by_fullname = BTreeMap::new();
    for receiver in receivers {
        by_fullname.insert(
            receiver.fullname.clone(),
            NearbyReceiver {
                fullname: receiver.fullname,
                label: receiver.label,
                device_type: match receiver.device_type {
                    drift_core::protocol::DeviceType::Phone => "phone".to_owned(),
                    drift_core::protocol::DeviceType::Laptop => "laptop".to_owned(),
                },
                code: receiver.code,
                ticket: receiver.ticket,
            },
        );
    }

    Ok(by_fullname.into_values().collect())
}
