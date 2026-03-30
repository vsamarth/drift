use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args, ValueEnum};
use drift_core::lan;
use drift_core::receiver::{
    ReceiveTransferPhase, ReceiveTransferProgress, handle_receiver_connection_with_progress,
};
use drift_core::rendezvous::RendezvousClient;
use drift_core::sender::{
    SendTransferPhase, SendTransferProgress, send_files_with_progress,
    send_files_with_progress_via_lan_ticket,
};
use drift_core::session::bind_endpoint;
use drift_core::transfer::{ReceiverMachine, ReceiverState};
use drift_core::util::{confirm_accept, describe_remote, human_size, random_device_name};
use drift_core::wire::DeviceType;
use drift_core::wire::make_ticket;
use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio::fs;
use tokio::signal;
use tokio::time::{Duration, Instant, MissedTickBehavior, interval};
use tracing::{debug, info, warn};
use tracing_subscriber::EnvFilter;

const CONNECT_GRACE_PERIOD: Duration = Duration::from_secs(30);

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

/// Install a global tracing subscriber. Call once at process start.
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
    let code_normalized = code.trim().to_uppercase();
    let device_name = local_device_name();
    let device_type = DeviceType::Laptop;
    info!(
        code = %code_normalized,
        file_count = files.len(),
        device = %device_name,
        rendezvous_override = ?server_url,
        "send.started"
    );
    for (i, path) in files.iter().enumerate() {
        debug!(index = i, path = %path.display(), "send.input_path");
    }

    let mut last_phase = None;

    // Create the progress bar lazily only once the receiver has accepted and
    // payload streaming starts.
    let mut progress_bar: Option<ProgressBar> = None;

    let mut transfer_done = false;
    let mut length_set = false;
    let outcome = send_files_with_progress(
        code,
        files,
        server_url,
        device_name,
        device_type,
        |progress| {
            log_send_progress(&mut last_phase, &progress);

            match progress.phase {
                SendTransferPhase::Connecting | SendTransferPhase::WaitingForDecision => {}
                SendTransferPhase::Sending => {
                    if progress_bar.is_none() {
                        let pb = ProgressBar::new(0);
                        pb.set_draw_target(ProgressDrawTarget::stderr());
                        pb.set_style(
                            ProgressStyle::with_template(
                                "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
                            )
                            .expect("valid indicatif template"),
                        );
                        pb.enable_steady_tick(Duration::from_millis(100));
                        progress_bar = Some(pb);
                    }
                    let pb = progress_bar.as_ref().expect("progress bar set");

                    // Set the total once we have it (it comes from the manifest).
                    if !length_set {
                        pb.set_length(progress.manifest.total_size);
                        length_set = true;
                    }
                    pb.set_position(progress.bytes_sent);

                    let msg = match progress.current_file_index {
                        Some(idx) => {
                            let i = idx as usize;
                            progress.manifest.files.get(i).map_or_else(
                                || format!("file {idx}"),
                                |f| format!("file: {} ({}/{}) bytes", f.path, progress.bytes_sent_in_file, f.size),
                            )
                        }
                        None => "starting...".to_string(),
                    };
                    pb.set_message(msg);
                }
                SendTransferPhase::Completed => {
                    transfer_done = true;
                    if let Some(pb) = progress_bar.take() {
                        pb.finish_and_clear();
                    }
                }
            }
        },
    )
    .await;

    // If the transfer errors out (e.g. receiver declined), we may never see `Completed`.
    if let Some(pb) = progress_bar.take() {
        if !transfer_done {
            pb.finish_and_clear();
        }
    }

    match &outcome {
        Ok(o) => info!(
            receiver = %o.receiver_device_name,
            file_count = o.manifest.file_count,
            total_bytes = o.manifest.total_size,
            "send.completed"
        ),
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome.map(|_| ())
}

