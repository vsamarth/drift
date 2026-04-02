use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args, ValueEnum};
use drift_app::{
    ConflictPolicy, OfferDecision, ReceiverConfig, ReceiverEvent, ReceiverOfferEvent,
    ReceiverOfferPhase, ReceiverService, SendConfig, SendEvent, SendPhase, SendSession,
};
use drift_core::util::{confirm_accept, human_size, process_display_device_name};
use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};
use iroh::SecretKey;
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
    let outcome = session
        .send_to_code(code, server_url, |event| {
            render_send_event(&mut last_phase, &mut progress_bar, &event)
        })
        .await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(()) => info!("send.completed"),
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome
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
    let outcome = session
        .send_to_nearby(
            picked.ticket.clone(),
            format!("Nearby: {}", picked.label),
            |event| render_send_event(&mut last_phase, &mut progress_bar, &event),
        )
        .await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(()) => info!("send.completed"),
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome
}

pub async fn receive(out_dir: PathBuf, server_url: Option<String>) -> Result<()> {
    let device_name = process_display_device_name();
    info!(
        out_dir = %out_dir.display(),
        server = ?server_url,
        device = %device_name,
        "receive.started"
    );

    let mut progress_bar = None;
    let mut last_phase = None;
    let service = ReceiverService::start(ReceiverConfig {
        device_name,
        device_type: "laptop".to_owned(),
        download_root: out_dir,
        conflict_policy: ConflictPolicy::Reject,
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
    let outcome = loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                break Ok(());
            }
            event = event_rx.recv() => {
                match event {
                    Ok(ReceiverEvent::OfferUpdated(event)) => {
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
                            ReceiverOfferPhase::Completed | ReceiverOfferPhase::Declined => {
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
            pb.set_message(event.status_message.clone());
        }
        SendPhase::Completed | SendPhase::Failed => finish_progress_bar(progress_bar),
        SendPhase::Connecting | SendPhase::WaitingForDecision => {}
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
