use std::sync::Mutex;

use drift_core::rendezvous::{resolve_server_url, RegisterPeerResponse, RendezvousClient};
use drift_core::session::bind_endpoint;
use drift_core::wire::make_ticket_now;
use iroh::Endpoint;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use super::RUNTIME;

const LOCAL_RENDEZVOUS_URL: &str = "http://127.0.0.1:8787";

static IDLE_RECEIVER: Mutex<Option<IdleReceiver>> = Mutex::new(None);

struct IdleReceiver {
    endpoint: Endpoint,
    server_url: String,
    registration: RegisterPeerResponse,
}

#[derive(Debug, Clone)]
pub struct IdleReceiverRegistration {
    pub code: String,
    pub expires_at: String,
}

pub fn register_idle_receiver(
    server_url: Option<String>,
) -> Result<IdleReceiverRegistration, String> {
    RUNTIME.block_on(async move {
        let resolved_url = resolve_server_url(server_url.as_deref().or(Some(LOCAL_RENDEZVOUS_URL)));
        log(&format!("registering idle receiver against {resolved_url}"));
        replace_idle_receiver(register_new_idle_receiver(resolved_url).await).await
    })
}

pub fn ensure_idle_receiver(
    server_url: Option<String>,
) -> Result<IdleReceiverRegistration, String> {
    RUNTIME.block_on(async move {
        let resolved_url = resolve_server_url(server_url.as_deref().or(Some(LOCAL_RENDEZVOUS_URL)));
        log(&format!("ensuring idle receiver against {resolved_url}"));
        let existing = take_idle_receiver()?;

        let next = match existing {
            Some(receiver) => {
                if receiver.server_url != resolved_url {
                    receiver.endpoint.close().await;
                    register_new_idle_receiver(resolved_url).await?
                } else if is_expired(&receiver.registration)? {
                    receiver.endpoint.close().await;
                    register_new_idle_receiver(resolved_url).await?
                } else {
                    match RendezvousClient::new(receiver.server_url.clone())
                        .pair_status(&receiver.registration.code)
                        .await
                        .map_err(|err| err.to_string())?
                    {
                        Some(_) => {
                            log(&format!(
                                "reusing idle receiver code {} on {}",
                                receiver.registration.code, receiver.server_url
                            ));
                            receiver
                        }
                        None => {
                            receiver.endpoint.close().await;
                            register_new_idle_receiver(resolved_url).await?
                        }
                    }
                }
            }
            None => register_new_idle_receiver(resolved_url).await?,
        };

        replace_idle_receiver(Ok(next)).await
    })
}

pub fn current_idle_receiver_registration() -> Option<IdleReceiverRegistration> {
    IDLE_RECEIVER.lock().ok().and_then(|state| {
        state.as_ref().map(|receiver| IdleReceiverRegistration {
            code: receiver.registration.code.clone(),
            expires_at: receiver.registration.expires_at.clone(),
        })
    })
}

async fn register_new_idle_receiver(server_url: String) -> Result<IdleReceiver, String> {
    let endpoint = bind_endpoint().await.map_err(|err| err.to_string())?;
    let ticket = make_ticket_now(&endpoint).map_err(|err| err.to_string())?;
    let registration = RendezvousClient::new(server_url.clone())
        .register_peer(ticket)
        .await
        .map_err(|err| err.to_string())?;
    log(&format!(
        "registered idle receiver code {} on {}",
        registration.code, server_url
    ));

    Ok(IdleReceiver {
        endpoint,
        server_url,
        registration,
    })
}

fn take_idle_receiver() -> Result<Option<IdleReceiver>, String> {
    let mut state = IDLE_RECEIVER.lock().map_err(|err| err.to_string())?;
    Ok(state.take())
}

async fn replace_idle_receiver(
    receiver: Result<IdleReceiver, String>,
) -> Result<IdleReceiverRegistration, String> {
    let receiver = receiver?;
    let response = IdleReceiverRegistration {
        code: receiver.registration.code.clone(),
        expires_at: receiver.registration.expires_at.clone(),
    };

    let mut state = IDLE_RECEIVER.lock().map_err(|err| err.to_string())?;
    *state = Some(receiver);
    Ok(response)
}

fn is_expired(registration: &RegisterPeerResponse) -> Result<bool, String> {
    let expires_at =
        OffsetDateTime::parse(&registration.expires_at, &Rfc3339).map_err(|err| err.to_string())?;
    Ok(OffsetDateTime::now_utc() >= expires_at)
}

fn log(message: &str) {
    eprintln!("[drift_bridge::receiver] {message}");
}