/// Send after picking a receiver discovered via mDNS (`--nearby`).
pub async fn send_nearby(
    files: Vec<PathBuf>,
    nearby_timeout_secs: u64,
    _server_url: Option<String>,
) -> Result<()> {
    let scan = Duration::from_secs(nearby_timeout_secs.max(1));
    let device_name = local_device_name();
    let device_type = DeviceType::Laptop;

    info!(
        file_count = files.len(),
        device = %device_name,
        scan_secs = scan.as_secs(),
        "send.nearby_started"
    );

    let receivers = tokio::task::spawn_blocking(move || lan::browse_nearby_receivers(scan))
        .await
        .context("mdns browse task")??;

    if receivers.is_empty() {
        bail!(
            "no Drift receivers found on the LAN. \
             On the other machine run `drift receive` (same Wi‑Fi / LAN), then try again."
        );
    }

    eprintln!("Nearby receivers:");
    for (i, r) in receivers.iter().enumerate() {
        let code_display = if r.code.is_empty() {
            "—".to_owned()
        } else {
            r.code.clone()
        };
        eprintln!("  {}. {}  (code {})", i + 1, r.label, code_display);
    }

    let upper = receivers.len();
    eprint!("Enter number (1–{upper}), or q to quit: ");
    io::stdout().flush().context("flushing prompt")?;

    let mut line = String::new();
    io::stdin().read_line(&mut line).context("reading choice")?;
    let trimmed = line.trim();
    if trimmed.eq_ignore_ascii_case("q") {
        bail!("cancelled");
    }
    let idx: usize = trimmed
        .parse()
        .with_context(|| format!("expected a number 1–{upper}, got {trimmed:?}"))?;
    if idx == 0 || idx > upper {
        bail!("choice must be between 1 and {upper}");
    }

    let picked = &receivers[idx - 1];
    let destination_label = if picked.code.is_empty() {
        format!("Nearby: {}", picked.label)
    } else {
        format!("Nearby: {} ({})", picked.label, picked.code)
    };

    info!(
        label = %picked.label,
        code = %picked.code,
        "send.nearby_picked"
    );

    let mut last_phase = None;
    let mut progress_bar: Option<ProgressBar> = None;
    let mut transfer_done = false;
    let mut length_set = false;

    let outcome = send_files_with_progress_via_lan_ticket(
        picked.ticket.clone(),
        destination_label,
        files,
        device_name,
        device_type,
        |progress| {
            log_send_progress(&mut last_phase, &progress);

            match progress.phase {
                SendTransferPhase::Connecting | SendTransferPhase::WaitingForDecision => {}
                SendTransferPhase::Sending => {
                    if progress_bar.is_none() {
                        let pb = ProgressBar::new(0);
                        pb.set_draw_target(ProgressDrawTarget::stderr());
                        pb.set_style(
                            ProgressStyle::with_template(
                                "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
                            )
                            .expect("valid indicatif template"),
                        );
                        pb.enable_steady_tick(Duration::from_millis(100));
                        progress_bar = Some(pb);
                    }
                    let pb = progress_bar.as_ref().expect("progress bar set");

                    if !length_set {
                        pb.set_length(progress.manifest.total_size);
                        length_set = true;
                    }
                    pb.set_position(progress.bytes_sent);

                    let msg = match progress.current_file_index {
                        Some(idx) => {
                            let i = idx as usize;
                            progress.manifest.files.get(i).map_or_else(
                                || format!("file {idx}"),
                                |f| format!(
                                    "file: {} ({}/{}) bytes",
                                    f.path, progress.bytes_sent_in_file, f.size
                                ),
                            )
                        }
                        None => "starting...".to_string(),
                    };
                    pb.set_message(msg);
                }
                SendTransferPhase::Completed => {
                    transfer_done = true;
                    if let Some(pb) = progress_bar.take() {
                        pb.finish_and_clear();
                    }
                }
            }
        },
    )
    .await;

    if let Some(pb) = progress_bar.take() {
        if !transfer_done {
            pb.finish_and_clear();
        }
    }

    match &outcome {
        Ok(o) => info!(
            receiver = %o.receiver_device_name,
            file_count = o.manifest.file_count,
            total_bytes = o.manifest.total_size,
            "send.completed"
        ),
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome.map(|_| ())
}

pub async fn receive(out_dir: PathBuf, server_url: Option<String>) -> Result<()> {
    let resolved_url = drift_core::rendezvous::resolve_server_url(server_url.as_deref());
    info!(
        out_dir = %out_dir.display(),
        server = %resolved_url,
        device = %local_device_name(),
        "receive.started"
    );

    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let client = RendezvousClient::new(resolved_url.clone());
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let ticket = make_ticket(&endpoint).await?;
    let registration = client.register_peer(ticket.clone()).await?;
    let expires_at = OffsetDateTime::parse(&registration.expires_at, &Rfc3339)
        .context("parsing discovery expiry")?;
    let device_name = local_device_name();
    let device_type = DeviceType::Laptop;

    let mut machine = ReceiverMachine::new();
    machine.transition(ReceiverState::Discoverable)?;

    info!(
        code = %registration.code,
        expires_at = %registration.expires_at,
        out_dir = %out_dir.display(),
        device = %device_name,
        "receive.registered"
    );
    info!(code = %registration.code, "receive.waiting_for_sender");

    let _lan_advertise =
        match lan::LanReceiveAdvertisement::start(&ticket, &device_name, &registration.code) {
            Ok(Some(guard)) => {
                info!("receive.lan_mdns_publishing");
                Some(guard)
            }
            Ok(None) => {
                info!("receive.lan_mdns_skipped_no_ipv4");
                None
            }
            Err(e) => {
                warn!(
                    error = %e,
                    error_chain = %format!("{e:#}"),
                    "receive.lan_mdns_publish_failed"
                );
                None
            }
        };

    let mut accept_future = Box::pin(endpoint.accept());
    let mut poll = interval(Duration::from_secs(2));
    poll.set_missed_tick_behavior(MissedTickBehavior::Delay);
    poll.tick().await;
    let mut ctrl_c = Box::pin(signal::ctrl_c());
    let mut claimed_at: Option<Instant> = None;

    loop {
        tokio::select! {
            _ = &mut ctrl_c => {
                debug!("receive.ctrl_c");
                endpoint.close().await;
                info!("receive.stopped_by_user");
                return Ok(());
            }
            incoming = &mut accept_future => {
                machine.transition(ReceiverState::Connecting)?;
                let incoming = incoming.context("receiver stopped before a sender connected")?;
                let connection = incoming.await.context("accepting sender connection")?;
                let remote_label = describe_remote(
                    connection.remote_id(),
                    endpoint.remote_info(connection.remote_id()).await.as_ref()
                );
                info!(
                    remote_id = %connection.remote_id(),
                    remote = %remote_label,
                    "receive.peer_connected"
                );
                machine.transition(ReceiverState::Connected)?;
                let mut last_phase: Option<ReceiveTransferPhase> = None;

                // Create the progress bar lazily only once the offer is accepted.
                // (So users don't see a bar while waiting for confirmation.)
                let mut progress_bar: Option<ProgressBar> = None;

                let mut transfer_done = false;
                let mut length_set = false;

                let mut final_phase: Option<ReceiveTransferPhase> = None;
                let mut completed_sender_device_name: Option<String> = None;
                let mut completed_file_count: u64 = 0;
                let mut completed_total_bytes: u64 = 0;

                let result = handle_receiver_connection_with_progress(
                    connection,
                    out_dir.clone(),
                    &device_name,
                    device_type,
                    &mut machine,
                    async {
                        tokio::task::spawn_blocking(|| confirm_accept())
                            .await
                            .context("confirm task")?
                    },
                    |progress: ReceiveTransferProgress| {
                        log_receive_progress(&mut last_phase, &progress);

                        match progress.phase {
                            ReceiveTransferPhase::WaitingForDecision => {}
                            ReceiveTransferPhase::Receiving => {
                                if progress_bar.is_none() {
                                    let pb = ProgressBar::new(0);
                                    pb.set_draw_target(ProgressDrawTarget::stderr());
                                    pb.set_style(
                                        ProgressStyle::with_template(
                                            "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
                                        )
                                        .expect("valid indicatif template"),
                                    );
                                    pb.enable_steady_tick(Duration::from_millis(100));
                                    progress_bar = Some(pb);
                                }

                                let pb = progress_bar.as_ref().expect("progress bar set");

                                if !length_set && progress.bytes_to_receive > 0 {
                                    pb.set_length(progress.bytes_to_receive);
                                    length_set = true;
                                }
                                if length_set {
                                    pb.set_position(progress.bytes_received);
                                }

                                let msg = match progress.current_file_path {
                                    Some(path) => format!(
                                        "file: {} ({}/{}) bytes",
                                        path, progress.bytes_received_in_file, progress.current_file_size
                                    ),
                                    None => "starting...".to_string(),
                                };
                                pb.set_message(msg);
                            }
                            ReceiveTransferPhase::Completed => {
                                final_phase = Some(ReceiveTransferPhase::Completed);
                                completed_sender_device_name =
                                    Some(progress.sender_device_name.clone());
                                completed_file_count = progress.file_count;
                                completed_total_bytes = progress.total_bytes;
                                transfer_done = true;
                                if let Some(pb) = progress_bar.take() {
                                    pb.finish_and_clear();
                                }
                            }
                            ReceiveTransferPhase::Declined => {
                                final_phase = Some(ReceiveTransferPhase::Declined);
                                completed_sender_device_name =
                                    Some(progress.sender_device_name.clone());
                                completed_file_count = progress.file_count;
                                completed_total_bytes = progress.total_bytes;
                                transfer_done = true;
                                if let Some(pb) = progress_bar.take() {
                                    pb.finish_and_clear();
                                }
                            }
                            ReceiveTransferPhase::Failed => {
                                final_phase = Some(ReceiveTransferPhase::Failed);
                                transfer_done = true;
                                if let Some(pb) = progress_bar.take() {
                                    pb.finish_and_clear();
                                }
                            }
                        }
                    },
                )
                .await;

                endpoint.close().await;

                if let Some(pb) = progress_bar.take() {
                    // If anything unexpected happened, make sure we don't leave the bar hanging.
                    // Normal completion paths already finish it in the callback.
                    if !transfer_done {
                        pb.finish_and_clear();
                    }
                }

                match &result {
                    Ok(()) => match final_phase {
                        Some(ReceiveTransferPhase::Completed) => {
                            info!(
                                sender = %completed_sender_device_name.unwrap_or_else(|| "Sender".to_owned()),
                                file_count = completed_file_count,
                                total_bytes = completed_total_bytes,
                                total_human = %human_size(completed_total_bytes),
                                "receive.completed"
                            );
                        }
                        Some(ReceiveTransferPhase::Declined) => {
                            info!(
                                sender = %completed_sender_device_name.unwrap_or_else(|| "Sender".to_owned()),
                                file_count = completed_file_count,
                                total_bytes = completed_total_bytes,
                                "receive.declined"
                            );
                        }
                        _ => info!("receive.session_finished_ok"),
                    },
                    Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "receive.session_finished_err"),
                }
                return result;
            }
            _ = poll.tick() => {
                match client.pair_status(&registration.code).await? {
                    Some(status) => {
                        debug!(code = %registration.code, ?status, "receive.pair_status_open");
                    }
                    None => {
                        if claimed_at.is_none() {
                            if OffsetDateTime::now_utc() >= expires_at {
                                warn!(code = %registration.code, "receive.code_expired");
                                endpoint.close().await;
                                return Ok(());
                            }
                            claimed_at = Some(Instant::now());
                            info!(code = %registration.code, "receive.code_claimed_waiting_connect");
                        } else if claimed_at.unwrap().elapsed() >= CONNECT_GRACE_PERIOD {
                            warn!(
                                code = %registration.code,
                                grace_secs = CONNECT_GRACE_PERIOD.as_secs(),
                                "receive.claim_connect_timeout"
                            );
                            bail!("sender claimed the code but did not connect in time");
                        }
                    }
                }
            }
        }
    }
}

