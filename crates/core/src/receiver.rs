use std::collections::BTreeMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::time::timeout;

use crate::fs_plan::receive::{ExpectedFile, build_expected_files};
use crate::rendezvous::OfferManifest;
use crate::session::receive_files_over_connection;
use crate::transfer::{ReceiverMachine, ReceiverState, ensure_session_id, validate_hello};
use crate::util::human_size;
use crate::wire::{
    Accept, ControlMessage, Decline, DeviceType, Hello, TRANSFER_PROTOCOL_VERSION, TransferRole,
    read_message, write_message,
};

const CONTROL_STREAM_FINISH_TIMEOUT: Duration = Duration::from_secs(2);

/// State after the offer is known and destinations are planned; waiting for user accept/decline.
pub struct ReceiverPendingDecision {
    connection: iroh::endpoint::Connection,
    control_send: iroh::endpoint::SendStream,
    /// Held so the control stream stays open until the transfer finishes.
    #[allow(dead_code)]
    control_recv: iroh::endpoint::RecvStream,
    session_id: String,
    sender_device_name: String,
    manifest: OfferManifest,
    expected_files: BTreeMap<String, ExpectedFile>,
    out_dir: PathBuf,
}

impl ReceiverPendingDecision {
    pub fn sender_device_name(&self) -> &str {
        &self.sender_device_name
    }

    pub fn manifest(&self) -> &OfferManifest {
        &self.manifest
    }

    pub fn out_dir(&self) -> &Path {
        &self.out_dir
    }
}

/// Hello, our hello, read offer, validate destinations — stops at [ReceiverState::AwaitingDecision].
pub async fn receiver_run_until_decision(
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    device_name: &str,
    device_type: DeviceType,
    machine: &mut ReceiverMachine,
) -> Result<ReceiverPendingDecision> {
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
        device_type,
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

    Ok(ReceiverPendingDecision {
        connection,
        control_send,
        control_recv,
        session_id: hello.session_id,
        sender_device_name: hello.device_name,
        manifest: offer.manifest,
        expected_files,
        out_dir,
    })
}

/// Send accept/decline and optionally receive payload.
pub async fn receiver_finish_after_decision(
    mut pending: ReceiverPendingDecision,
    machine: &mut ReceiverMachine,
    approved: bool,
) -> Result<()> {
    let session_id = pending.session_id.clone();
    if !approved {
        machine.transition(ReceiverState::Declined)?;
        send_decline(
            &mut pending.control_send,
            &session_id,
            "receiver declined the offer".to_owned(),
        )
        .await?;
        println!("Offer declined");
        return Ok(());
    }

    send_accept(&mut pending.control_send, &session_id).await?;
    machine.transition(ReceiverState::Approved)?;
    println!("Accepted offer. Receiving files...");

    machine.transition(ReceiverState::Receiving)?;
    receive_files_over_connection(
        pending.connection,
        pending.out_dir,
        Some(pending.expected_files),
    )
    .await?;
    machine.transition(ReceiverState::Completed)?;
    Ok(())
}

/// Run the receiver-side transfer protocol after the iroh connection is established.
///
/// `approve` resolves when the user (or host app) decides whether to accept the offer.
/// Return `Ok(true)` to accept, `Ok(false)` to decline politely, `Err` to abort (e.g. I/O).
pub async fn handle_receiver_connection<A>(
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    device_name: &str,
    device_type: DeviceType,
    machine: &mut ReceiverMachine,
    approve: A,
) -> Result<()>
where
    A: Future<Output = Result<bool>>,
{
    let pending =
        receiver_run_until_decision(connection, out_dir, device_name, device_type, machine).await?;
    let approved = approve.await?;
    receiver_finish_after_decision(pending, machine, approved).await
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
    let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, send_stream.stopped()).await;
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
    let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, send_stream.stopped()).await;
    Ok(())
}

async fn send_hello(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    role: TransferRole,
    device_name: &str,
    device_type: DeviceType,
) -> Result<()> {
    write_message(
        send_stream,
        &ControlMessage::Hello(Hello {
            version: TRANSFER_PROTOCOL_VERSION,
            session_id: session_id.to_owned(),
            role,
            device_name: device_name.to_owned(),
            device_type,
        }),
    )
    .await
}
