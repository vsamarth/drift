mod device_name;

pub use device_name::{normalize_hostname_label, process_display_device_name, random_device_name};

use std::io::{self, Write};

use iroh::TransportAddr;

use crate::error::{DriftError, DriftErrorKind, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionPathKind {
    Direct,
    Relay,
    Unknown,
}

pub async fn classify_connection_path(
    endpoint: &iroh::Endpoint,
    remote_id: iroh::EndpointId,
) -> ConnectionPathKind {
    let Some(info) = endpoint.remote_info(remote_id).await else {
        return ConnectionPathKind::Unknown;
    };

    let mut has_ip = false;
    let mut has_relay = false;
    for addr in info.addrs() {
        match addr.addr() {
            TransportAddr::Ip(_) => has_ip = true,
            TransportAddr::Relay(_) => has_relay = true,
            _ => {}
        }
    }

    if has_ip {
        ConnectionPathKind::Direct
    } else if has_relay {
        ConnectionPathKind::Relay
    } else {
        ConnectionPathKind::Unknown
    }
}

pub fn confirm_accept() -> Result<bool> {
    print!("Accept? [y/N]: ");
    io::stdout().flush().map_err(|error| {
        DriftError::with_reason(DriftErrorKind::Io, format!("flushing prompt: {error}"))
    })?;

    let mut input = String::new();
    io::stdin()
        .read_line(&mut input)
        .map_err(|error| {
            DriftError::with_reason(DriftErrorKind::Io, format!("reading confirmation: {error}"))
        })?;

    let response = input.trim().to_ascii_lowercase();
    Ok(matches!(response.as_str(), "y" | "yes"))
}

pub fn describe_remote(
    remote_id: iroh::EndpointId,
    remote: Option<&iroh::endpoint::RemoteInfo>,
) -> String {
    let relay = remote
        .and_then(|info| {
            info.addrs().find_map(|addr| match addr.addr() {
                TransportAddr::Relay(url) => Some(format!(" via relay {url}")),
                TransportAddr::Ip(_) => None,
                _ => None,
            })
        })
        .unwrap_or_default();
    format!("{remote_id}{relay}")
}

pub fn human_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut unit = 0;
    while value >= 1024.0 && unit < UNITS.len() - 1 {
        value /= 1024.0;
        unit += 1;
    }

    if unit == 0 {
        format!("{} {}", bytes, UNITS[unit])
    } else {
        format!("{value:.1} {}", UNITS[unit])
    }
}
