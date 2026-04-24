use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, ValueEnum};
use drift_app::{
    ConflictPolicy, OfferDecision, ReceiverConfig, ReceiverEvent, ReceiverOfferEvent,
    ReceiverOfferPhase, ReceiverService, SendConfig, SendDestination, SendDraft, SendEvent,
    SendPhase, SendRun, SendSessionOutcome, TransferPlan, TransferSnapshot, UserFacingError,
    from_anyhow_error,
};
use drift_core::util::{confirm_accept, human_size, process_display_device_name};
use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};
use iroh::SecretKey;
use rand::random;
use tokio::sync::broadcast::error::RecvError;
use tokio::time::Duration;
use tokio_stream::StreamExt;
use tracing::{info, warn};
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

pub async fn send(code: String, files: Vec<PathBuf>) -> Result<()> {
    send_with_server(code, files, None).await
}

pub async fn send_with_server(
    code: String,
    files: Vec<PathBuf>,
    server_url: Option<String>,
) -> Result<()> {
    let device_name = process_display_device_name();
    let draft = SendDraft::new(
        SendConfig {
            device_name: device_name.clone(),
            device_type: "laptop".to_owned(),
        },
        files,
    );

    info!(
        code = %code.trim().to_uppercase(),
        file_count = draft.paths().len(),
        device = %device_name,
        rendezvous_override = ?server_url,
        "send.resolving_code"
    );

    let session = draft.into_session(SendDestination::code(code, server_url));

    let mut progress_bar = None;
    let run = session.start();
    let outcome = consume_sender_run(run, &mut progress_bar).await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(SendSessionOutcome::Accepted { .. }) => {
            info!("send.completed");
        }
        Ok(SendSessionOutcome::Declined { reason }) => {
            info!(reason = %reason, "send.declined");
        }
        Err(_) => {}
    }
    outcome.map(|_| ())
}

pub async fn send_nearby(
    files: Vec<PathBuf>,
    nearby_timeout_secs: u64,
    _server_url: Option<String>,
) -> Result<()> {
    let device_name = process_display_device_name();
    let draft = SendDraft::new(
        SendConfig {
            device_name: device_name.clone(),
            device_type: "laptop".to_owned(),
        },
        files,
    );

    info!(
        file_count = draft.paths().len(),
        device = %device_name,
        scan_secs = nearby_timeout_secs.max(1),
        "send.nearby_scanning"
    );

    let receivers = draft.scan_nearby(nearby_timeout_secs).await?;

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
    info!(label = %picked.label, endpoint = %picked.fullname, "send.nearby_picked");

    let session = draft.into_session(SendDestination::nearby(
        picked.ticket.clone(),
        picked.label.clone(),
    ));

    let mut progress_bar = None;
    let run = session.start();
    let outcome = consume_sender_run(run, &mut progress_bar).await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(SendSessionOutcome::Accepted { .. }) => {
            info!("send.completed");
        }
        Ok(SendSessionOutcome::Declined { reason }) => {
            info!(reason = %reason, "send.declined");
        }
        Err(_) => {}
    }

    outcome.map(|_| ())
}

async fn consume_sender_run(
    run: SendRun,
    progress_bar: &mut Option<ProgressBar>,
) -> Result<SendSessionOutcome> {
    let cancel_handle = run.cancel_handle();
    let (mut events, outcome_rx) = run.into_parts();

    let mut outcome_rx = outcome_rx;
    let mut current_plan: Option<TransferPlan> = None;
    let mut reported_failure = false;
    loop {
        tokio::select! {
            event = events.next() => {
                match event {
                    Some(event) => {
                        reported_failure |= render_sender_event(progress_bar, &event, &mut current_plan);
                    }
                    None => break,
                }
            }
            _ = tokio::signal::ctrl_c() => {
                info!("send.cancel_requested");
                let _ = cancel_handle.cancel_transfer().await;
                return Err(anyhow!("cancelled"));
            }
            res = &mut outcome_rx => {
                finish_progress_bar(progress_bar);
                let outcome = res.context("waiting for send outcome")?;
                match outcome {
                    Ok(outcome) => return Ok(outcome),
                    Err(error) => {
                        if !reported_failure {
                            report_anyhow_failure("send.failed", &error.clone().into(), false);
                        }
                        return Err(error.into());
                    }
                }
            }
        }
    }

    finish_progress_bar(progress_bar);
    let outcome = outcome_rx.await.context("waiting for send outcome")?;
    match outcome {
        Ok(outcome) => Ok(outcome),
        Err(error) => {
            if !reported_failure {
                report_anyhow_failure("send.failed", &error.clone().into(), false);
            }
            Err(error.into())
        }
    }
}

