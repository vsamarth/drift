use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use drift_core::fs_plan::{build_expected_files, prepare_files};
use drift_core::rendezvous::RendezvousClient;
use drift_core::session::{
    bind_endpoint, connect_to_ticket, receive_files_over_connection, send_files_over_connection,
};
use drift_core::transfer::{
    ReceiverMachine, ReceiverState, SenderMachine, SenderState, ensure_session_id, validate_hello,
};
use drift_core::util::{confirm_accept, describe_remote, human_size};
use drift_core::wire::{
    Accept, ControlMessage, Decline, Hello, Offer, TRANSFER_PROTOCOL_VERSION, TransferRole,
    decode_ticket, make_ticket, read_message, write_message,
};
use rand::random;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio::fs;
use tokio::signal;
use tokio::time::{Duration, Instant, MissedTickBehavior, interval, timeout};

const CONNECT_GRACE_PERIOD: Duration = Duration::from_secs(30);

pub async fn send(code: String, files: Vec<PathBuf>, server_url: Option<String>) -> Result<()> {
    drift_core::rendezvous::validate_code(&code)?;
    let prepared = prepare_files(files).await?;
    let session_id = make_session_id();
    let device_name = local_device_name();
    let mut machine = SenderMachine::new();

    machine.transition(SenderState::Resolving)?;
    let client = RendezvousClient::new(drift_core::rendezvous::resolve_server_url(
        server_url.as_deref(),
    ));
    let resolved = client.claim_peer(&code).await?;
    let endpoint_addr = decode_ticket(&resolved.ticket)?;

    machine.transition(SenderState::Connecting)?;
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let connection = connect_to_ticket(&endpoint, endpoint_addr).await?;
    machine.transition(SenderState::Connected)?;

    machine.transition(SenderState::Offering)?;
    let (mut control_send, mut control_recv) = connection
        .open_bi()
        .await
        .context("opening transfer control stream")?;
    send_hello(
        &mut control_send,
        &session_id,
        TransferRole::Sender,
        &device_name,
    )
    .await?;
    let receiver_hello = match read_message::<ControlMessage>(&mut control_recv)
        .await
        .context("waiting for receiver hello")?
    {
        ControlMessage::Hello(message) => {
            validate_hello(&message, TransferRole::Receiver)?;
            ensure_session_id(&message.session_id, &session_id)?;
            message
        }
        other => {
            machine.transition(SenderState::Failed)?;
            bail!("expected hello from receiver, got {:?}", other);
        }
    };
    println!("Receiver: {}", receiver_hello.device_name);
    send_offer(&mut control_send, &session_id, prepared.manifest.clone()).await?;
    control_send.finish()?;
    machine.transition(SenderState::WaitingForDecision)?;

    match read_message::<ControlMessage>(&mut control_recv)
        .await
        .context("waiting for receiver decision")?
    {
        ControlMessage::Accept(message) => {
            ensure_session_id(&message.session_id, &session_id)?;
            machine.transition(SenderState::Sending)?;
            println!("Receiver accepted the offer");
            println!(
                "Files: {} ({})",
                prepared.manifest.file_count,
                human_size(prepared.manifest.total_size)
            );
            send_files_over_connection(connection, &prepared.files).await?;
            machine.transition(SenderState::Completed)?;
        }
        ControlMessage::Decline(message) => {
            ensure_session_id(&message.session_id, &session_id)?;
            machine.transition(SenderState::Declined)?;
            bail!("receiver declined the offer: {}", message.reason);
        }
        other => {
            machine.transition(SenderState::Failed)?;
            bail!("unexpected control message from receiver: {:?}", other);
        }
    }

    endpoint.close().await;
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

async fn send_offer(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    manifest: drift_core::rendezvous::OfferManifest,
) -> Result<()> {
    write_message(
        send_stream,
        &ControlMessage::Offer(Offer {
            session_id: session_id.to_owned(),
            manifest,
        }),
    )
    .await
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

fn make_session_id() -> String {
    format!("{:016x}", random::<u64>())
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

    "unknown-device".to_owned()
}
