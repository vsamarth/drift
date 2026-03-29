use std::collections::{HashMap, VecDeque};
use std::net::{IpAddr, SocketAddr};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use axum::Json;
use axum::Router;
use axum::extract::{ConnectInfo, Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use drift_core::discovery::{DiscoveryError, DiscoverySession, DiscoveryState};
use drift_core::rendezvous::{
    CODE_ALPHABET, CODE_LENGTH, ClaimPeerResponse, PairStatus, PairStatusResponse,
    RegisterPeerRequest, RegisterPeerResponse, validate_code,
};
use rand::Rng;
use serde::Serialize;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio::net::TcpListener;
use tokio::time::sleep;
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

const CREATE_LIMIT_PER_MINUTE: usize = 10;
const ACCESS_LIMIT_PER_MINUTE: usize = 60;
const DISCOVERY_TTL_SECONDS: i64 = 300;
const CLEANUP_INTERVAL_SECONDS: u64 = 30;
const MAX_TICKET_LENGTH: usize = 4096;

type SharedState = Arc<AppState>;

#[derive(Debug)]
pub struct AppState {
    pairs: Mutex<HashMap<String, DiscoverySession>>,
    create_limiter: Mutex<RateLimiter>,
    access_limiter: Mutex<RateLimiter>,
}

impl AppState {
    fn new() -> Self {
        Self {
            pairs: Mutex::new(HashMap::new()),
            create_limiter: Mutex::new(RateLimiter::default()),
            access_limiter: Mutex::new(RateLimiter::default()),
        }
    }
}

#[derive(Debug, Default)]
struct RateLimiter {
    entries: HashMap<IpAddr, VecDeque<Instant>>,
}

impl RateLimiter {
    fn check(&mut self, ip: IpAddr, limit: usize) -> Result<(), ApiError> {
        let now = Instant::now();
        let window = self.entries.entry(ip).or_default();
        while let Some(front) = window.front() {
            if now.duration_since(*front) >= Duration::from_secs(60) {
                window.pop_front();
            } else {
                break;
            }
        }

        if window.len() >= limit {
            return Err(ApiError::new(
                StatusCode::TOO_MANY_REQUESTS,
                "rate limit exceeded",
            ));
        }

        window.push_back(now);
        Ok(())
    }
}

#[derive(Debug)]
struct ApiError {
    status: StatusCode,
    message: String,
}

#[derive(Debug, Serialize)]
struct ErrorBody {
    error: String,
}

impl ApiError {
    fn new(status: StatusCode, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let body = Json(ErrorBody {
            error: self.message,
        });
        (self.status, body).into_response()
    }
}

pub fn app(state: SharedState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/v1/pairs", post(register_peer))
        .route("/v1/pairs/{code}/status", get(get_pair_status))
        .route("/v1/pairs/{code}/claim", post(claim_peer))
        .with_state(state)
}

pub async fn serve(listen_addr: SocketAddr) -> Result<()> {
    init_logging();
    let state = Arc::new(AppState::new());
    tokio::spawn(cleanup_task(state.clone()));

    let listener = TcpListener::bind(listen_addr)
        .await
        .with_context(|| format!("binding rendezvous server on {listen_addr}"))?;

    info!(%listen_addr, "rendezvous server listening");

    axum::serve(
        listener,
        app(state).into_make_service_with_connect_info::<SocketAddr>(),
    )
    .await
    .context("running rendezvous server")
}

async fn healthz() -> &'static str {
    "ok"
}

async fn register_peer(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<RegisterPeerRequest>,
) -> Result<(StatusCode, Json<RegisterPeerResponse>), ApiError> {
    info!(
        client_ip = %addr.ip(),
        ticket_len = request.ticket.len(),
        "register request received"
    );
    state
        .create_limiter
        .lock()
        .map_err(lock_error)?
        .check(addr.ip(), CREATE_LIMIT_PER_MINUTE)?;

    validate_discovery_request(&request)?;

    let now = OffsetDateTime::now_utc();
    let expires_at = now + time::Duration::seconds(DISCOVERY_TTL_SECONDS);
    let session = DiscoverySession::new(request.ticket, now, expires_at)
        .map_err(|err| ApiError::new(StatusCode::BAD_REQUEST, err.to_string()))?;

    let mut pairs = state.pairs.lock().map_err(lock_error)?;
    purge_discovery_locked(&mut pairs, now);
    let code = unique_code(&pairs);
    pairs.insert(code.clone(), session);
    let pair_count = pairs.len();
    let expires_at_formatted = format_timestamp(expires_at)?;

    info!(
        client_ip = %addr.ip(),
        %code,
        expires_at = %expires_at_formatted,
        pair_count,
        "peer registered"
    );

    Ok((
        StatusCode::CREATED,
        Json(RegisterPeerResponse {
            code,
            expires_at: expires_at_formatted,
        }),
    ))
}