fn render_sender_event(
    progress_bar: &mut Option<ProgressBar>,
    event: &SendEvent,
    current_plan: &mut Option<TransferPlan>,
) -> bool {
    match event {
        SendEvent {
            phase: SendPhase::Connecting,
            destination_label,
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!("Connecting to {destination_label}..."));
            false
        }
        SendEvent {
            phase: SendPhase::WaitingForDecision,
            destination_label,
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!("Waiting for {destination_label} to accept..."));
            false
        }
        SendEvent {
            phase: SendPhase::Accepted,
            destination_label,
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!(
                "Accepted by {destination_label}. Starting transfer..."
            ));
            false
        }
        SendEvent {
            phase: SendPhase::Sending,
            plan: Some(plan),
            snapshot: None,
            ..
        } => {
            *current_plan = Some(plan.clone());
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, plan.total_bytes);
            pb.set_message(render_transfer_message("Sending", Some(plan), None));
            false
        }
        SendEvent {
            phase: SendPhase::Sending,
            snapshot: Some(snapshot),
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Sending",
                current_plan.as_ref(),
                Some(snapshot),
            ));
            false
        }
        SendEvent {
            phase: SendPhase::Completed,
            snapshot: Some(snapshot),
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Sending",
                current_plan.as_ref(),
                Some(snapshot),
            ));
            finish_progress_bar(progress_bar);
            false
        }
        SendEvent {
            phase: SendPhase::Declined,
            error: Some(error),
            ..
        }
        | SendEvent {
            phase: SendPhase::Failed,
            error: Some(error),
            ..
        } => {
            finish_progress_bar(progress_bar);
            report_user_facing_error("send.failed", error);
            true
        }
        SendEvent {
            phase: SendPhase::Declined,
            ..
        }
        | SendEvent {
            phase: SendPhase::Failed,
            ..
        } => {
            finish_progress_bar(progress_bar);
            false
        }
        _ => false,
    }
}

