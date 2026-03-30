//! mDNS LAN discovery for CLI: publish the same iroh ticket as rendezvous while receiving,
//! and browse for nearby receivers when sending with `--nearby`.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use flume::RecvTimeoutError;
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo, TxtProperties};

/// DNS-SD type for drift receivers on the LAN (`drift` ≤ 15 bytes per RFC 6763).
pub const DRIFT_MDNS_SERVICE_TYPE: &str = "_drift._udp.local.";

/// TXT `ver` value for this wire format (ticket chunks `t0`… + `tc`).
pub const DRIFT_MDNS_TXT_VER: &str = "1";

const TICKET_CHUNK_LEN: usize = 200;

/// SRV port is unused for iroh; discard is a conventional placeholder.
const MDNS_SRV_PORT: u16 = 9;

fn default_route_ipv4() -> Result<Ipv4Addr> {
    let socket = UdpSocket::bind("0.0.0.0:0").context("binding UDP socket for local IP probe")?;
    socket
        .connect("192.0.2.1:1")
        .context("connecting UDP socket for local IP probe")?;
    match socket.local_addr().context("local_addr after connect")? {
        SocketAddr::V4(addr) => Ok(*addr.ip()),
        SocketAddr::V6(_) => bail!("expected an IPv4 local address"),
    }
}

fn chunk_ascii(s: &str, max: usize) -> Vec<String> {
    s.as_bytes()
        .chunks(max)
        .map(|c| String::from_utf8_lossy(c).into_owned())
        .collect()
}

fn ticket_from_txt(txt: &TxtProperties) -> Option<String> {
    let n = txt.get_property_val_str("tc")?.parse::<usize>().ok()?;
    let mut out = String::new();
    for i in 0..n {
        let piece = txt.get_property_val_str(&format!("t{i}"))?;
        out.push_str(piece);
    }
    Some(out)
}

/// Holds mDNS registration for `receive`; unregister on drop.
pub struct LanReceiveAdvertisement {
    daemon: ServiceDaemon,
    fullname: String,
}

impl LanReceiveAdvertisement {
    /// Publishes the given iroh `ticket` (same string as rendezvous) on the LAN.
    ///
    /// Returns `Ok(None)` when there is no usable IPv4 default route (LAN advertising skipped).
    pub fn start(ticket: &str, device_label: &str, rendezvous_code: &str) -> Result<Option<Self>> {
        let ip = match default_route_ipv4() {
            Ok(ip) => ip,
            Err(_) => return Ok(None),
        };

        let host_name = format!("{ip}.local.");
        let code_key = rendezvous_code.trim().to_uppercase();
        let instance = format!(
            "recv-{}",
            code_key
                .chars()
                .filter(|c| c.is_ascii_alphanumeric())
                .collect::<String>()
        );
        if instance.len() <= "recv-".len() {
            bail!("rendezvous code is empty after sanitizing for mDNS instance name");
        }

        let chunks = chunk_ascii(ticket, TICKET_CHUNK_LEN);
        let mut properties: Vec<(String, String)> = vec![
            ("ver".into(), DRIFT_MDNS_TXT_VER.into()),
            ("code".into(), code_key),
            ("label".into(), device_label.to_owned()),
            ("tc".into(), chunks.len().to_string()),
        ];
        for (i, c) in chunks.iter().enumerate() {
            properties.push((format!("t{i}"), c.clone()));
        }

        let txt: Vec<(&str, &str)> = properties
            .iter()
            .map(|(k, v)| (k.as_str(), v.as_str()))
            .collect();

        let service = ServiceInfo::new(
            DRIFT_MDNS_SERVICE_TYPE,
            &instance,
            &host_name,
            IpAddr::V4(ip),
            MDNS_SRV_PORT,
            txt.as_slice(),
        )
        .context("building mDNS service info")?
        .enable_addr_auto();

        let fullname = service.get_fullname().to_owned();
        let daemon = ServiceDaemon::new().context("creating mDNS daemon")?;
        daemon
            .register(service)
            .context("registering mDNS drift receive service")?;

        Ok(Some(Self { daemon, fullname }))
    }
}

impl Drop for LanReceiveAdvertisement {
    fn drop(&mut self) {
        if let Ok(rx) = self.daemon.unregister(&self.fullname) {
            let _ = rx.recv_timeout(Duration::from_secs(2));
        }
        std::thread::sleep(Duration::from_millis(100));
        if let Ok(rx) = self.daemon.shutdown() {
            let _ = rx.recv_timeout(Duration::from_secs(2));
        }
    }
}

/// One resolved nearby receiver from mDNS.
#[derive(Debug, Clone)]
pub struct NearbyReceiver {
    pub fullname: String,
    pub label: String,
    pub code: String,
    pub ticket: String,
}

/// Browse for `scan` duration and return the latest snapshot of matching receivers.
pub fn browse_nearby_receivers(scan: Duration) -> Result<Vec<NearbyReceiver>> {
    let daemon = ServiceDaemon::new().context("creating mDNS daemon")?;
    let browse_rx = daemon
        .browse(DRIFT_MDNS_SERVICE_TYPE)
        .context("starting mDNS browse")?;

    let deadline = Instant::now() + scan;
    let mut peers: HashMap<String, NearbyReceiver> = HashMap::new();

    while Instant::now() < deadline {
        let remaining = deadline.saturating_duration_since(Instant::now());
        let wait = Duration::from_millis(250).min(remaining);
        if wait.is_zero() {
            break;
        }

        match browse_rx.recv_timeout(wait) {
            Ok(ServiceEvent::ServiceResolved(info)) => {
                if !info.is_valid() {
                    continue;
                }
                if info.txt_properties.get_property_val_str("ver") != Some(DRIFT_MDNS_TXT_VER) {
                    continue;
                }
                let Some(ticket) = ticket_from_txt(&info.txt_properties) else {
                    continue;
                };
                let label = info
                    .txt_properties
                    .get_property_val_str("label")
                    .unwrap_or("Drift receiver")
                    .to_owned();
                let code = info
                    .txt_properties
                    .get_property_val_str("code")
                    .unwrap_or("")
                    .to_owned();
                peers.insert(
                    info.fullname.clone(),
                    NearbyReceiver {
                        fullname: info.fullname,
                        label,
                        code,
                        ticket,
                    },
                );
            }
            Ok(ServiceEvent::ServiceRemoved(fullname, _)) => {
                peers.remove(&fullname);
            }
            Ok(_) => {}
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break,
        }
    }

    if let Ok(rx) = daemon.shutdown() {
        let _ = rx.recv_timeout(Duration::from_secs(2));
    }

    let mut list: Vec<NearbyReceiver> = peers.into_values().collect();
    list.sort_by(|a, b| {
        a.label
            .cmp(&b.label)
            .then_with(|| a.fullname.cmp(&b.fullname))
    });
    Ok(list)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use mdns_sd::IntoTxtProperties;

    use super::*;

    #[test]
    fn ticket_roundtrip_txt_chunks() {
        let ticket = "a".repeat(450);
        let chunks = chunk_ascii(&ticket, TICKET_CHUNK_LEN);
        assert_eq!(chunks.len(), 3);

        let mut m: HashMap<String, String> = HashMap::new();
        m.insert("ver".into(), DRIFT_MDNS_TXT_VER.into());
        m.insert("tc".into(), chunks.len().to_string());
        for (i, c) in chunks.iter().enumerate() {
            m.insert(format!("t{i}"), c.clone());
        }
        let txt = m.into_txt_properties();
        let got = ticket_from_txt(&txt).expect("reassembled");
        assert_eq!(got, ticket);
    }
}
