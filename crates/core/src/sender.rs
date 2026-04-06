use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use rand::random;
use tokio::sync::watch;

use crate::fs_plan::prepare::{PreparedFiles, prepare_files};
use crate::rendezvous::{OfferManifest, RendezvousClient, resolve_server_url, validate_code};

enum PeerResolution {
    Rendezvous {
        code: String,
        server_url: Option<String>,
    },
    LanTicket(String),
}
use crate::session::{bind_endpoint, connect_to_ticket, send_files_over_connection};
use crate::transfer::{
    SenderMachine, SenderState, TransferCancellation, ensure_session_id, validate_hello,
};
use crate::util::{ConnectionPathKind, classify_connection_path};
use crate::wire::{
    CancelPhase, ControlMessage, DeviceType, Hello, Offer, TRANSFER_PROTOCOL_VERSION, TransferRole,
    decode_ticket, read_message, write_message,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendTransferPhase {
    Connecting,
    WaitingForDecision,
    Sending,
    Completed,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendTransferProgress {
    pub phase: SendTransferPhase,
    pub destination_label: String,
    /// The receiver device type (if known yet).
    pub remote_device_type: Option<DeviceType>,
    pub manifest: OfferManifest,
    /// Total payload bytes sent so far (file contents only); `0` until streaming starts.
    pub bytes_sent: u64,
    /// Index of the currently streaming file in `manifest.files`.
    /// `None` until file streaming begins (or once the transfer is completed/declined).
    pub current_file_index: Option<u64>,
    /// Bytes sent in the currently streaming file so far.
    pub bytes_sent_in_file: u64,
    /// Observed transport path kind for the session.
    pub connection_path_kind: Option<ConnectionPathKind>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendTransferOutcome {
    pub receiver_device_name: String,
    pub manifest: OfferManifest,
    pub connection_path_kind: ConnectionPathKind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendTransferResult {
    Completed(SendTransferOutcome),
    Cancelled(TransferCancellation),
}

pub async fn send_files_with_progress<F>(
    code: String,
    files: Vec<PathBuf>,
    server_url: Option<String>,
    device_name: String,
    device_type: DeviceType,
    cancel_rx: Option<watch::Receiver<bool>>,
    mut on_progress: F,
) -> Result<SendTransferResult>
where
    F: FnMut(SendTransferProgress),
{
    validate_code(&code)?;
    let prepared = prepare_files(files).await?;
    let session_id = make_session_id();
    let destination_label = format_code_label(&code);
    let mut machine = SenderMachine::new();

    on_progress(progress(
        SendTransferPhase::Connecting,
        destination_label.clone(),
        &prepared,
        None,
        0,
        None,
        0,
        None,
    ));

    let result = send_prepared_files(
        PeerResolution::Rendezvous { code, server_url },
        &device_name,
        device_type,
        &session_id,
        &prepared,
        cancel_rx,
        &mut machine,
        &mut on_progress,
    )
    .await;

    result
}

/// Send after resolving the receiver via LAN (mDNS ticket); skips rendezvous claim.
pub async fn send_files_with_progress_via_lan_ticket<F>(
    ticket: String,
    destination_label: String,
    files: Vec<PathBuf>,
    device_name: String,
    device_type: DeviceType,
    cancel_rx: Option<watch::Receiver<bool>>,
    mut on_progress: F,
) -> Result<SendTransferResult>
where
    F: FnMut(SendTransferProgress),
{
    let prepared = prepare_files(files).await?;
    let session_id = make_session_id();
    let mut machine = SenderMachine::new();

    on_progress(progress(
        SendTransferPhase::Connecting,
        destination_label.clone(),
        &prepared,
        None,
        0,
        None,
        0,
        None,
    ));

    send_prepared_files(
        PeerResolution::LanTicket(ticket),
        &device_name,
        device_type,
        &session_id,
        &prepared,
        cancel_rx,
        &mut machine,
        &mut on_progress,
    )
    .await
}

async fn send_prepared_files<F>(
    resolution: PeerResolution,
    device_name: &str,
    device_type: DeviceType,
    session_id: &str,
    prepared: &PreparedFiles,
    mut cancel_rx: Option<watch::Receiver<bool>>,
    machine: &mut SenderMachine,
    on_progress: &mut F,
) -> Result<SendTransferResult>
where
    F: FnMut(SendTransferProgress),
{
    machine.transition(SenderState::Resolving)?;
    let endpoint_addr = match resolution {
        PeerResolution::Rendezvous { code, server_url } => {
            let client = RendezvousClient::new(resolve_server_url(server_url.as_deref()));
            let resolved = client.claim_peer(&code).await?;
            decode_ticket(&resolved.ticket)?
        }
        PeerResolution::LanTicket(ticket) => decode_ticket(ticket.trim())?,
    };

    machine.transition(SenderState::Connecting)?;
    let endpoint = bind_endpoint()
        .await
        .context("binding local iroh endpoint")?;
    let connection = connect_to_ticket(&endpoint, endpoint_addr).await?;
    let connection_path_kind = classify_connection_path(&endpoint, connection.remote_id()).await;
    machine.transition(SenderState::Connected)?;
    let mut last_bytes_sent = 0_u64;
    let mut last_file_index = None;
    let mut last_bytes_sent_in_file = 0_u64;

    machine.transition(SenderState::Offering)?;
    let (mut control_send, mut control_recv) = connection
        .open_bi()
        .await
        .context("opening transfer control stream")?;
    send_hello(
        &mut control_send,
        session_id,
        TransferRole::Sender,
        device_name,
        device_type,
    )
    .await?;
    let receiver_hello = match read_message::<ControlMessage>(&mut control_recv)
        .await
        .context("waiting for receiver hello")?
    {
        ControlMessage::Hello(message) => {
            validate_hello(&message, TransferRole::Receiver)?;
            ensure_session_id(&message.session_id, session_id)?;
            message
        }
        other => {
            machine.transition(SenderState::Failed)?;
            bail!("expected hello from receiver, got {:?}", other);
        }
    };

    send_offer(&mut control_send, session_id, prepared.manifest.clone()).await?;
    machine.transition(SenderState::WaitingForDecision)?;
    on_progress(progress(
        SendTransferPhase::WaitingForDecision,
        receiver_hello.device_name.clone(),
        prepared,
        Some(receiver_hello.device_type),
        0,
        None,
        0,
        Some(connection_path_kind),
    ));

    let decision = tokio::select! {
        cancel_requested = async {
            let Some(cancel_rx) = cancel_rx.as_mut() else {
                return false;
            };
            if *cancel_rx.borrow() {
                return true;
            }
            loop {
                if cancel_rx.changed().await.is_err() {
                    return *cancel_rx.borrow();
                }
                if *cancel_rx.borrow() {
                    return true;
                }
            }
        }, if cancel_rx.is_some() => {
            if cancel_requested {
                let cancellation = TransferCancellation {
                    by: TransferRole::Sender,
                    phase: CancelPhase::WaitingForDecision,
                    reason: "sender cancelled before approval".to_owned(),
                };
                let _ = send_cancel(
                    &mut control_send,
                    session_id,
                    cancellation.phase,
                    cancellation.reason.clone(),
                ).await;
                machine.transition(SenderState::Cancelled)?;
                on_progress(progress(
                    SendTransferPhase::Cancelled,
                    receiver_hello.device_name.clone(),
                    prepared,
                    Some(receiver_hello.device_type),
                    0,
                    None,
                    0,
                    Some(connection_path_kind),
                ));
                endpoint.close().await;
                return Ok(SendTransferResult::Cancelled(cancellation));
            }
            unreachable!()
        }
        decision = read_message::<ControlMessage>(&mut control_recv) => {
            decision.context("waiting for receiver decision")?
        }
    };

    match decision {
        ControlMessage::Accept(message) => {
            ensure_session_id(&message.session_id, session_id)?;
            machine.transition(SenderState::Sending)?;
            on_progress(progress(
                SendTransferPhase::Sending,
                receiver_hello.device_name.clone(),
                prepared,
                Some(receiver_hello.device_type),
                0,
                None,
                0,
                Some(connection_path_kind),
            ));
            let session_result = send_files_over_connection(
                &endpoint,
                &mut control_send,
                &mut control_recv,
                session_id,
                &prepared.files,
                cancel_rx.clone(),
                |p| {
                    last_bytes_sent = p.total_bytes_sent;
                    last_file_index = Some(p.file_index as u64);
                    last_bytes_sent_in_file = p.bytes_sent_in_file;
                    on_progress(progress(
                        SendTransferPhase::Sending,
                        receiver_hello.device_name.clone(),
                        prepared,
                        Some(receiver_hello.device_type),
                        p.total_bytes_sent,
                        Some(p.file_index as u64),
                        p.bytes_sent_in_file,
                        Some(connection_path_kind),
                    ));
                },
            )
            .await?;
            if let Some(cancellation) = session_result {
                machine.transition(SenderState::Cancelled)?;
                on_progress(progress(
                    SendTransferPhase::Cancelled,
                    receiver_hello.device_name.clone(),
                    prepared,
                    Some(receiver_hello.device_type),
                    last_bytes_sent,
                    last_file_index,
                    last_bytes_sent_in_file,
                    Some(connection_path_kind),
                ));
                endpoint.close().await;
                return Ok(SendTransferResult::Cancelled(cancellation));
            }
            machine.transition(SenderState::Completed)?;
            on_progress(progress(
                SendTransferPhase::Completed,
                receiver_hello.device_name.clone(),
                prepared,
                Some(receiver_hello.device_type),
                prepared.manifest.total_size,
                None,
                0,
                Some(connection_path_kind),
            ));
        }
        ControlMessage::Decline(message) => {
            ensure_session_id(&message.session_id, session_id)?;
            machine.transition(SenderState::Declined)?;
            endpoint.close().await;
            bail!("receiver declined the offer: {}", message.reason);
        }
        ControlMessage::Cancel(message) => {
            ensure_session_id(&message.session_id, session_id)?;
            let cancellation = TransferCancellation {
                by: message.by,
                phase: message.phase,
                reason: message.reason,
            };
            machine.transition(SenderState::Cancelled)?;
            on_progress(progress(
                SendTransferPhase::Cancelled,
                receiver_hello.device_name.clone(),
                prepared,
                Some(receiver_hello.device_type),
                0,
                None,
                0,
                Some(connection_path_kind),
            ));
            endpoint.close().await;
            return Ok(SendTransferResult::Cancelled(cancellation));
        }
        other => {
            machine.transition(SenderState::Failed)?;
            endpoint.close().await;
            bail!("unexpected control message from receiver: {:?}", other);
        }
    }

    endpoint.close().await;
    Ok(SendTransferResult::Completed(SendTransferOutcome {
        receiver_device_name: receiver_hello.device_name,
        manifest: prepared.manifest.clone(),
        connection_path_kind,
    }))
}

fn progress(
    phase: SendTransferPhase,
    destination_label: String,
    prepared: &PreparedFiles,
    remote_device_type: Option<DeviceType>,
    bytes_sent: u64,
    current_file_index: Option<u64>,
    bytes_sent_in_file: u64,
    connection_path_kind: Option<ConnectionPathKind>,
) -> SendTransferProgress {
    SendTransferProgress {
        phase,
        destination_label,
        remote_device_type,
        manifest: prepared.manifest.clone(),
        bytes_sent,
        current_file_index,
        bytes_sent_in_file,
        connection_path_kind,
    }
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

async fn send_offer(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    manifest: OfferManifest,
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

async fn send_cancel(
    send_stream: &mut iroh::endpoint::SendStream,
    session_id: &str,
    phase: CancelPhase,
    reason: String,
) -> Result<()> {
    write_message(
        send_stream,
        &ControlMessage::Cancel(crate::wire::Cancel {
            session_id: session_id.to_owned(),
            by: TransferRole::Sender,
            phase,
            reason,
        }),
    )
    .await?;
    let _ = send_stream.finish();
    Ok(())
}

fn make_session_id() -> String {
    format!("{:016x}", random::<u64>())
}

pub fn format_code_label(code: &str) -> String {
    let trimmed = code.trim().to_uppercase();
    if trimmed.len() == 6 {
        format!("Code {} {}", &trimmed[..3], &trimmed[3..])
    } else {
        "Code".to_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::format_code_label;

    #[test]
    fn format_code_label_groups_characters() {
        assert_eq!(format_code_label("ab2cd3"), "Code AB2 CD3");
    }

    #[test]
    fn format_code_label_falls_back_when_length_is_invalid() {
        assert_eq!(format_code_label("oops"), "Code");
    }
}
