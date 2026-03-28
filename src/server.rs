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
use rand::Rng;
use serde::Serialize;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tokio::net::TcpListener;
use tokio::time::sleep;

use crate::validate_transfer_path;
use crate::rendezvous::{
    CODE_ALPHABET, CODE_LENGTH, CreateOfferRequest, CreateOfferResponse, OfferAcceptResponse,
    OfferManifest, OfferPreviewResponse, OfferStatus, OfferStatusResponse, validate_code,
};

const CREATE_LIMIT_PER_MINUTE: usize = 10;
const ACCESS_LIMIT_PER_MINUTE: usize = 60;
const OFFER_TTL_SECONDS: i64 = 300;
const CLEANUP_INTERVAL_SECONDS: u64 = 30;
const MAX_TICKET_LENGTH: usize = 4096;
const MAX_FILES_PER_OFFER: usize = 1000;
const MAX_FILE_PATH_LENGTH: usize = 1024;

type SharedState = Arc<AppState>;

#[derive(Debug)]
pub struct AppState {
    offers: Mutex<HashMap<String, OfferEntry>>,
    create_limiter: Mutex<RateLimiter>,
    access_limiter: Mutex<RateLimiter>,
}

impl AppState {
    fn new() -> Self {
        Self {
            offers: Mutex::new(HashMap::new()),
            create_limiter: Mutex::new(RateLimiter::default()),
            access_limiter: Mutex::new(RateLimiter::default()),
        }
    }
}

#[derive(Debug, Clone)]
struct OfferEntry {
    ticket: Option<String>,
    manifest: OfferManifest,
    _created_at: OffsetDateTime,
    expires_at: OffsetDateTime,
    status: OfferStatus,
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
        .route("/v1/offers", post(create_offer))
        .route("/v1/offers/{code}", get(get_offer))
        .route("/v1/offers/{code}/accept", post(accept_offer))
        .route("/v1/offers/{code}/decline", post(decline_offer))
        .route("/v1/offers/{code}/status", get(get_offer_status))
        .with_state(state)
}

pub async fn serve(listen_addr: SocketAddr) -> Result<()> {
    let state = Arc::new(AppState::new());
    tokio::spawn(cleanup_task(state.clone()));

    let listener = TcpListener::bind(listen_addr)
        .await
        .with_context(|| format!("binding rendezvous server on {listen_addr}"))?;

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

async fn create_offer(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(request): Json<CreateOfferRequest>,
) -> Result<(StatusCode, Json<CreateOfferResponse>), ApiError> {
    state
        .create_limiter
        .lock()
        .map_err(lock_error)?
        .check(addr.ip(), CREATE_LIMIT_PER_MINUTE)?;

    validate_offer_request(&request)?;

    let now = OffsetDateTime::now_utc();
    let expires_at = now + time::Duration::seconds(OFFER_TTL_SECONDS);

    let mut offers = state.offers.lock().map_err(lock_error)?;
    purge_expired_locked(&mut offers, now);
    let code = unique_code(&offers);
    offers.insert(
        code.clone(),
        OfferEntry {
            ticket: Some(request.ticket),
            manifest: request.manifest,
            _created_at: now,
            expires_at,
            status: OfferStatus::Pending,
        },
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateOfferResponse {
            code,
            expires_at: format_timestamp(expires_at)?,
        }),
    ))
}

async fn get_offer(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(code): Path<String>,
) -> Result<Json<OfferPreviewResponse>, ApiError> {
    rate_limit_access(&state, addr.ip())?;
    validate_code_api(&code)?;

    let now = OffsetDateTime::now_utc();
    let mut offers = state.offers.lock().map_err(lock_error)?;
    let entry = lookup_offer_mut(&mut offers, &code, now)?;

    if entry.status != OfferStatus::Pending {
        return Err(ApiError::new(
            StatusCode::CONFLICT,
            "offer is no longer pending",
        ));
    }

    Ok(Json(OfferPreviewResponse {
        manifest: entry.manifest.clone(),
        expires_at: format_timestamp(entry.expires_at)?,
    }))
}

async fn accept_offer(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(code): Path<String>,
) -> Result<Json<OfferAcceptResponse>, ApiError> {
    rate_limit_access(&state, addr.ip())?;
    validate_code_api(&code)?;

    let now = OffsetDateTime::now_utc();
    let mut offers = state.offers.lock().map_err(lock_error)?;
    let entry = lookup_offer_mut(&mut offers, &code, now)?;

    match entry.status {
        OfferStatus::Pending => {
            entry.status = OfferStatus::Accepted;
            let ticket = entry.ticket.take().ok_or_else(|| {
                ApiError::new(StatusCode::CONFLICT, "offer has already been accepted")
            })?;
            Ok(Json(OfferAcceptResponse { ticket }))
        }
        OfferStatus::Accepted | OfferStatus::Declined => Err(ApiError::new(
            StatusCode::CONFLICT,
            "offer is no longer actionable",
        )),
        OfferStatus::Expired => Err(ApiError::new(StatusCode::NOT_FOUND, "offer expired")),
    }
}

