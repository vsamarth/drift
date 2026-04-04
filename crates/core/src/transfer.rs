use anyhow::{Result, bail};

use crate::wire::{CancelPhase, Hello, TRANSFER_PROTOCOL_VERSION, TransferRole};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SenderState {
    Idle,
    Resolving,
    Connecting,
    Connected,
    Offering,
    WaitingForDecision,
    Sending,
    Completed,
    Declined,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReceiverState {
    Idle,
    Discoverable,
    Connecting,
    Connected,
    ReviewingOffer,
    AwaitingDecision,
    Approved,
    Receiving,
    Completed,
    Declined,
    Cancelled,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TransferCancellation {
    pub by: TransferRole,
    pub phase: CancelPhase,
    pub reason: String,
}

#[derive(Debug)]
pub struct SenderMachine {
    state: SenderState,
}

impl SenderMachine {
    pub fn new() -> Self {
        Self {
            state: SenderState::Idle,
        }
    }

    pub fn transition(&mut self, next: SenderState) -> Result<()> {
        use SenderState::*;

        let allowed = matches!(
            (self.state, next),
            (Idle, Resolving)
                | (Resolving, Connecting)
                | (Connecting, Connected)
                | (Connected, Offering)
                | (Offering, WaitingForDecision)
                | (WaitingForDecision, Sending)
                | (WaitingForDecision, Declined)
                | (WaitingForDecision, Cancelled)
                | (Sending, Cancelled)
                | (Sending, Completed)
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

#[derive(Debug)]
pub struct ReceiverMachine {
    state: ReceiverState,
}

impl ReceiverMachine {
    pub fn new() -> Self {
        Self {
            state: ReceiverState::Idle,
        }
    }

    pub fn transition(&mut self, next: ReceiverState) -> Result<()> {
        use ReceiverState::*;

        let allowed = matches!(
            (self.state, next),
            (Idle, Discoverable)
                | (Discoverable, Connecting)
                | (Connecting, Connected)
                | (Connected, ReviewingOffer)
                | (ReviewingOffer, AwaitingDecision)
                | (ReviewingOffer, Declined)
                | (AwaitingDecision, Approved)
                | (AwaitingDecision, Declined)
                | (AwaitingDecision, Cancelled)
                | (Approved, Receiving)
                | (Receiving, Cancelled)
                | (Receiving, Completed)
                | (_, Failed)
        );

        if !allowed {
            bail!(
                "invalid receiver transition: {:?} -> {:?}",
                self.state,
                next
            );
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

pub fn validate_hello(message: &Hello, expected_role: TransferRole) -> Result<()> {
    if message.version != TRANSFER_PROTOCOL_VERSION {
        bail!("unsupported transfer protocol version {}", message.version);
    }

    if message.role != expected_role {
        bail!(
            "unexpected transfer role {:?}, expected {:?}",
            message.role,
            expected_role
        );
    }

    if message.session_id.trim().is_empty() {
        bail!("transfer session id must not be empty");
    }

    if message.device_name.trim().is_empty() {
        bail!("transfer device name must not be empty");
    }

    Ok(())
}

pub fn ensure_session_id(actual: &str, expected: &str) -> Result<()> {
    if actual == expected {
        Ok(())
    } else {
        bail!("session id mismatch: expected {expected}, got {actual}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wire::DeviceType;

    #[test]
    fn sender_machine_allows_happy_path() {
        let mut machine = SenderMachine::new();
        machine.transition(SenderState::Resolving).unwrap();
        machine.transition(SenderState::Connecting).unwrap();
        machine.transition(SenderState::Connected).unwrap();
        machine.transition(SenderState::Offering).unwrap();
        machine.transition(SenderState::WaitingForDecision).unwrap();
        machine.transition(SenderState::Sending).unwrap();
        machine.transition(SenderState::Completed).unwrap();
    }

    #[test]
    fn receiver_machine_rejects_skipping_review() {
        let mut machine = ReceiverMachine::new();
        machine.transition(ReceiverState::Discoverable).unwrap();
        machine.transition(ReceiverState::Connecting).unwrap();
        machine.transition(ReceiverState::Connected).unwrap();
        assert!(machine.transition(ReceiverState::Receiving).is_err());
    }

    #[test]
    fn hello_validation_checks_version_and_role() {
        let hello = Hello {
            version: TRANSFER_PROTOCOL_VERSION,
            session_id: "abc123".to_owned(),
            role: TransferRole::Sender,
            device_name: "sam-mac".to_owned(),
            device_type: DeviceType::Laptop,
        };

        assert!(validate_hello(&hello, TransferRole::Sender).is_ok());
        assert!(validate_hello(&hello, TransferRole::Receiver).is_err());

        let wrong_version = Hello {
            version: TRANSFER_PROTOCOL_VERSION + 1,
            ..hello.clone()
        };
        assert!(validate_hello(&wrong_version, TransferRole::Sender).is_err());

        let empty_device_name = Hello {
            device_name: "   ".to_owned(),
            ..hello
        };
        assert!(validate_hello(&empty_device_name, TransferRole::Sender).is_err());
    }
}