fn local_device_name() -> String {
    for key in ["DRIFT_DEVICE_NAME", "HOSTNAME", "COMPUTERNAME"] {
        if let Ok(value) = std::env::var(key) {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return trimmed.to_owned();
            }
        }
    }

    random_device_name()
}

fn log_send_progress(last_phase: &mut Option<SendTransferPhase>, progress: &SendTransferProgress) {
    if last_phase.as_ref() == Some(&progress.phase) {
        return;
    }

    match progress.phase {
        SendTransferPhase::Connecting => {
            debug!(phase = "connecting", "send.phase");
        }
        SendTransferPhase::WaitingForDecision => {
            info!(
                phase = "waiting_for_decision",
                receiver = %progress.destination_label,
                "send.phase"
            );
        }
        SendTransferPhase::Sending => {
            info!(
                phase = "sending",
                receiver = %progress.destination_label,
                file_count = progress.manifest.file_count,
                total_bytes = progress.manifest.total_size,
                total_human = %human_size(progress.manifest.total_size),
                "send.phase"
            );
        }
        SendTransferPhase::Completed => {
            info!(
                phase = "completed",
                receiver = %progress.destination_label,
                bytes_sent = progress.bytes_sent,
                "send.phase"
            );
        }
    }

    *last_phase = Some(progress.phase);
}

