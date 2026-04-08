use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, anyhow, bail};
use clap::{Args, ValueEnum};
use drift_core::discovery::{resolve_nearby, resolve_pairing_code};
use drift_core::lan::LanReceiveAdvertisement;
use drift_core::protocol::DeviceType;
use drift_core::rendezvous::{RendezvousClient, resolve_server_url};
use drift_core::transfer::{
    ReceiverDecision, ReceiverEvent, ReceiverOffer, ReceiverRequest, ReceiverSession,
    ReceiverStart, SendRequest, Sender, SenderEvent, TransferOutcome, TransferPlan,
    TransferSnapshot,
};
use drift_core::util::{confirm_accept, human_size, make_ticket, process_display_device_name};
use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};
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

    info!(
        code = %code.trim().to_uppercase(),
        file_count = files.len(),
        device = %device_name,
        rendezvous_override = ?server_url,
        "send.resolving_code"
    );

    let peer_endpoint_addr = resolve_pairing_code(&code, server_url.as_deref()).await?;

    let sender = Sender::new(
        device_name,
        DeviceType::Laptop,
        SendRequest {
            peer_endpoint_addr: peer_endpoint_addr.clone(),
            peer_endpoint_id: peer_endpoint_addr.id,
            files,
        },
    );

    let mut progress_bar = None;
    let run = sender.run_with_events();
    let outcome = consume_sender_run(run, &mut progress_bar).await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(TransferOutcome::Completed) => {
            info!("send.completed");
        }
        Ok(TransferOutcome::Declined { reason }) => {
            info!(reason = %reason, "send.declined");
        }
        Ok(TransferOutcome::Cancelled(c)) => {
            info!(by = ?c.by, reason = %c.reason, "send.cancelled");
        }
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

    info!(
        file_count = files.len(),
        device = %device_name,
        scan_secs = nearby_timeout_secs.max(1),
        "send.nearby_scanning"
    );

    let receivers = resolve_nearby(Duration::from_secs(nearby_timeout_secs)).await?;

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
    info!(label = %picked.label, endpoint = %picked.endpoint_id, "send.nearby_picked");

    let sender = Sender::new(
        device_name,
        DeviceType::Laptop,
        SendRequest {
            peer_endpoint_addr: picked.endpoint_addr.clone(),
            peer_endpoint_id: picked.endpoint_id,
            files,
        },
    );

    let mut progress_bar = None;
    let run = sender.run_with_events();
    let outcome = consume_sender_run(run, &mut progress_bar).await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(TransferOutcome::Completed) => {
            info!("send.completed");
        }
        Ok(TransferOutcome::Declined { reason }) => {
            info!(reason = %reason, "send.declined");
        }
        Ok(TransferOutcome::Cancelled(c)) => {
            info!(by = ?c.by, reason = %c.reason, "send.cancelled");
        }
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome.map(|_| ())
}

async fn consume_sender_run(
    run: drift_core::transfer::sender::SenderRun,
    progress_bar: &mut Option<ProgressBar>,
) -> Result<TransferOutcome> {
    let (mut events, cancel_tx, outcome_rx) = run.into_parts();

    let mut outcome_rx = outcome_rx;
    let mut current_plan: Option<TransferPlan> = None;
    loop {
        tokio::select! {
            event = events.next() => {
                match event {
                    Some(Ok(event)) => render_sender_event(progress_bar, &event, &mut current_plan),
                    Some(Err(error)) => {
                        warn!(error = %error, error_chain = %format!("{error:#}"), "send.failed");
                        finish_progress_bar(progress_bar);
                        return Err(error);
                    }
                    None => break,
                }
            }
            _ = tokio::signal::ctrl_c() => {
                info!("send.cancel_requested");
                let _ = cancel_tx.send(true);
            }
            res = &mut outcome_rx => {
                finish_progress_bar(progress_bar);
                return Ok(res.context("waiting for send outcome")??);
            }
        }
    }

    finish_progress_bar(progress_bar);
    Ok(outcome_rx.await.context("waiting for send outcome")??)
}

fn render_sender_event(
    progress_bar: &mut Option<ProgressBar>,
    event: &SenderEvent,
    current_plan: &mut Option<TransferPlan>,
) {
    match event {
        SenderEvent::Connecting {
            peer_endpoint_id, ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!("Connecting to {peer_endpoint_id}..."));
        }
        SenderEvent::WaitingForDecision {
            receiver_device_name,
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!("Waiting for {receiver_device_name} to accept..."));
        }
        SenderEvent::Accepted {
            receiver_device_name,
            ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!(
                "Accepted by {receiver_device_name}. Starting transfer..."
            ));
        }
        SenderEvent::TransferStarted { plan, .. } => {
            *current_plan = Some(plan.clone());
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, plan.total_bytes);
            pb.set_message(render_transfer_message("Sending", Some(plan), None));
        }
        SenderEvent::TransferProgress { snapshot, .. } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Sending",
                current_plan.as_ref(),
                Some(snapshot),
            ));
        }
        SenderEvent::TransferCompleted { snapshot, .. } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Sending",
                current_plan.as_ref(),
                Some(snapshot),
            ));
            finish_progress_bar(progress_bar);
        }
        SenderEvent::Declined { reason, .. } => {
            finish_progress_bar(progress_bar);
            info!(%reason, "Transfer declined");
        }
        SenderEvent::Failed { message, .. } => {
            finish_progress_bar(progress_bar);
            warn!(%message, "Transfer failed");
        }
    }
}

