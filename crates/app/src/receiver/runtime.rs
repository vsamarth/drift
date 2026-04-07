use anyhow::{Context, Result};
use drift_core::lan::LanReceiveAdvertisement;
use drift_core::rendezvous::{RendezvousClient, resolve_server_url};
use drift_core::util::make_ticket;
use iroh::{Endpoint, EndpointId};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio::sync::{broadcast, watch};
use tokio::task::JoinHandle;
use tracing::warn;

use crate::types::{PairingCodeState, ReceiverConfig, ReceiverRegistration};

use super::{OfferDecision, ReceiverEvent};
use super::session::ReceiverRun;

pub(super) struct ReceiverRuntime {
    config: ReceiverConfig,
    endpoint: Endpoint,
    listener_task: JoinHandle<()>,
    server_url: Option<String>,
    registration: Option<ReceiverRegistration>,
    pub(super) discoverable_requested: bool,
    advertising: Option<LanReceiveAdvertisement>,
    offer_state: OfferState,
}

#[derive(Debug)]
pub(super) enum OfferResolution {
    Accept,
    Decline,
    Cancel,
}

pub(super) enum OfferState {
    Idle,
    Pending(PendingOfferState),
    Receiving {
        offer_id: u64,
        cancel_tx: watch::Sender<bool>,
    },
}

pub(super) struct PendingOfferState {
    run: ReceiverRun,
}

impl ReceiverRuntime {
    pub(super) fn new(
        config: ReceiverConfig,
        endpoint: Endpoint,
        listener_task: JoinHandle<()>,
    ) -> Self {
        Self {
            config,
            endpoint,
            listener_task,
            server_url: None,
            registration: None,
            discoverable_requested: false,
            advertising: None,
            offer_state: OfferState::Idle,
        }
    }

    pub(super) fn endpoint_id(&self) -> EndpointId {
        self.endpoint.addr().id
    }

    pub(super) fn has_registration(&self) -> bool {
        self.registration.is_some()
    }

    pub(super) fn has_pending_offer(&self) -> bool {
        matches!(self.offer_state, OfferState::Pending(_))
    }

    pub(super) fn is_available_for_new_offer(&self) -> bool {
        matches!(self.offer_state, OfferState::Idle)
    }

    pub(super) fn advertising_active(&self) -> bool {
        self.advertising.is_some()
    }

    pub(super) fn clear_advertising(&mut self) {
        self.advertising.take();
    }

    pub(super) async fn close_endpoint(&self) {
        self.endpoint.close().await;
    }

    pub(super) fn abort_listener(&self) {
        self.listener_task.abort();
    }

    pub(super) async fn handle_setup(
        &mut self,
        server_url: Option<String>,
        pairing_tx: &watch::Sender<PairingCodeState>,
        event_tx: &broadcast::Sender<ReceiverEvent>,
    ) -> Result<ReceiverRegistration> {
        self.server_url = Some(resolve_server_url(server_url.as_deref()));
        let was_active = self.advertising_active();
        let result = self.ensure_registered_with_current_server().await;
        match &result {
            Ok(registration) => {
                let _ = pairing_tx.send(PairingCodeState::Active(registration.clone()));
                let _ = event_tx.send(ReceiverEvent::SetupCompleted(registration.clone()));
            }
            Err(_) => {
                self.reconcile_advertising().await;
                let _ = pairing_tx.send(PairingCodeState::Unavailable);
            }
        }
        self.publish_discoverability_change_if_needed(was_active, event_tx);
        result
    }

    pub(super) async fn handle_ensure_registered(
        &mut self,
        server_url: Option<String>,
        pairing_tx: &watch::Sender<PairingCodeState>,
        event_tx: &broadcast::Sender<ReceiverEvent>,
    ) -> Result<ReceiverRegistration> {
        let was_active = self.advertising_active();
        let result = self.ensure_registered(server_url).await;
        match &result {
            Ok(registration) => {
                let _ = pairing_tx.send(PairingCodeState::Active(registration.clone()));
                let _ = event_tx.send(ReceiverEvent::RegistrationUpdated(registration.clone()));
            }
            Err(_) => {
                self.reconcile_advertising().await;
                let _ = pairing_tx.send(PairingCodeState::Unavailable);
            }
        }
        self.publish_discoverability_change_if_needed(was_active, event_tx);
        result
    }

