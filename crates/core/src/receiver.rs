use std::collections::BTreeMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio::time::timeout;

use crate::fs_plan::receive::{ExpectedFile, build_expected_files};
use crate::rendezvous::OfferManifest;
use crate::session::{FileReceiveProgress, receive_files_over_connection_with_progress};
use crate::transfer::{ReceiverMachine, ReceiverState, ensure_session_id, validate_hello};
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
    sender_device_type: DeviceType,
    manifest: OfferManifest,
    expected_files: BTreeMap<String, ExpectedFile>,
    out_dir: PathBuf,
}

impl ReceiverPendingDecision {
    pub fn connection(&self) -> &iroh::endpoint::Connection {
        &self.connection
    }

    pub fn sender_device_name(&self) -> &str {
        &self.sender_device_name
    }

    pub fn sender_device_type(&self) -> DeviceType {
        self.sender_device_type
    }

    pub fn manifest(&self) -> &OfferManifest {
        &self.manifest
    }

    pub fn out_dir(&self) -> &Path {
        &self.out_dir
    }

    pub async fn wait_for_disconnect(&mut self) -> Result<()> {
        let mut byte = [0_u8; 1];
        self.control_recv
            .read_exact(&mut byte)
            .await
            .context("waiting for sender disconnect")?;
        bail!("unexpected control data while waiting for decision")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReceiveTransferPhase {
    WaitingForDecision,
    Receiving,
    Completed,
    Declined,
    Failed,
}

/// High-level receiving metrics suitable for CLI/UI progress rendering.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveTransferProgress {
    pub phase: ReceiveTransferPhase,
    pub sender_device_name: String,
    pub sender_device_type: DeviceType,
    pub file_count: u64,
    pub total_bytes: u64,

    /// Payload bytes received so far (file contents only).
    pub bytes_received: u64,
    pub bytes_to_receive: u64,

    pub current_file_path: Option<String>,
    pub bytes_received_in_file: u64,
    pub current_file_size: u64,

    pub error_message: Option<String>,
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
        sender_device_type: hello.device_type,
        manifest: offer.manifest,
        expected_files,
        out_dir,
    })
}

pub async fn receiver_finish_after_decision_with_progress<F>(
    mut pending: ReceiverPendingDecision,
    machine: &mut ReceiverMachine,
    approved: bool,
    on_progress: &mut F,
) -> Result<()>
where
    F: FnMut(ReceiveTransferProgress),
{
    let sender_device_name = pending.sender_device_name.clone();
    let sender_device_type = pending.sender_device_type;
    let file_count = pending.manifest.file_count;
    let total_bytes = pending.manifest.total_size;

    if !approved {
        machine.transition(ReceiverState::Declined)?;
        send_decline(
            &mut pending.control_send,
            &pending.session_id,
            "receiver declined the offer".to_owned(),
        )
        .await?;
        on_progress(ReceiveTransferProgress {
            phase: ReceiveTransferPhase::Declined,
            sender_device_name,
            sender_device_type,
            file_count,
            total_bytes,
            bytes_received: 0,
            bytes_to_receive: total_bytes,
            current_file_path: None,
            bytes_received_in_file: 0,
            current_file_size: 0,
            error_message: None,
        });
        return Ok(());
    }

    let session_id = pending.session_id.clone();
    send_accept(&mut pending.control_send, &session_id).await?;
    machine.transition(ReceiverState::Approved)?;
    machine.transition(ReceiverState::Receiving)?;
    receive_files_over_connection_with_progress(
        pending.connection,
        pending.out_dir,
        Some(pending.expected_files),
        |p: FileReceiveProgress| {
            let current_file_path = if p.file_path.is_empty() {
                None
            } else {
                Some(p.file_path.to_string())
            };
            on_progress(ReceiveTransferProgress {
                phase: ReceiveTransferPhase::Receiving,
                sender_device_name: sender_device_name.clone(),
                sender_device_type,
                file_count,
                total_bytes,
                bytes_received: p.total_bytes_received,
                bytes_to_receive: p.total_bytes_to_receive,
                current_file_path,
                bytes_received_in_file: p.bytes_received_in_file,
                current_file_size: p.file_size,
                error_message: None,
            });
        },
    )
    .await?;

    machine.transition(ReceiverState::Completed)?;
    on_progress(ReceiveTransferProgress {
        phase: ReceiveTransferPhase::Completed,
        sender_device_name,
        sender_device_type,
        file_count,
        total_bytes,
        bytes_received: total_bytes,
        bytes_to_receive: total_bytes,
        current_file_path: None,
        bytes_received_in_file: 0,
        current_file_size: 0,
        error_message: None,
    });
    Ok(())
}

/// Send accept/decline and optionally receive payload.
pub async fn receiver_finish_after_decision(
    pending: ReceiverPendingDecision,
    machine: &mut ReceiverMachine,
    approved: bool,
) -> Result<()> {
    let mut noop = |_| {};
    receiver_finish_after_decision_with_progress(pending, machine, approved, &mut noop).await
}

/// Like [handle_receiver_connection], but also reports receiving progress.
pub async fn handle_receiver_connection_with_progress<A, F>(
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    device_name: &str,
    device_type: DeviceType,
    machine: &mut ReceiverMachine,
    approve: A,
    mut on_progress: F,
) -> Result<()>
where
    A: Future<Output = Result<bool>>,
    F: FnMut(ReceiveTransferProgress),
{
    let pending =
        receiver_run_until_decision(connection, out_dir, device_name, device_type, machine).await?;

    let sender_device_name = pending.sender_device_name.clone();
    let sender_device_type = pending.sender_device_type;
    let file_count = pending.manifest.file_count;
    let total_bytes = pending.manifest.total_size;

    on_progress(ReceiveTransferProgress {
        phase: ReceiveTransferPhase::WaitingForDecision,
        sender_device_name: sender_device_name.clone(),
        sender_device_type,
        file_count,
        total_bytes,
        bytes_received: 0,
        bytes_to_receive: total_bytes,
        current_file_path: None,
        bytes_received_in_file: 0,
        current_file_size: 0,
        error_message: None,
    });

    let approved = approve.await?;

    let res =
        receiver_finish_after_decision_with_progress(pending, machine, approved, &mut on_progress)
            .await;

    if let Err(err) = &res {
        on_progress(ReceiveTransferProgress {
            phase: ReceiveTransferPhase::Failed,
            sender_device_name,
            sender_device_type,
            file_count,
            total_bytes,
            bytes_received: 0,
            bytes_to_receive: total_bytes,
            current_file_path: None,
            bytes_received_in_file: 0,
            current_file_size: 0,
            error_message: Some(err.to_string()),
        });
    }

    res
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
    handle_receiver_connection_with_progress(
        connection,
        out_dir,
        device_name,
        device_type,
        machine,
        approve,
        |_| {},
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
