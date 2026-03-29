use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use clap::{Args, ValueEnum};
use drift_core::receiver::handle_receiver_connection;
use drift_core::rendezvous::RendezvousClient;
use drift_core::sender::{SendTransferPhase, SendTransferProgress, send_files_with_progress};
use drift_core::session::bind_endpoint;
use drift_core::transfer::{ReceiverMachine, ReceiverState};
use drift_core::util::{confirm_accept, describe_remote, human_size};
use drift_core::wire::make_ticket;
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
    let outcome = send_files_with_progress(code, files, server_url, device_name, |progress| {
        log_send_progress(&mut last_phase, progress);
    })
    .await;

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
    let registration = client.register_peer(ticket).await?;
    let expires_at = OffsetDateTime::parse(&registration.expires_at, &Rfc3339)
        .context("parsing discovery expiry")?;
    let device_name = local_device_name();

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
                let result = handle_receiver_connection(
                    connection,
                    out_dir.clone(),
                    &device_name,
                    &mut machine,
                    async {
                        tokio::task::spawn_blocking(|| confirm_accept())
                            .await
                            .context("confirm task")?
                    },
                )
                .await;
                endpoint.close().await;
                match &result {
                    Ok(()) => info!("receive.session_finished_ok"),
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

    "Recipient device".to_owned()
}

fn log_send_progress(last_phase: &mut Option<SendTransferPhase>, progress: SendTransferProgress) {
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
