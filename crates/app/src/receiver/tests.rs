use std::path::PathBuf;

use anyhow::Result;
use iroh::SecretKey;
use tokio::sync::{oneshot, watch};

use super::runtime::{
    OfferResolution, ReceiverRuntime, registration_needs_refresh, should_advertise,
};
use super::session::ReceiverRun;
use super::{
    OfferDecision, PairingCodeState, ReceiverLifecycle, ReceiverRegistration, ReceiverService,
};
use crate::types::{ConflictPolicy, ReceiverConfig};

fn test_config() -> ReceiverConfig {
    ReceiverConfig {
        device_name: "Test Receiver".to_owned(),
        device_type: "laptop".to_owned(),
        download_root: PathBuf::from("downloads"),
        conflict_policy: ConflictPolicy::Reject,
        secret_key: SecretKey::from_bytes(&rand::random()),
    }
}

async fn try_start_service() -> Result<Option<ReceiverService>> {
    match ReceiverService::start(test_config()).await {
        Ok(service) => Ok(Some(service)),
        Err(error) if bind_unavailable(&error) => Ok(None),
        Err(error) => Err(error),
    }
}

async fn try_bind_endpoint() -> Result<Option<iroh::Endpoint>> {
    match iroh::Endpoint::builder(iroh::endpoint::presets::N0)
        .secret_key(SecretKey::from_bytes(&rand::random()))
        .bind()
        .await
    {
        Ok(endpoint) => Ok(Some(endpoint)),
        Err(error) => {
            let error = anyhow::Error::from(error);
            if bind_unavailable(&error) {
                Ok(None)
            } else {
                Err(error)
            }
        }
    }
}

fn bind_unavailable(error: &anyhow::Error) -> bool {
    let chain = format!("{error:#}");
    chain.contains("Failed to bind sockets") || chain.contains("Operation not permitted")
}

#[tokio::test]
async fn service_starts_with_unavailable_pairing_code() -> Result<()> {
    let Some(service) = try_start_service().await? else {
        return Ok(());
    };
    assert_eq!(service.pairing_code(), PairingCodeState::Unavailable);
    assert_eq!(service.snapshot().lifecycle, ReceiverLifecycle::Ready);
    service.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn respond_to_offer_fails_without_pending_offer() -> Result<()> {
    let Some(service) = try_start_service().await? else {
        return Ok(());
    };
    let error = service
        .respond_to_offer(OfferDecision::Accept)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("no pending offer"));
    service.shutdown().await?;
    Ok(())
}

#[test]
fn registration_refreshes_when_expired() {
    let registration = ReceiverRegistration {
        code: "ABC123".to_owned(),
        expires_at: "2000-01-01T00:00:00Z".to_owned(),
    };
    assert!(registration_needs_refresh(&registration));
}

#[test]
fn registration_stays_valid_when_future_expiry_parses() {
    let registration = ReceiverRegistration {
        code: "ABC123".to_owned(),
        expires_at: "2999-01-01T00:00:00Z".to_owned(),
    };
    assert!(!registration_needs_refresh(&registration));
}

#[test]
fn discoverability_only_requires_opt_in() {
    assert!(should_advertise(true, false));
    assert!(!should_advertise(false, true));
    assert!(should_advertise(true, true));
}

#[tokio::test]
async fn stale_offer_updates_are_ignored() -> Result<()> {
    let Some(endpoint) = try_bind_endpoint().await? else {
        return Ok(());
    };
    let listener = tokio::spawn(async {});
    let mut runtime = ReceiverRuntime::new(test_config(), endpoint, listener);

    let (tx, _rx) = oneshot::channel::<OfferResolution>();
    let (cancel_tx, _cancel_rx) = watch::channel(false);
    let run = ReceiverRun {
        offer_id: 7,
        decision_tx: tx,
        cancel_tx,
    };
    assert!(runtime.handle_offer_prepared(run));
    assert!(!runtime.handle_offer_progress(8));
    assert!(!runtime.handle_offer_finished(8));
    Ok(())
}

#[tokio::test]
async fn busy_runtime_rejects_second_offer() -> Result<()> {
    let Some(endpoint) = try_bind_endpoint().await? else {
        return Ok(());
    };
    let listener = tokio::spawn(async {});
    let mut runtime = ReceiverRuntime::new(test_config(), endpoint, listener);

    let (tx1, _rx1) = oneshot::channel::<OfferResolution>();
    let (tx2, rx2) = oneshot::channel::<OfferResolution>();
    let (cancel_tx1, _cancel_rx1) = watch::channel(false);
    let (cancel_tx2, _cancel_rx2) = watch::channel(false);
    assert!(runtime.handle_offer_prepared(ReceiverRun {
        offer_id: 1,
        decision_tx: tx1,
        cancel_tx: cancel_tx1,
    }));
    assert!(!runtime.handle_offer_prepared(ReceiverRun {
        offer_id: 2,
        decision_tx: tx2,
        cancel_tx: cancel_tx2,
    }));
    assert!(matches!(rx2.await.unwrap(), OfferResolution::Decline));
    Ok(())
}
