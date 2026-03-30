use std::path::PathBuf;

use anyhow::{Context, Result, bail};
use rand::random;

use crate::fs_plan::prepare::{PreparedFiles, prepare_files};
use crate::rendezvous::{OfferManifest, RendezvousClient, resolve_server_url, validate_code};
use crate::session::{bind_endpoint, connect_to_ticket, send_files_over_connection};
use crate::transfer::{SenderMachine, SenderState, ensure_session_id, validate_hello};
use crate::wire::{
    ControlMessage, DeviceType, Hello, Offer, TRANSFER_PROTOCOL_VERSION, TransferRole,
    decode_ticket, read_message, write_message,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SendTransferPhase {
    Connecting,
    WaitingForDecision,
    Sending,
    Completed,
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendTransferOutcome {
    pub receiver_device_name: String,
    pub manifest: OfferManifest,
}

pub async fn send_files_with_progress<F>(
    code: String,
    files: Vec<PathBuf>,
    server_url: Option<String>,
    device_name: String,
    device_type: DeviceType,
    mut on_progress: F,
) -> Result<SendTransferOutcome>
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
    ));

    let result = send_prepared_files(
        &code,
        server_url.as_deref(),
        &device_name,
        device_type,
        &session_id,
        &prepared,
        &mut machine,
        &mut on_progress,
    )
    .await;

    result
}

async fn send_prepared_files<F>(
    code: &str,
    server_url: Option<&str>,
    device_name: &str,
    device_type: DeviceType,
    session_id: &str,
    prepared: &PreparedFiles,
    machine: &mut SenderMachine,
    on_progress: &mut F,
) -> Result<SendTransferOutcome>
where
    F: FnMut(SendTransferProgress),
{
    machine.transition(SenderState::Resolving)?;
    let client = RendezvousClient::new(resolve_server_url(server_url));
    let resolved = client.claim_peer(code).await?;
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
    control_send.finish()?;
    machine.transition(SenderState::WaitingForDecision)?;
    on_progress(progress(
        SendTransferPhase::WaitingForDecision,
        receiver_hello.device_name.clone(),
        prepared,
        Some(receiver_hello.device_type),
        0,
    ));

    match read_message::<ControlMessage>(&mut control_recv)
        .await
        .context("waiting for receiver decision")?
    {
        ControlMessage::Accept(message) => {
            ensure_session_id(&message.session_id, session_id)?;
            machine.transition(SenderState::Sending)?;
            on_progress(progress(
                SendTransferPhase::Sending,
                receiver_hello.device_name.clone(),
                prepared,
                Some(receiver_hello.device_type),
                0,
            ));
            send_files_over_connection(connection, &prepared.files, |sent| {
                on_progress(progress(
                    SendTransferPhase::Sending,
                    receiver_hello.device_name.clone(),
                    prepared,
                    Some(receiver_hello.device_type),
                    sent,
                ));
            })
            .await?;
            machine.transition(SenderState::Completed)?;
            on_progress(progress(
                SendTransferPhase::Completed,
                receiver_hello.device_name.clone(),
                prepared,
                Some(receiver_hello.device_type),
                prepared.manifest.total_size,
            ));
        }
        ControlMessage::Decline(message) => {
            ensure_session_id(&message.session_id, session_id)?;
            machine.transition(SenderState::Declined)?;
            endpoint.close().await;
            bail!("receiver declined the offer: {}", message.reason);
        }
        other => {
            machine.transition(SenderState::Failed)?;
            endpoint.close().await;
            bail!("unexpected control message from receiver: {:?}", other);
        }
    }

    endpoint.close().await;
    Ok(SendTransferOutcome {
        receiver_device_name: receiver_hello.device_name,
        manifest: prepared.manifest.clone(),
    })
}

fn progress(
    phase: SendTransferPhase,
    destination_label: String,
    prepared: &PreparedFiles,
    remote_device_type: Option<DeviceType>,
    bytes_sent: u64,
) -> SendTransferProgress {
    SendTransferProgress {
        phase,
        destination_label,
        remote_device_type,
        manifest: prepared.manifest.clone(),
        bytes_sent,
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