    pub(super) async fn ensure_registered(
        &mut self,
        server_url: Option<String>,
    ) -> Result<ReceiverRegistration> {
        self.server_url = Some(resolve_server_url(server_url.as_deref()));
        self.ensure_registered_with_current_server().await
    }

    async fn ensure_registered_with_current_server(&mut self) -> Result<ReceiverRegistration> {
        let resolved_url = self
            .server_url
            .clone()
            .context("receiver setup has not been completed")?;
        let ticket = make_ticket(&self.endpoint).await?;
        let registration = RendezvousClient::new(resolved_url)
            .register_peer(ticket)
            .await?;
        let registration = ReceiverRegistration {
            code: registration.code,
            expires_at: registration.expires_at,
        };
        self.registration = Some(registration.clone());
        self.reconcile_advertising().await;
        Ok(registration)
    }

    pub(super) async fn refresh_registration_after_offer(
        &mut self,
        pairing_tx: &watch::Sender<PairingCodeState>,
        event_tx: &broadcast::Sender<ReceiverEvent>,
    ) -> Result<Option<ReceiverRegistration>> {
        let Some(_) = self.server_url else {
            return Ok(None);
        };
        let was_active = self.advertising_active();
        let registration = self.ensure_registered_with_current_server().await?;
        let _ = pairing_tx.send(PairingCodeState::Active(registration.clone()));
        let _ = event_tx.send(ReceiverEvent::RegistrationUpdated(registration.clone()));
        self.publish_discoverability_change_if_needed(was_active, event_tx);
        Ok(Some(registration))
    }

    pub(super) async fn maintain_registration(
        &mut self,
        pairing_tx: &watch::Sender<PairingCodeState>,
        event_tx: &broadcast::Sender<ReceiverEvent>,
    ) -> Result<()> {
        let Some(server_url) = self.server_url.clone() else {
            return Ok(());
        };

        let Some(existing) = self.registration.clone() else {
            let registration = self.ensure_registered(Some(server_url)).await?;
            let _ = pairing_tx.send(PairingCodeState::Active(registration.clone()));
            let _ = event_tx.send(ReceiverEvent::RegistrationUpdated(registration));
            return Ok(());
        };

        if registration_needs_refresh(&existing) {
            let was_active = self.advertising_active();
            let registration = self.ensure_registered(Some(server_url)).await?;
            let _ = pairing_tx.send(PairingCodeState::Active(registration.clone()));
            let _ = event_tx.send(ReceiverEvent::RegistrationUpdated(registration));
            self.publish_discoverability_change_if_needed(was_active, event_tx);
            return Ok(());
        }

        match RendezvousClient::new(server_url)
            .pair_status(&existing.code)
            .await?
        {
            Some(_) => Ok(()),
            None => {
                let was_active = self.advertising_active();
                let registration = self.ensure_registered_with_current_server().await?;
                let _ = pairing_tx.send(PairingCodeState::Active(registration.clone()));
                let _ = event_tx.send(ReceiverEvent::RegistrationUpdated(registration));
                self.publish_discoverability_change_if_needed(was_active, event_tx);
                Ok(())
            }
        }
    }

    pub(super) async fn set_discoverable(&mut self, enabled: bool) -> Result<()> {
        self.discoverable_requested = enabled;
        self.reconcile_advertising().await;
        Ok(())
    }

    pub(super) fn respond_to_offer(&mut self, decision: OfferDecision) -> Result<()> {
        let OfferState::Pending(pending_offer) =
            std::mem::replace(&mut self.offer_state, OfferState::Idle)
        else {
            return Err(anyhow::anyhow!("no pending offer"));
        };
        let run = pending_offer.run;

        let offer_id = run.offer_id;
        let resolution = if matches!(decision, OfferDecision::Accept) {
            self.offer_state = OfferState::Receiving {
                offer_id,
                cancel_tx: run.cancel_tx.clone(),
            };
            OfferResolution::Accept
        } else {
            OfferResolution::Decline
        };
        run.decision_tx
            .send(resolution)
            .map_err(|_| anyhow::anyhow!("offer is no longer active"))?;
        Ok(())
    }

