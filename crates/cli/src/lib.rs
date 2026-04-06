use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args, ValueEnum};
use drift_app::{
    ConflictPolicy, OfferDecision, ReceiverConfig, ReceiverEvent, ReceiverOfferEvent,
    ReceiverOfferPhase, ReceiverService, SendConfig, SendEvent, SendPhase, SendSession,
    SendSessionOutcome,
};
use drift_core::util::{confirm_accept, human_size, process_display_device_name};
use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};
use iroh::SecretKey;
use tokio::sync::watch;
use tokio::time::Duration;
use tracing::{debug, info, warn};
use tracing_subscriber::EnvFilter;

/// Log line format for stderr (`json` is one JSON object per line).
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq, ValueEnum)]
pub enum LogFormat {
    #[default]
    Pretty,
    Json,
}

/// Shared CLI flags (also available on subcommands via `global = true`).
#[derive(Args, Debug, Clone)]
pub struct LoggingOpts {
    /// Log line format for stderr
    #[arg(
        long,
        value_enum,
        default_value_t = LogFormat::Pretty,
        global = true,
        env = "DRIFT_LOG_FORMAT"
    )]
    pub log_format: LogFormat,

    /// Increase log verbosity for the `drift` target (repeat: `-v` debug, `-vv` trace). Ignored if `RUST_LOG` is set.
    #[arg(short, long, action = clap::ArgAction::Count, global = true)]
    pub verbose: u8,
}

pub fn init_tracing(log_format: LogFormat, verbose: u8) {
    let filter = log_env_filter(verbose);
    let result = match log_format {
        LogFormat::Pretty => tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_target(true)
            .with_writer(std::io::stderr)
            .try_init(),
        LogFormat::Json => tracing_subscriber::fmt()
            .json()
            .with_env_filter(filter)
            .with_target(true)
            .with_writer(std::io::stderr)
            .try_init(),
    };
    if result.is_err() {
        // Tests or embedders may have initialized tracing already.
    }
}

fn log_env_filter(verbose: u8) -> EnvFilter {
    if let Ok(directives) = std::env::var("RUST_LOG") {
        return EnvFilter::try_new(&directives).unwrap_or_else(|_| EnvFilter::new("warn"));
    }
    let level = match verbose {
        0 => "info",
        1 => "debug",
        _ => "trace",
    };
    EnvFilter::new(format!("warn,drift={level}"))
}

pub async fn send(code: String, files: Vec<PathBuf>, server_url: Option<String>) -> Result<()> {
    let device_name = process_display_device_name();
    let session = SendSession::new(
        SendConfig {
            device_name: device_name.clone(),
            device_type: "laptop".to_owned(),
        },
        files,
    );
    info!(
        code = %code.trim().to_uppercase(),
        file_count = session.paths().len(),
        device = %device_name,
        rendezvous_override = ?server_url,
        "send.started"
    );
    for (i, path) in session.paths().iter().enumerate() {
        debug!(index = i, path = %path.display(), "send.input_path");
    }

    let mut progress_bar = None;
    let mut last_phase = None;
    let mut metrics = SendProgressMetrics::default();
    let (cancel_tx, cancel_rx) = watch::channel(false);
    let outcome = {
        let send_future = session.send_to_code(code, server_url, Some(cancel_rx), |event| {
            render_send_event(&mut last_phase, &mut progress_bar, &mut metrics, &event)
        });
        tokio::pin!(send_future);
        let mut cancellation_requested = false;
        let result = loop {
            tokio::select! {
                result = &mut send_future => break result,
                _ = tokio::signal::ctrl_c(), if !cancellation_requested => {
                    cancellation_requested = true;
                    info!("send.cancel_requested");
                    let _ = cancel_tx.send(true);
                }
            }
        };
        drop(send_future);
        result
    };
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(SendSessionOutcome::Completed) => info!("send.completed"),
        Ok(SendSessionOutcome::Cancelled) => info!("send.cancelled"),
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }
    outcome.map(|_| ())
}

