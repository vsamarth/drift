use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use drift_core::fs_plan::build_expected_files;
use drift_core::rendezvous::RendezvousClient;
use drift_core::sender::{SendTransferPhase, SendTransferProgress, send_files_with_progress};
use drift_core::session::{bind_endpoint, receive_files_over_connection};
use drift_core::transfer::{ReceiverMachine, ReceiverState, ensure_session_id, validate_hello};
use drift_core::util::{confirm_accept, describe_remote, human_size};
use drift_core::wire::{
    Accept, ControlMessage, Decline, Hello, TRANSFER_PROTOCOL_VERSION, TransferRole, make_ticket,
    read_message, write_message,
};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio::fs;
use tokio::signal;
use tokio::time::{Duration, Instant, MissedTickBehavior, interval, timeout};

const CONNECT_GRACE_PERIOD: Duration = Duration::from_secs(30);

pub async fn send(code: String, files: Vec<PathBuf>, server_url: Option<String>) -> Result<()> {
    let device_name = local_device_name();
    let mut last_phase = None;
    send_files_with_progress(code, files, server_url, device_name, |progress| {
        log_send_progress(&mut last_phase, progress)
    })
    .await?;
    Ok(())
}

pub async fn receive(out_dir: PathBuf, server_url: Option<String>) -> Result<()> {
    fs::create_dir_all(&out_dir)
        .await
        .with_context(|| format!("creating output directory {}", out_dir.display()))?;

    let client = RendezvousClient::new(drift_core::rendezvous::resolve_server_url(
        server_url.as_deref(),
    ));
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

    println!("Receiver registered");
    println!("Code: {}", registration.code);
    println!("Expires: {}", registration.expires_at);
    println!("Save directory: {}", out_dir.display());
    println!("Device: {}", device_name);
    println!("Waiting for a sender...");

    let mut accept_future = Box::pin(endpoint.accept());
    let mut poll = interval(Duration::from_secs(2));
    poll.set_missed_tick_behavior(MissedTickBehavior::Delay);
    poll.tick().await;
    let mut ctrl_c = Box::pin(signal::ctrl_c());
    let mut claimed_at: Option<Instant> = None;

    loop {
        tokio::select! {
            _ = &mut ctrl_c => {
                endpoint.close().await;
                return Ok(());
            }
            incoming = &mut accept_future => {
                machine.transition(ReceiverState::Connecting)?;
                let incoming = incoming.context("receiver stopped before a sender connected")?;
                let connection = incoming.await.context("accepting sender connection")?;
                println!(
                    "Connected to {}",
                    describe_remote(
                        connection.remote_id(),
                        endpoint.remote_info(connection.remote_id()).await.as_ref()
                    )
                );
                machine.transition(ReceiverState::Connected)?;
                let result = handle_receiver_connection(connection, out_dir.clone(), &device_name, &mut machine).await;
                endpoint.close().await;
                return result;
            }
            _ = poll.tick() => {
                match client.pair_status(&registration.code).await? {
                    Some(_) => {}
                    None => {
                        if claimed_at.is_none() {
                            if OffsetDateTime::now_utc() >= expires_at {
                                println!("Code {} expired. Closing receiver.", registration.code);
                                endpoint.close().await;
                                return Ok(());
                            }
                            claimed_at = Some(Instant::now());
                            println!("Code claimed. Waiting for sender connection...");
                        } else if claimed_at.unwrap().elapsed() >= CONNECT_GRACE_PERIOD {
                            bail!("sender claimed the code but did not connect in time");
                        }
                    }
                }
            }
        }
    }
}

async fn handle_receiver_connection(
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    device_name: &str,
    machine: &mut ReceiverMachine,
) -> Result<()> {
    let (mut control_send, mut control_recv) = connection
        .accept_bi()
        .await
        .context("waiting for transfer control stream")?;

    let hello = match read_message::<ControlMessage>(&mut control_recv)
        .await
        .context("reading sender hello")?
    {
        ControlMessage::Hello(message) => {
            validate_hello(&message, TransferRole::Sender)?;
            message
        }
        other => {
            machine.transition(ReceiverState::Failed)?;
            bail!("expected hello from sender, got {:?}", other);
        }
    };
    println!("Sender: {}", hello.device_name);
    send_hello(
        &mut control_send,
        &hello.session_id,
        TransferRole::Receiver,
        device_name,
    )
    .await?;

    machine.transition(ReceiverState::ReviewingOffer)?;
    let offer = match read_message::<ControlMessage>(&mut control_recv)
        .await
        .context("reading sender offer")?
    {
        ControlMessage::Offer(message) => {
            ensure_session_id(&message.session_id, &hello.session_id)?;
            message
        }
        other => {
            machine.transition(ReceiverState::Failed)?;
            bail!("expected offer from sender, got {:?}", other);
        }
    };

    println!("Incoming offer");
    println!("Files: {}", offer.manifest.file_count);
    println!("Total size: {}", human_size(offer.manifest.total_size));
    for file in &offer.manifest.files {
        println!("  {} ({})", file.path, human_size(file.size));
    }

    let expected_files = match build_expected_files(&offer.manifest, &out_dir).await {
        Ok(expected_files) => expected_files,
        Err(err) => {
            machine.transition(ReceiverState::Declined)?;
            send_decline(&mut control_send, &hello.session_id, err.to_string()).await?;
            return Err(err);
        }
    };

    machine.transition(ReceiverState::AwaitingDecision)?;
    if !confirm_accept()? {
        machine.transition(ReceiverState::Declined)?;
        send_decline(
            &mut control_send,
            &hello.session_id,
            "receiver declined the offer".to_owned(),
        )
        .await?;
        println!("Offer declined");
        return Ok(());
    }

    send_accept(&mut control_send, &hello.session_id).await?;
    machine.transition(ReceiverState::Approved)?;
    println!("Accepted offer. Receiving files...");

    machine.transition(ReceiverState::Receiving)?;
    receive_files_over_connection(connection, out_dir, Some(expected_files)).await?;
    machine.transition(ReceiverState::Completed)?;
    Ok(())
}

async fn send_accept(send_stream: &mut iroh::endpoint::SendStream, session_id: &str) -> Result<()> {
    write_message(
        send_stream,
        &ControlMessage::Accept(Accept {
            session_id: session_id.to_owned(),
        }),
    )
    .await?;
    send_stream.finish()?;
    let _ = timeout(Duration::from_secs(2), send_stream.stopped()).await;
    Ok(())
}

async fn send_decline(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    reason: String,
) -> Result<()> {
    write_message(
        send_stream,
        &ControlMessage::Decline(Decline {
            session_id: session_id.to_owned(),
            reason,
        }),
    )
    .await?;
    send_stream.finish()?;
    let _ = timeout(Duration::from_secs(2), send_stream.stopped()).await;
    Ok(())
}

async fn send_hello(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    role: TransferRole,
    device_name: &str,
) -> Result<()> {
    write_message(
        send_stream,
        &ControlMessage::Hello(Hello {
            version: TRANSFER_PROTOCOL_VERSION,
            session_id: session_id.to_owned(),
            role,
            device_name: device_name.to_owned(),
        }),
    )
    .await
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
        SendTransferPhase::Connecting => {}
        SendTransferPhase::WaitingForDecision => {
            println!("Receiver: {}", progress.destination_label);
        }
        SendTransferPhase::Sending => {
            println!("Receiver accepted the offer");
            println!(
                "Files: {} ({})",
                progress.manifest.file_count,
                human_size(progress.manifest.total_size)
            );
        }
        SendTransferPhase::Completed => {}
    }

    *last_phase = Some(progress.phase);
}
