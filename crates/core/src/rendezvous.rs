use reqwest::StatusCode;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use thiserror::Error;

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

#[derive(Debug, Error)]
pub enum RendezvousError {
    #[error("short code must be exactly {code_length} characters from {code_alphabet}")]
    InvalidCode {
        code_length: usize,
        code_alphabet: &'static str,
    },
    #[error("{action} with rendezvous server")]
    Request {
        action: &'static str,
        #[source]
        source: reqwest::Error,
    },
    #[error("parsing rendezvous response for {action}")]
    ResponseParse {
        action: &'static str,
        #[source]
        source: reqwest::Error,
    },
    #[error("rendezvous server error ({status})")]
    Api {
        status: StatusCode,
        message: Option<String>,
    },
}

impl RendezvousClient {
    pub fn new(base_url: String) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_owned(),
            http: reqwest::Client::new(),
        }
    }

    pub async fn register_peer(
        &self,
        ticket: String,
    ) -> std::result::Result<RegisterPeerResponse, RendezvousError> {
        let request = RegisterPeerRequest { ticket };
        let response = self
            .http
            .post(self.url("/v1/pairs"))
            .json(&request)
            .send()
            .await
            .map_err(|source| RendezvousError::request("registering peer", source))?;
        parse_json(response, "registering peer").await
    }

    pub async fn claim_peer(
        &self,
        code: &str,
    ) -> std::result::Result<ClaimPeerResponse, RendezvousError> {
        validate_code(code)?;
        let response = self
            .http
            .post(self.url(&format!("/v1/pairs/{code}/claim")))
            .send()
            .await
            .map_err(|source| RendezvousError::request("claiming peer", source))?;
        parse_json(response, "claiming peer").await
    }

    pub async fn pair_status(
        &self,
        code: &str,
    ) -> std::result::Result<Option<PairStatusResponse>, RendezvousError> {
        validate_code(code)?;
        let response = self
            .http
            .get(self.url(&format!("/v1/pairs/{code}/status")))
            .send()
            .await
            .map_err(|source| RendezvousError::request("checking pair status", source))?;

        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }

        parse_json(response, "checking pair status").await.map(Some)
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }
}

pub fn validate_code(code: &str) -> std::result::Result<(), RendezvousError> {
    let valid = code.len() == CODE_LENGTH
        && code.bytes().all(|byte| {
            CODE_ALPHABET
                .as_bytes()
                .contains(&byte.to_ascii_uppercase())
        });
    if valid {
        Ok(())
    } else {
        Err(RendezvousError::InvalidCode {
            code_length: CODE_LENGTH,
            code_alphabet: CODE_ALPHABET,
        })
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

async fn parse_json<T: DeserializeOwned>(
    response: reqwest::Response,
    action: &'static str,
) -> std::result::Result<T, RendezvousError> {
    if response.status().is_success() {
        return response
            .json::<T>()
            .await
            .map_err(|source| RendezvousError::response_parse(action, source));
    }

    let (status, message) = error_message(response).await;
    Err(RendezvousError::Api { status, message })
}

async fn error_message(response: reqwest::Response) -> (StatusCode, Option<String>) {
    let status = response.status();
    match response.json::<ApiErrorBody>().await {
        Ok(body) if !body.error.is_empty() => (status, Some(body.error)),
        _ => (status, None),
    }
}

impl RendezvousError {
    fn request(action: &'static str, source: reqwest::Error) -> Self {
        Self::Request { action, source }
    }

    fn response_parse(action: &'static str, source: reqwest::Error) -> Self {
        Self::ResponseParse { action, source }
    }

    pub fn is_invalid_code(&self) -> bool {
        matches!(self, Self::InvalidCode { .. })
    }

    pub fn status_code(&self) -> Option<StatusCode> {
        match self {
            Self::Api { status, .. } => Some(*status),
            _ => None,
        }
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
