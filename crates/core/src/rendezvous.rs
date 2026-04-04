use reqwest::StatusCode;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::error::{DriftError, DriftErrorKind, Result};

pub const DEFAULT_RENDEZVOUS_URL: &str = "https://drift.samarthv.com";
pub const CODE_LENGTH: usize = 6;
pub const CODE_ALPHABET: &str = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OfferFile {
    pub path: String,
    pub size: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OfferManifest {
    pub files: Vec<OfferFile>,
    pub file_count: u64,
    pub total_size: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterPeerRequest {
    pub ticket: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterPeerResponse {
    pub code: String,
    pub expires_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClaimPeerResponse {
    pub ticket: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum PairStatus {
    Open,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PairStatusResponse {
    pub status: PairStatus,
}

#[derive(Debug, Clone, Deserialize)]
struct ApiErrorBody {
    error: String,
}

#[derive(Debug, Clone)]
pub struct RendezvousClient {
    base_url: String,
    http: reqwest::Client,
}

impl RendezvousClient {
    pub fn new(base_url: String) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_owned(),
            http: reqwest::Client::new(),
        }
    }

    pub async fn register_peer(&self, ticket: String) -> Result<RegisterPeerResponse> {
        let request = RegisterPeerRequest { ticket };
        let response = self
            .http
            .post(self.url("/v1/pairs"))
            .json(&request)
            .send()
            .await
            .map_err(|error| {
                DriftError::with_reason(
                    DriftErrorKind::RendezvousUnavailable,
                    format!("registering peer with rendezvous server: {error}"),
                )
            })?;
        parse_json(response).await
    }

    pub async fn claim_peer(&self, code: &str) -> Result<ClaimPeerResponse> {
        validate_code(code)?;
        let response = self
            .http
            .post(self.url(&format!("/v1/pairs/{code}/claim")))
            .send()
            .await
            .map_err(|error| {
                DriftError::with_reason(
                    DriftErrorKind::RendezvousUnavailable,
                    format!("claiming peer for code {code}: {error}"),
                )
            })?;
        parse_json(response).await
    }

    pub async fn pair_status(&self, code: &str) -> Result<Option<PairStatusResponse>> {
        validate_code(code)?;
        let response = self
            .http
            .get(self.url(&format!("/v1/pairs/{code}/status")))
            .send()
            .await
            .map_err(|error| {
                DriftError::with_reason(
                    DriftErrorKind::RendezvousUnavailable,
                    format!("checking status for peer {code}: {error}"),
                )
            })?;

        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }

        parse_json(response).await.map(Some)
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }
}

pub fn validate_code(code: &str) -> Result<()> {
    let valid = code.len() == CODE_LENGTH
        && code.bytes().all(|byte| {
            CODE_ALPHABET
                .as_bytes()
                .contains(&byte.to_ascii_uppercase())
        });
    if valid {
        Ok(())
    } else {
        Err(DriftError::with_reason(
            DriftErrorKind::InvalidCode,
            format!(
                "short code must be exactly {} characters from {}",
                CODE_LENGTH, CODE_ALPHABET
            ),
        ))
    }
}

pub fn resolve_server_url(override_url: Option<&str>) -> String {
    resolve_server_url_with_env(override_url, std::env::var("DRIFT_RENDEZVOUS_URL").ok())
}

fn resolve_server_url_with_env(override_url: Option<&str>, env_url: Option<String>) -> String {
    if let Some(url) = override_url {
        return normalize_url(url);
    }

    if let Some(url) = env_url {
        return normalize_url(&url);
    }

    DEFAULT_RENDEZVOUS_URL.to_owned()
}

fn normalize_url(url: &str) -> String {
    url.trim().trim_end_matches('/').to_owned()
}

async fn parse_json<T: DeserializeOwned>(response: reqwest::Response) -> Result<T> {
    if response.status().is_success() {
        return response
            .json::<T>()
            .await
            .map_err(|error| {
                DriftError::with_reason(
                    DriftErrorKind::Internal,
                    format!("parsing rendezvous response: {error}"),
                )
            });
    }

    Err(error_from_response(response).await)
}

async fn error_from_response(response: reqwest::Response) -> DriftError {
    let status = response.status();
    let reason = match response.json::<ApiErrorBody>().await {
        Ok(body) if !body.error.is_empty() => {
            format!("rendezvous server error ({status}): {}", body.error)
        }
        _ => format!("rendezvous server error ({status})"),
    };
    DriftError::with_reason(error_kind_for_status(status), reason)
}

fn error_kind_for_status(status: StatusCode) -> DriftErrorKind {
    match status {
        StatusCode::NOT_FOUND => DriftErrorKind::PeerNotFound,
        StatusCode::CONFLICT => DriftErrorKind::PeerAlreadyClaimed,
        StatusCode::REQUEST_TIMEOUT | StatusCode::GATEWAY_TIMEOUT => {
            DriftErrorKind::RendezvousUnavailable
        }
        StatusCode::BAD_REQUEST | StatusCode::UNPROCESSABLE_ENTITY => DriftErrorKind::InvalidInput,
        StatusCode::TOO_MANY_REQUESTS => DriftErrorKind::RendezvousRejected,
        status if status.is_server_error() => DriftErrorKind::RendezvousUnavailable,
        _ => DriftErrorKind::RendezvousRejected,
    }
}

#[cfg(test)]
mod tests {
    use super::{DEFAULT_RENDEZVOUS_URL, resolve_server_url_with_env, validate_code};

    #[test]
    fn code_validation_rejects_invalid_inputs() {
        assert!(validate_code("AB2CD3").is_ok());
        assert!(validate_code("ab2cd3").is_ok());
        assert!(validate_code("12345").is_err());
        assert!(validate_code("12345O").is_err());
        assert!(validate_code("12345I").is_err());
    }

    #[test]
    fn server_url_precedence_prefers_flag_then_env_then_default() {
        let from_flag = resolve_server_url_with_env(
            Some("https://flag.example/path/"),
            Some("https://env.example".to_owned()),
        );
        assert_eq!(from_flag, "https://flag.example/path");

        let from_env = resolve_server_url_with_env(None, Some("https://env.example/".to_owned()));
        assert_eq!(from_env, "https://env.example");

        let default = resolve_server_url_with_env(None, None);
        assert_eq!(default, DEFAULT_RENDEZVOUS_URL);
    }
}