async fn decline_offer(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(code): Path<String>,
) -> Result<StatusCode, ApiError> {
    rate_limit_access(&state, addr.ip())?;
    validate_code_api(&code)?;

    let now = OffsetDateTime::now_utc();
    let mut offers = state.offers.lock().map_err(lock_error)?;
    let entry = lookup_offer_mut(&mut offers, &code, now)?;

    match entry.status {
        OfferStatus::Pending => {
            entry.status = OfferStatus::Declined;
            entry.ticket = None;
            Ok(StatusCode::NO_CONTENT)
        }
        OfferStatus::Accepted | OfferStatus::Declined => Err(ApiError::new(
            StatusCode::CONFLICT,
            "offer is no longer actionable",
        )),
        OfferStatus::Expired => Err(ApiError::new(StatusCode::NOT_FOUND, "offer expired")),
    }
}

async fn get_offer_status(
    State(state): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Path(code): Path<String>,
) -> Result<Json<OfferStatusResponse>, ApiError> {
    rate_limit_access(&state, addr.ip())?;
    validate_code_api(&code)?;

    let now = OffsetDateTime::now_utc();
    let mut offers = state.offers.lock().map_err(lock_error)?;
    let entry = offers
        .get_mut(&code)
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "offer not found"))?;

    let status = if entry.status == OfferStatus::Pending && entry.expires_at <= now {
        entry.status = OfferStatus::Expired;
        OfferStatus::Expired
    } else {
        entry.status.clone()
    };

    Ok(Json(OfferStatusResponse { status }))
}

fn rate_limit_access(state: &SharedState, ip: IpAddr) -> Result<(), ApiError> {
    state
        .access_limiter
        .lock()
        .map_err(lock_error)?
        .check(ip, ACCESS_LIMIT_PER_MINUTE)
}

fn validate_offer_request(request: &CreateOfferRequest) -> Result<(), ApiError> {
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

    if request.manifest.files.len() > MAX_FILES_PER_OFFER {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "too many files in offer",
        ));
    }

    if request.manifest.file_count != request.manifest.files.len() as u64 {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "file_count does not match files",
        ));
    }

    let total_size = request
        .manifest
        .files
        .iter()
        .try_fold(0_u64, |acc, file| acc.checked_add(file.size))
        .ok_or_else(|| ApiError::new(StatusCode::BAD_REQUEST, "total_size overflow"))?;

    if total_size != request.manifest.total_size {
        return Err(ApiError::new(
            StatusCode::BAD_REQUEST,
            "total_size does not match files",
        ));
    }

    for file in &request.manifest.files {
        if file.path.trim().is_empty() {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "file paths must not be empty",
            ));
        }

        if file.path.len() > MAX_FILE_PATH_LENGTH {
            return Err(ApiError::new(
                StatusCode::BAD_REQUEST,
                "file path is too long",
            ));
        }

        validate_transfer_path(&file.path)
            .map_err(|err| ApiError::new(StatusCode::BAD_REQUEST, err.to_string()))?;
    }

    Ok(())
}

fn validate_code_api(code: &str) -> Result<(), ApiError> {
    validate_code(code).map_err(|err| ApiError::new(StatusCode::BAD_REQUEST, err.to_string()))
}

fn unique_code(offers: &HashMap<String, OfferEntry>) -> String {
    let mut rng = rand::thread_rng();
    let alphabet = CODE_ALPHABET.as_bytes();
    loop {
        let code: String = (0..CODE_LENGTH)
            .map(|_| {
                let idx = rng.gen_range(0..alphabet.len());
                alphabet[idx] as char
            })
            .collect();
        if !offers.contains_key(&code) {
            return code;
        }
    }
}

fn lookup_offer_mut<'a>(
    offers: &'a mut HashMap<String, OfferEntry>,
    code: &str,
    now: OffsetDateTime,
) -> Result<&'a mut OfferEntry, ApiError> {
    let entry = offers
        .get_mut(code)
        .ok_or_else(|| ApiError::new(StatusCode::NOT_FOUND, "offer not found"))?;

    if entry.status == OfferStatus::Pending && entry.expires_at <= now {
        entry.status = OfferStatus::Expired;
    }

    if entry.status == OfferStatus::Expired {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "offer expired"));
    }

    Ok(entry)
}

