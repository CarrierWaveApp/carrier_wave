//! Another Morse Trainer (AMT) stats surface — email-link sign-in, token
//! lifecycle and the read-only `/v1/me/stats` fetch, shared by Swift and
//! Kotlin. Wraps `cw_net::AmtClient`; **secret storage is delegated to the
//! host** via the same [`SecureStore`] trait the Carrier Wave OAuth client
//! uses (iOS/macOS Keychain, Android `EncryptedSharedPreferences`).
//!
//! What lives where:
//! - the 15-minute access token: in memory only;
//! - the rotating 60-day refresh token, the signed-in account, and the
//!   in-flight PKCE verifier/poll token: in the host secure store so sign-in
//!   survives relaunch;
//! - the last fetched stats (streak, totals, activity calendar): in the host
//!   secure store too, so the dashboard can show the streak offline and the
//!   three apps don't each need their own cache.
//!
//! Every refresh rotates the token and presenting an old one signs the device
//! out, so refreshes are single-flighted and the new refresh token is saved
//! before the new access token is used.

use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use chrono::Utc;
use cw_net::{
    amt_pkce_challenge, generate_amt_verifier, AmtAccount, AmtClient, AmtError, AmtPollOutcome,
    AmtStats, AmtTokens, HttpClient, AMT_BASE_URL,
};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex as AsyncMutex;

use crate::auth_api::{poll_error_is_transient, SecureStore};
use crate::CwError;

// Secure-store keys, namespaced away from the Carrier Wave OAuth keys.
const KEY_REFRESH: &str = "cw.amt.refresh";
const KEY_ACCOUNT: &str = "cw.amt.account";
const KEY_STATS: &str = "cw.amt.stats";
const KEY_PENDING_VERIFIER: &str = "cw.amt.pending.verifier";
const KEY_PENDING_POLL_TOKEN: &str = "cw.amt.pending.pollToken";
const KEY_PENDING_EMAIL: &str = "cw.amt.pending.email";

/// Refresh the access token once it has less than this many seconds left.
const ACCESS_REFRESH_SKEW_SECS: i64 = 30;

/// The contract's poll cadence: once per 2 s per sign-in.
const POLL_INTERVAL_SECS: u64 = 2;

impl From<AmtError> for CwError {
    fn from(err: AmtError) -> Self {
        match err {
            AmtError::Http(http) => CwError::Network { reason: http.to_string() },
            AmtError::Unauthorized => CwError::Auth { reason: "AMT access token rejected".into() },
            AmtError::SessionExpired => CwError::Auth {
                reason: "AMT session ended; sign in to Another Morse Trainer again".into(),
            },
            AmtError::InvalidVerifier => CwError::Auth { reason: "AMT sign-in verifier mismatch".into() },
            AmtError::Api { status, code, message } => {
                let reason = if message.is_empty() {
                    format!("AMT HTTP {status} {code}")
                } else {
                    format!("AMT HTTP {status} {code}: {message}")
                };
                if status == 401 || status == 403 {
                    CwError::Auth { reason }
                } else {
                    CwError::Network { reason }
                }
            }
        }
    }
}

/// The signed-in AMT account (`GET /v1/me` subset carried in the poll body).
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FfiAmtAccount {
    pub id: String,
    pub callsign: Option<String>,
    pub display_name: Option<String>,
}

impl From<AmtAccount> for FfiAmtAccount {
    fn from(a: AmtAccount) -> Self {
        FfiAmtAccount { id: a.id, callsign: a.callsign, display_name: a.display_name }
    }
}

/// AMT practice streak.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct FfiAmtStreak {
    /// Consecutive practice days ending today or yesterday (local calendar).
    pub current: i64,
    /// Longest run in the last 400 days.
    pub longest: i64,
    /// Newest practice day, `yyyy-mm-dd`.
    pub last_practised_day: Option<String>,
}