    pub(super) fn handle_offer_prepared(&mut self, run: ReceiverRun) -> bool {
        if !matches!(self.offer_state, OfferState::Idle) {
    
            let _ = run.decision_tx.send(OfferResolution::Decline);
            return false;
        }

        self.offer_state = OfferState::Pending(PendingOfferState { run });
        true
    }

    pub(super) fn handle_offer_progress(&mut self, offer_id: u64) -> bool {
        match &mut self.offer_state {
            OfferState::Pending(pending) if pending.run.offer_id == offer_id => {

                self.offer_state = OfferState::Receiving {
                    offer_id,
                    cancel_tx: pending.run.cancel_tx.clone(),
                };
                true
            }
            OfferState::Receiving {
                offer_id: active_offer_id,
                ..
            } if *active_offer_id == offer_id => true,
            _ => false,
        }
    }

    pub(super) fn handle_offer_finished(&mut self, offer_id: u64) -> bool {
        if offer_id == 0 {
            self.offer_state = OfferState::Idle;
            return true;
        }

        match &mut self.offer_state {
            OfferState::Pending(pending) if pending.run.offer_id == offer_id => {

                self.offer_state = OfferState::Idle;
                true
            }
            OfferState::Receiving {
                offer_id: active_offer_id,
                ..
            } if *active_offer_id == offer_id => {
                self.offer_state = OfferState::Idle;
                true
            }
            _ => false,
        }
    }

    pub(super) fn cancel_active_transfer(&mut self) -> Result<()> {
        match &self.offer_state {
            OfferState::Receiving { cancel_tx, .. } => {
                let _ = cancel_tx.send(true);
                Ok(())
            }
            _ => Err(anyhow::anyhow!("no active transfer")),
        }
    }

    fn cancel_pending_offer(&mut self, offer_id: u64) -> bool {
        match std::mem::replace(&mut self.offer_state, OfferState::Idle) {
            OfferState::Pending(pending) if pending.run.offer_id == offer_id => {

                let _ = pending.run.decision_tx.send(OfferResolution::Cancel);
                true
            }
            other => {
                self.offer_state = other;
                false
            }
        }
    }

    async fn reconcile_advertising(&mut self) {
        if !should_advertise(self.discoverable_requested, self.registration.is_some()) {
            self.clear_advertising();
            return;
        }

        self.clear_advertising();
        let ticket = match make_ticket(&self.endpoint).await {
            Ok(ticket) => ticket,
            Err(error) => {
                warn!(
                    device = %self.config.device_name,
                    error = %error,
                    error_chain = %format!("{error:#}"),
                    "receiver.lan_advertising_unavailable"
                );
                return;
            }
        };

        match LanReceiveAdvertisement::start(&ticket, &self.config.device_name) {
            Ok(Some(advertising)) => {
                self.advertising = Some(advertising);
            }
            Ok(None) => {
                warn!(
                    device = %self.config.device_name,
                    "receiver.lan_advertising_unavailable_no_ipv4_route"
                );
            }
            Err(error) => {
                warn!(
                    device = %self.config.device_name,
                    error = %error,
                    error_chain = %format!("{error:#}"),
                    "receiver.lan_advertising_unavailable"
                );
            }
        }
    }

    pub(super) fn publish_discoverability_change_if_needed(
        &self,
        was_active: bool,
        event_tx: &broadcast::Sender<ReceiverEvent>,
    ) {
        let is_active = self.advertising_active();
        if was_active != is_active || !self.discoverable_requested {
            let _ = event_tx.send(ReceiverEvent::DiscoverabilityChanged {
                requested: self.discoverable_requested,
                active: is_active,
            });
        }
    }
}

pub(super) fn registration_needs_refresh(registration: &ReceiverRegistration) -> bool {
    let Ok(expires_at) = OffsetDateTime::parse(&registration.expires_at, &Rfc3339) else {
        return true;
    };
    OffsetDateTime::now_utc() >= expires_at
}

pub(super) fn should_advertise(discoverable_requested: bool, _has_registration: bool) -> bool {
    discoverable_requested
}