fn purge_expired_locked(offers: &mut HashMap<String, OfferEntry>, now: OffsetDateTime) {
    offers.retain(|_, entry| entry.expires_at > now);
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
        if let Ok(mut offers) = state.offers.lock() {
            purge_expired_locked(&mut offers, now);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::str::from_utf8;

    use axum::body::{Body, to_bytes};
    use axum::http::{Method, Request, header};
    use tower::ServiceExt;

    use super::*;
    use crate::rendezvous::OfferFile;

    fn test_app() -> Router {
        app(Arc::new(AppState::new()))
    }

    fn test_manifest() -> OfferManifest {
        OfferManifest {
            files: vec![OfferFile {
                path: "sample.txt".to_owned(),
                size: 12,
            }],
            file_count: 1,
            total_size: 12,
        }
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
    async fn create_preview_accept_flow_works_once() {
        let app = test_app();
        let body = serde_json::to_vec(&CreateOfferRequest {
            ticket: "ticket".to_owned(),
            manifest: test_manifest(),
        })
        .expect("create body");

        let response = app
            .clone()
            .oneshot(request(Method::POST, "/v1/offers", Body::from(body)))
            .await
            .expect("create response");
        assert_eq!(response.status(), StatusCode::CREATED);
        let created: CreateOfferResponse = read_json(response).await;

        let preview = app
            .clone()
            .oneshot(request(
                Method::GET,
                &format!("/v1/offers/{}", created.code),
                Body::empty(),
            ))
            .await
            .expect("preview response");
        assert_eq!(preview.status(), StatusCode::OK);
        let preview: OfferPreviewResponse = read_json(preview).await;
        assert_eq!(preview.manifest.file_count, 1);
        assert_eq!(preview.manifest.total_size, 12);

        let accepted = app
            .clone()
            .oneshot(request(
                Method::POST,
                &format!("/v1/offers/{}/accept", created.code),
                Body::empty(),
            ))
            .await
            .expect("accept response");
        assert_eq!(accepted.status(), StatusCode::OK);
        let accepted: OfferAcceptResponse = read_json(accepted).await;
        assert_eq!(accepted.ticket, "ticket");

        let second_accept = app
            .oneshot(request(
                Method::POST,
                &format!("/v1/offers/{}/accept", created.code),
                Body::empty(),
            ))
            .await
            .expect("second accept response");
        assert_eq!(second_accept.status(), StatusCode::CONFLICT);
    }

    #[tokio::test]
    async fn decline_marks_offer_terminal() {
        let app = test_app();
        let body = serde_json::to_vec(&CreateOfferRequest {
            ticket: "ticket".to_owned(),
            manifest: test_manifest(),
        })
        .expect("create body");

        let response = app
            .clone()
            .oneshot(request(Method::POST, "/v1/offers", Body::from(body)))
            .await
            .expect("create response");
        let created: CreateOfferResponse = read_json(response).await;

        let declined = app
            .clone()
            .oneshot(request(
                Method::POST,
                &format!("/v1/offers/{}/decline", created.code),
                Body::empty(),
            ))
            .await
            .expect("decline response");
        assert_eq!(declined.status(), StatusCode::NO_CONTENT);

        let status = app
            .oneshot(request(
                Method::GET,
                &format!("/v1/offers/{}/status", created.code),
                Body::empty(),
            ))
            .await
            .expect("status response");
        assert_eq!(status.status(), StatusCode::OK);
        let status: OfferStatusResponse = read_json(status).await;
        assert_eq!(status.status, OfferStatus::Declined);
    }

    #[tokio::test]
    async fn create_is_rate_limited() {
        let app = test_app();
        for _ in 0..CREATE_LIMIT_PER_MINUTE {
            let body = serde_json::to_vec(&CreateOfferRequest {
                ticket: "ticket".to_owned(),
                manifest: test_manifest(),
            })
            .expect("create body");

            let response = app
                .clone()
                .oneshot(request(Method::POST, "/v1/offers", Body::from(body)))
                .await
                .expect("create response");
            assert_eq!(response.status(), StatusCode::CREATED);
        }

        let body = serde_json::to_vec(&CreateOfferRequest {
            ticket: "ticket".to_owned(),
            manifest: test_manifest(),
        })
        .expect("create body");
        let response = app
            .oneshot(request(Method::POST, "/v1/offers", Body::from(body)))
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
    async fn invalid_manifest_is_rejected() {
        let app = test_app();
        let body = serde_json::to_vec(&CreateOfferRequest {
            ticket: String::new(),
            manifest: test_manifest(),
        })
        .expect("create body");

        let response = app
            .oneshot(request(Method::POST, "/v1/offers", Body::from(body)))
            .await
            .expect("invalid response");
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn invalid_path_manifest_is_rejected() {
        let app = test_app();
        let body = serde_json::to_vec(&CreateOfferRequest {
            ticket: "ticket".to_owned(),
            manifest: OfferManifest {
                files: vec![OfferFile {
                    path: "../sample.txt".to_owned(),
                    size: 12,
                }],
                file_count: 1,
                total_size: 12,
            },
        })
        .expect("create body");

        let response = app
            .oneshot(request(Method::POST, "/v1/offers", Body::from(body)))
            .await
            .expect("invalid response");
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    }
}
