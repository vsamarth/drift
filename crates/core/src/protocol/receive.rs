#![allow(dead_code)]

use tokio::io::{AsyncRead, AsyncWrite};

use super::error::{ProtocolError, Result};
use super::message::{
    Accept, Decline, Hello, Identity, MessageKind, Offer, PROTOCOL_VERSION, SenderMessage,
    TransferRole,
};
use super::wire::{read_sender_message, write_receiver_message};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ReceiverState {
    Idle,
    PeerHelloReceived,
    HelloSent,
    OfferReceived,
    AwaitingDecision,
    Accepted,
    Declined,
    Failed,
}

#[derive(Debug)]
pub(crate) struct ReceiverMachine {
    state: ReceiverState,
}

impl ReceiverMachine {
    pub(crate) fn new() -> Self {
        Self {
            state: ReceiverState::Idle,
        }
    }

    pub(crate) fn transition(&mut self, next: ReceiverState) -> Result<()> {
        use ReceiverState::*;

        let allowed = matches!(
            (self.state, next),
            (Idle, PeerHelloReceived)
                | (PeerHelloReceived, HelloSent)
                | (HelloSent, OfferReceived)
                | (OfferReceived, AwaitingDecision)
                | (AwaitingDecision, Accepted)
                | (AwaitingDecision, Declined)
                | (_, Failed)
        );

        if !allowed {
            return Err(ProtocolError::invalid_transition(
                "receiver",
                format!("{:?}", self.state),
                format!("{:?}", next),
            ));
        }

        self.state = next;
        Ok(())
    }
}

impl Default for ReceiverMachine {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ReceiverPeer {
    pub(crate) session_id: String,
    pub(crate) identity: Identity,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ReceiverPendingDecision {
    pub(crate) sender: ReceiverPeer,
    pub(crate) manifest: Offer,
}

impl ReceiverPendingDecision {
    pub(crate) fn session_id(&self) -> &str {
        &self.sender.session_id
    }

    pub(crate) fn sender(&self) -> &ReceiverPeer {
        &self.sender
    }

