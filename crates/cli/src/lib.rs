use std::io::{self, Write};
use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args, ValueEnum};
use drift_app::{
    ConflictPolicy, OfferDecision, ReceiverConfig, ReceiverEvent, ReceiverOfferEvent,
    ReceiverOfferPhase, ReceiverService, SendConfig, SendDestination, SendDraft, SendEvent,
    SendPhase, SendSessionOutcome,
};
use drift_core::transfer_flow::{
    ReceiverDecision as DemoReceiverDecision, ReceiverEvent as DemoReceiverEvent,
    ReceiverOffer as DemoReceiverOffer, ReceiverOfferItem as DemoReceiverOfferItem,
    ReceiverRequest as DemoReceiverRequest, ReceiverSession as DemoReceiverSession,
    SendRequest as DemoSendRequest, Sender as DemoSender, SenderEvent as DemoSenderEvent,
    TransferOutcome as DemoTransferOutcome,
};
use drift_core::util::{human_size, process_display_device_name};
use drift_core::protocol::DeviceType;
use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};
use iroh::SecretKey;
use std::collections::BTreeMap;
use tokio::time::Duration;
use tokio_stream::StreamExt;
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
        "send.started"
    );
    for (i, path) in draft.paths().iter().enumerate() {
        debug!(index = i, path = %path.display(), "send.input_path");
    }

    let mut progress_bar = None;
    let mut last_phase = None;
    let session = draft.into_session(SendDestination::code(code, server_url));
    let outcome = consume_send_run(session.start(), &mut progress_bar, &mut last_phase).await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(SendSessionOutcome::Accepted {
            receiver_device_name,
            receiver_endpoint_id,
        }) => {
            info!(
                receiver_device_name = %receiver_device_name,
                receiver_endpoint_id = %receiver_endpoint_id,
                "send.accepted"
            );
        }
        Ok(SendSessionOutcome::Declined { reason }) => {
            info!(reason = %reason, "send.declined");
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
        "send.nearby_started"
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
    info!(label = %picked.label, "send.nearby_picked");

    let mut progress_bar = None;
    let mut last_phase = None;
    let session = draft.into_session(SendDestination::nearby(
        picked.ticket.clone(),
        format!("Nearby: {}", picked.label),
    ));
    let outcome = consume_send_run(session.start(), &mut progress_bar, &mut last_phase).await;
    finish_progress_bar(&mut progress_bar);

    match &outcome {
        Ok(SendSessionOutcome::Accepted {
            receiver_device_name,
            receiver_endpoint_id,
        }) => {
            info!(
                receiver_device_name = %receiver_device_name,
                receiver_endpoint_id = %receiver_endpoint_id,
                "send.accepted"
            );
        }
        Ok(SendSessionOutcome::Declined { reason }) => {
            info!(reason = %reason, "send.declined");
        }
        Err(e) => warn!(error = %e, error_chain = %format!("{e:#}"), "send.failed"),
    }

    outcome.map(|_| ())
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
                                info!("receive.auto_accepting");
                                service.respond_to_offer(OfferDecision::Accept).await?;
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

pub async fn demo_send(peer_endpoint_id: String, files: Vec<PathBuf>) -> Result<()> {
    let device_name = process_display_device_name();
    let peer_endpoint_id: iroh::EndpointId = peer_endpoint_id
        .parse()
        .context("parsing peer endpoint id")?;
    let sender = DemoSender::new(
        device_name.clone(),
        DeviceType::Laptop,
        DemoSendRequest {
            peer_endpoint_id,
            files,
        },
    );

    info!(
        session_id = %sender.session_id(),
        peer_endpoint_id = %sender.request().peer_endpoint_id,
        device = %device_name,
        "demo.send.started"
    );

    let sender_run = sender.run_with_events();
    let (mut events, outcome_rx) = sender_run.into_parts();
    let mut progress_bar = None;
    ensure_demo_sender_progress_bar(&mut progress_bar).set_message("waiting for receiver");
    while let Some(event) = events.next().await {
        match event {
            Ok(event) => render_demo_sender_event(&mut progress_bar, &event),
            Err(error) => {
                warn!(error = %error, error_chain = %format!("{error:#}"), "demo.send.failed");
                finish_demo_sender_progress_bar(&mut progress_bar);
                return Err(error);
            }
        }
    }
    finish_demo_sender_progress_bar(&mut progress_bar);

    match outcome_rx
        .await
        .context("waiting for demo sender outcome")??
    {
        DemoTransferOutcome::Completed => {
            info!("demo.send.completed");
        }
        DemoTransferOutcome::Declined { reason } => {
            info!(reason = %reason, "demo.send.declined");
        }
        DemoTransferOutcome::Cancelled(cancellation) => {
            info!(reason = %cancellation.reason, "demo.send.cancelled");
        }
    }

    Ok(())
}

pub async fn demo_receive() -> Result<()> {
    let device_name = process_display_device_name();
    let _session = DemoReceiverSession::new(DemoReceiverRequest {
        device_name: device_name.clone(),
        device_type: DeviceType::Laptop,
        out_dir: PathBuf::from("downloads"),
    });

    info!(device = %device_name, "demo.receive.started");

    // The CLI demo_receive was using a high-level Receiver::run_with_events which handled
    // iroh endpoint binding, listening, and accepting.
    // The new ReceiverSession is a per-connection actor.
    // Since this is a CLI demo, it should probably be using ReceiverService or a simple
    // listener loop. For now, I'll disable it to unblock the build.
    anyhow::bail!("demo_receive CLI is currently disabled during refactoring");
}

fn render_demo_offer(offer: &DemoReceiverOffer) {
    info!(
        session_id = %offer.session_id,
        sender_device_name = %offer.sender_device_name,
        sender_endpoint_id = %offer.sender_endpoint_id,
        file_count = offer.file_count,
        total_size = offer.total_size,
        "demo.receive.offer"
    );

    let tree = build_offer_tree(&offer.items);
    print_demo_offer(&offer.sender_device_name, &tree);
}

fn render_demo_sender_event(progress_bar: &mut Option<ProgressBar>, event: &DemoSenderEvent) {
    match event {
        DemoSenderEvent::Connecting {
            session_id,
            peer_endpoint_id,
        } => {
            let pb = ensure_demo_sender_progress_bar(progress_bar);
            pb.set_message("connecting".to_owned());
            info!(
                session_id = %session_id,
                peer_endpoint_id = %peer_endpoint_id,
                "demo.send.connecting"
            );
        }
        DemoSenderEvent::WaitingForDecision {
            session_id,
            receiver_device_name,
            receiver_endpoint_id,
        } => {
            let pb = ensure_demo_sender_progress_bar(progress_bar);
            pb.set_message(format!("waiting for {}", receiver_device_name));
            info!(
                session_id = %session_id,
                receiver_device_name = %receiver_device_name,
                receiver_endpoint_id = %receiver_endpoint_id,
                "demo.send.waiting_for_decision"
            );
        }
        DemoSenderEvent::Accepted {
            session_id,
            receiver_device_name,
            receiver_endpoint_id,
        } => {
            let pb = ensure_demo_sender_progress_bar(progress_bar);
            pb.set_message(format!("accepted by {}", receiver_device_name));
            info!(
                session_id = %session_id,
                receiver_device_name = %receiver_device_name,
                receiver_endpoint_id = %receiver_endpoint_id,
                "demo.send.accepted"
            );
        }
        DemoSenderEvent::Declined { session_id, reason } => {
            finish_demo_sender_progress_bar(progress_bar);
            info!(
                session_id = %session_id,
                reason = %reason,
                "demo.send.declined"
            );
        }
        DemoSenderEvent::Failed {
            session_id,
            message,
        } => {
            finish_demo_sender_progress_bar(progress_bar);
            warn!(
                session_id = %session_id,
                message = %message,
                "demo.send.failed"
            );
        }
        DemoSenderEvent::TransferStarted {
            session_id,
            file_count,
            total_bytes,
        } => {
            let pb = ensure_demo_sender_progress_bar(progress_bar);
            configure_demo_sender_transfer_bar(pb, (*total_bytes).max(1));
            pb.set_message(format!("sending {file_count} files"));
            info!(
                session_id = %session_id,
                file_count = file_count,
                total_bytes = total_bytes,
                "demo.send.transfer_started"
            );
        }
        DemoSenderEvent::TransferProgress {
            session_id: _,
            bytes_sent,
            total_bytes,
        } => {
            let pb = ensure_demo_sender_progress_bar(progress_bar);
            configure_demo_sender_transfer_bar(pb, (*total_bytes).max(1));
            pb.set_position((*bytes_sent).min(*total_bytes));
            pb.set_message(format!(
                "{} / {}",
                human_size(*bytes_sent),
                human_size(*total_bytes)
            ));
        }
        DemoSenderEvent::TransferCompleted { session_id } => {
            finish_demo_sender_progress_bar(progress_bar);
            info!(session_id = %session_id, "demo.send.transfer_completed");
        }
    }
}

fn ensure_demo_sender_progress_bar(progress_bar: &mut Option<ProgressBar>) -> &ProgressBar {
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

fn configure_demo_sender_transfer_bar(progress_bar: &ProgressBar, total: u64) {
    progress_bar.set_style(
        ProgressStyle::with_template(
            "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
        )
        .expect("valid indicatif transfer template"),
    );
    progress_bar.set_length(total.max(1));
}

fn finish_demo_sender_progress_bar(progress_bar: &mut Option<ProgressBar>) {
    if let Some(pb) = progress_bar.take() {
        pb.finish_and_clear();
    }
}

#[derive(Default)]
struct OfferTreeNode {
    dirs: BTreeMap<String, OfferTreeNode>,
    files: Vec<OfferTreeFile>,
}

#[derive(Clone)]
struct OfferTreeFile {
    name: String,
    size: u64,
}

fn build_offer_tree(items: &[DemoReceiverOfferItem]) -> OfferTreeNode {
    let mut root = OfferTreeNode::default();
    for item in items {
        let parts = item
            .path
            .split('/')
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>();
        insert_offer_item(&mut root, &parts, item.size);
    }
    root
}

fn insert_offer_item(node: &mut OfferTreeNode, parts: &[&str], size: u64) {
    if parts.is_empty() {
        return;
    }
    if parts.len() == 1 {
        node.files.push(OfferTreeFile {
            name: parts[0].to_owned(),
            size,
        });
        node.files.sort_by(|left, right| left.name.cmp(&right.name));
        return;
    }

    let dir = parts[0].to_owned();
    let child = node.dirs.entry(dir).or_default();
    insert_offer_item(child, &parts[1..], size);
}

fn print_demo_offer(sender_device_name: &str, tree: &OfferTreeNode) {
    print!("Offer from {sender_device_name}:\n");
    print_offer_tree(tree, "");
    let _ = io::stdout().flush();
}

fn print_offer_tree(node: &OfferTreeNode, prefix: &str) {
    let mut entries = Vec::new();
    for (dir, child) in &node.dirs {
        entries.push(OfferTreeEntry::Dir {
            name: dir,
            node: child,
        });
    }
    for file in &node.files {
        entries.push(OfferTreeEntry::File { file });
    }

    for (index, entry) in entries.iter().enumerate() {
        let last = index + 1 == entries.len();
        let branch = if last { "└── " } else { "├── " };
        let next_prefix = if last {
            format!("{prefix}    ")
        } else {
            format!("{prefix}│   ")
        };
        match entry {
            OfferTreeEntry::Dir { name, node } => {
                print!("{prefix}{branch}{name}/\n");
                print_offer_tree(node, &next_prefix);
            }
            OfferTreeEntry::File { file } => {
                print!(
                    "{prefix}{branch}{} ({})\n",
                    file.name,
                    human_size(file.size)
                );
            }
        }
    }
}

enum OfferTreeEntry<'a> {
    Dir {
        name: &'a str,
        node: &'a OfferTreeNode,
    },
    File {
        file: &'a OfferTreeFile,
    },
}

fn render_demo_receive_event(progress_bar: &mut Option<ProgressBar>, event: &DemoReceiverEvent) {
    match event {
        DemoReceiverEvent::Listening { .. } => {
            let pb = ensure_demo_receive_progress_bar(progress_bar);
            pb.set_message("waiting for sender");
        }
        DemoReceiverEvent::OfferReceived {
            sender_device_name, ..
        } => {
            let pb = ensure_demo_receive_progress_bar(progress_bar);
            pb.set_message(format!("offer received from {sender_device_name}"));
        }
        DemoReceiverEvent::TransferStarted {
            file_count,
            total_bytes,
            ..
        } => {
            let pb = ensure_demo_receive_progress_bar(progress_bar);
            configure_demo_receive_transfer_bar(pb, *total_bytes);
            pb.set_message(format!("transferring {file_count} files"));
        }
        DemoReceiverEvent::TransferProgress {
            bytes_received,
            total_bytes,
            ..
        } => {
            let pb = ensure_demo_receive_progress_bar(progress_bar);
            configure_demo_receive_transfer_bar(pb, *total_bytes);
            pb.set_position((*bytes_received).min(*total_bytes));
            pb.set_message(format!(
                "{} / {}",
                human_size(*bytes_received),
                human_size(*total_bytes)
            ));
        }
        DemoReceiverEvent::Completed { .. } => {
            finish_demo_receive_progress_bar(progress_bar);
        }
    }
}

fn ensure_demo_receive_progress_bar(progress_bar: &mut Option<ProgressBar>) -> &ProgressBar {
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

fn configure_demo_receive_transfer_bar(progress_bar: &ProgressBar, total: u64) {
    progress_bar.set_style(
        ProgressStyle::with_template(
            "{spinner:.green} [{bar:40.cyan/blue}] {bytes}/{total_bytes} ({percent}%) {msg}",
        )
        .expect("valid indicatif transfer template"),
    );
    progress_bar.set_length(total.max(1));
}

fn finish_demo_receive_progress_bar(progress_bar: &mut Option<ProgressBar>) {
    if let Some(pb) = progress_bar.take() {
        pb.finish_and_clear();
    }
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
            SendPhase::Accepted => {
                info!(phase = "accepted", receiver = %event.destination_label, "send.phase");
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
            SendPhase::Declined => {
                info!(phase = "declined", receiver = %event.destination_label, "send.phase");
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
            pb.set_message(event.status_message.clone());
        }
        SendPhase::Completed | SendPhase::Declined | SendPhase::Cancelled | SendPhase::Failed => {
            finish_progress_bar(progress_bar)
        }
        SendPhase::Connecting | SendPhase::WaitingForDecision | SendPhase::Accepted => {}
    }
}

async fn consume_send_run(
    run: drift_app::send::SendRun,
    progress_bar: &mut Option<ProgressBar>,
    last_phase: &mut Option<SendPhase>,
) -> Result<SendSessionOutcome> {
    let (mut events, outcome_rx) = run.into_parts();
    while let Some(event) = events.next().await {
        match event {
            Ok(event) => render_send_event(last_phase, progress_bar, &event),
            Err(error) => {
                warn!(error = %error, error_chain = %format!("{error:#}"), "send.failed");
                finish_progress_bar(progress_bar);
                return Err(error);
            }
        }
    }

    finish_progress_bar(progress_bar);
    Ok(outcome_rx.await.context("waiting for send outcome")??)
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
