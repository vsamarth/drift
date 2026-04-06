use anyhow::{Context, Result, bail};
use std::collections::BTreeMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use tokio::sync::watch;

use crate::fs_plan::receive::{ExpectedFile, build_expected_files};
use crate::protocol::{
    message as protocol_message, receive as protocol_receiver, wire as protocol_wire,
};
use crate::rendezvous::OfferManifest;
use iroh::Endpoint;

use crate::session::{
    ExpectedTransferFile, FileReceiveProgress, build_expected_transfer_files,
    receive_files_over_connection_with_progress,
};
use crate::transfer::{ReceiverMachine, ReceiverState, TransferCancellation};
use crate::util::{ConnectionPathKind, classify_connection_path};
use crate::wire::DeviceType;

/// State after the offer is known and destinations are planned; waiting for user accept/decline.
pub struct ReceiverPendingDecision {
    endpoint: Endpoint,
    connection: iroh::endpoint::Connection,
    control_send: iroh::endpoint::SendStream,
    control_recv: iroh::endpoint::RecvStream,
    session_id: String,
    sender_device_name: String,
    sender_device_type: DeviceType,
    manifest: OfferManifest,
    expected_files: BTreeMap<String, ExpectedFile>,
    out_dir: PathBuf,
    connection_path_kind: ConnectionPathKind,
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
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveTransferOutcome {
    Completed,
    Declined,
    Cancelled(TransferCancellation),
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
    pub connection_path_kind: ConnectionPathKind,

    pub error_message: Option<String>,
}

/// Hello, our hello, read offer, validate destinations — stops at [ReceiverState::AwaitingDecision].
pub async fn receiver_run_until_decision(
    endpoint: Endpoint,
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

    let local_endpoint_id = endpoint.addr().id;
    let mut handshake = protocol_receiver::Receiver::new(protocol_identity(
        device_name,
        device_type,
        protocol_message::TransferRole::Receiver,
        local_endpoint_id,
    ));
    let peer_hello = handshake.read_peer_hello(&mut control_recv).await?;
    handshake
        .send_hello(&mut control_send, &peer_hello.session_id)
        .await?;

    machine.transition(ReceiverState::ReviewingOffer)?;
    let offer = handshake
        .read_offer(&mut control_recv, &peer_hello.session_id)
        .await?;

    let expected_files = match build_expected_files(&to_local_manifest(&offer), &out_dir).await {
        Ok(expected_files) => expected_files,
        Err(err) => {
            machine.transition(ReceiverState::Declined)?;
            handshake
                .decline(&mut control_send, &peer_hello.session_id, err.to_string())
                .await?;
            return Err(err);
        }
    };
    let connection_path_kind = classify_connection_path(&endpoint, connection.remote_id()).await;

    machine.transition(ReceiverState::AwaitingDecision)?;

    Ok(ReceiverPendingDecision {
        endpoint,
        connection,
        control_send,
        control_recv,
        session_id: peer_hello.session_id,
        sender_device_name: peer_hello.identity.device_name,
        sender_device_type: to_local_device_type(peer_hello.identity.device_type),
        manifest: to_local_manifest(&offer),
        expected_files,
        out_dir,
        connection_path_kind,
    })
}

pub async fn receiver_finish_after_decision_with_progress<F>(
    mut pending: ReceiverPendingDecision,
    machine: &mut ReceiverMachine,
    approved: bool,
    cancel_rx: Option<watch::Receiver<bool>>,
    on_progress: &mut F,
) -> Result<ReceiveTransferOutcome>
where
    F: FnMut(ReceiveTransferProgress),
{
    let sender_device_name = pending.sender_device_name.clone();
    let sender_device_type = pending.sender_device_type;
    let file_count = pending.manifest.file_count;
    let total_bytes = pending.manifest.total_size;
    let connection_path_kind = pending.connection_path_kind;

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
            connection_path_kind,
            error_message: None,
        });
        return Ok(ReceiveTransferOutcome::Declined);
    }

    let session_id = pending.session_id.clone();
    send_accept(&mut pending.control_send, &session_id).await?;
    machine.transition(ReceiverState::Approved)?;
    machine.transition(ReceiverState::Receiving)?;
    let expected_files = expected_transfer_files(&pending.manifest, pending.expected_files)?;
    let mut last_bytes_received = 0_u64;
    let transfer_result = receive_files_over_connection_with_progress(
        &pending.endpoint,
        &mut pending.control_send,
        &mut pending.control_recv,
        &session_id,
        expected_files,
        cancel_rx,
        |p: FileReceiveProgress| {
            let current_file_path = if p.file_path.is_empty() {
                None
            } else {
                Some(p.file_path.to_string())
            };
            last_bytes_received = p.total_bytes_received;
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
                connection_path_kind,
                error_message: None,
            });
        },
    )
    .await?;
    if let Some(cancellation) = transfer_result {
        machine.transition(ReceiverState::Cancelled)?;
        on_progress(ReceiveTransferProgress {
            phase: ReceiveTransferPhase::Cancelled,
            sender_device_name,
            sender_device_type,
            file_count,
            total_bytes,
            bytes_received: last_bytes_received,
            bytes_to_receive: total_bytes,
            current_file_path: None,
            bytes_received_in_file: 0,
            current_file_size: 0,
            connection_path_kind,
            error_message: Some(cancellation.reason.clone()),
        });
        return Ok(ReceiveTransferOutcome::Cancelled(cancellation));
    }

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
        connection_path_kind,
        error_message: None,
    });
    Ok(ReceiveTransferOutcome::Completed)
}