pub async fn send_nearby(
    files: Vec<PathBuf>,
    nearby_timeout_secs: u64,
    _server_url: Option<String>,
) -> Result<()> {
    let device_name = process_display_device_name();
    let session = SendSession::new(
        SendConfig {
            device_name: device_name.clone(),
            device_type: "laptop".to_owned(),
        },
        files,
    );
    info!(
        file_count = session.paths().len(),
        device = %device_name,
        scan_secs = nearby_timeout_secs.max(1),
        "send.nearby_started"
    );

    let receivers = session.scan_nearby(nearby_timeout_secs).await?;

    if receivers.is_empty() {
        bail!(
            "no Drift receivers found on the LAN. \
             On the other machine run `drift receive` (same Wi-Fi / LAN), then try again."
        );
    }

    eprintln!("Nearby receivers:");
    for (i, receiver) in receivers.iter().enumerate() {
        eprintln!("  {}. {}", i + 1, receiver.label);
    }
    let upper = receivers.len();
    eprint!("Enter number (1-{upper}), or q to quit: ");
    io::stdout().flush().context("flushing prompt")?;

    let mut line = String::new();
    io::stdin().read_line(&mut line).context("reading choice")?;
    let trimmed = line.trim();
    if trimmed.eq_ignore_ascii_case("q") {
        bail!("cancelled");
    }
    let idx: usize = trimmed
        .parse()
        .with_context(|| format!("expected a number 1-{upper}, got {trimmed:?}"))?;
    if idx == 0 || idx > upper {
        bail!("choice must be between 1 and {upper}");
    }

    let picked = &receivers[idx - 1];
    info!(label = %picked.label, "send.nearby_picked");

    let mut progress_bar = None;
    let mut last_phase = None;
    let mut metrics = SendProgressMetrics::default();
    let (cancel_tx, cancel_rx) = watch::channel(false);
    let outcome = {
        let send_future = session.send_to_nearby(
            picked.ticket.clone(),
            format!("Nearby: {}", picked.label),
            Some(cancel_rx),
            |event| render_send_event(&mut last_phase, &mut progress_bar, &mut metrics, &event),
        );
        tokio::pin!(send_future);
        let mut cancellation_requested = false;
        let result = loop {
            tokio::select! {
                result = &mut send_future => break result,
                _ = tokio::signal::ctrl_c(), if !cancellation_requested => {
                    cancellation_requested = true;
                    info!("send.cancel_requested");
                    let _ = cancel_tx.send(true);
                }
            }
        };
        drop(send_future);
        result
    };
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(SendSessionOutcome::Completed) => info!("send.completed"),
        Ok(SendSessionOutcome::Cancelled) => info!("send.cancelled"),
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome.map(|_| ())
}