async fn claim_peer(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(code): Path<String>,
) -> Result<Json<ClaimPeerResponse>, ApiError> {
    info!(client_ip = %addr.ip(), %code, "claim request received");
    rate_limit_access(&state, addr.ip())?;
    validate_code_api(&code)?;

    let now = OffsetDateTime::now_utc();
    let mut pairs = state.pairs.lock().map_err(lock_error)?;
    purge_discovery_locked(&mut pairs, now);
    let mut session = pairs
        .remove(&code)
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "peer not found"))?;

    match session.claim(now) {
        Ok(ticket) => {
            info!(client_ip = %addr.ip(), %code, "peer claimed");
            Ok(Json(ClaimPeerResponse { ticket }))
        }
        Err(DiscoveryError::Claimed) => {
            warn!(client_ip = %addr.ip(), %code, "claim rejected because peer was already claimed");
            Err(ApiError::new(
                StatusCode::CONFLICT,
                "peer has already been claimed",
            ))
        }
        Err(DiscoveryError::Expired) => {
            warn!(client_ip = %addr.ip(), %code, "claim rejected because peer expired");
            Err(ApiError::new(StatusCode::NOT_FOUND, "peer expired"))
        }
    }
}

async fn get_pair_status(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(code): Path<String>,
) -> Result<Json<PairStatusResponse>, ApiError> {
    info!(client_ip = %addr.ip(), %code, "status request received");
    rate_limit_access(&state, addr.ip())?;
    validate_code_api(&code)?;

    let now = OffsetDateTime::now_utc();
    let mut pairs = state.pairs.lock().map_err(lock_error)?;
    purge_discovery_locked(&mut pairs, now);
    let session = pairs
        .get_mut(&code)
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "peer not found"))?;

    if session.state(now) != DiscoveryState::Open {
        warn!(client_ip = %addr.ip(), %code, "status lookup found non-open peer");
        return Err(ApiError::new(StatusCode::NOT_FOUND, "peer not found"));
    }

    info!(client_ip = %addr.ip(), %code, status = "open", "status request resolved");
    Ok(Json(PairStatusResponse {
        status: PairStatus::Open,
    }))
}

fn rate_limit_access(state: &SharedState, ip: IpAddr) -> Result<(), ApiError> {
    state
        .access_limiter
        .lock()
        .map_err(lock_error)?
        .check(ip, ACCESS_LIMIT_PER_MINUTE)
}

fn validate_discovery_request(request: &RegisterPeerRequest) -> Result<(), ApiError> {
    if request.ticket.trim().is_empty() {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "ticket must not be empty",
        ));
    }

    if request.ticket.len() > MAX_TICKET_LENGTH {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "ticket is too large",
        ));
    }

    Ok(())
}

fn validate_code_api(code: &str) -> Result<(), ApiError> {
    validate_code(code).map_err(|err| ApiError::new(StatusCode::BAD_REQUEST, err.to_string()))
}

fn unique_code<T>(entries: &HashMap<String, T>) -> String {
    let mut rng = rand::thread_rng();
    let alphabet = CODE_ALPHABET.as_bytes();
    loop {
        let code: String = (0..CODE_LENGTH)
            .map(|_| {
                let idx = rng.gen_range(0..alphabet.len());
                alphabet[idx] as char
            })
            .collect();
        if !entries.contains_key(&code) {
            return code;
        }
    }
}

fn purge_discovery_locked(pairs: &mut HashMap<String, DiscoverySession>, now: OffsetDateTime) {
    pairs.retain(|_, session| !session.is_removable(now));
}

fn lock_error<T>(_: T) -> ApiError {
    ApiError::new(
        StatusCode::INTERNAL_SERVER_ERROR,
        "server state is unavailable",
    )
}

fn format_timestamp(timestamp: OffsetDateTime) -> Result<String, ApiError> {
    timestamp
        .format(&Rfc3339)
        .map_err(|err| ApiError::new(StatusCode::INTERNAL_SERVER_ERROR, err.to_string()))
}

async fn cleanup_task(state: SharedState) {
    loop {
        sleep(Duration::from_secs(CLEANUP_INTERVAL_SECONDS)).await;
        let now = OffsetDateTime::now_utc();
        if let Ok(mut pairs) = state.pairs.lock() {
            let before = pairs.len();
            purge_discovery_locked(&mut pairs, now);
            let after = pairs.len();
            if after != before {
                info!(
                    removed = before - after,
                    remaining = after,
                    "expired peers cleaned up"
                );
            }
        }
    }
}

fn init_logging() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("drift_server=info")),
        )
        .with_target(true)
        .compact()
        .try_init();
}

