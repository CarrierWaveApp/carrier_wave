//! Another Morse Trainer (AMT) stats client — read-only access to one user's
//! own practice statistics at `https://amt-accounts.n9ho-amt.workers.dev`.
//!
//! Sign-in is an emailed link: the app presents an RFC 7636 PKCE challenge,
//! the user presses **Confirm** in the email, and the app polls until tokens
//! are issued. There is no password, client secret or API key — the PKCE
//! verifier the app keeps is the only proof the tokens belong to it. The host
//! owns secret storage; this layer drives the wire protocol and parses the
//! `/v1` contract (fields may be added but never removed or renamed, so every
//! struct is `#[serde(default)]`-tolerant and ignores unknown keys).
//!
//! Only the `stats:read` scope is ever requested: Carrier Wave can read the
//! user's id/callsign/display name, their stats and session history, and sign
//! itself out. All numbers are self-reported by the AMT apps.

use std::collections::BTreeMap;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::http::{HttpClient, HttpError};

/// Production AMT accounts service.
pub const AMT_BASE_URL: &str = "https://amt-accounts.n9ho-amt.workers.dev";

/// The client identifier AMT registered for Carrier Wave. The user sees this
/// name in the sign-in email, on the confirm page and in their devices list.
/// It is one id for every Carrier Wave platform; the actual platform is sent
/// separately in `platform`.
pub const AMT_CLIENT_ID: &str = "carrier-wave-ios";

/// The only scope Carrier Wave asks for.
pub const AMT_SCOPES: &str = "stats:read";

// ---------------------------------------------------------------------------
// PKCE (RFC 7636 S256, base64url without padding)
// ---------------------------------------------------------------------------

/// Fresh PKCE verifier: 32 CSPRNG bytes, base64url without padding (43 chars).
pub fn generate_amt_verifier() -> String {
    let mut bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

/// S256 challenge for `verifier`: `base64url(sha256(verifier_utf8))` (43 chars).
pub fn amt_pkce_challenge(verifier: &str) -> String {
    URL_SAFE_NO_PAD.encode(Sha256::digest(verifier.as_bytes()))
}

// ---------------------------------------------------------------------------
// Wire bodies / responses (bare JSON, camelCase)
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct StartBody<'a> {
    email: &'a str,
    pkce_challenge: &'a str,
    client: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    device_name: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    platform: Option<&'a str>,
    scopes: &'a str,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StartResponse {
    poll_token: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct PollBody<'a> {
    poll_token: &'a str,
    pkce_verifier: &'a str,
}

#[derive(Debug, Serialize)]
struct RefreshBody<'a> {
    refresh: &'a str,
}

/// Shared error envelope: `{ "error": "<code>", "message": "<text>" }`.
#[derive(Debug, Deserialize)]
struct ErrorEnvelope {
    #[serde(default)]
    error: String,
    #[serde(default)]
    message: String,
}

/// The signed-in account, as returned in the `201` poll body.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtAccount {
    pub id: String,
    pub callsign: Option<String>,
    pub display_name: Option<String>,
}

/// Token pair from the `201` poll body and `/v1/auth/token/refresh`.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AmtTokens {
    pub access: String,
    pub refresh: String,
    /// Access-token lifetime in seconds (15 minutes today).
    pub expires_in: i64,
    /// Present on the poll body, absent on refresh.
    #[serde(default)]
    pub account: Option<AmtAccount>,
}

/// Outcome of one `/v1/auth/verify/poll` call.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AmtPollOutcome {
    /// `202` — the user hasn't pressed Confirm yet.
    Pending,
    /// `201` — signed in.
    SignedIn(AmtTokens),
    /// `410` — the link expired (15 min) or was already used.
    Expired,
    /// `429` — polled faster than every 2 s; wait this many seconds.
    RateLimited { retry_after_secs: u64 },
}

