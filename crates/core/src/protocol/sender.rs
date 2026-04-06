#![allow(dead_code)]

use anyhow::{Context, Result, bail};
use tokio::io::{AsyncRead, AsyncWrite};

use super::message::{
    Cancel, Decline, Hello, Identity, Offer, PROTOCOL_VERSION, ReceiverMessage, SenderMessage,
    TransferRole,
};
use super::wire::{read_receiver_message, write_sender_message};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum SenderState {
    Idle,
    HelloSent,
    PeerHelloReceived,
    OfferSent,
    WaitingForDecision,
    Accepted,
    Declined,
    Cancelled,
    Failed,
}

#[derive(Debug)]
pub(crate) struct SenderMachine {
    state: SenderState,
}

impl SenderMachine {
    pub(crate) fn new() -> Self {
        Self {
            state: SenderState::Idle,
        }
    }

    pub(crate) fn transition(&mut self, next: SenderState) -> Result<()> {
        use SenderState::*;

        let allowed = matches!(
            (self.state, next),
            (Idle, HelloSent)
                | (HelloSent, PeerHelloReceived)
                | (PeerHelloReceived, OfferSent)
                | (OfferSent, WaitingForDecision)
                | (WaitingForDecision, Accepted)
                | (WaitingForDecision, Declined)
                | (WaitingForDecision, Cancelled)
                | (_, Failed)
        );

        if !allowed {
            bail!("invalid sender transition: {:?} -> {:?}", self.state, next);
        }

        self.state = next;
        Ok(())
    }
}

impl Default for SenderMachine {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct SenderPeer {
    pub(crate) session_id: String,
    pub(crate) identity: Identity,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum SenderControlOutcome {
    Accepted(SenderPeer),
    Declined(Decline),
    Cancelled(Cancel),
}

#[derive(Debug)]
pub(crate) struct Sender {
    session_id: String,
    identity: Identity,
    peer_identity: Option<Identity>,
    machine: SenderMachine,
}

impl Sender {
    pub(crate) fn new(session_id: String, identity: Identity) -> Self {
        Self {
            session_id,
            identity,
            peer_identity: None,
            machine: SenderMachine::new(),
        }
    }

    pub(crate) fn session_id(&self) -> &str {
        &self.session_id
    }

    pub(crate) fn identity(&self) -> &Identity {
        &self.identity
    }

    pub(crate) fn state(&self) -> SenderState {
        self.machine.state
    }

    pub(crate) async fn run_control<R, W>(
        &mut self,
        send: &mut W,
        recv: &mut R,
        manifest: super::message::TransferManifest,
    ) -> Result<SenderControlOutcome>
    where
        R: AsyncRead + Unpin,
        W: AsyncWrite + Unpin,
    {
        self.send_hello(send).await?;
        self.read_peer_hello(recv).await?;
        self.send_offer(send, manifest).await?;
        self.await_decision(recv).await
    }

    pub(crate) async fn send_hello<W>(&mut self, send: &mut W) -> Result<()>
    where
        W: AsyncWrite + Unpin,
    {
        self.machine.transition(SenderState::HelloSent)?;
        write_sender_message(
            send,
            &SenderMessage::Hello(Hello {
                version: PROTOCOL_VERSION,
                session_id: self.session_id.clone(),
                identity: self.identity.clone(),
            }),
        )
        .await
    }

    pub(crate) async fn read_peer_hello<R>(&mut self, recv: &mut R) -> Result<Hello>
    where
        R: AsyncRead + Unpin,
    {
        let hello = match read_receiver_message(recv).await? {
            ReceiverMessage::Hello(message) => message,
            other => {
                self.machine.transition(SenderState::Failed)?;
                bail!("expected hello from receiver, got {:?}", other);
            }
        };

        validate_hello(&hello, &self.session_id, TransferRole::Receiver)?;
        self.peer_identity = Some(hello.identity.clone());
        self.machine.transition(SenderState::PeerHelloReceived)?;
        Ok(hello)
    }

    pub(crate) async fn send_offer<W>(
        &mut self,
        send: &mut W,
        manifest: super::message::TransferManifest,
    ) -> Result<()>
    where
        W: AsyncWrite + Unpin,
    {
        self.machine.transition(SenderState::OfferSent)?;
        write_sender_message(
            send,
            &SenderMessage::Offer(Offer {
                session_id: self.session_id.clone(),
                manifest,
            }),
        )
        .await?;
        self.machine.transition(SenderState::WaitingForDecision)?;
        Ok(())
    }