    pub(crate) fn manifest(&self) -> &Offer {
        &self.manifest
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ReceiverControlOutcome {
    Pending(ReceiverPendingDecision),
    Accepted(ReceiverPeer),
    Declined(Decline),
}

#[derive(Debug)]
pub(crate) struct Receiver {
    identity: Identity,
    peer_identity: Option<Identity>,
    machine: ReceiverMachine,
}

impl Receiver {
    pub(crate) fn new(identity: Identity) -> Self {
        Self {
            identity,
            peer_identity: None,
            machine: ReceiverMachine::new(),
        }
    }

    pub(crate) fn identity(&self) -> &Identity {
        &self.identity
    }

    pub(crate) fn state(&self) -> ReceiverState {
        self.machine.state
    }

    pub(crate) async fn run_control_until_decision<R, W>(
        &mut self,
        send: &mut W,
        recv: &mut R,
    ) -> Result<ReceiverPendingDecision>
    where
        R: AsyncRead + Unpin,
        W: AsyncWrite + Unpin,
    {
        let peer_hello = self.read_peer_hello(recv).await?;
        self.send_hello(send, &peer_hello.session_id).await?;
        let offer = self.read_offer(recv, &peer_hello.session_id).await?;
        Ok(ReceiverPendingDecision {
            sender: ReceiverPeer {
                session_id: peer_hello.session_id,
                identity: peer_hello.identity,
            },
            manifest: offer,
        })
    }

    pub(crate) async fn read_peer_hello<R>(&mut self, recv: &mut R) -> Result<Hello>
    where
        R: AsyncRead + Unpin,
    {
        let hello = match read_sender_message(recv).await? {
            SenderMessage::Hello(message) => message,
            other => {
                self.machine.transition(ReceiverState::Failed)?;
                return Err(ProtocolError::unexpected_message_kind(
                    "sender handshake",
                    MessageKind::Hello,
                    other.kind(),
                ));
            }
        };

        validate_hello(&hello, TransferRole::Sender)?;
        self.peer_identity = Some(hello.identity.clone());
        self.machine.transition(ReceiverState::PeerHelloReceived)?;
        Ok(hello)
    }

    pub(crate) async fn send_hello<W>(&mut self, send: &mut W, session_id: &str) -> Result<()>
    where
        W: AsyncWrite + Unpin,
    {
        self.machine.transition(ReceiverState::HelloSent)?;
        write_receiver_message(
            send,
            &super::message::ReceiverMessage::Hello(Hello {
                version: PROTOCOL_VERSION,
                session_id: session_id.to_owned(),
                identity: self.identity.clone(),
            }),
        )
        .await
    }

    pub(crate) async fn read_offer<R>(
        &mut self,
        recv: &mut R,
        expected_session_id: &str,
    ) -> Result<Offer>
    where
        R: AsyncRead + Unpin,
    {
        let offer = match read_sender_message(recv).await? {
            SenderMessage::Offer(message) => message,
            other => {
                self.machine.transition(ReceiverState::Failed)?;
                return Err(ProtocolError::unexpected_message_kind(
                    "sender offer",
                    MessageKind::Offer,
                    other.kind(),
                ));
            }
        };

        ensure_session_id(&offer.session_id, expected_session_id)?;
        self.machine.transition(ReceiverState::OfferReceived)?;
        self.machine.transition(ReceiverState::AwaitingDecision)?;
        Ok(offer)
    }

    pub(crate) async fn accept<W>(
        &mut self,
        send: &mut W,
        session_id: &str,
    ) -> Result<ReceiverControlOutcome>
    where
        W: AsyncWrite + Unpin,
    {
        self.machine.transition(ReceiverState::Accepted)?;
        write_receiver_message(
            send,
            &super::message::ReceiverMessage::Accept(Accept {
                session_id: session_id.to_owned(),
            }),
        )
        .await?;

        let sender = ReceiverPeer {
            session_id: session_id.to_owned(),
            identity: self
                .peer_identity
                .clone()
                .ok_or_else(|| ProtocolError::missing_peer_identity("sender"))?,
        };
        Ok(ReceiverControlOutcome::Accepted(sender))
    }

    pub(crate) async fn decline<W>(
        &mut self,
        send: &mut W,
        session_id: &str,
        reason: String,
    ) -> Result<ReceiverControlOutcome>
    where
        W: AsyncWrite + Unpin,
    {
        self.machine.transition(ReceiverState::Declined)?;
        let message = Decline {
            session_id: session_id.to_owned(),
            reason,
        };
        write_receiver_message(
            send,
            &super::message::ReceiverMessage::Decline(message.clone()),
        )
        .await?;
        Ok(ReceiverControlOutcome::Declined(message))
    }
}

fn validate_hello(message: &Hello, expected_role: TransferRole) -> Result<()> {
    if message.version != PROTOCOL_VERSION {
        return Err(ProtocolError::unsupported_version(
            PROTOCOL_VERSION,
            message.version,
        ));
    }

    if message.identity.role != expected_role {
        return Err(ProtocolError::unexpected_role(
            expected_role,
            message.identity.role,
        ));
    }

    if message.identity.device_name.trim().is_empty() {
        return Err(ProtocolError::empty_device_name(message.identity.role));
    }

    Ok(())
}

fn ensure_session_id(actual: &str, expected: &str) -> Result<()> {
    if actual == expected {
        Ok(())
    } else {
        Err(ProtocolError::session_id_mismatch(expected, actual))
    }
}

#[cfg(test)]
mod tests {
    use super::{Receiver, ReceiverControlOutcome, ReceiverMachine, ReceiverState};
    use crate::protocol::message::{
        DeviceType, Hello, Identity, ManifestItem, Offer, PROTOCOL_VERSION, ReceiverMessage,
        SenderMessage, TransferManifest, TransferRole,
    };
    use crate::protocol::wire::{read_receiver_message, write_sender_message};
    use iroh::SecretKey;
    use tokio::io::duplex;

    #[test]
    fn receiver_machine_allows_happy_path() {
        let mut machine = ReceiverMachine::new();
        machine
            .transition(ReceiverState::PeerHelloReceived)
            .unwrap();
        machine.transition(ReceiverState::HelloSent).unwrap();
        machine.transition(ReceiverState::OfferReceived).unwrap();
        machine.transition(ReceiverState::AwaitingDecision).unwrap();
        machine.transition(ReceiverState::Accepted).unwrap();
    }

    #[tokio::test]
    async fn receiver_handler_runs_handshake() -> std::result::Result<(), Box<dyn std::error::Error>>
    {
        let (local, remote) = duplex(1024);
        let (mut local_read, mut local_write) = tokio::io::split(local);
        let (mut remote_read, mut remote_write) = tokio::io::split(remote);

        let mut handler = Receiver::new(Identity {
            role: TransferRole::Receiver,
            endpoint_id: SecretKey::from_bytes(&[2; 32]).public(),
            device_name: "receiver".to_owned(),
            device_type: DeviceType::Laptop,
        });

        let sender_task = tokio::spawn(async move {
            write_sender_message(
                &mut remote_write,
                &SenderMessage::Hello(Hello {
                    version: PROTOCOL_VERSION,
                    session_id: "session-1".to_owned(),
                    identity: Identity {
                        role: TransferRole::Sender,
                        endpoint_id: SecretKey::from_bytes(&[1; 32]).public(),
                        device_name: "sender".to_owned(),
                        device_type: DeviceType::Phone,
                    },
                }),
            )
            .await
            .unwrap();

            let hello = read_receiver_message(&mut remote_read).await.unwrap();
            assert!(matches!(hello, ReceiverMessage::Hello(_)));

            write_sender_message(
                &mut remote_write,
                &SenderMessage::Offer(Offer {
                    session_id: "session-1".to_owned(),
                    manifest: TransferManifest {
                        items: vec![ManifestItem::File {
                            path: "a.txt".to_owned(),
                            size: 1,
                        }],
                    },
                    collection_hash: [0u8; 32].into(),
                }),
            )
            .await
            .unwrap();

            let accept = read_receiver_message(&mut remote_read).await.unwrap();
            assert!(matches!(accept, ReceiverMessage::Accept(_)));
        });

        let pending = handler
            .run_control_until_decision(&mut local_write, &mut local_read)
            .await?;

        assert_eq!(pending.session_id(), "session-1");
        assert_eq!(pending.sender().identity.device_name, "sender");

        let outcome = handler
            .accept(&mut local_write, pending.session_id())
            .await?;
        assert!(matches!(outcome, ReceiverControlOutcome::Accepted(_)));

        sender_task.await.unwrap();
        Ok(())
    }
}