pub async fn receive(out_dir: PathBuf, conflict: String, server_url: Option<String>) -> Result<()> {
    let device_name = process_display_device_name();
    info!(
        out_dir = %out_dir.display(),
        conflict = %conflict,
        server = ?server_url,
        device = %device_name,
        "receive.started"
    );

    let config = ReceiverConfig {
        device_name,
        device_type: "laptop".to_owned(),
        download_root: out_dir,
        conflict_policy: parse_conflict_policy(&conflict)?,
        secret_key: SecretKey::from_bytes(&random::<[u8; 32]>()),
    };
    let service = match ReceiverService::start(config).await {
        Ok(service) => service,
        Err(error) => {
            report_anyhow_failure("receive.failed", &error.clone().into(), false);
            return Err(error.into());
        }
    };

    let registration = match service.ensure_registered(server_url).await {
        Ok(registration) => registration,
        Err(error) => {
            report_anyhow_failure("receive.failed", &error.clone().into(), false);
            return Err(error.into());
        }
    };

    info!(code = %registration.code, expires_at = %registration.expires_at, "receive.ready");
    eprintln!(
        "Pairing code: {} (expires {})",
        registration.code, registration.expires_at
    );
    eprintln!("Waiting for a sender to connect...");

    let mut events = service.subscribe_events();
    let mut progress_bar = None;
    let mut current_plan: Option<TransferPlan> = None;
    let mut terminal_event: Option<ReceiverOfferEvent> = None;
    let mut reported_failure = false;

    loop {
        tokio::select! {
            event = events.recv() => {
                match event {
                    Ok(ReceiverEvent::OfferUpdated(event)) => {
                        match event.phase {
                            ReceiverOfferPhase::Connecting => {
                                let pb = ensure_spinner(&mut progress_bar);
                                pb.set_message("Connecting...");
                            }
                            ReceiverOfferPhase::OfferReady => {
                                render_offer(&event);
                                let accepted = confirm_accept()?;
                                let decision = if accepted {
                                    OfferDecision::Accept
                                } else {
                                    OfferDecision::Decline
                                };
                                service.respond_to_offer(decision).await?;
                                if !accepted {
                                    info!("receive.declined_local");
                                }
                            }
                            ReceiverOfferPhase::Receiving
                            | ReceiverOfferPhase::Completed
                            | ReceiverOfferPhase::Cancelled
                            | ReceiverOfferPhase::Failed
                            | ReceiverOfferPhase::Declined => {
                                reported_failure |=
                                    render_receiver_event(&mut progress_bar, &event, &mut current_plan);
                                if matches!(
                                    event.phase,
                                    ReceiverOfferPhase::Completed
                                        | ReceiverOfferPhase::Cancelled
                                        | ReceiverOfferPhase::Failed
                                        | ReceiverOfferPhase::Declined
                                ) {
                                    terminal_event = Some(event.clone());
                                    break;
                                }
                            }
                        }
                    }
                    Ok(ReceiverEvent::Shutdown) => break,
                    Ok(ReceiverEvent::RegistrationUpdated(_))
                    | Ok(ReceiverEvent::SetupCompleted(_))
                    | Ok(ReceiverEvent::DiscoverabilityChanged { .. }) => {}
                    Err(RecvError::Closed) => break,
                    Err(RecvError::Lagged(count)) => {
                        warn!(dropped = count, "receiver.events_lagged");
                    }
                }
            }
            _ = tokio::signal::ctrl_c() => {
                info!("receive.cancel_requested");
                let _ = service.shutdown().await;
                bail!("cancelled");
            }
        }
    }

    finish_progress_bar(&mut progress_bar);
    let _ = service.shutdown().await;

    if let Some(event) = terminal_event {
        match event.phase {
            ReceiverOfferPhase::Completed => {
                info!("receive.completed");
                println!("\nTransfer completed successfully!");
            }
            ReceiverOfferPhase::Declined if !reported_failure => {
                info!("receive.declined");
                println!("\nTransfer declined.");
            }
            ReceiverOfferPhase::Cancelled if !reported_failure => {
                info!("receive.cancelled");
                println!("\nTransfer cancelled.");
            }
            ReceiverOfferPhase::Failed if !reported_failure => {
                if let Some(error) = event.error.as_ref() {
                    report_user_facing_error("receive.failed", error);
                }
            }
            _ => {}
        }
    }

    Ok(())
}

fn render_offer(offer: &ReceiverOfferEvent) {
    println!("\nIncoming Transfer from {}:", offer.sender_name);
    println!("  Files: {}", offer.item_count);
    println!("  Total Size: {}", human_size(offer.total_size_bytes));
    println!();
}

fn render_receiver_event(
    progress_bar: &mut Option<ProgressBar>,
    event: &ReceiverOfferEvent,
    current_plan: &mut Option<TransferPlan>,
) -> bool {
    match event {
        ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Receiving,
            plan: Some(plan),
            snapshot: None,
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            *current_plan = Some(plan.clone());
            configure_transfer_bar(pb, plan.total_bytes);
            pb.set_message(render_transfer_message("Receiving", Some(plan), None));
            false
        }
        ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Receiving,
            snapshot: Some(snapshot),
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Receiving",
                current_plan.as_ref(),
                Some(snapshot),
            ));
            false
        }
        ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Completed,
            snapshot: Some(snapshot),
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Receiving",
                current_plan.as_ref(),
                Some(snapshot),
            ));
            finish_progress_bar(progress_bar);
            false
        }
        ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Cancelled,
            error: Some(error),
            ..
        }
        | ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Failed,
            error: Some(error),
            ..
        } => {
            finish_progress_bar(progress_bar);
            report_user_facing_error("receive.failed", error);
            true
        }
        ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Cancelled,
            ..
        }
        | ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Failed,
            ..
        }
        | ReceiverOfferEvent {
            phase: ReceiverOfferPhase::Declined,
            ..
        } => {
            finish_progress_bar(progress_bar);
            false
        }
        _ => false,
    }
}

