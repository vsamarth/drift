use std::path::PathBuf;

use iroh::SecretKey;

use super::runtime::{
    OfferResolution, ReceiverRuntime, registration_needs_refresh, should_advertise,
};
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

#[tokio::test]
async fn service_starts_with_unavailable_pairing_code() {
    let service = ReceiverService::start(test_config()).await.unwrap();
    assert_eq!(service.pairing_code(), PairingCodeState::Unavailable);
    assert_eq!(service.snapshot().lifecycle, ReceiverLifecycle::Ready);
    service.shutdown().await.unwrap();
}

#[tokio::test]
async fn respond_to_offer_fails_without_pending_offer() {
    let service = ReceiverService::start(test_config()).await.unwrap();
    let error = service
        .respond_to_offer(OfferDecision::Accept)
        .await
        .unwrap_err();
    assert!(error.to_string().contains("no pending offer"));
    service.shutdown().await.unwrap();
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
fn discoverability_requires_setup() {
    assert!(!should_advertise(true, false));
    assert!(!should_advertise(false, true));
    assert!(should_advertise(true, true));
}

#[tokio::test]
async fn stale_offer_updates_are_ignored() {
    let endpoint = iroh::Endpoint::builder()
        .secret_key(SecretKey::from_bytes(&rand::random()))
        .bind()
        .await
        .unwrap();
    let listener = tokio::spawn(async {});
    let mut runtime = ReceiverRuntime::new(test_config(), endpoint, listener);

    let (tx, _rx) = tokio::sync::oneshot::channel::<OfferResolution>();
    let watch_task = tokio::spawn(async {});
    assert!(runtime.handle_offer_prepared(7, tx, watch_task));
    assert!(!runtime.handle_offer_progress(8));
    assert!(!runtime.handle_offer_finished(8));
}

#[tokio::test]
async fn busy_runtime_rejects_second_offer() {
    let endpoint = iroh::Endpoint::builder()
        .secret_key(SecretKey::from_bytes(&rand::random()))
        .bind()
        .await
        .unwrap();
    let listener = tokio::spawn(async {});
    let mut runtime = ReceiverRuntime::new(test_config(), endpoint, listener);

    let (tx1, _rx1) = tokio::sync::oneshot::channel::<OfferResolution>();
    let (tx2, rx2) = tokio::sync::oneshot::channel::<OfferResolution>();
    let watch1 = tokio::spawn(async {});
    let watch2 = tokio::spawn(async {});
    assert!(runtime.handle_offer_prepared(1, tx1, watch1));
    assert!(!runtime.handle_offer_prepared(2, tx2, watch2));
    assert!(matches!(rx2.await.unwrap(), OfferResolution::Decline));
}