/// One practice day on the activity calendar.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FfiAmtActivityDay {
    /// Local calendar day, `yyyy-mm-dd`.
    pub day: String,
    /// Practice seconds that day, summed across the user's devices.
    pub seconds: f64,
    /// Calendar tile shade 1–4 (a recorded day is never 0).
    pub level: i64,
}

/// Per-mode summary (`perMode[mode]`), keyed by AMT's mode id. Unknown ids are
/// passed through as-is; new modes may appear.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FfiAmtModeStats {
    pub mode: String,
    pub sessions: i64,
    pub answered: i64,
    pub correct: i64,
    pub accuracy: Option<f64>,
    pub median_ttr_ms: Option<i64>,
    /// Newest session of that mode, epoch ms.
    pub last_date: i64,
    /// The user's best score in this mode, if any (`personalBests[mode]`).
    pub personal_best: Option<i64>,
}

/// The stats the apps display: totals, streak, activity calendar, per-mode.
/// Also the shape persisted as the offline cache.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct FfiAmtStats {
    pub sessions: i64,
    pub answered: i64,
    pub correct: i64,
    /// `correct / answered`, 0–1; `None` when nothing was answered.
    pub accuracy: Option<f64>,
    pub practice_seconds: f64,
    /// Fastest single recognition ever, ms.
    pub best_ttr_ms: Option<i64>,
    pub streak: FfiAmtStreak,
    /// Practice days, ascending by day.
    pub activity: Vec<FfiAmtActivityDay>,
    /// Seconds at which levels 1–4 begin, e.g. `[1, 300, 900, 1800]`.
    pub level_thresholds: Vec<i64>,
    pub per_mode: Vec<FfiAmtModeStats>,
    /// When the stats last changed server-side, epoch ms.
    pub updated_at: i64,
    /// When this snapshot was fetched, unix seconds.
    pub fetched_at: i64,
}

impl FfiAmtStats {
    fn from_wire(stats: AmtStats, fetched_at: i64) -> Self {
        let activity = stats
            .activity
            .days
            .iter()
            .map(|(day, seconds)| FfiAmtActivityDay {
                day: day.clone(),
                seconds: *seconds,
                level: stats.activity.level.get(day).copied().unwrap_or(1).max(1),
            })
            .collect();
        let per_mode = stats
            .per_mode
            .into_iter()
            .map(|(mode, m)| FfiAmtModeStats {
                personal_best: stats.personal_bests.get(&mode).copied(),
                mode,
                sessions: m.sessions,
                answered: m.answered,
                correct: m.correct,
                accuracy: m.accuracy,
                median_ttr_ms: m.median_ttr_ms,
                last_date: m.last_date,
            })
            .collect();
        FfiAmtStats {
            sessions: stats.totals.sessions,
            answered: stats.totals.answered,
            correct: stats.totals.correct,
            accuracy: stats.totals.accuracy,
            practice_seconds: stats.totals.practice_seconds,
            best_ttr_ms: stats.best_ttr_ms,
            streak: FfiAmtStreak {
                current: stats.streak.current,
                longest: stats.streak.longest,
                last_practised_day: stats.streak.last_practised_day,
            },
            activity,
            level_thresholds: stats.activity.level_thresholds,
            per_mode,
            updated_at: stats.updated_at,
            fetched_at,
        }
    }
}

/// Result of polling an AMT sign-in to completion.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiAmtSignInOutcome {
    /// The user pressed Confirm — tokens issued, the device has a session.
    SignedIn,
    /// Nobody confirmed before the deadline; the link may still be live.
    TimedOut,
    /// The link expired (15 min) or was already used — offer "send another link".
    LinkExpired,
}

/// Async AMT client bound to a [`SecureStore`].
#[derive(uniffi::Object)]
pub struct AmtApi {
    client: AmtClient,
    secure: Arc<dyn SecureStore>,
    platform: String,
    device_name: Option<String>,
    /// In-memory access token + its unix-seconds expiry. Never persisted.
    access: StdMutex<Option<(String, i64)>>,
    /// Single-flight guard: concurrent callers share one refresh rotation
    /// instead of racing (a race counts as reuse and signs the device out).
    refresh_guard: AsyncMutex<()>,
}