pub async fn receive(out_dir: PathBuf, server_url: Option<String>) -> Result<()> {
    let device_name = process_display_device_name();
    info!(
        out_dir = %out_dir.display(),
        server = ?server_url,
        device = %device_name,
        "receive.started"
    );

    let endpoint = drift_core::transfer::receiver::bind_endpoint().await?;
    let ticket = make_ticket(&endpoint).await?;

    // 1. Start mDNS Advertising
    let _advertiser = LanReceiveAdvertisement::start(&ticket, &device_name)?;

    // 2. Register with Rendezvous
    let rendezvous = RendezvousClient::new(resolve_server_url(server_url.as_deref()));
    let registration = rendezvous.register_peer(ticket).await?;

    info!(code = %registration.code, expires_at = %registration.expires_at, "receive.ready");
    eprintln!(
        "Pairing code: {} (expires {})",
        registration.code, registration.expires_at
    );
    eprintln!("Waiting for a sender to connect...");

    // 3. Wait for one connection
    let incoming = tokio::select! {
        incoming = endpoint.accept() => incoming.ok_or_else(|| anyhow!("listener closed"))?,
        _ = tokio::signal::ctrl_c() => {
            bail!("cancelled while waiting for connection");
        }
    };
    let connection = incoming.await?;

    // 4. Run the session
    let session = ReceiverSession::new(ReceiverRequest {
        device_name,
        device_type: DeviceType::Laptop,
        out_dir,
    });

    let start = session.start(endpoint, connection);
    let outcome = consume_receiver_run(start).await?;

    match outcome {
        TransferOutcome::Completed => {
            info!("receive.completed");
            println!("\nTransfer completed successfully!");
        }
        TransferOutcome::Declined { reason } => {
            info!(%reason, "receive.declined");
            println!("\nTransfer declined: {}", reason);
        }
        TransferOutcome::Cancelled(c) => {
            info!(by = ?c.by, reason = %c.reason, "receive.cancelled");
            println!("\nTransfer cancelled by {:?}: {}", c.by, c.reason);
        }
    }

    Ok(())
}

async fn consume_receiver_run(start: ReceiverStart) -> Result<TransferOutcome> {
    let ReceiverStart {
        mut events,
        offer_rx,
        outcome_rx,
        control,
    } = start;

    let mut progress_bar = None;
    let mut current_plan: Option<TransferPlan> = None;

    // 1. Wait for offer
    let offer = tokio::select! {
        offer = offer_rx => offer.context("waiting for offer")??,
        _ = tokio::signal::ctrl_c() => {
            let _ = control.decision_tx.send(ReceiverDecision::Decline);
            bail!("interrupted");
        }
    };

    // 2. Render offer and ask for permission
    render_offer(&offer);

    let accepted = confirm_accept()?;
    if !accepted {
        let _ = control.decision_tx.send(ReceiverDecision::Decline);
        return Ok(TransferOutcome::Declined {
            reason: "local user declined".to_owned(),
        });
    }

    control
        .decision_tx
        .send(ReceiverDecision::Accept)
        .map_err(|_| anyhow!("failed to send decision"))?;

    // 3. Process events
    let mut outcome_rx = outcome_rx;
    loop {
        tokio::select! {
            event = events.next() => {
                match event {
                    Some(Ok(event)) => render_receiver_event(
                        &mut progress_bar,
                        &event,
                        &mut current_plan,
                    ),
                    Some(Err(error)) => {
                        warn!(error = %error, error_chain = %format!("{error:#}"), "receive.failed");
                        finish_progress_bar(&mut progress_bar);
                        return Err(error);
                    }
                    None => break,
                }
            }
            _ = tokio::signal::ctrl_c() => {
                info!("receive.cancel_requested");
                let _ = control.cancel_tx.send(true);
            }
            res = &mut outcome_rx => {
                finish_progress_bar(&mut progress_bar);
                return Ok(res.context("waiting for outcome")??);
            }
        }
    }

    finish_progress_bar(&mut progress_bar);
    Ok(outcome_rx.await.context("waiting for outcome")??)
}

fn render_offer(offer: &ReceiverOffer) {
    println!("\nIncoming Transfer from {}:", offer.sender_device_name);
    println!("  Files: {}", offer.file_count);
    println!("  Total Size: {}", human_size(offer.total_size));
    println!();
}

fn render_receiver_event(
    progress_bar: &mut Option<ProgressBar>,
    event: &ReceiverEvent,
    current_plan: &mut Option<TransferPlan>,
) {
    match event {
        ReceiverEvent::Listening { .. } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message("Waiting for sender...");
        }
        ReceiverEvent::OfferReceived {
            sender_device_name, ..
        } => {
            let pb = ensure_spinner(progress_bar);
            pb.set_message(format!("Offer received from {sender_device_name}"));
        }
        ReceiverEvent::TransferStarted { plan, .. } => {
            *current_plan = Some(plan.clone());
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, plan.total_bytes);
            pb.set_message(render_transfer_message("Receiving", Some(plan), None));
        }
        ReceiverEvent::TransferProgress { snapshot, .. } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Receiving",
                current_plan.as_ref(),
                Some(snapshot),
            ));
        }
        ReceiverEvent::TransferCompleted { snapshot, .. } => {
            let pb = ensure_spinner(progress_bar);
            configure_transfer_bar(pb, snapshot.total_bytes);
            pb.set_position(snapshot.bytes_transferred);
            pb.set_message(render_transfer_message(
                "Receiving",
                current_plan.as_ref(),
                Some(snapshot),
            ));
            finish_progress_bar(progress_bar);
        }
        ReceiverEvent::Completed { .. } => {
            finish_progress_bar(progress_bar);
        }
        ReceiverEvent::Failed { message, .. } => {
            finish_progress_bar(progress_bar);
            warn!(%message, "Transfer failed");
        }
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
