#![allow(dead_code)]

use anyhow::{Context, Result};
use iroh::{
    Endpoint, EndpointAddr, EndpointId, RelayMode, SecretKey, address_lookup::MdnsAddressLookup,
    endpoint::presets,
};
use std::path::{Path, PathBuf};
use rand::random;
use tokio::time::{timeout, Duration};
use tracing::info;

use crate::{
    blobs::send::{BlobService, PreparedStore},
    fs_plan::prepare::prepare_files,
    protocol::{message as protocol_message, send as protocol_sender},
    protocol::wire as protocol_wire,
    wire::ALPN,
};

const CONTROL_STREAM_FINISH_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendRequest {
    pub peer_endpoint_id: EndpointId,
    pub files: Vec<std::path::PathBuf>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SenderOutcome {
    Accepted {
        receiver_device_name: String,
        receiver_endpoint_id: EndpointId,
    },
    Declined {
        reason: String,
    },
}

#[derive(Debug)]
pub struct Sender {
    secret_key: SecretKey,
    session_id: String,
    identity: protocol_message::Identity,
    request: SendRequest,
}

impl Sender {
    pub fn new(
        device_name: String,
        device_type: crate::wire::DeviceType,
        request: SendRequest,
    ) -> Self {
        let secret_key = SecretKey::from_bytes(&random());
        Self {
            identity: protocol_message::Identity {
                role: protocol_message::TransferRole::Sender,
                endpoint_id: secret_key.public(),
                device_name,
                device_type: to_protocol_device_type(device_type),
            },
            secret_key,
            session_id: make_session_id(),
            request,
        }
    }

    pub fn session_id(&self) -> &str {
        &self.session_id
    }

    pub fn request(&self) -> &SendRequest {
        &self.request
    }

    pub async fn run(&self) -> Result<SenderOutcome> {
        let prepared_files = prepare_files(self.request.files.clone()).await?;
        let manifest = prepared_files.manifest.clone();
        let endpoint = bind_endpoint(self.secret_key.clone()).await?;
        info!(
            session_id = %self.session_id,
            peer_endpoint_id = %self.request.peer_endpoint_id,
            local_endpoint_id = %endpoint.addr().id,
            file_count = manifest.file_count,
            total_size = manifest.total_size,
            "demo.send.connecting"
        );

        let connection = endpoint
            .connect(EndpointAddr::new(self.request.peer_endpoint_id), ALPN)
            .await
            .context("connecting to receiver")?;

        let (mut control_send, mut control_recv) = connection
            .open_bi()
            .await
            .context("opening control stream")?;

        let mut handshake = protocol_sender::Sender::new(self.session_id.clone(), self.identity.clone());
        let outcome = handshake
            .run_control(
                &mut control_send,
                &mut control_recv,
                to_protocol_manifest(&manifest),
            )
            .await?;

        match outcome {
            protocol_sender::SenderControlOutcome::Accepted(peer) => {
                self.handle_accepted(
                    &endpoint,
                    &mut control_send,
                    &mut control_recv,
                    peer,
                    self.request.files.clone(),
                )
                .await
            }
            protocol_sender::SenderControlOutcome::Declined(message) => {
                info!(
                    session_id = %self.session_id,
                    reason = %message.reason,
                    "demo.send.declined"
                );
                let _ = control_send.finish();
                endpoint.close().await;
                Ok(SenderOutcome::Declined {
                    reason: message.reason,
                })
            }
        }
    }

    async fn handle_accepted(
        &self,
        endpoint: &Endpoint,
        control_send: &mut iroh::endpoint::SendStream,
        control_recv: &mut iroh::endpoint::RecvStream,
        peer: protocol_sender::SenderPeer,
        files: Vec<PathBuf>,
    ) -> Result<SenderOutcome> {
        let store_root = TempDir::new(self.session_id.clone())?;
        let store = PreparedStore::prepare(self.session_id.clone(), store_root.path(), files)
            .await
            .context("preparing blob store")?;
        let registration = BlobService::new(endpoint.clone())
            .register(store)
            .await
            .context("registering blob service")?;
        let ticket = registration.ticket().to_string();
        info!(session_id = %self.session_id, ticket = %ticket, "demo.send.ticket_ready");
        protocol_wire::write_sender_message(
            control_send,
            &protocol_message::SenderMessage::BlobTicket(
                protocol_message::BlobTicketMessage {
                    session_id: self.session_id.clone(),
                    ticket,
                },
            ),
        )
        .await
        .context("sending blob ticket")?;

        let completion = match self.read_transfer_result(control_recv).await {
            Ok(result) => result,
            Err(error) => {
                let _ = registration.shutdown().await;
                endpoint.close().await;
                return Err(error);
            }
        };

        if !matches!(completion.status, protocol_message::TransferStatus::Ok) {
            let _ = registration.shutdown().await;
            endpoint.close().await;
            anyhow::bail!("receiver reported transfer failure: {:?}", completion.status);
        }

        info!(session_id = %self.session_id, "demo.send.completed");
        let shutdown_result = registration.shutdown().await;
        self.finish_control_stream(control_send).await?;
        info!(
            session_id = %self.session_id,
            receiver_device_name = %peer.identity.device_name,
            receiver_endpoint_id = %peer.identity.endpoint_id,
            "demo.send.accepted"
        );
        endpoint.close().await;
        shutdown_result.context("shutting down blob service")?;
        Ok(SenderOutcome::Accepted {
            receiver_device_name: peer.identity.device_name,
            receiver_endpoint_id: peer.identity.endpoint_id,
        })
    }

    async fn read_transfer_result(
        &self,
        control_recv: &mut iroh::endpoint::RecvStream,
    ) -> Result<protocol_message::TransferResult> {
        let completion = match protocol_wire::read_receiver_message(control_recv)
            .await
            .context("waiting for receiver completion")?
        {
            protocol_message::ReceiverMessage::TransferResult(result) => result,
            other => anyhow::bail!("unexpected receiver completion message: {:?}", other),
        };

        if completion.session_id != self.session_id {
            anyhow::bail!(
                "session id mismatch: expected {}, got {}",
                self.session_id,
                completion.session_id
            );
        }

        Ok(completion)
    }

    async fn finish_control_stream(
        &self,
        control_send: &mut iroh::endpoint::SendStream,
    ) -> Result<()> {
        control_send.finish().context("finishing control send")?;
        let _ = timeout(CONTROL_STREAM_FINISH_TIMEOUT, control_send.stopped()).await;
        Ok(())
    }
}

#[derive(Debug)]
struct TempDir {
    path: PathBuf,
}

impl TempDir {
    fn new(session_id: String) -> Result<Self> {
        let unique = format!(
            "drift-transfer-flow-sender-{}-{}",
            session_id,
            rand::random::<u64>()
        );
        let path = std::env::temp_dir().join(unique);
        std::fs::create_dir_all(&path)
            .with_context(|| format!("creating temp directory {}", path.display()))?;
        Ok(Self { path })
    }

    fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.path);
    }
}