fn log_receive_progress(
    last_phase: &mut Option<ReceiveTransferPhase>,
    progress: &ReceiveTransferProgress,
) {
    if last_phase.as_ref() == Some(&progress.phase) {
        return;
    }

    match progress.phase {
        ReceiveTransferPhase::WaitingForDecision => {
            info!(
                phase = "waiting_for_decision",
                sender = %progress.sender_device_name,
                file_count = progress.file_count,
                total_bytes = progress.total_bytes,
                total_human = %human_size(progress.total_bytes),
                "receive.phase"
            );
        }
        ReceiveTransferPhase::Receiving => {
            info!(
                phase = "receiving",
                sender = %progress.sender_device_name,
                file_count = progress.file_count,
                total_bytes = progress.total_bytes,
                bytes_received = progress.bytes_received,
                "receive.phase"
            );
        }
        ReceiveTransferPhase::Completed => {
            info!(
                phase = "completed",
                sender = %progress.sender_device_name,
                bytes_received = progress.bytes_received,
                "receive.phase"
            );
        }
        ReceiveTransferPhase::Declined => {
            info!(
                phase = "declined",
                sender = %progress.sender_device_name,
                "receive.phase"
            );
        }
        ReceiveTransferPhase::Failed => {
            warn!(
                phase = "failed",
                sender = %progress.sender_device_name,
                error = ?progress.error_message,
                "receive.phase"
            );
        }
    }

    *last_phase = Some(progress.phase);
}
