//! mDNS LAN discovery for CLI: publish the same iroh ticket as rendezvous while receiving,
//! and browse for nearby receivers when sending with `--nearby`.
//!
//! Receivers answer a small UDP **presence** protocol on [`DRIFT_LAN_PRESENCE_PORT`]; browsers
//! only list peers that respond, so stale mDNS cache entries are dropped.

use std::collections::HashMap;
use std::error::Error as StdError;
use std::mem::ManuallyDrop;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use flume::RecvTimeoutError;
use iroh::EndpointId;
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo, TxtProperties};
use rand::seq::SliceRandom;
use thiserror::Error;
use tracing::info;
/// DNS-SD type for drift receivers on the LAN (`drift` ≤ 15 bytes per RFC 6763).
pub const DRIFT_MDNS_SERVICE_TYPE: &str = "_drift._udp.local.";

/// TXT `ver` value for this wire format (ticket chunks `t0`… + `tc`).
pub const DRIFT_MDNS_TXT_VER: &str = "1";

/// UDP port for presence ping/pong (SRV port in mDNS). Not the iroh data plane.
pub const DRIFT_LAN_PRESENCE_PORT: u16 = 47_474;

const TICKET_CHUNK_LEN: usize = 200;

const PRESENCE_MAGIC: &[u8; 4] = b"DRFP";
const PRESENCE_VER: u16 = 1;
const OP_PING: u8 = 1;
const OP_PONG: u8 = 2;
const PRESENCE_PKT_LEN: usize = 16;

#[derive(Debug, Error)]
pub enum LanError {
    #[error("could not determine a usable IPv4 address for LAN discovery")]
    NoUsableIpv4Address,
    #[error("{context}")]
    Mdns {
        context: &'static str,
        #[source]
        source: Box<dyn StdError + Send + Sync + 'static>,
    },
    #[error("{context}")]
    Io {
        context: &'static str,
        #[source]
        source: std::io::Error,
    },
    #[error("spawn presence thread")]
    SpawnPresenceThread {
        #[source]
        source: std::io::Error,
    },
    #[error("presence ping reply from unexpected address")]
    PresenceUnexpectedReply,
    #[error("presence ping invalid pong")]
    PresenceInvalidPong,
}

fn default_route_ipv4() -> std::result::Result<Ipv4Addr, LanError> {
    let probes = ["1.1.1.1:53", "8.8.8.8:53", "192.0.2.1:1"];
    for probe in probes {
        if let Ok(socket) = UdpSocket::bind("0.0.0.0:0") {
            if socket.connect(probe).is_ok() {
                if let Ok(SocketAddr::V4(addr)) = socket.local_addr() {
                    let ip = *addr.ip();
                    if !ip.is_unspecified() && !ip.is_loopback() {
                        return Ok(ip);
                    }
                }
            }
        }
    }

    // Fallback: search for any non-loopback IPv4 interface
    if let Ok(addrs) = if_addrs::get_if_addrs() {
        for iface in addrs {
            if !iface.is_loopback() {
                if let IpAddr::V4(ip) = iface.ip() {
                    return Ok(ip);
                }
            }
        }
    }

    Err(LanError::NoUsableIpv4Address)
}

fn chunk_ascii(s: &str, max: usize) -> Vec<String> {
    s.as_bytes()
        .chunks(max)
        .map(|c| String::from_utf8_lossy(c).into_owned())
        .collect()
}