    pub(crate) async fn await_decision<R>(&mut self, recv: &mut R) -> Result<SenderControlOutcome>
    where
        R: AsyncRead + Unpin,
    {
        let outcome = match read_receiver_message(recv).await? {
            ReceiverMessage::Accept(message) => {
                ensure_session_id(&message.session_id, &self.session_id)?;
                self.machine.transition(SenderState::Accepted)?;
                SenderControlOutcome::Accepted(SenderPeer {
                    session_id: message.session_id,
                    identity: self
                        .peer_identity
                        .clone()
                        .context("receiver identity missing after hello")?,
                })
            }
            ReceiverMessage::Decline(message) => {
                ensure_session_id(&message.session_id, &self.session_id)?;
                self.machine.transition(SenderState::Declined)?;
                SenderControlOutcome::Declined(message)
            }
            ReceiverMessage::Cancel(message) => {
                ensure_session_id(&message.session_id, &self.session_id)?;
                self.machine.transition(SenderState::Cancelled)?;
                SenderControlOutcome::Cancelled(message)
            }
            other => {
                self.machine.transition(SenderState::Failed)?;
                bail!("unexpected decision message from receiver: {:?}", other);
            }
        };

        Ok(outcome)
    }
}

fn validate_hello(
    message: &Hello,
    expected_session_id: &str,
    expected_role: TransferRole,
) -> Result<()> {
    if message.version != PROTOCOL_VERSION {
        bail!("unsupported protocol version {}", message.version);
    }

    if message.session_id != expected_session_id {
        bail!(
            "session id mismatch: expected {}, got {}",
            expected_session_id,
            message.session_id
        );
    }

    if message.identity.role != expected_role {
        bail!(
            "unexpected identity role {:?}, expected {:?}",
            message.identity.role,
            expected_role
        );
    }

    if message.identity.device_name.trim().is_empty() {
        bail!("device name must not be empty");
    }

    Ok(())
}

fn ensure_session_id(actual: &str, expected: &str) -> Result<()> {
    if actual == expected {
        Ok(())
    } else {
        bail!("session id mismatch: expected {expected}, got {actual}")
    }
}

#[cfg(test)]
mod tests {
    use super::{Sender, SenderMachine, SenderState};
    use crate::protocol::message::{
        Accept, DeviceType, Identity, PROTOCOL_VERSION, ReceiverMessage, SenderMessage,
        TransferManifest, TransferRole,
    };
    use crate::protocol::wire::{read_sender_message, write_receiver_message};
    use tokio::io::duplex;

    #[test]
    fn sender_machine_allows_happy_path() {
        let mut machine = SenderMachine::new();
        machine.transition(SenderState::HelloSent).unwrap();
        machine.transition(SenderState::PeerHelloReceived).unwrap();
        machine.transition(SenderState::OfferSent).unwrap();
        machine.transition(SenderState::WaitingForDecision).unwrap();
        machine.transition(SenderState::Accepted).unwrap();
    }

    #[tokio::test]
    async fn sender_handler_runs_handshake() -> anyhow::Result<()> {
        let (local, remote) = duplex(1024);
        let (mut local_read, mut local_write) = tokio::io::split(local);
        let (mut remote_read, mut remote_write) = tokio::io::split(remote);

        let mut handler = Sender::new(
            "session-1".to_owned(),
            Identity {
                role: TransferRole::Sender,
                device_name: "sender".to_owned(),
                device_type: DeviceType::Laptop,
            },
        );

        let receiver_task = tokio::spawn(async move {
            let hello = read_sender_message(&mut remote_read).await.unwrap();
            assert!(matches!(hello, SenderMessage::Hello(_)));

            write_receiver_message(
                &mut remote_write,
                &ReceiverMessage::Hello(crate::protocol::message::Hello {
                    version: PROTOCOL_VERSION,
                    session_id: "session-1".to_owned(),
                    identity: Identity {
                        role: TransferRole::Receiver,
                        device_name: "receiver".to_owned(),
                        device_type: DeviceType::Phone,
                    },
                }),
            )
            .await
            .unwrap();

            let offer = read_sender_message(&mut remote_read).await.unwrap();
            assert!(matches!(offer, SenderMessage::Offer(_)));

            write_receiver_message(
                &mut remote_write,
                &ReceiverMessage::Accept(Accept {
                    session_id: "session-1".to_owned(),
                }),
            )
            .await
            .unwrap();
        });

        let outcome = handler
            .run_control(
                &mut local_write,
                &mut local_read,
                TransferManifest {
                    files: vec![],
                    file_count: 0,
                    total_size: 0,
                },
            )
            .await;

        receiver_task.await.unwrap();
        assert!(outcome.is_ok());
        Ok(())
    }
}
