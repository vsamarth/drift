#![allow(dead_code)]

mod actor;
mod runtime;

#[cfg(test)]
mod tests;

use std::time::Duration;

use iroh::{Endpoint, RelayMode, endpoint::presets};
use tokio::sync::{broadcast, mpsc, oneshot, watch};

use crate::error::{actor_reply_dropped, actor_stopped, invalid_device_type};
use crate::types::{
    NearbyReceiver, PairingCodeState, ReceiverConfig, ReceiverOfferEvent, ReceiverRegistration,
};
use drift_core::error::{DriftError, Result};
use drift_core::wire::ALPN;

use self::actor::{ReceiverCommand, run_receiver_actor, spawn_listener_task};
use self::runtime::ReceiverRuntime;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReceiverLifecycle {
    Starting,
    Ready,
    Stopped,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiverSnapshot {
    pub lifecycle: ReceiverLifecycle,
    pub discoverable_requested: bool,
    pub advertising_active: bool,
    pub has_registration: bool,
    pub has_pending_offer: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OfferDecision {
    Accept,
    Decline,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiverEvent {
    RegistrationUpdated(ReceiverRegistration),
    SetupCompleted(ReceiverRegistration),
    DiscoverabilityChanged { requested: bool, active: bool },
    OfferUpdated(ReceiverOfferEvent),
    Shutdown,
}

#[derive(Debug)]
pub struct ReceiverService {
    cmd_tx: mpsc::Sender<ReceiverCommand>,
    state_rx: watch::Receiver<ReceiverSnapshot>,
    pairing_rx: watch::Receiver<PairingCodeState>,
    event_tx: broadcast::Sender<ReceiverEvent>,
}

impl ReceiverService {
    pub async fn start(config: ReceiverConfig) -> Result<Self> {
        let endpoint = Endpoint::builder(presets::N0)
            .alpns(vec![ALPN.to_vec()])
            .relay_mode(RelayMode::Default)
            .secret_key(config.secret_key.clone())
            .bind()
            .await
            .map_err(|error| DriftError::connection(format!("binding receiver v2 endpoint: {error}")))?;
        let (cmd_tx, cmd_rx) = mpsc::channel(16);
        let (state_tx, state_rx) = watch::channel(ReceiverSnapshot {
            lifecycle: ReceiverLifecycle::Ready,
            discoverable_requested: false,
            advertising_active: false,
            has_registration: false,
            has_pending_offer: false,
        });
        let (pairing_tx, pairing_rx) = watch::channel(PairingCodeState::Unavailable);
        let (event_tx, _) = broadcast::channel(32);
        let endpoint_for_listener = endpoint.clone();
        let cmd_tx_for_listener = cmd_tx.clone();
        let listener = spawn_listener_task(
            endpoint_for_listener,
            cmd_tx_for_listener,
            config.download_root.clone(),
            config.device_name.clone(),
            config.device_type.clone(),
            config.conflict_policy,
        )?;

        let runtime = ReceiverRuntime::new(config, endpoint, listener);

        tokio::spawn(run_receiver_actor(
            runtime,
            cmd_rx,
            state_tx,
            pairing_tx,
            event_tx.clone(),
        ));

        Ok(Self {
            cmd_tx,
            state_rx,
            pairing_rx,
            event_tx,
        })
    }

    pub fn snapshot(&self) -> ReceiverSnapshot {
        self.state_rx.borrow().clone()
    }

    pub fn subscribe_state(&self) -> watch::Receiver<ReceiverSnapshot> {
        self.state_rx.clone()
    }

    pub fn pairing_code(&self) -> PairingCodeState {
        self.pairing_rx.borrow().clone()
    }

    pub fn subscribe_pairing_code(&self) -> watch::Receiver<PairingCodeState> {
        self.pairing_rx.clone()
    }

    pub fn subscribe_events(&self) -> broadcast::Receiver<ReceiverEvent> {
        self.event_tx.subscribe()
    }

    pub async fn setup(&self, server_url: Option<String>) -> Result<ReceiverRegistration> {
        self.call_registration_command(|reply| ReceiverCommand::Setup { server_url, reply })
            .await
    }

    pub async fn ensure_registered(
        &self,
        server_url: Option<String>,
    ) -> Result<ReceiverRegistration> {
        self.call_registration_command(|reply| ReceiverCommand::EnsureRegistered {
            server_url,
            reply,
        })
        .await
    }

    pub async fn set_discoverable(&self, enabled: bool) -> Result<()> {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.cmd_tx
            .send(ReceiverCommand::SetDiscoverable {
                enabled,
                reply: reply_tx,
            })
            .await
            .map_err(|_| actor_stopped("set_discoverable"))?;
        reply_rx
            .await
            .map_err(|_| actor_reply_dropped("set_discoverable"))?
    }

    pub async fn respond_to_offer(&self, decision: OfferDecision) -> Result<()> {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.cmd_tx
            .send(ReceiverCommand::RespondToOffer {
                decision,
                reply: reply_tx,
            })
            .await
            .map_err(|_| actor_stopped("respond_to_offer"))?;
        reply_rx
            .await
            .map_err(|_| actor_reply_dropped("respond_to_offer"))?
    }

    pub async fn cancel_transfer(&self) -> Result<()> {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.cmd_tx
            .send(ReceiverCommand::CancelTransfer { reply: reply_tx })
            .await
            .map_err(|_| actor_stopped("cancel_transfer"))?;
        reply_rx
            .await
            .map_err(|_| actor_reply_dropped("cancel_transfer"))?
    }

    pub async fn scan_nearby(&self, timeout_secs: u64) -> Result<Vec<NearbyReceiver>> {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.cmd_tx
            .send(ReceiverCommand::ScanNearby {
                timeout: Duration::from_secs(timeout_secs.max(1)),
                reply: reply_tx,
            })
            .await
            .map_err(|_| actor_stopped("scan_nearby"))?;
        reply_rx
            .await
            .map_err(|_| actor_reply_dropped("scan_nearby"))?
    }

    pub async fn shutdown(&self) -> Result<()> {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.cmd_tx
            .send(ReceiverCommand::Shutdown { reply: reply_tx })
            .await
            .map_err(|_| actor_stopped("shutdown"))?;
        reply_rx
            .await
            .map_err(|_| actor_reply_dropped("shutdown"))?
    }

    async fn call_registration_command(
        &self,
        command: impl FnOnce(oneshot::Sender<Result<ReceiverRegistration>>) -> ReceiverCommand,
    ) -> Result<ReceiverRegistration> {
        let (reply_tx, reply_rx) = oneshot::channel();
        self.cmd_tx
            .send(command(reply_tx))
            .await
            .map_err(|_| actor_stopped("registration command"))?;
        reply_rx
            .await
            .map_err(|_| actor_reply_dropped("registration"))?
    }
}

pub(super) fn parse_device_type(value: &str) -> Result<drift_core::wire::DeviceType> {
    match value.trim().to_ascii_lowercase().as_str() {
        "phone" => Ok(drift_core::wire::DeviceType::Phone),
        "laptop" => Ok(drift_core::wire::DeviceType::Laptop),
        other => Err(invalid_device_type(other)),
    }
}