/// `GET /v1/me`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtProfile {
    pub id: String,
    pub callsign: Option<String>,
    pub display_name: Option<String>,
    /// Join date, epoch ms.
    pub created_at: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtTotals {
    pub sessions: i64,
    pub answered: i64,
    pub correct: i64,
    /// `correct / answered`, 0–1, `None` when nothing was answered.
    pub accuracy: Option<f64>,
    pub practice_seconds: f64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtStreak {
    /// Consecutive practice days ending today or yesterday.
    pub current: i64,
    /// Longest run in the last 400 days.
    pub longest: i64,
    /// Newest practice day, `yyyy-mm-dd`.
    pub last_practised_day: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtModeStats {
    pub sessions: i64,
    pub answered: i64,
    pub correct: i64,
    pub accuracy: Option<f64>,
    pub median_ttr_ms: Option<i64>,
    /// Newest session of that mode, epoch ms.
    pub last_date: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtCharacterStats {
    pub attempts: i64,
    pub correct: i64,
    pub accuracy: Option<f64>,
    pub median_ttr_ms: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtActivity {
    /// Practice seconds per local calendar day (`yyyy-mm-dd`), last 400 days.
    pub days: BTreeMap<String, f64>,
    /// Calendar tile shade 0–4; a recorded day is never below 1.
    pub level: BTreeMap<String, i64>,
    /// Seconds at which levels 1–4 begin, e.g. `[1, 300, 900, 1800]`.
    pub level_thresholds: Vec<i64>,
}

/// `GET /v1/me/stats`.
#[derive(Debug, Clone, Default, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AmtStats {
    pub totals: AmtTotals,
    pub best_ttr_ms: Option<i64>,
    /// The user's own best score per mode; 0 is a real best.
    pub personal_bests: BTreeMap<String, i64>,
    pub streak: AmtStreak,
    pub per_mode: BTreeMap<String, AmtModeStats>,
    pub per_character: BTreeMap<String, AmtCharacterStats>,
    pub activity: AmtActivity,
    /// When the stats last changed, epoch ms.
    pub updated_at: i64,
}

/// Why an AMT call failed. Only `Unauthorized` (refresh once, retry once) and
/// `RateLimited` (wait) are worth retrying.
#[derive(Debug, thiserror::Error)]
pub enum AmtError {
    #[error(transparent)]
    Http(#[from] HttpError),
    /// A bearer call answered `401` — refresh and retry once.
    #[error("AMT access token rejected")]
    Unauthorized,
    /// The refresh token was rejected: the user removed Carrier Wave from their
    /// devices, or the token leaked. Sign out locally.
    #[error("AMT refresh rejected; signed out")]
    SessionExpired,
    /// Our verifier didn't match the challenge — an app bug, not the user's.
    #[error("AMT PKCE verifier does not match the challenge")]
    InvalidVerifier,
    /// Any other `{ error, message }` reply.
    #[error("AMT {status} {code}: {message}")]
    Api { status: u16, code: String, message: String },
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Async client for the eight AMT routes Carrier Wave calls.
#[derive(Debug, Clone)]
pub struct AmtClient {
    http: HttpClient,
    base_url: String,
}

impl AmtClient {
    /// Build a client against `base_url` (normally [`AMT_BASE_URL`]).
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        let base_url = base_url.into().trim_end_matches('/').to_string();
        Self { http, base_url }
    }

    /// Step 1: ask AMT to email `email` a sign-in link. Always `202 { pollToken }`,
    /// whether or not the address has an account — nothing tells you which.
    pub async fn start_sign_in(
        &self,
        email: &str,
        pkce_challenge: &str,
        device_name: Option<&str>,
        platform: Option<&str>,
    ) -> Result<String, AmtError> {
        let body = StartBody {
            email,
            pkce_challenge,
            client: AMT_CLIENT_ID,
            device_name,
            platform,
            scopes: AMT_SCOPES,
        };
        let (status, bytes) = self.post("/v1/auth/verify/start", &body, None).await?;
        if !(200..300).contains(&status) {
            return Err(api_error(status, &bytes));
        }
        let resp: StartResponse = serde_json::from_slice(&bytes).map_err(HttpError::from)?;
        Ok(resp.poll_token)
    }

    /// Poll once (no faster than every 2 s) for the user pressing Confirm.
    pub async fn poll(&self, poll_token: &str, pkce_verifier: &str) -> Result<AmtPollOutcome, AmtError> {
        let body = PollBody { poll_token, pkce_verifier };
        let url = format!("{}/v1/auth/verify/poll", self.base_url);
        let response = self.http.inner().post(&url).json(&body).send().await.map_err(HttpError::from)?;
        let status = response.status().as_u16();
        let retry_after = response
            .headers()
            .get("retry-after")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.trim().parse::<u64>().ok());
        let bytes = response.bytes().await.map_err(HttpError::from)?;
        parse_poll_response(status, retry_after, &bytes)
    }

    /// Rotate the refresh token. Save the new refresh token before using the new
    /// access token; presenting an old one signs the device out.
    pub async fn refresh(&self, refresh: &str) -> Result<AmtTokens, AmtError> {
        let body = RefreshBody { refresh };
        let (status, bytes) = self.post("/v1/auth/token/refresh", &body, None).await?;
        match status {
            200..=299 => Ok(serde_json::from_slice(&bytes).map_err(HttpError::from)?),
            401 => Err(AmtError::SessionExpired),
            _ => Err(api_error(status, &bytes)),
        }
    }

    /// Sign this device out (`204`). The tokens are dead afterwards.
    pub async fn logout(&self, access: &str) -> Result<(), AmtError> {
        let url = format!("{}/v1/auth/logout", self.base_url);
        let response = self
            .http
            .inner()
            .post(&url)
            .bearer_auth(access)
            .send()
            .await
            .map_err(HttpError::from)?;
        let status = response.status().as_u16();
        let bytes = response.bytes().await.map_err(HttpError::from)?;
        match status {
            200..=299 => Ok(()),
            401 => Err(AmtError::Unauthorized),
            _ => Err(api_error(status, &bytes)),
        }
    }

    /// `GET /v1/me` — id, callsign, display name, join date.
    pub async fn me(&self, access: &str) -> Result<AmtProfile, AmtError> {
        let url = format!("{}/v1/me", self.base_url);
        self.get_bearer(&url, access).await
    }

    /// `GET /v1/me/stats?today=yyyy-mm-dd`. Pass `today` as the user's *local*
    /// calendar date so the current streak is exact; without it the server
    /// uses its own UTC date, which can be a day generous.
    pub async fn stats(&self, access: &str, today: Option<&str>) -> Result<AmtStats, AmtError> {
        let mut url = format!("{}/v1/me/stats", self.base_url);
        if let Some(today) = today {
            url.push_str("?today=");
            url.push_str(today);
        }
        self.get_bearer(&url, access).await
    }

    // --- internals ---------------------------------------------------------

    async fn get_bearer<T: serde::de::DeserializeOwned>(&self, url: &str, access: &str) -> Result<T, AmtError> {
        let response = self
            .http
            .inner()
            .get(url)
            .bearer_auth(access)
            .send()
            .await
            .map_err(HttpError::from)?;
        let status = response.status().as_u16();
        let bytes = response.bytes().await.map_err(HttpError::from)?;
        match status {
            200..=299 => Ok(serde_json::from_slice(&bytes).map_err(HttpError::from)?),
            401 => Err(AmtError::Unauthorized),
            _ => Err(api_error(status, &bytes)),
        }
    }

    /// POST `body`, returning `(status, bytes)` for *any* status so callers can
    /// map the contract's status codes themselves.
    async fn post<B: Serialize>(
        &self,
        path: &str,
        body: &B,
        bearer: Option<&str>,
    ) -> Result<(u16, Vec<u8>), AmtError> {
        let url = format!("{}{}", self.base_url, path);
        let mut request = self.http.inner().post(&url).json(body);
        if let Some(bearer) = bearer {
            request = request.bearer_auth(bearer);
        }
        let response = request.send().await.map_err(HttpError::from)?;
        let status = response.status().as_u16();
        let bytes = response.bytes().await.map_err(HttpError::from)?;
        Ok((status, bytes.to_vec()))
    }
}

/// Map a `/v1/auth/verify/poll` reply to an outcome.
pub fn parse_poll_response(status: u16, retry_after: Option<u64>, bytes: &[u8]) -> Result<AmtPollOutcome, AmtError> {
    match status {
        202 => Ok(AmtPollOutcome::Pending),
        201 => Ok(AmtPollOutcome::SignedIn(serde_json::from_slice(bytes).map_err(HttpError::from)?)),
        410 => Ok(AmtPollOutcome::Expired),
        429 => Ok(AmtPollOutcome::RateLimited { retry_after_secs: retry_after.unwrap_or(2).max(1) }),
        400 if error_code(bytes) == "invalid_verifier" => Err(AmtError::InvalidVerifier),
        _ => Err(api_error(status, bytes)),
    }
}

fn error_code(bytes: &[u8]) -> String {
    serde_json::from_slice::<ErrorEnvelope>(bytes).map(|e| e.error).unwrap_or_default()
}

fn api_error(status: u16, bytes: &[u8]) -> AmtError {
    let env = serde_json::from_slice::<ErrorEnvelope>(bytes).unwrap_or_else(|_| ErrorEnvelope {
        error: String::new(),
        message: String::from_utf8_lossy(bytes).trim().chars().take(200).collect(),
    });
    AmtError::Api { status, code: env.error, message: env.message }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn verifier_is_43_base64url_chars() {
        let v = generate_amt_verifier();
        assert_eq!(v.len(), 43);
        assert!(v.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));
        assert_ne!(v, generate_amt_verifier());
    }

    #[test]
    fn challenge_matches_rfc7636_appendix_b() {
        // RFC 7636 Appendix B worked example.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
        assert_eq!(amt_pkce_challenge(verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
        assert_eq!(amt_pkce_challenge(verifier).len(), 43);
    }

    #[test]
    fn start_body_carries_client_and_scope() {
        let body = StartBody {
            email: "op@example.com",
            pkce_challenge: "c",
            client: AMT_CLIENT_ID,
            device_name: None,
            platform: Some("ios"),
            scopes: AMT_SCOPES,
        };
        let json: serde_json::Value = serde_json::to_value(&body).unwrap();
        assert_eq!(json["client"], "carrier-wave-ios");
        assert_eq!(json["scopes"], "stats:read");
        assert_eq!(json["pkceChallenge"], "c");
        assert!(json.get("deviceName").is_none());
        assert_eq!(json["platform"], "ios");
    }

    #[test]
    fn poll_statuses_map_to_outcomes() {
        assert_eq!(parse_poll_response(202, None, b"").unwrap(), AmtPollOutcome::Pending);
        assert_eq!(parse_poll_response(410, None, b"{\"error\":\"expired\"}").unwrap(), AmtPollOutcome::Expired);
        assert_eq!(
            parse_poll_response(429, Some(7), b"").unwrap(),
            AmtPollOutcome::RateLimited { retry_after_secs: 7 }
        );
        assert_eq!(
            parse_poll_response(429, None, b"").unwrap(),
            AmtPollOutcome::RateLimited { retry_after_secs: 2 }
        );
        let signed = parse_poll_response(
            201,
            None,
            br#"{"access":"a","refresh":"r","expiresIn":900,"account":{"id":"u1","callsign":"N9HO","displayName":"Justin"}}"#,
        )
        .unwrap();
        match signed {
            AmtPollOutcome::SignedIn(t) => {
                assert_eq!(t.access, "a");
                assert_eq!(t.refresh, "r");
                assert_eq!(t.expires_in, 900);
                let acct = t.account.unwrap();
                assert_eq!(acct.id, "u1");
                assert_eq!(acct.callsign.as_deref(), Some("N9HO"));
            }
            other => panic!("unexpected {other:?}"),
        }
        assert!(matches!(
            parse_poll_response(400, None, br#"{"error":"invalid_verifier","message":"x"}"#),
            Err(AmtError::InvalidVerifier)
        ));
        match parse_poll_response(500, None, br#"{"error":"internal","message":"boom"}"#) {
            Err(AmtError::Api { status: 500, code, message }) => {
                assert_eq!(code, "internal");
                assert_eq!(message, "boom");
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn stats_parse_full_shape_and_tolerate_missing_fields() {
        let json = r#"{
          "totals": {"sessions": 12, "answered": 300, "correct": 270, "accuracy": 0.9, "practiceSeconds": 3600.5},
          "bestTtrMs": 410,
          "personalBests": {"rapidFire": 42, "invaders": 0},
          "streak": {"current": 3, "longest": 9, "lastPractisedDay": "2026-10-06"},
          "perMode": {"characters": {"sessions": 5, "answered": 100, "correct": 95, "accuracy": 0.95, "medianTtrMs": 520, "lastDate": 1759700000000}},
          "perCharacter": {"K": {"attempts": 20, "correct": 19, "accuracy": 0.95, "medianTtrMs": 480}},
          "activity": {"days": {"2026-10-06": 600, "2026-10-05": 120.5}, "level": {"2026-10-06": 2, "2026-10-05": 1}, "levelThresholds": [1, 300, 900, 1800]},
          "updatedAt": 1759750000000,
          "someFutureField": true
        }"#;
        let stats: AmtStats = serde_json::from_str(json).unwrap();
        assert_eq!(stats.totals.sessions, 12);
        assert_eq!(stats.totals.accuracy, Some(0.9));
        assert_eq!(stats.best_ttr_ms, Some(410));
        assert_eq!(stats.personal_bests["invaders"], 0);
        assert_eq!(stats.streak.current, 3);
        assert_eq!(stats.streak.longest, 9);
        assert_eq!(stats.streak.last_practised_day.as_deref(), Some("2026-10-06"));
        assert_eq!(stats.per_mode["characters"].median_ttr_ms, Some(520));
        assert_eq!(stats.per_character["K"].attempts, 20);
        assert_eq!(stats.activity.days["2026-10-05"], 120.5);
        assert_eq!(stats.activity.level["2026-10-06"], 2);
        assert_eq!(stats.activity.level_thresholds, vec![1, 300, 900, 1800]);
        assert_eq!(stats.updated_at, 1759750000000);

        // A fresh account before the AMT apps sync: zeros and nulls everywhere.
        let zeros: AmtStats = serde_json::from_str(
            r#"{"totals":{"sessions":0,"answered":0,"correct":0,"accuracy":null,"practiceSeconds":0},"bestTtrMs":null,"personalBests":{},"streak":{"current":0,"longest":0,"lastPractisedDay":null},"perMode":{},"perCharacter":{},"activity":{"days":{},"level":{},"levelThresholds":[1,300,900,1800]},"updatedAt":0}"#,
        )
        .unwrap();
        assert_eq!(zeros.totals.accuracy, None);
        assert_eq!(zeros.streak.current, 0);
        assert!(zeros.activity.days.is_empty());
        // And an entirely empty object still parses.
        let empty: AmtStats = serde_json::from_str("{}").unwrap();
        assert_eq!(empty, AmtStats::default());
    }

    #[test]
    fn api_error_falls_back_to_body_text() {
        match api_error(502, b"<html>bad gateway</html>") {
            AmtError::Api { status, code, message } => {
                assert_eq!(status, 502);
                assert_eq!(code, "");
                assert_eq!(message, "<html>bad gateway</html>");
            }
            other => panic!("unexpected {other:?}"),
        }
    }
}
