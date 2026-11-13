//! Carrier Wave Phase-5 OAuth client — PKCE magic-link verification → access +
//! rotating refresh tokens → refresh. A faithful port of the iOS
//! `OAuthClient.swift`; the host owns secret storage (keychain /
//! EncryptedSharedPreferences), this layer drives the protocol.
//!
//! Token endpoints return a **bare** JSON token pair (no `{ "data": … }`
//! envelope), unlike the clubs API. The poll endpoint is status-driven:
//! `201` issued, `204` attached-to-account, `202` still pending.

use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::http::{HttpClient, HttpError};

// ---------------------------------------------------------------------------
// PKCE
// ---------------------------------------------------------------------------

/// Generate a fresh PKCE verifier: 32 CSPRNG bytes, lower-hex encoded (64 chars).
/// Mirrors `OAuthClient.randomVerifier()`.
pub fn generate_verifier() -> String {
    let mut bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    to_hex(&bytes)
}

/// The S256 challenge the server expects: `hex(sha256(verifier_utf8))` (64 chars).
/// Note the hash is over the UTF-8 bytes of the *hex verifier string*, matching
/// `OAuthClient.pkceChallenge(for:)`.
pub fn pkce_challenge(verifier: &str) -> String {
    let digest = Sha256::digest(verifier.as_bytes());
    to_hex(&digest)
}

fn to_hex(bytes: &[u8]) -> String {
    const TABLE: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(TABLE[(byte >> 4) as usize] as char);
        out.push(TABLE[(byte & 0x0f) as usize] as char);
    }
    out
}