/// Send accept/decline and optionally receive payload.
pub async fn receiver_finish_after_decision(
    pending: ReceiverPendingDecision,
    machine: &mut ReceiverMachine,
    approved: bool,
) -> Result<ReceiveTransferOutcome> {
    let mut noop = |_| {};
    receiver_finish_after_decision_with_progress(pending, machine, approved, None, &mut noop).await
}

/// Like [handle_receiver_connection], but also reports receiving progress.
pub async fn handle_receiver_connection_with_progress<A, F>(
    endpoint: Endpoint,
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    device_name: &str,
    device_type: DeviceType,
    machine: &mut ReceiverMachine,
    approve: A,
    cancel_rx: Option<watch::Receiver<bool>>,
    mut on_progress: F,
) -> Result<ReceiveTransferOutcome>
where
    A: Future<Output = Result<bool>>,
    F: FnMut(ReceiveTransferProgress),
{
    let pending = receiver_run_until_decision(
        endpoint,
        connection,
        out_dir,
        device_name,
        device_type,
        machine,
    )
    .await?;

    let sender_device_name = pending.sender_device_name.clone();
    let sender_device_type = pending.sender_device_type;
    let file_count = pending.manifest.file_count;
    let total_bytes = pending.manifest.total_size;
    let connection_path_kind = pending.connection_path_kind;

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
        connection_path_kind,
        error_message: None,
    });

    let approved = approve.await?;

    let res = receiver_finish_after_decision_with_progress(
        pending,
        machine,
        approved,
        cancel_rx,
        &mut on_progress,
    )
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
            connection_path_kind,
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
    endpoint: Endpoint,
    connection: iroh::endpoint::Connection,
    out_dir: PathBuf,
    device_name: &str,
    device_type: DeviceType,
    machine: &mut ReceiverMachine,
    approve: A,
) -> Result<ReceiveTransferOutcome>
where
    A: Future<Output = Result<bool>>,
{
    handle_receiver_connection_with_progress(
        endpoint,
        connection,
        out_dir,
        device_name,
        device_type,
        machine,
        approve,
        None,
        |_| {},
    )
    .await
}

async fn send_accept(send_stream: &mut iroh::endpoint::SendStream, session_id: &str) -> Result<()> {
    protocol_wire::write_receiver_message(
        send_stream,
        &protocol_message::ReceiverMessage::Accept(protocol_message::Accept {
            session_id: session_id.to_owned(),
        }),
    )
    .await
}

async fn send_decline(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    reason: String,
) -> Result<()> {
    protocol_wire::write_receiver_message(
        send_stream,
        &protocol_message::ReceiverMessage::Decline(protocol_message::Decline {
            session_id: session_id.to_owned(),
            reason,
        }),
    )
    .await?;
    send_stream.finish()?;
    Ok(())
}

fn expected_transfer_files(
    manifest: &OfferManifest,
    expected_files: BTreeMap<String, ExpectedFile>,
) -> Result<Vec<ExpectedTransferFile>> {
    build_expected_transfer_files(manifest, expected_files)
}

fn protocol_identity(
    device_name: &str,
    device_type: DeviceType,
    role: protocol_message::TransferRole,
    endpoint_id: iroh::EndpointId,
) -> protocol_message::Identity {
    protocol_message::Identity {
        role,
        endpoint_id,
        device_name: device_name.to_owned(),
        device_type: to_protocol_device_type(device_type),
    }
}

fn to_local_device_type(device_type: protocol_message::DeviceType) -> DeviceType {
    match device_type {
        protocol_message::DeviceType::Phone => DeviceType::Phone,
        protocol_message::DeviceType::Laptop => DeviceType::Laptop,
    }
}

fn to_protocol_device_type(device_type: DeviceType) -> protocol_message::DeviceType {
    match device_type {
        DeviceType::Phone => protocol_message::DeviceType::Phone,
        DeviceType::Laptop => protocol_message::DeviceType::Laptop,
    }
}

fn to_local_manifest(manifest: &protocol_message::Offer) -> OfferManifest {
    let files: Vec<_> = manifest
        .manifest
        .items
        .iter()
        .map(|item| match item {
            protocol_message::ManifestItem::File { path, size } => crate::rendezvous::OfferFile {
                path: path.clone(),
                size: *size,
            },
        })
        .collect();
    let file_count = files.len() as u64;
    let total_size = files.iter().map(|file| file.size).sum();

    OfferManifest {
        files,
        file_count,
        total_size,
    }
}