#[cfg(test)]
mod tests {
    use std::str::from_utf8;

    use axum::body::{Body, to_bytes};
    use axum::http::{Method, Request, header};
    use tower::ServiceExt;

    use super::*;

    fn test_app() -> Router {
        app(Arc::new(AppState::new()))
    }

    fn request(method: Method, uri: &str, body: Body) -> Request<Body> {
        let mut builder = Request::builder().method(method.clone()).uri(uri);
        if method == Method::POST {
            builder = builder.header(header::CONTENT_TYPE, "application/json");
        }
        let mut request = builder.body(body).expect("request");
        request
            .extensions_mut()
            .insert(ConnectInfo(SocketAddr::from(([127, 0, 0, 1], 4000))));
        request
    }

    async fn read_json<T: serde::de::DeserializeOwned>(response: Response) -> T {
        let bytes = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body bytes");
        serde_json::from_slice(&bytes).expect("json body")
    }

    #[tokio::test]
    async fn register_and_claim_pair_flow_works_once() {
        let app = test_app();
        let body = serde_json::to_vec(&RegisterPeerRequest {
            ticket: "ticket".to_owned(),
        })
        .expect("register body");

        let response = app
            .clone()
            .oneshot(request(Method::POST, "/v1/pairs", Body::from(body)))
            .await
            .expect("register response");
        assert_eq!(response.status(), StatusCode::CREATED);
        let created: RegisterPeerResponse = read_json(response).await;

        let claimed = app
            .clone()
            .oneshot(request(
                Method::POST,
                &format!("/v1/pairs/{}/claim", created.code),
                Body::empty(),
            ))
            .await
            .expect("claim response");
        assert_eq!(claimed.status(), StatusCode::OK);
        let claimed: ClaimPeerResponse = read_json(claimed).await;
        assert_eq!(claimed.ticket, "ticket");

        let second_claim = app
            .oneshot(request(
                Method::POST,
                &format!("/v1/pairs/{}/claim", created.code),
                Body::empty(),
            ))
            .await
            .expect("second claim response");
        assert_eq!(second_claim.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn pair_status_is_open_until_claimed() {
        let app = test_app();
        let body = serde_json::to_vec(&RegisterPeerRequest {
            ticket: "ticket".to_owned(),
        })
        .expect("register body");

        let response = app
            .clone()
            .oneshot(request(Method::POST, "/v1/pairs", Body::from(body)))
            .await
            .expect("register response");
        let created: RegisterPeerResponse = read_json(response).await;

        let status = app
            .clone()
            .oneshot(request(
                Method::GET,
                &format!("/v1/pairs/{}/status", created.code),
                Body::empty(),
            ))
            .await
            .expect("status response");
        assert_eq!(status.status(), StatusCode::OK);
        let status: PairStatusResponse = read_json(status).await;
        assert_eq!(status.status, PairStatus::Open);

        let claimed = app
            .clone()
            .oneshot(request(
                Method::POST,
                &format!("/v1/pairs/{}/claim", created.code),
                Body::empty(),
            ))
            .await
            .expect("claim response");
        assert_eq!(claimed.status(), StatusCode::OK);

        let status_after_claim = app
            .oneshot(request(
                Method::GET,
                &format!("/v1/pairs/{}/status", created.code),
                Body::empty(),
            ))
            .await
            .expect("status response");
        assert_eq!(status_after_claim.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn create_is_rate_limited() {
        let app = test_app();
        for _ in 0..CREATE_LIMIT_PER_MINUTE {
            let body = serde_json::to_vec(&RegisterPeerRequest {
                ticket: "ticket".to_owned(),
            })
            .expect("create body");

            let response = app
                .clone()
                .oneshot(request(Method::POST, "/v1/pairs", Body::from(body)))
                .await
                .expect("create response");
            assert_eq!(response.status(), StatusCode::CREATED);
        }

        let body = serde_json::to_vec(&RegisterPeerRequest {
            ticket: "ticket".to_owned(),
        })
        .expect("create body");
        let response = app
            .oneshot(request(Method::POST, "/v1/pairs", Body::from(body)))
            .await
            .expect("rate limit response");
        assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);

        let bytes = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body bytes");
        let body = from_utf8(&bytes).expect("utf8");
        assert!(body.contains("rate limit exceeded"));
    }

    #[tokio::test]
    async fn invalid_pair_registration_is_rejected() {
        let app = test_app();
        let body = serde_json::to_vec(&RegisterPeerRequest {
            ticket: String::new(),
        })
        .expect("register body");

        let response = app
            .oneshot(request(Method::POST, "/v1/pairs", Body::from(body)))
            .await
            .expect("invalid response");
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
}