#[uniffi::export]
impl AmtApi {
    /// Build a client against the production AMT service. `platform`
    /// (`"ios"`, `"macos"`, `"android"`) and `device_name` appear in the
    /// sign-in email and the user's AMT devices list.
    #[uniffi::constructor]
    pub fn new(
        secure: Arc<dyn SecureStore>,
        platform: String,
        device_name: Option<String>,
    ) -> Result<Self, CwError> {
        Self::with_base_url(secure, AMT_BASE_URL.into(), platform, device_name)
    }

    /// Build a client against a non-production `base_url` (tests / staging).
    #[uniffi::constructor]
    pub fn with_base_url(
        secure: Arc<dyn SecureStore>,
        base_url: String,
        platform: String,
        device_name: Option<String>,
    ) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(AmtApi {
            client: AmtClient::new(http, base_url),
            secure,
            platform,
            device_name,
            access: StdMutex::new(None),
            refresh_guard: AsyncMutex::new(()),
        })
    }

    /// Whether a refresh token is stored (the device is signed in to AMT).
    pub fn has_session(&self) -> bool {
        self.secure.get(KEY_REFRESH.into()).is_some()
    }

    /// The signed-in account, if any.
    pub fn account(&self) -> Option<FfiAmtAccount> {
        self.secure
            .get(KEY_ACCOUNT.into())
            .and_then(|json| serde_json::from_str(&json).ok())
    }

    /// Whether a sign-in is in flight (link emailed, not yet confirmed).
    pub fn has_pending_sign_in(&self) -> bool {
        self.secure.get(KEY_PENDING_POLL_TOKEN.into()).is_some()
    }

    /// The email address of the in-flight sign-in, for UI display.
    pub fn pending_email(&self) -> Option<String> {
        self.secure.get(KEY_PENDING_EMAIL.into())
    }

    /// Abandon the in-flight sign-in (user cancelled).
    pub fn cancel_pending_sign_in(&self) {
        self.clear_pending();
    }

    /// The last fetched stats, if any — present offline and across relaunch.
    pub fn cached_stats(&self) -> Option<FfiAmtStats> {
        self.secure
            .get(KEY_STATS.into())
            .and_then(|json| serde_json::from_str(&json).ok())
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl AmtApi {
    /// Step 1: ask AMT to email `email` a sign-in link, generating and persisting
    /// the PKCE verifier and poll token so completion survives relaunch. AMT
    /// always accepts, whether or not the address has an account.
    pub async fn start_sign_in(&self, email: String) -> Result<(), CwError> {
        let email = email.trim().to_string();
        if email.is_empty() {
            return Err(CwError::Auth { reason: "email is required".into() });
        }
        let verifier = generate_amt_verifier();
        let challenge = amt_pkce_challenge(&verifier);
        let poll_token = self
            .client
            .start_sign_in(&email, &challenge, self.device_name.as_deref(), Some(&self.platform))
            .await?;
        self.secure.set(KEY_PENDING_VERIFIER.into(), verifier);
        self.secure.set(KEY_PENDING_POLL_TOKEN.into(), poll_token);
        self.secure.set(KEY_PENDING_EMAIL.into(), email);
        Ok(())
    }

    /// Poll (every 2 s, honouring `Retry-After`) until the user presses Confirm,
    /// then persist the issued tokens and account. Returns `TimedOut` if the
    /// deadline passes first — the pending sign-in is kept so the caller can
    /// poll again — and `LinkExpired` when AMT says the link is dead.
    pub async fn poll_for_completion(&self, timeout_secs: u32) -> Result<FfiAmtSignInOutcome, CwError> {
        let poll_token = self
            .secure
            .get(KEY_PENDING_POLL_TOKEN.into())
            .ok_or_else(|| CwError::Auth { reason: "no pending AMT sign-in".into() })?;
        let verifier = self
            .secure
            .get(KEY_PENDING_VERIFIER.into())
            .ok_or_else(|| CwError::Auth { reason: "no pending AMT sign-in".into() })?;

        let deadline = Utc::now().timestamp() + i64::from(timeout_secs);
        loop {
            // The contract is "once per 2 s"; sleep first so an immediate
            // re-poll after a relaunch can't trip the limiter.
            let mut wait = POLL_INTERVAL_SECS;
            match self.client.poll(&poll_token, &verifier).await {
                Ok(AmtPollOutcome::SignedIn(tokens)) => {
                    self.persist(&tokens);
                    self.clear_pending();
                    return Ok(FfiAmtSignInOutcome::SignedIn);
                }
                Ok(AmtPollOutcome::Expired) => {
                    self.clear_pending();
                    return Ok(FfiAmtSignInOutcome::LinkExpired);
                }
                Ok(AmtPollOutcome::RateLimited { retry_after_secs }) => {
                    wait = retry_after_secs.max(POLL_INTERVAL_SECS);
                }
                Ok(AmtPollOutcome::Pending) => {}
                // A mismatched verifier is our bug; nothing will change by polling.
                Err(AmtError::InvalidVerifier) => {
                    self.clear_pending();
                    return Err(AmtError::InvalidVerifier.into());
                }
                // Transport blips and 5xx are expected while the user is out of
                // the app reading email — keep polling until the deadline.
                Err(AmtError::Http(http)) if poll_error_is_transient(&http) => {}
                Err(AmtError::Api { status, .. }) if status >= 500 => {}
                Err(err) => return Err(err.into()),
            }
            if Utc::now().timestamp() >= deadline {
                return Ok(FfiAmtSignInOutcome::TimedOut);
            }
            tokio::time::sleep(Duration::from_secs(wait)).await;
        }
    }

    /// Fetch `/v1/me/stats` with one refresh-and-retry on 401, persist the
    /// snapshot as the offline cache, and return it. `today` is the user's
    /// *local* calendar date (`yyyy-mm-dd`) so the current streak is exact.
    /// Errors with [`CwError::Auth`] once the session is gone (the user removed
    /// Carrier Wave in AMT); the local session is cleared in that case.
    pub async fn refresh_stats(&self, today: String) -> Result<FfiAmtStats, CwError> {
        let today = today.trim();
        let today = (!today.is_empty()).then_some(today);
        let access = self.valid_access_token().await?;
        let stats = match self.client.stats(&access, today).await {
            Ok(stats) => stats,
            Err(AmtError::Unauthorized) => {
                // The server rejected a token we still thought valid: forget
                // it so the single-flight refresh can't hand it back.
                self.invalidate_access();
                let access = self.force_refresh().await?;
                self.client.stats(&access, today).await?
            }
            Err(err) => return Err(err.into()),
        };
        let snapshot = FfiAmtStats::from_wire(stats, Utc::now().timestamp());
        if let Ok(json) = serde_json::to_string(&snapshot) {
            self.secure.set(KEY_STATS.into(), json);
        }
        Ok(snapshot)
    }

    /// A currently valid access token, refreshing if expired or absent.
    /// Errors with [`CwError::Auth`] when there is no session.
    pub async fn valid_access_token(&self) -> Result<String, CwError> {
        if let Some(token) = self.cached_access() {
            return Ok(token);
        }
        self.force_refresh().await
    }

    /// Sign out: `POST /v1/auth/logout` (best effort), then delete tokens,
    /// account and the cached stats.
    pub async fn sign_out(&self) -> Result<(), CwError> {
        if self.has_session() {
            // Best-effort: a network failure must not block local sign-out, and
            // the server invalidates tokens the moment the device is removed.
            if let Ok(access) = self.valid_access_token().await {
                let _ = self.client.logout(&access).await;
            }
        }
        self.clear_session();
        self.clear_pending();
        Ok(())
    }
}

impl AmtApi {
    fn cached_access(&self) -> Option<String> {
        let guard = self.access.lock().expect("access mutex poisoned");
        match &*guard {
            Some((token, expiry)) if *expiry - Utc::now().timestamp() > ACCESS_REFRESH_SKEW_SECS => {
                Some(token.clone())
            }
            _ => None,
        }
    }

    /// Single-flight rotation. The re-check after taking the guard means a
    /// caller queued behind an in-progress refresh reuses its result.
    async fn force_refresh(&self) -> Result<String, CwError> {
        let _guard = self.refresh_guard.lock().await;
        if let Some(token) = self.cached_access() {
            return Ok(token);
        }
        let refresh_token = self
            .secure
            .get(KEY_REFRESH.into())
            .ok_or_else(|| CwError::Auth { reason: "not signed in to Another Morse Trainer".into() })?;
        match self.client.refresh(&refresh_token).await {
            Ok(tokens) => {
                let access = tokens.access.clone();
                self.persist(&tokens);
                Ok(access)
            }
            Err(AmtError::SessionExpired) => {
                // The user removed Carrier Wave from their AMT devices (or the
                // token leaked). Drop the session so the UI prompts a sign-in.
                self.clear_session();
                Err(AmtError::SessionExpired.into())
            }
            Err(other) => Err(other.into()),
        }
    }

    /// Save the rotated refresh token *first*, then the account, then cache the
    /// access token — the order the contract requires.
    fn persist(&self, tokens: &AmtTokens) {
        self.secure.set(KEY_REFRESH.into(), tokens.refresh.clone());
        if let Some(account) = &tokens.account {
            let ffi: FfiAmtAccount = account.clone().into();
            if let Ok(json) = serde_json::to_string(&ffi) {
                self.secure.set(KEY_ACCOUNT.into(), json);
            }
        }
        let expiry = Utc::now().timestamp() + tokens.expires_in;
        *self.access.lock().expect("access mutex poisoned") = Some((tokens.access.clone(), expiry));
    }

    fn invalidate_access(&self) {
        *self.access.lock().expect("access mutex poisoned") = None;
    }

    fn clear_session(&self) {
        self.invalidate_access();
        self.secure.delete(KEY_REFRESH.into());
        self.secure.delete(KEY_ACCOUNT.into());
        self.secure.delete(KEY_STATS.into());
    }

    fn clear_pending(&self) {
        self.secure.delete(KEY_PENDING_VERIFIER.into());
        self.secure.delete(KEY_PENDING_POLL_TOKEN.into());
        self.secure.delete(KEY_PENDING_EMAIL.into());
    }
}


#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;
    use wiremock::matchers::{body_partial_json, header, method, path, query_param};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    struct MemStore {
        map: Mutex<HashMap<String, String>>,
    }

    impl SecureStore for MemStore {
        fn get(&self, key: String) -> Option<String> {
            self.map.lock().unwrap().get(&key).cloned()
        }
        fn set(&self, key: String, value: String) {
            self.map.lock().unwrap().insert(key, value);
        }
        fn delete(&self, key: String) {
            self.map.lock().unwrap().remove(&key);
        }
    }

    fn api(base_url: &str) -> (AmtApi, Arc<MemStore>) {
        let store = Arc::new(MemStore { map: Mutex::new(HashMap::new()) });
        let api = AmtApi::with_base_url(store.clone(), base_url.into(), "ios".into(), Some("iPhone".into())).unwrap();
        (api, store)
    }

    fn stats_json(current: i64) -> serde_json::Value {
        serde_json::json!({
            "totals": {"sessions": 4, "answered": 80, "correct": 72, "accuracy": 0.9, "practiceSeconds": 1200.0},
            "bestTtrMs": 390,
            "personalBests": {"rapidFire": 31},
            "streak": {"current": current, "longest": 11, "lastPractisedDay": "2026-10-06"},
            "perMode": {"rapidFire": {"sessions": 2, "answered": 40, "correct": 36, "accuracy": 0.9, "medianTtrMs": 500, "lastDate": 1759750000000i64}},
            "perCharacter": {},
            "activity": {"days": {"2026-10-05": 300.0, "2026-10-06": 900.0}, "level": {"2026-10-05": 2, "2026-10-06": 3}, "levelThresholds": [1, 300, 900, 1800]},
            "updatedAt": 1759750000000i64
        })
    }

    #[test]
    fn stats_conversion_joins_days_levels_and_personal_bests() {
        let wire: AmtStats = serde_json::from_value(stats_json(5)).unwrap();
        let ffi = FfiAmtStats::from_wire(wire, 1_700_000_000);
        assert_eq!(ffi.sessions, 4);
        assert_eq!(ffi.streak.current, 5);
        assert_eq!(ffi.streak.longest, 11);
        assert_eq!(ffi.activity.len(), 2);
        assert_eq!(ffi.activity[0].day, "2026-10-05");
        assert_eq!(ffi.activity[0].level, 2);
        assert_eq!(ffi.activity[1].seconds, 900.0);
        assert_eq!(ffi.level_thresholds, vec![1, 300, 900, 1800]);
        assert_eq!(ffi.per_mode[0].mode, "rapidFire");
        assert_eq!(ffi.per_mode[0].personal_best, Some(31));
        assert_eq!(ffi.fetched_at, 1_700_000_000);
        // Round-trips through the cache encoding.
        let json = serde_json::to_string(&ffi).unwrap();
        let back: FfiAmtStats = serde_json::from_str(&json).unwrap();
        assert_eq!(back, ffi);
    }

    #[test]
    fn missing_level_for_a_recorded_day_is_never_below_one() {
        let wire: AmtStats = serde_json::from_value(serde_json::json!({
            "activity": {"days": {"2026-10-01": 5.0}, "level": {}, "levelThresholds": [1, 300, 900, 1800]}
        }))
        .unwrap();
        let ffi = FfiAmtStats::from_wire(wire, 0);
        assert_eq!(ffi.activity[0].level, 1);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn sign_in_flow_persists_tokens_account_and_clears_pending() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/start"))
            .and(body_partial_json(serde_json::json!({
                "email": "op@example.com", "client": "carrier-wave-ios",
                "scopes": "stats:read", "platform": "ios", "deviceName": "iPhone"
            })))
            .respond_with(ResponseTemplate::new(202).set_body_json(serde_json::json!({"pollToken": "pt-1"})))
            .expect(1)
            .mount(&server)
            .await;
        // First poll: not confirmed yet. Second: signed in.
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .and(body_partial_json(serde_json::json!({"pollToken": "pt-1"})))
            .respond_with(ResponseTemplate::new(202))
            .up_to_n_times(1)
            .expect(1)
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
                "access": "acc-1", "refresh": "ref-1", "expiresIn": 900,
                "account": {"id": "u-1", "callsign": "N9HO", "displayName": "Justin"}
            })))
            .expect(1)
            .mount(&server)
            .await;

        let (api, store) = api(&server.uri());
        api.start_sign_in(" op@example.com ".into()).await.unwrap();
        assert!(api.has_pending_sign_in());
        assert_eq!(api.pending_email().as_deref(), Some("op@example.com"));
        assert!(!api.has_session());

        let outcome = api.poll_for_completion(30).await.unwrap();
        assert_eq!(outcome, FfiAmtSignInOutcome::SignedIn);
        assert!(api.has_session());
        assert!(!api.has_pending_sign_in());
        assert_eq!(store.get(KEY_REFRESH.into()).as_deref(), Some("ref-1"));
        let account = api.account().unwrap();
        assert_eq!(account.id, "u-1");
        assert_eq!(account.callsign.as_deref(), Some("N9HO"));
        assert_eq!(api.cached_access().as_deref(), Some("acc-1"));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn expired_link_ends_the_sign_in() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .respond_with(ResponseTemplate::new(410).set_body_json(serde_json::json!({"error": "expired", "message": "gone"})))
            .mount(&server)
            .await;
        let (api, store) = api(&server.uri());
        store.set(KEY_PENDING_POLL_TOKEN.into(), "pt".into());
        store.set(KEY_PENDING_VERIFIER.into(), "v".into());
        store.set(KEY_PENDING_EMAIL.into(), "e".into());
        assert_eq!(api.poll_for_completion(10).await.unwrap(), FfiAmtSignInOutcome::LinkExpired);
        assert!(!api.has_pending_sign_in());
        assert!(!api.has_session());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn refresh_stats_rotates_token_on_401_and_caches_snapshot() {
        let server = MockServer::start().await;
        // The first stats call with the stale access token is rejected.
        Mock::given(method("GET"))
            .and(path("/v1/me/stats"))
            .and(header("authorization", "Bearer stale"))
            .respond_with(ResponseTemplate::new(401).set_body_json(serde_json::json!({"error": "unauthorized", "message": "x"})))
            .expect(1)
            .mount(&server)
            .await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/token/refresh"))
            .and(body_partial_json(serde_json::json!({"refresh": "ref-old"})))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "access": "acc-new", "refresh": "ref-new", "expiresIn": 900
            })))
            .expect(1)
            .mount(&server)
            .await;
        Mock::given(method("GET"))
            .and(path("/v1/me/stats"))
            .and(query_param("today", "2026-10-06"))
            .and(header("authorization", "Bearer acc-new"))
            .respond_with(ResponseTemplate::new(200).set_body_json(stats_json(7)))
            .expect(1)
            .mount(&server)
            .await;

        let (api, store) = api(&server.uri());
        store.set(KEY_REFRESH.into(), "ref-old".into());
        // A still-"valid" but server-rejected access token in memory.
        *api.access.lock().unwrap() = Some(("stale".into(), Utc::now().timestamp() + 600));

        let stats = api.refresh_stats("2026-10-06".into()).await.unwrap();
        assert_eq!(stats.streak.current, 7);
        assert_eq!(store.get(KEY_REFRESH.into()).as_deref(), Some("ref-new"), "rotated token saved");
        assert_eq!(api.cached_access().as_deref(), Some("acc-new"));
        let cached = api.cached_stats().expect("snapshot cached");
        assert_eq!(cached.streak.current, 7);
        assert_eq!(cached.activity.len(), 2);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn rejected_refresh_signs_out_locally() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/token/refresh"))
            .respond_with(ResponseTemplate::new(401).set_body_json(serde_json::json!({"error": "unauthorized", "message": "removed"})))
            .mount(&server)
            .await;
        let (api, store) = api(&server.uri());
        store.set(KEY_REFRESH.into(), "ref-dead".into());
        store.set(KEY_ACCOUNT.into(), r#"{"id":"u","callsign":null,"display_name":null}"#.into());
        store.set(KEY_STATS.into(), "{}".into());

        let err = api.refresh_stats("2026-10-06".into()).await.unwrap_err();
        assert!(matches!(err, CwError::Auth { .. }), "got {err:?}");
        assert!(!api.has_session());
        assert!(api.account().is_none());
        assert!(api.cached_stats().is_none());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn sign_out_calls_logout_and_clears_everything() {
        let server = MockServer::start().await;
        Mock::given(method("POST"))
            .and(path("/v1/auth/logout"))
            .and(header("authorization", "Bearer acc"))
            .respond_with(ResponseTemplate::new(204))
            .expect(1)
            .mount(&server)
            .await;
        let (api, store) = api(&server.uri());
        store.set(KEY_REFRESH.into(), "ref".into());
        store.set(KEY_STATS.into(), "{}".into());
        *api.access.lock().unwrap() = Some(("acc".into(), Utc::now().timestamp() + 600));

        api.sign_out().await.unwrap();
        assert!(!api.has_session());
        assert!(store.get(KEY_STATS.into()).is_none());
        assert_eq!(api.cached_access(), None);
    }
}