fn ensure_spinner(progress_bar: &mut Option<ProgressBar>) -> &ProgressBar {
    if progress_bar.is_none() {
        let pb = ProgressBar::new_spinner();
        pb.set_draw_target(ProgressDrawTarget::stderr());
        pb.set_style(
            ProgressStyle::with_template("{spinner:.green} {msg}")
                .expect("valid indicatif spinner template"),
        );
        pb.enable_steady_tick(Duration::from_millis(100));
        *progress_bar = Some(pb);
    }
    progress_bar.as_ref().expect("progress bar set")
}

fn configure_transfer_bar(progress_bar: &ProgressBar, total: u64) {
    progress_bar.set_style(
        ProgressStyle::with_template(
            "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
        )
        .expect("valid indicatif transfer template"),
    );
    progress_bar.set_length(total.max(1));
}

fn render_transfer_message(
    verb: &str,
    plan: Option<&TransferPlan>,
    snapshot: Option<&TransferSnapshot>,
) -> String {
    let mut parts = Vec::new();
    if let (Some(plan), Some(snapshot)) = (plan, snapshot) {
        if let Some(file_id) = snapshot.active_file_id {
            if let Some(file) = plan.file(file_id) {
                parts.push(format!("current: {}", file.path));
            }
        }
        parts.push(format!(
            "files {}/{}",
            snapshot.completed_files, snapshot.total_files
        ));
        if let Some(rate) = snapshot.bytes_per_sec {
            parts.push(format!("{}/s", human_size(rate)));
        }
        if let Some(eta) = snapshot.eta_seconds {
            parts.push(format!("ETA {}s", eta));
        }
    } else if let Some(plan) = plan {
        parts.push(format!("files {}/{}", 0, plan.total_files));
    }

    if parts.is_empty() {
        verb.to_owned()
    } else {
        format!("{verb} {}", parts.join(" | "))
    }
}

fn finish_progress_bar(progress_bar: &mut Option<ProgressBar>) {
    if let Some(pb) = progress_bar.take() {
        pb.finish_and_clear();
    }
}

fn parse_conflict_policy(value: &str) -> Result<ConflictPolicy> {
    match value.trim().to_ascii_lowercase().as_str() {
        "reject" => Ok(ConflictPolicy::Reject),
        "overwrite" => Ok(ConflictPolicy::Overwrite),
        "rename" => Ok(ConflictPolicy::Rename),
        other => bail!("invalid conflict policy {other:?} (expected rename, overwrite, or reject)"),
    }
}

fn report_user_facing_error(context: &str, error: &UserFacingError) {
    warn!(
        context = %context,
        kind = ?error.kind(),
        title = %error.title(),
        message = %error.message(),
        recovery = ?error.recovery(),
        retryable = error.is_retryable(),
        "transfer.failed"
    );
    render_user_facing_error(error);
}

fn render_user_facing_error(error: &UserFacingError) {
    eprintln!();
    eprintln!("{}", error.title());
    eprintln!("{}", error.message());
    if let Some(recovery) = error.recovery() {
        eprintln!("{}", recovery);
    }
}

fn report_anyhow_failure(context: &str, error: &anyhow::Error, already_reported: bool) {
    let error_chain = error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ");
    let user_facing_error = from_anyhow_error(error);
    warn!(
        context = %context,
        error = %error,
        error_chain = %error_chain,
        "transfer.failed"
    );

    if !already_reported {
        render_user_facing_error(&user_facing_error);
    }
}