pub async fn receive(out_dir: PathBuf, conflict: String, server_url: Option<String>) -> Result<()> {
    let device_name = process_display_device_name();
    let conflict_policy = match conflict.to_lowercase().as_str() {
        "rename" => ConflictPolicy::Rename,
        "overwrite" => ConflictPolicy::Overwrite,
        "reject" => ConflictPolicy::Reject,
        _ => bail!("invalid conflict strategy: {conflict}. Use: rename, overwrite, or reject"),
    };
    info!(
        out_dir = %out_dir.display(),
        server = ?server_url,
        device = %device_name,
        conflict_strategy = ?conflict_policy,
        "receive.started"
    );

    let mut progress_bar = None;
    let mut last_phase = None;
    let service = ReceiverService::start(ReceiverConfig {
        device_name,
        device_type: "laptop".to_owned(),
        download_root: out_dir,
        conflict_policy,
        secret_key: SecretKey::from_bytes(&rand::random()),
    })
    .await?;

    let registration = service.setup(server_url).await?;
    info!(code = %registration.code, expires_at = %registration.expires_at, "receive.ready");
    eprintln!(
        "Pairing code: {} (expires {})",
        registration.code, registration.expires_at
    );
    if let Err(error) = service.set_discoverable(true).await {
        warn!(error = %error, "receive.discoverability_unavailable");
    }

    let mut event_rx = service.subscribe_events();
    let mut current_offer_phase = None;
    let mut cancellation_requested = false;
    let outcome = loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                match current_offer_phase {
                    Some(ReceiverOfferPhase::OfferReady) if !cancellation_requested => {
                        cancellation_requested = true;
                        info!("receive.decline_requested");
                        service.respond_to_offer(OfferDecision::Decline).await?;
                    }
                    Some(ReceiverOfferPhase::Receiving) if !cancellation_requested => {
                        cancellation_requested = true;
                        info!("receive.cancel_requested");
                        service.cancel_transfer().await?;
                    }
                    _ => break Ok(()),
                }
            }
            event = event_rx.recv() => {
                match event {
                    Ok(ReceiverEvent::OfferUpdated(event)) => {
                        current_offer_phase = Some(event.phase);
                        render_receive_event(&mut last_phase, &mut progress_bar, &event);
                        match event.phase {
                            ReceiverOfferPhase::OfferReady => {
                                let accept = tokio::task::spawn_blocking(confirm_accept)
                                    .await
                                    .context("confirm task")??;
                                let decision = if accept {
                                    OfferDecision::Accept
                                } else {
                                    OfferDecision::Decline
                                };
                                service.respond_to_offer(decision).await?;
                            }
                            ReceiverOfferPhase::Completed
                            | ReceiverOfferPhase::Declined
                            | ReceiverOfferPhase::Cancelled => {
                                break Ok(());
                            }
                            ReceiverOfferPhase::Failed => {
                                let message = event
                                    .error_message
                                    .clone()
                                    .unwrap_or_else(|| event.status_message.clone());
                                break Err(anyhow::anyhow!(message));
                            }
                            ReceiverOfferPhase::Connecting | ReceiverOfferPhase::Receiving => {}
                        }
                    }
                    Ok(ReceiverEvent::RegistrationUpdated(registration)) => {
                        info!(code = %registration.code, expires_at = %registration.expires_at, "receive.code_rotated");
                    }
                    Ok(ReceiverEvent::SetupCompleted(_)) => {}
                    Ok(ReceiverEvent::DiscoverabilityChanged { requested, active }) => {
                        debug!(requested, active, "receive.discoverability");
                    }
                    Ok(ReceiverEvent::Shutdown) => break Ok(()),
                    Err(tokio::sync::broadcast::error::RecvError::Closed) => break Ok(()),
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(skipped)) => {
                        debug!(skipped, "receive.event_lagged");
                    }
                }
            }
        }
    };
    finish_progress_bar(&mut progress_bar);
    let _ = service.shutdown().await;

    match &outcome {
        Ok(()) => info!("receive.session_finished_ok"),
        Err(e) => {
            warn!(error = %e, error_chain = %format!("{e:#}"), "receive.session_finished_err")
        }
    }

    outcome
}