/// Random `recv-xxxx` instance name (does not embed the rendezvous pairing code).
fn random_mdns_instance_name() -> String {
    let mut rng = rand::thread_rng();
    const CHARS: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";
    let suffix: String = (0..10)
        .map(|_| *CHARS.choose(&mut rng).unwrap() as char)
        .collect();
    format!("recv-{suffix}")
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

fn build_presence_packet(op: u8, nonce: u64) -> [u8; PRESENCE_PKT_LEN] {
    let mut b = [0u8; PRESENCE_PKT_LEN];
    b[0..4].copy_from_slice(PRESENCE_MAGIC);
    b[4..6].copy_from_slice(&PRESENCE_VER.to_be_bytes());
    b[6] = op;
    b[7] = 0;
    b[8..16].copy_from_slice(&nonce.to_be_bytes());
    b
}

fn parse_presence_pong(buf: &[u8], expected_nonce: u64) -> bool {
    if buf.len() != PRESENCE_PKT_LEN {
        return false;
    }
    if &buf[0..4] != PRESENCE_MAGIC {
        return false;
    }
    if u16::from_be_bytes([buf[4], buf[5]]) != PRESENCE_VER {
        return false;
    }
    if buf[6] != OP_PONG {
        return false;
    }
    u64::from_be_bytes(buf[8..16].try_into().unwrap()) == expected_nonce
}

/// Returns true if the peer echoed our nonce over UDP within `timeout`.
pub fn presence_ping(target: SocketAddr, timeout: Duration) -> std::result::Result<(), LanError> {
    let socket = UdpSocket::bind("0.0.0.0:0").map_err(|source| LanError::Io {
        context: "presence ping bind",
        source,
    })?;
    socket
        .set_read_timeout(Some(timeout))
        .map_err(|source| LanError::Io {
            context: "presence ping set_read_timeout",
            source,
        })?;

    let nonce: u64 = rand::random();
    let pkt = build_presence_packet(OP_PING, nonce);
    socket
        .send_to(&pkt, target)
        .map_err(|source| LanError::Io {
            context: "presence ping send_to",
            source,
        })?;

    let mut buf = [0u8; PRESENCE_PKT_LEN];
    let (n, from) = socket.recv_from(&mut buf).map_err(|source| LanError::Io {
        context: "presence ping recv_from",
        source,
    })?;
    if from != target {
        return Err(LanError::PresenceUnexpectedReply);
    }
    if !parse_presence_pong(&buf[..n], nonce) {
        return Err(LanError::PresenceInvalidPong);
    }
    Ok(())
}

/// Tries each IPv4 until one answers presence ping.
fn verify_presence(info: &mdns_sd::ResolvedService) -> bool {
    if info.get_port() != DRIFT_LAN_PRESENCE_PORT {
        return false;
    }
    let timeout = Duration::from_millis(400);
    for ip in info.get_addresses_v4() {
        let target = SocketAddr::new(IpAddr::V4(ip), info.get_port());
        if presence_ping(target, timeout).is_ok() {
            return true;
        }
    }
    false
}

/// Answers [`DRIFT_LAN_PRESENCE_PORT`] UDP datagrams while alive.
pub struct PresenceResponder {
    stop: Arc<AtomicBool>,
    join: Option<JoinHandle<()>>,
}

impl PresenceResponder {
    pub fn bind(port: u16) -> std::result::Result<Self, LanError> {
        let socket = UdpSocket::bind(SocketAddr::from(([0, 0, 0, 0], port))).map_err(|source| {
            LanError::Io {
                context: "binding presence UDP",
                source,
            }
        })?;
        socket
            .set_read_timeout(Some(Duration::from_millis(500)))
            .map_err(|source| LanError::Io {
                context: "presence responder set_read_timeout",
                source,
            })?;

        let stop = Arc::new(AtomicBool::new(false));
        let stop_t = Arc::clone(&stop);
        let join = std::thread::Builder::new()
            .name("drift-lan-presence".into())
            .spawn(move || run_presence_loop(socket, stop_t))
            .map_err(|source| LanError::SpawnPresenceThread { source })?;

        Ok(Self {
            stop,
            join: Some(join),
        })
    }

    fn shutdown(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        if let Some(j) = self.join.take() {
            let _ = j.join();
        }
    }
}

impl Drop for PresenceResponder {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn run_presence_loop(socket: UdpSocket, stop: Arc<AtomicBool>) {
    let mut buf = [0u8; 256];
    while !stop.load(Ordering::SeqCst) {
        match socket.recv_from(&mut buf) {
            Ok((n, from)) => {
                if n != PRESENCE_PKT_LEN {
                    continue;
                }
                let p = &buf[..n];
                if &p[0..4] != PRESENCE_MAGIC {
                    continue;
                }
                if u16::from_be_bytes([p[4], p[5]]) != PRESENCE_VER {
                    continue;
                }
                if p[6] != OP_PING {
                    continue;
                }
                let nonce = u64::from_be_bytes(p[8..16].try_into().unwrap());
                let pong = build_presence_packet(OP_PONG, nonce);
                let _ = socket.send_to(&pong, from);
            }
            Err(e)
                if e.kind() == std::io::ErrorKind::WouldBlock
                    || e.kind() == std::io::ErrorKind::TimedOut => {}
            Err(_) => break,
        }
    }
}

/// Holds mDNS registration for `receive`; unregister on drop.
pub struct LanReceiveAdvertisement {
    fullname: String,
    daemon: ManuallyDrop<ServiceDaemon>,
    presence: ManuallyDrop<PresenceResponder>,
}

impl LanReceiveAdvertisement {
    /// Publishes the given iroh `ticket` (same string as rendezvous) on the LAN.
    ///
    /// Returns `Ok(None)` when there is no usable IPv4 default route (LAN advertising skipped).
    pub fn start(ticket: &str, device_label: &str) -> std::result::Result<Option<Self>, LanError> {
        let ip = match default_route_ipv4() {
            Ok(ip) => ip,
            Err(_) => return Ok(None),
        };
        info!(%ip, %device_label, "lan_advertisement.starting");

        let presence = PresenceResponder::bind(DRIFT_LAN_PRESENCE_PORT)
            .map_err(|source| LanError::mdns("starting LAN presence responder", source))?;

        let host_name = format!("{ip}.local.");
        let instance = random_mdns_instance_name();

        let chunks = chunk_ascii(ticket, TICKET_CHUNK_LEN);
        let mut properties: Vec<(String, String)> = vec![
            ("ver".into(), DRIFT_MDNS_TXT_VER.into()),
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
            DRIFT_LAN_PRESENCE_PORT,
            txt.as_slice(),
        )
        .map_err(|source| LanError::mdns("building mDNS service info", source))?
        .enable_addr_auto();

        let fullname = service.get_fullname().to_owned();
        let daemon = ServiceDaemon::new()
            .map_err(|source| LanError::mdns("creating mDNS daemon", source))?;
        if let Err(e) = daemon.register(service) {
            return Err(LanError::mdns("registering mDNS drift receive service", e));
        }

        Ok(Some(Self {
            fullname,
            daemon: ManuallyDrop::new(daemon),
            presence: ManuallyDrop::new(presence),
        }))
    }
}

impl Drop for LanReceiveAdvertisement {
    fn drop(&mut self) {
        if let Ok(rx) = self.daemon.unregister(&self.fullname) {
            let _ = rx.recv_timeout(Duration::from_secs(2));
        }
        std::thread::sleep(Duration::from_millis(100));
        unsafe {
            ManuallyDrop::drop(&mut self.presence);
        }
        if let Ok(rx) = self.daemon.shutdown() {
            let _ = rx.recv_timeout(Duration::from_secs(2));
        }
        unsafe {
            ManuallyDrop::drop(&mut self.daemon);
        }
    }
}

/// One resolved nearby receiver from mDNS.
#[derive(Debug, Clone)]
pub struct NearbyReceiver {
    pub fullname: String,
    pub label: String,
    /// Always empty for current advertisers (pairing code is not published on LAN).
    pub code: String,
    pub ticket: String,
}

/// Browse for `scan` duration and return the latest snapshot of matching receivers.
///
/// Only includes services that answer the UDP presence protocol on [`DRIFT_LAN_PRESENCE_PORT`].
///
/// When `exclude_endpoint_id` is set, drops entries whose mDNS ticket decodes to that iroh
/// endpoint id (same process advertising while browsing, e.g. Flutter idle receive + send UI).
pub fn browse_nearby_receivers(
    scan: Duration,
    exclude_endpoint_id: Option<EndpointId>,
) -> std::result::Result<Vec<NearbyReceiver>, LanError> {
    let daemon =
        ServiceDaemon::new().map_err(|source| LanError::mdns("creating mDNS daemon", source))?;
    let browse_rx = daemon
        .browse(DRIFT_MDNS_SERVICE_TYPE)
        .map_err(|source| LanError::mdns("starting mDNS browse", source))?;

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
                if info.get_properties().get_property_val_str("ver") != Some(DRIFT_MDNS_TXT_VER) {
                    continue;
                }
                let Some(ticket) = ticket_from_txt(info.get_properties()) else {
                    continue;
                };
                if !verify_presence(&info) {
                    continue;
                }
                let label = info
                    .get_properties()
                    .get_property_val_str("label")
                    .unwrap_or("Drift receiver")
                    .to_owned();
                peers.insert(
                    info.get_fullname().to_owned(),
                    NearbyReceiver {
                        fullname: info.get_fullname().to_owned(),
                        label,
                        code: String::new(),
                        ticket,
                    },
                );
            }
            Ok(ServiceEvent::ServiceRemoved(_ty_domain, instance_fullname)) => {
                peers.remove(&instance_fullname);
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
    if let Some(exclude) = exclude_endpoint_id {
        list.retain(|r| {
            crate::util::decode_ticket(r.ticket.trim())
                .map(|addr| addr.id != exclude)
                .unwrap_or(true)
        });
    }
    list.sort_by(|a, b| {
        a.label
            .cmp(&b.label)
            .then_with(|| a.fullname.cmp(&b.fullname))
    });
    Ok(list)
}

impl LanError {
    fn mdns(context: &'static str, source: impl StdError + Send + Sync + 'static) -> Self {
        Self::Mdns {
            context,
            source: Box::new(source),
        }
    }
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

    #[test]
    fn presence_ping_pong_localhost() {
        let socket = match UdpSocket::bind("127.0.0.1:0") {
            Ok(socket) => socket,
            Err(error)
                if error.kind() == std::io::ErrorKind::PermissionDenied
                    || error.raw_os_error() == Some(1) =>
            {
                return;
            }
            Err(error) => panic!("bind: {error}"),
        };
        let port = socket.local_addr().unwrap().port();
        socket
            .set_read_timeout(Some(Duration::from_millis(500)))
            .unwrap();

        let stop = Arc::new(AtomicBool::new(false));
        let stop_t = Arc::clone(&stop);
        let join = std::thread::spawn(move || run_presence_loop(socket, stop_t));

        let target = SocketAddr::from(([127, 0, 0, 1], port));
        presence_ping(target, Duration::from_secs(1)).expect("ping");

        stop.store(true, Ordering::SeqCst);
        join.join().unwrap();
    }
}