// ---------------------------------------------------------------------------
// Wire bodies / responses (bare JSON, camelCase)
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct VerifyStartBody<'a> {
    callsign: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    email: Option<&'a str>,
    pkce_challenge: &'a str,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct VerifyStartResponse {
    poll_token: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct VerifyPollBody<'a> {
    poll_token: &'a str,
    pkce_verifier: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    device_name: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    platform: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    scopes: Option<&'a str>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct TokenExchangeBody<'a> {
    code: &'a str,
    pkce_verifier: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    device_name: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    platform: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    scopes: Option<&'a str>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RefreshBody<'a> {
    refresh: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    aud: Option<&'a str>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LogoutBody<'a> {
    refresh: &'a str,
}

/// Issued token pair (`/v1/auth/token`, `/token/refresh`, and the `201` poll body).
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TokenPair {
    pub access: String,
    pub refresh: String,
    /// Access-token lifetime in seconds.
    pub expires_in: i64,
    pub account_id: Option<String>,
}

/// Outcome of one `/v1/auth/verify/poll` call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PollOutcome {
    /// `201` — onboarding completed, tokens issued.
    Issued(TokenPair),
    /// `204` — attached to an existing account (no new tokens).
    Attached,
    /// `202` — the magic link hasn't been clicked yet.
    Pending,
}

/// Why a refresh failed, distinguishing a dead session (drop it) from transport.
#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error(transparent)]
    Http(#[from] HttpError),
    /// The refresh token was rejected (rotated/revoked) — the session is dead.
    #[error("refresh rejected; session is no longer valid")]
    SessionExpired,
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Async OAuth client for the activities server `/v1/auth/*` surface.
#[derive(Debug, Clone)]
pub struct AuthClient {
    http: HttpClient,
    base_url: String,
}

impl AuthClient {
    /// Build a client against `base_url` (e.g. `https://activities.carrierwave.app`).
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        let base_url = base_url.into().trim_end_matches('/').to_string();
        Self { http, base_url }
    }

    /// Step 1: request a magic link for `callsign`, presenting the PKCE challenge.
    /// Returns the opaque poll token (always present, even when nothing was
    /// deliverable, so callsign validity never leaks).
    pub async fn verify_start(
        &self,
        callsign: &str,
        email: Option<&str>,
        pkce_challenge: &str,
    ) -> Result<String, HttpError> {
        let body = VerifyStartBody { callsign, email, pkce_challenge };
        let resp: VerifyStartResponse = self.post_json("/v1/auth/verify/start", &body).await?;
        Ok(resp.poll_token)
    }

    /// Poll once for completion. Returns [`PollOutcome::Pending`] until the link
    /// is clicked, then [`PollOutcome::Issued`] (new account) or
    /// [`PollOutcome::Attached`] (existing account).
    pub async fn verify_poll(
        &self,
        poll_token: &str,
        pkce_verifier: &str,
        device_name: Option<&str>,
        platform: Option<&str>,
    ) -> Result<PollOutcome, HttpError> {
        let body = VerifyPollBody {
            poll_token,
            pkce_verifier,
            device_name,
            platform,
            scopes: None,
        };
        let (status, bytes) = self.post_for_status("/v1/auth/verify/poll", &body).await?;
        match status {
            201 => Ok(PollOutcome::Issued(serde_json::from_slice(&bytes)?)),
            204 => Ok(PollOutcome::Attached),
            _ => Ok(PollOutcome::Pending), // 202
        }
    }

    /// Universal-link return path: redeem a clicked verification `code` with the
    /// stored PKCE verifier for a token pair.
    pub async fn exchange(
        &self,
        code: &str,
        pkce_verifier: &str,
        device_name: Option<&str>,
        platform: Option<&str>,
    ) -> Result<TokenPair, HttpError> {
        let body = TokenExchangeBody {
            code,
            pkce_verifier,
            device_name,
            platform,
            scopes: None,
        };
        self.post_json("/v1/auth/token", &body).await
    }

    /// Mark the emailed magic link clicked — the same `GET /v1/auth/verify/complete`
    /// the browser hits when the link is opened outside the app. Used by the
    /// deep-link return path so that, when the OS hands the link to the app
    /// instead of a browser, the verification is still marked clicked (setting
    /// `consumed_at`) and either this device's exchange/poll *or* the originating
    /// device's poll can complete. The HTML body is ignored.
    pub async fn mark_link_clicked(&self, code: &str) -> Result<(), HttpError> {
        let url = format!("{}/v1/auth/verify/complete", self.base_url);
        let response = self.http.inner().get(&url).query(&[("code", code)]).send().await?;
        let status = response.status();
        let _ = response.bytes().await?; // drain the static HTML page
        if !status.is_success() {
            return Err(HttpError::Http { status: status.as_u16(), body: String::new() });
        }
        Ok(())
    }

    /// Rotate the refresh token and mint a new access token. A `401` means the
    /// token was rotated/revoked → [`AuthError::SessionExpired`].
    pub async fn refresh(&self, refresh_token: &str) -> Result<TokenPair, AuthError> {
        let body = RefreshBody { refresh: refresh_token, aud: None };
        match self.post_json::<_, TokenPair>("/v1/auth/token/refresh", &body).await {
            Ok(pair) => Ok(pair),
            Err(HttpError::Http { status: 401, .. }) => Err(AuthError::SessionExpired),
            Err(err) => Err(AuthError::Http(err)),
        }
    }

    /// Best-effort device logout (revokes this refresh family server-side).
    pub async fn logout(&self, refresh_token: &str) -> Result<(), HttpError> {
        let body = LogoutBody { refresh: refresh_token };
        let (_status, _bytes) = self.post_for_status("/v1/auth/logout", &body).await?;
        Ok(())
    }

    // --- internals ---------------------------------------------------------

    async fn post_json<B: Serialize, T: serde::de::DeserializeOwned>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<T, HttpError> {
        let (_status, bytes) = self.post_for_status(path, body).await?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    /// POST `body`, returning `(status, bytes)` for any 2xx; non-2xx is an error.
    async fn post_for_status<B: Serialize>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<(u16, Vec<u8>), HttpError> {
        let url = format!("{}{}", self.base_url, path);
        let response = self.http.inner().post(&url).json(body).send().await?;
        let status = response.status();
        let bytes = response.bytes().await?;
        if !status.is_success() {
            return Err(HttpError::Http {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        Ok((status.as_u16(), bytes.to_vec()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verifier_is_64_lowercase_hex() {
        let verifier = generate_verifier();
        assert_eq!(verifier.len(), 64);
        assert!(verifier.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()));
        // Two calls differ (CSPRNG).
        assert_ne!(verifier, generate_verifier());
    }

    #[test]
    fn challenge_matches_known_sha256_hex() {
        // hex(sha256("abc")) — the documented S256-over-utf8 form.
        assert_eq!(
            pkce_challenge("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(pkce_challenge("abc").len(), 64);
    }

    #[test]
    fn token_pair_parses_bare_json() {
        let json = r#"{
            "access": "ey.aaa.bbb",
            "refresh": "cwr_deadbeef",
            "expiresIn": 900,
            "accountId": "11111111-1111-1111-1111-111111111111"
        }"#;
        let pair: TokenPair = serde_json::from_str(json).unwrap();
        assert_eq!(pair.access, "ey.aaa.bbb");
        assert_eq!(pair.expires_in, 900);
        assert_eq!(pair.account_id.as_deref(), Some("11111111-1111-1111-1111-111111111111"));
    }

    #[test]
    fn token_pair_account_id_optional() {
        let json = r#"{ "access": "a", "refresh": "r", "expiresIn": 900 }"#;
        let pair: TokenPair = serde_json::from_str(json).unwrap();
        assert_eq!(pair.account_id, None);
    }
}