fn render_send_event(
    last_phase: &mut Option<SendPhase>,
    progress_bar: &mut Option<ProgressBar>,
    metrics: &mut SendProgressMetrics,
    event: &SendEvent,
) {
    if last_phase.as_ref() != Some(&event.phase) {
        match event.phase {
            SendPhase::Connecting => debug!(phase = "connecting", "send.phase"),
            SendPhase::WaitingForDecision => {
                info!(phase = "waiting_for_decision", receiver = %event.destination_label, "send.phase");
            }
            SendPhase::Sending => {
                let path = event.connection_path.as_deref().unwrap_or("unknown");
                info!(
                    phase = "sending",
                    receiver = %event.destination_label,
                    connection_path = path,
                    file_count = event.item_count,
                    total_bytes = event.total_size,
                    total_human = %human_size(event.total_size),
                    "send.phase"
                );
            }
            SendPhase::Completed => {
                let path = event.connection_path.as_deref().unwrap_or("unknown");
                info!(
                    phase = "completed",
                    receiver = %event.destination_label,
                    connection_path = path,
                    bytes_sent = event.bytes_sent,
                    "send.phase"
                );
            }
            SendPhase::Cancelled => {
                info!(phase = "cancelled", receiver = %event.destination_label, "send.phase");
            }
            SendPhase::Failed => {
                warn!(phase = "failed", receiver = %event.destination_label, error = ?event.error_message, "send.phase");
            }
        }
        *last_phase = Some(event.phase);
    }

    match event.phase {
        SendPhase::Sending => {
            let pb = ensure_progress_bar(progress_bar, event.total_size);
            pb.set_position(event.bytes_sent);
            let now = std::time::Instant::now();
            let message = metrics.message_for(event, now);
            pb.set_message(message);
        }
        SendPhase::Completed | SendPhase::Cancelled | SendPhase::Failed => {
            metrics.reset();
            finish_progress_bar(progress_bar)
        }
        SendPhase::Connecting | SendPhase::WaitingForDecision => {
            metrics.reset();
        }
    }
}

fn render_receive_event(
    last_phase: &mut Option<ReceiverOfferPhase>,
    progress_bar: &mut Option<ProgressBar>,
    event: &ReceiverOfferEvent,
) {
    if last_phase.as_ref() != Some(&event.phase) {
        match event.phase {
            ReceiverOfferPhase::OfferReady => {
                info!(
                    phase = "waiting_for_decision",
                    sender = %event.sender_name,
                    file_count = event.item_count,
                    total_bytes = event.total_size_bytes,
                    total_human = %event.total_size_label,
                    "receive.phase"
                );
            }
            ReceiverOfferPhase::Receiving => {
                let path = event.connection_path.as_deref().unwrap_or("unknown");
                info!(
                    phase = "receiving",
                    sender = %event.sender_name,
                    connection_path = path,
                    file_count = event.item_count,
                    total_bytes = event.total_size_bytes,
                    "receive.phase"
                );
            }
            ReceiverOfferPhase::Completed => {
                let path = event.connection_path.as_deref().unwrap_or("unknown");
                info!(phase = "completed", sender = %event.sender_name, connection_path = path, "receive.phase");
            }
            ReceiverOfferPhase::Declined => {
                info!(phase = "declined", sender = %event.sender_name, "receive.phase");
            }
            ReceiverOfferPhase::Cancelled => {
                info!(phase = "cancelled", sender = %event.sender_name, "receive.phase");
            }
            ReceiverOfferPhase::Failed => {
                warn!(phase = "failed", sender = %event.sender_name, error = ?event.error_message, "receive.phase");
            }
            ReceiverOfferPhase::Connecting => {}
        }
        *last_phase = Some(event.phase);
    }

    match event.phase {
        ReceiverOfferPhase::Receiving => {
            let pb = ensure_progress_bar(progress_bar, event.total_size_bytes.max(1));
            pb.set_position(event.bytes_received.min(event.total_size_bytes));
            pb.set_message(event.status_message.clone());
        }
        ReceiverOfferPhase::Completed
        | ReceiverOfferPhase::Cancelled
        | ReceiverOfferPhase::Declined
        | ReceiverOfferPhase::Failed => finish_progress_bar(progress_bar),
        ReceiverOfferPhase::OfferReady | ReceiverOfferPhase::Connecting => {}
    }
}

fn ensure_progress_bar(progress_bar: &mut Option<ProgressBar>, total: u64) -> &ProgressBar {
    if progress_bar.is_none() {
        let pb = ProgressBar::new(total);
        pb.set_draw_target(ProgressDrawTarget::stderr());
        pb.set_style(
            ProgressStyle::with_template(
                "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
            )
            .expect("valid indicatif template"),
        );
        pb.enable_steady_tick(Duration::from_millis(100));
        *progress_bar = Some(pb);
    }
    let pb = progress_bar.as_ref().expect("progress bar set");
    if total > 0 && pb.length().unwrap_or(0) == 0 {
        pb.set_length(total);
    }
    pb
}