async fn bind_endpoint(secret_key: SecretKey) -> Result<Endpoint> {
    Endpoint::builder(presets::N0)
        .alpns(vec![ALPN.to_vec()])
        .relay_mode(RelayMode::Default)
        .address_lookup(MdnsAddressLookup::builder())
        .secret_key(secret_key)
        .bind()
        .await
        .context("binding iroh endpoint")
}

fn make_session_id() -> String {
    format!("{:016x}", random::<u64>())
}

fn to_protocol_device_type(
    device_type: crate::wire::DeviceType,
) -> protocol_message::DeviceType {
    match device_type {
        crate::wire::DeviceType::Phone => protocol_message::DeviceType::Phone,
        crate::wire::DeviceType::Laptop => protocol_message::DeviceType::Laptop,
    }
}

fn to_protocol_manifest(
    manifest: &crate::rendezvous::OfferManifest,
) -> protocol_message::TransferManifest {
    protocol_message::TransferManifest {
        items: manifest
            .files
            .iter()
            .map(|file| protocol_message::ManifestItem::File {
                path: file.path.clone(),
                size: file.size,
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::SendRequest;
    use iroh::SecretKey;

    #[test]
    fn request_keeps_peer_identity() {
        let request = SendRequest {
            peer_endpoint_id: SecretKey::from_bytes(&[1; 32]).public(),
            files: vec![],
        };

        assert_eq!(request.peer_endpoint_id, SecretKey::from_bytes(&[1; 32]).public());
    }
}