fn finish_progress_bar(progress_bar: &mut Option<ProgressBar>) {
    if let Some(pb) = progress_bar.take() {
        pb.finish_and_clear();
    }
}

#[derive(Debug, Default)]
struct SendProgressMetrics {
    sample_started_at: Option<std::time::Instant>,
    sample_started_bytes: Option<u64>,
    smoothed_bps: Option<f64>,
}

impl SendProgressMetrics {
    const MIN_SAMPLE_INTERVAL: std::time::Duration = std::time::Duration::from_millis(80);
    const MIN_VISIBLE_BPS: f64 = 16.0;
    const EWMA_ALPHA: f64 = 0.22;

    fn reset(&mut self) {
        self.sample_started_at = None;
        self.sample_started_bytes = None;
        self.smoothed_bps = None;
    }

    fn message_for(&mut self, event: &SendEvent, now: std::time::Instant) -> String {
        if event.phase != SendPhase::Sending {
            self.reset();
            return event.status_message.clone();
        }

        let prev_at = self.sample_started_at;
        let prev_bytes = self.sample_started_bytes;
        if let (Some(prev_at), Some(prev_bytes)) = (prev_at, prev_bytes) {
            let dt = now.saturating_duration_since(prev_at);
            let d_bytes = event.bytes_sent.saturating_sub(prev_bytes);
            if dt >= Self::MIN_SAMPLE_INTERVAL && d_bytes > 0 {
                let inst_bps = d_bytes as f64 / dt.as_secs_f64();
                self.smoothed_bps = Some(match self.smoothed_bps {
                    Some(prev) => Self::EWMA_ALPHA * inst_bps + (1.0 - Self::EWMA_ALPHA) * prev,
                    None => inst_bps,
                });
                self.sample_started_at = Some(now);
                self.sample_started_bytes = Some(event.bytes_sent);
            }
        } else {
            self.sample_started_at = Some(now);
            self.sample_started_bytes = Some(event.bytes_sent);
        }

        build_send_progress_message(
            &event.status_message,
            self.smoothed_bps,
            event.bytes_sent,
            event.total_size,
        )
    }
}

fn build_send_progress_message(
    status_message: &str,
    smoothed_bps: Option<f64>,
    bytes_sent: u64,
    total_size: u64,
) -> String {
    let Some(bps) = smoothed_bps.filter(|bps| *bps >= SendProgressMetrics::MIN_VISIBLE_BPS) else {
        return status_message.to_owned();
    };

    let speed = format_bytes_per_second(bps);
    let remaining = total_size.saturating_sub(bytes_sent);
    let eta = if remaining == 0 {
        None
    } else {
        Some(format_eta_seconds(remaining as f64 / bps))
    };

    match eta {
        Some(eta) => format!("{status_message} {speed}, ETA {eta}"),
        None => format!("{status_message} {speed}"),
    }
}

fn format_bytes_per_second(bytes_per_second: f64) -> String {
    let rounded = bytes_per_second.max(0.0).round();
    format!("{}/s", human_size(rounded as u64))
}

fn format_eta_seconds(seconds: f64) -> String {
    let total_seconds = seconds.max(0.0).round() as u64;
    let hours = total_seconds / 3600;
    let minutes = (total_seconds % 3600) / 60;
    let secs = total_seconds % 60;

    if hours > 0 {
        format!("{hours}:{minutes:02}:{secs:02}")
    } else {
        format!("{minutes:02}:{secs:02}")
    }
}

#[cfg(test)]
mod tests {
    use super::{
        SendProgressMetrics, build_send_progress_message, format_bytes_per_second,
        format_eta_seconds,
    };
    use drift_app::{SendEvent, SendPhase};
    use std::time::{Duration, Instant};

    fn sending_event(bytes_sent: u64, total_size: u64) -> SendEvent {
        SendEvent {
            phase: SendPhase::Sending,
            destination_label: "Receiver".to_owned(),
            status_message: "Sending to Receiver.".to_owned(),
            item_count: 1,
            total_size,
            bytes_sent,
            remote_device_type: None,
            connection_path: None,
            error_message: None,
        }
    }

    #[test]
    fn metrics_hide_speed_until_sample_window_is_large_enough() {
        let mut metrics = SendProgressMetrics::default();
        let start = Instant::now();

        let initial = metrics.message_for(&sending_event(0, 2_000), start);
        let early = metrics.message_for(
            &sending_event(500, 2_000),
            start + Duration::from_millis(40),
        );

        assert_eq!(initial, "Sending to Receiver.");
        assert_eq!(early, "Sending to Receiver.");
    }

    #[test]
    fn metrics_show_speed_and_eta_after_valid_progress_samples() {
        let mut metrics = SendProgressMetrics::default();
        let start = Instant::now();

        let first = metrics.message_for(&sending_event(0, 2_000), start);
        let second = metrics.message_for(
            &sending_event(1_000, 2_000),
            start + Duration::from_millis(100),
        );

        assert_eq!(first, "Sending to Receiver.");
        assert_eq!(second, "Sending to Receiver. 9.8 KB/s, ETA 00:00");
    }

    #[test]
    fn metrics_accumulate_across_fast_callbacks_until_sample_window_opens() {
        let mut metrics = SendProgressMetrics::default();
        let start = Instant::now();

        let _ = metrics.message_for(&sending_event(0, 50_000), start);
        let _ = metrics.message_for(
            &sending_event(16_384, 50_000),
            start + Duration::from_millis(20),
        );
        let _ = metrics.message_for(
            &sending_event(32_768, 50_000),
            start + Duration::from_millis(40),
        );
        let final_message = metrics.message_for(
            &sending_event(49_152, 50_000),
            start + Duration::from_millis(100),
        );

        assert_eq!(final_message, "Sending to Receiver. 480.0 KB/s, ETA 00:00");
    }

    #[test]
    fn metrics_apply_ewma_and_reset_outside_sending_phase() {
        let mut metrics = SendProgressMetrics::default();
        let start = Instant::now();

        let _ = metrics.message_for(&sending_event(0, 4_000), start);
        let _ = metrics.message_for(
            &sending_event(1_000, 4_000),
            start + Duration::from_millis(100),
        );
        let third = metrics.message_for(
            &sending_event(2_000, 4_000),
            start + Duration::from_millis(200),
        );

        assert_eq!(third, "Sending to Receiver. 9.8 KB/s, ETA 00:00");

        let completed = SendEvent {
            phase: SendPhase::Completed,
            destination_label: "Receiver".to_owned(),
            status_message: "Files sent successfully".to_owned(),
            item_count: 1,
            total_size: 4_000,
            bytes_sent: 4_000,
            remote_device_type: None,
            connection_path: None,
            error_message: None,
        };
        let completed_message = metrics.message_for(&completed, start + Duration::from_millis(300));
        assert_eq!(completed_message, "Files sent successfully");

        let restarted = metrics.message_for(
            &sending_event(500, 4_000),
            start + Duration::from_millis(400),
        );
        assert_eq!(restarted, "Sending to Receiver.");
    }

    #[test]
    fn build_message_omits_eta_when_transfer_is_complete() {
        let message = build_send_progress_message("Sending to Receiver.", Some(2_048.0), 10, 10);
        assert_eq!(message, "Sending to Receiver. 2.0 KB/s");
    }

    #[test]
    fn formatting_helpers_match_cli_output_expectations() {
        assert_eq!(format_bytes_per_second(1_536.0), "1.5 KB/s");
        assert_eq!(format_eta_seconds(5.0), "00:05");
        assert_eq!(format_eta_seconds(3_725.0), "1:02:05");
    }
}
