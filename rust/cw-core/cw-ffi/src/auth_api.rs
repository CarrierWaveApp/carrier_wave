//! Async OAuth surface — PKCE magic-link login + token lifecycle, shared by
//! Swift and Kotlin. Ports `OAuthClient.swift`: the protocol/state machine lives
//! in Rust, while **secret storage is delegated to the host** via the
//! [`SecureStore`] foreign trait (iOS Keychain / Android
//! `EncryptedSharedPreferences`). The short-lived access token is held only in
//! memory here; the rotating refresh token and the in-flight verification state
//! live in the host's secure store so they survive relaunch.
//!
//! Concurrency mirrors the Swift actor: refreshes are single-flighted (a tokio
//! mutex) so concurrent callers share one rotation instead of triggering the
//! server's refresh-reuse family revoke.

use std::sync::{Arc, Mutex as StdMutex};
use std::time::Duration;

use chrono::Utc;
use cw_net::{
    generate_verifier, pkce_challenge, AuthClient, AuthError, HttpClient, HttpError, PollOutcome,
};
use tokio::sync::Mutex as AsyncMutex;

use crate::CwError;

// Secure-store keys. Namespaced so they don't collide with other host data.
const KEY_REFRESH: &str = "cw.oauth.refresh";
const KEY_ACCOUNT_ID: &str = "cw.oauth.accountId";
const KEY_PENDING_VERIFIER: &str = "cw.oauth.pending.verifier";
const KEY_PENDING_POLL_TOKEN: &str = "cw.oauth.pending.pollToken";
const KEY_PENDING_CALLSIGN: &str = "cw.oauth.pending.callsign";

/// Refresh the access token once it has less than this many seconds left.
const ACCESS_REFRESH_SKEW_SECS: i64 = 30;

/// Deep-link completion (`complete_from_link`) polls briefly — the code was just
/// marked clicked, so success is near-immediate; the window only rides out a
/// transient network blip.
const POLL_FROM_LINK_TIMEOUT_SECS: u32 = 20;
const POLL_FROM_LINK_INTERVAL_SECS: u32 = 2;

impl From<AuthError> for CwError {
    fn from(err: AuthError) -> Self {
        match err {
            AuthError::Http(http) => CwError::Network { reason: http.to_string() },
            AuthError::SessionExpired => {
                CwError::Auth { reason: "session expired; sign in again".into() }
            }
        }
    }
}

/// Whether a failed magic-link poll should be retried within the deadline rather
/// than aborting the whole sign-in. The poll runs while the user is out of the
/// app opening the emailed link, so a torn-down socket or a transient server
/// hiccup is expected — only a genuine client-side rejection is fatal.
pub(crate) fn poll_error_is_transient(err: &HttpError) -> bool {
    match err {
        // Transport failure (DNS/TLS/connect/send/timeout). This is the reported
        // "error sending request for url …/verify/poll" that surfaces when
        // Android freezes the process/socket during backgrounding.
        HttpError::Network(_) => true,
        // Server-side error — worth another poll before giving up.
        HttpError::Http { status, .. } => *status >= 500,
        // Malformed response, bad URL, non-UTF-8, etc. won't fix themselves.
        _ => false,
    }
}

/// Host-provided secure key/value storage (Keychain / EncryptedSharedPreferences).
/// Values are small secrets (tokens, the in-flight PKCE verifier). Implementations
/// must be thread-safe.
#[uniffi::export(with_foreign)]
pub trait SecureStore: Send + Sync {
    fn get(&self, key: String) -> Option<String>;
    fn set(&self, key: String, value: String);
    fn delete(&self, key: String);
}

/// Result of polling a magic-link verification to completion.
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiAuthOutcome {
    /// New account onboarded — tokens issued, the device now has a session.
    SignedIn,
    /// The callsign was attached to an existing account — no new tokens here.
    AttachedToAccount,
    /// The magic link wasn't clicked before the timeout.
    TimedOut,
}

/// Result of completing sign-in from a tapped magic link (`complete_from_link`).
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiLinkOutcome {
    /// New account onboarded on this device — tokens issued.
    SignedIn,
    /// The callsign was attached to an existing account.
    AttachedToAccount,
    /// The link was marked clicked, but this device didn't start the sign-in
    /// (no pending verification here) — the originating device's poll completes.
    AcknowledgedRemotely,
    /// The link was invalid/expired, or completion didn't finish in time.
    NotCompleted,
}

/// Async OAuth client bound to a [`SecureStore`] and an activities-server base URL.
#[derive(uniffi::Object)]
pub struct AuthApi {
    client: AuthClient,
    secure: Arc<dyn SecureStore>,
    platform: String,
    device_name: Option<String>,
    /// In-memory access token + its unix-seconds expiry. Never persisted.
    access: StdMutex<Option<(String, i64)>>,
    /// Single-flight guard so concurrent `valid_access_token` callers share one
    /// refresh rotation.
    refresh_guard: AsyncMutex<()>,
}

#[uniffi::export]
impl AuthApi {
    /// Build an OAuth client against `base_url`, persisting secrets through
    /// `secure`. `platform` (e.g. `"android"`) and `device_name` are reported to
    /// the server for the device list.
    #[uniffi::constructor]
    pub fn new(
        secure: Arc<dyn SecureStore>,
        base_url: String,
        platform: String,
        device_name: Option<String>,
    ) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(AuthApi {
            client: AuthClient::new(http, base_url),
            secure,
            platform,
            device_name,
            access: StdMutex::new(None),
            refresh_guard: AsyncMutex::new(()),
        })
    }

    /// Whether a refresh token is stored (the device has a session).
    pub fn has_session(&self) -> bool {
        self.secure.get(KEY_REFRESH.into()).is_some()
    }

    /// The account id from the last successful exchange, if any.
    pub fn account_id(&self) -> Option<String> {
        self.secure.get(KEY_ACCOUNT_ID.into())
    }

    /// Whether a magic-link verification is in flight (started, not completed).
    pub fn has_pending_verification(&self) -> bool {
        self.secure.get(KEY_PENDING_VERIFIER.into()).is_some()
    }

    /// The callsign of the in-flight verification, for UI display.
    pub fn pending_callsign(&self) -> Option<String> {
        self.secure.get(KEY_PENDING_CALLSIGN.into())
    }

    /// Abandon the in-flight verification (user cancelled).
    pub fn cancel_pending_verification(&self) {
        self.clear_pending();
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl AuthApi {
    /// Step 1: request a magic link for `callsign`, generating + persisting the
    /// PKCE verifier and poll token so completion survives relaunch. `email` is a
    /// fallback used only when the directory has no on-file address.
    pub async fn start_verification(
        &self,
        callsign: String,
        email: Option<String>,
    ) -> Result<(), CwError> {
        let verifier = generate_verifier();
        let challenge = pkce_challenge(&verifier);
        let poll_token = self
            .client
            .verify_start(&callsign, email.as_deref(), &challenge)
            .await?;
        self.secure.set(KEY_PENDING_VERIFIER.into(), verifier);
        self.secure.set(KEY_PENDING_POLL_TOKEN.into(), poll_token);
        self.secure.set(KEY_PENDING_CALLSIGN.into(), callsign);
        Ok(())
    }

    /// Poll until the magic link is clicked, then persist the issued tokens.
    /// Returns [`FfiAuthOutcome::TimedOut`] if the deadline passes first.
    pub async fn poll_for_completion(
        &self,
        timeout_secs: u32,
        interval_secs: u32,
    ) -> Result<FfiAuthOutcome, CwError> {
        let poll_token = self
            .secure
            .get(KEY_PENDING_POLL_TOKEN.into())
            .ok_or_else(|| CwError::Auth { reason: "no pending verification".into() })?;
        let verifier = self
            .secure
            .get(KEY_PENDING_VERIFIER.into())
            .ok_or_else(|| CwError::Auth { reason: "no pending verification".into() })?;

        let deadline = Utc::now().timestamp() + i64::from(timeout_secs);
        loop {
            match self
                .client
                .verify_poll(
                    &poll_token,
                    &verifier,
                    self.device_name.as_deref(),
                    Some(&self.platform),
                )
                .await
            {
                Ok(PollOutcome::Issued(pair)) => {
                    self.persist(&pair);
                    self.clear_pending();
                    return Ok(FfiAuthOutcome::SignedIn);
                }
                Ok(PollOutcome::Attached) => {
                    self.clear_pending();
                    return Ok(FfiAuthOutcome::AttachedToAccount);
                }
                Ok(PollOutcome::Pending) => {
                    if Utc::now().timestamp() >= deadline {
                        return Ok(FfiAuthOutcome::TimedOut);
                    }
                }
                // A transient network blip (e.g. the socket torn down while the
                // user is out of the app opening the emailed link) must NOT end
                // the sign-in — the link may be clicked a moment later. Keep
                // polling until the deadline; surface the error only if it
                // persists that long. Fatal client errors (4xx/parse) abort now.
                Err(err) => {
                    if !poll_error_is_transient(&err) || Utc::now().timestamp() >= deadline {
                        return Err(err.into());
                    }
                }
            }
            tokio::time::sleep(Duration::from_secs(u64::from(interval_secs))).await;
        }
    }

    /// Deep-link return path: the OS handed the app the tapped magic link
    /// (`…/v1/auth/verify/complete?code=…`) instead of a browser.
    ///
    /// First marks the code clicked server-side (what the browser would have
    /// done), so completion can proceed here *or* on the device that started
    /// sign-in. Then, if this device has a pending verification, drives the
    /// normal poll to completion — reusing its issued/attached handling and its
    /// transient-failure resilience. A device without a pending verification
    /// just acknowledges (the originating device's poll finishes the job).
    pub async fn complete_from_link(&self, code: String) -> Result<FfiLinkOutcome, CwError> {
        // Idempotent: a code already redeemed / not-yet-clicked both surface via
        // the poll below; the GET simply sets `consumed_at`.
        self.client.mark_link_clicked(&code).await?;

        if self.secure.get(KEY_PENDING_POLL_TOKEN.into()).is_none() {
            return Ok(FfiLinkOutcome::AcknowledgedRemotely);
        }

        // The code is now clicked, so the first poll should succeed immediately;
        // a short window still absorbs a transient blip.
        match self.poll_for_completion(POLL_FROM_LINK_TIMEOUT_SECS, POLL_FROM_LINK_INTERVAL_SECS).await? {
            FfiAuthOutcome::SignedIn => Ok(FfiLinkOutcome::SignedIn),
            FfiAuthOutcome::AttachedToAccount => Ok(FfiLinkOutcome::AttachedToAccount),
            FfiAuthOutcome::TimedOut => Ok(FfiLinkOutcome::NotCompleted),
        }
    }

    /// Universal-link return path: redeem a clicked verification `code` with the
    /// stored PKCE verifier and persist the resulting tokens.
    pub async fn complete_with_code(&self, code: String) -> Result<(), CwError> {
        let verifier = self
            .secure
            .get(KEY_PENDING_VERIFIER.into())
            .ok_or_else(|| CwError::Auth { reason: "no pending verification".into() })?;
        let pair = self
            .client
            .exchange(&code, &verifier, self.device_name.as_deref(), Some(&self.platform))
            .await?;
        self.persist(&pair);
        self.clear_pending();
        Ok(())
    }

    /// A currently-valid access token, refreshing if expired/absent. Errors with
    /// [`CwError::Auth`] when there is no session.
    pub async fn valid_access_token(&self) -> Result<String, CwError> {
        if let Some(token) = self.cached_access() {
            return Ok(token);
        }
        self.refresh().await
    }

    /// Revoke this device's session (best-effort) and clear all local state.
    pub async fn logout(&self) -> Result<(), CwError> {
        if let Some(refresh) = self.secure.get(KEY_REFRESH.into()) {
            // Best-effort: a network failure shouldn't block local sign-out.
            let _ = self.client.logout(&refresh).await;
        }
        *self.access.lock().expect("access mutex poisoned") = None;
        self.secure.delete(KEY_REFRESH.into());
        self.secure.delete(KEY_ACCOUNT_ID.into());
        Ok(())
    }
}

impl AuthApi {
    /// Return the in-memory access token if it has comfortably more than the skew
    /// window left, else `None`.
    fn cached_access(&self) -> Option<String> {
        let guard = self.access.lock().expect("access mutex poisoned");
        match &*guard {
            Some((token, expiry)) if *expiry - Utc::now().timestamp() > ACCESS_REFRESH_SKEW_SECS => {
                Some(token.clone())
            }
            _ => None,
        }
    }

    /// Single-flight refresh: the guard serializes concurrent callers, and the
    /// re-check after acquiring it means only the first caller hits the network.
    async fn refresh(&self) -> Result<String, CwError> {
        let _guard = self.refresh_guard.lock().await;
        if let Some(token) = self.cached_access() {
            return Ok(token);
        }
        let refresh_token = self
            .secure
            .get(KEY_REFRESH.into())
            .ok_or_else(|| CwError::Auth { reason: "not authenticated".into() })?;
        match self.client.refresh(&refresh_token).await {
            Ok(pair) => {
                let access = pair.access.clone();
                self.persist(&pair);
                Ok(access)
            }
            Err(AuthError::SessionExpired) => {
                // Dead session — drop it so the UI prompts a fresh sign-in.
                *self.access.lock().expect("access mutex poisoned") = None;
                self.secure.delete(KEY_REFRESH.into());
                self.secure.delete(KEY_ACCOUNT_ID.into());
                Err(AuthError::SessionExpired.into())
            }
            Err(other) => Err(other.into()),
        }
    }

    fn persist(&self, pair: &cw_net::TokenPair) {
        self.secure.set(KEY_REFRESH.into(), pair.refresh.clone());
        if let Some(account_id) = &pair.account_id {
            self.secure.set(KEY_ACCOUNT_ID.into(), account_id.clone());
        }
        let expiry = Utc::now().timestamp() + pair.expires_in;
        *self.access.lock().expect("access mutex poisoned") = Some((pair.access.clone(), expiry));
    }

    fn clear_pending(&self) {
        self.secure.delete(KEY_PENDING_VERIFIER.into());
        self.secure.delete(KEY_PENDING_POLL_TOKEN.into());
        self.secure.delete(KEY_PENDING_CALLSIGN.into());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    /// In-memory `SecureStore` for exercising the persistence/cache logic.
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

    fn api() -> (AuthApi, Arc<MemStore>) {
        let store = Arc::new(MemStore { map: Mutex::new(HashMap::new()) });
        let api = AuthApi::new(
            store.clone(),
            "https://example.com".into(),
            "android".into(),
            Some("Pixel".into()),
        )
        .unwrap();
        (api, store)
    }

    #[test]
    fn persist_stores_refresh_and_caches_access() {
        let (api, store) = api();
        let pair = cw_net::TokenPair {
            access: "access-1".into(),
            refresh: "cwr_1".into(),
            expires_in: 900,
            account_id: Some("acct-1".into()),
        };
        api.persist(&pair);

        assert!(api.has_session());
        assert_eq!(store.get(KEY_REFRESH.into()).as_deref(), Some("cwr_1"));
        assert_eq!(api.account_id().as_deref(), Some("acct-1"));
        // Fresh token is returned from cache (well within the skew window).
        assert_eq!(api.cached_access().as_deref(), Some("access-1"));
    }

    #[test]
    fn expired_access_is_not_returned_from_cache() {
        let (api, _store) = api();
        // expires_in negative → already past, even accounting for skew.
        api.persist(&cw_net::TokenPair {
            access: "stale".into(),
            refresh: "cwr_1".into(),
            expires_in: -10,
            account_id: None,
        });
        assert_eq!(api.cached_access(), None, "expired token must force a refresh");
    }

    #[test]
    fn clear_pending_removes_all_pending_keys() {
        let (api, store) = api();
        store.set(KEY_PENDING_VERIFIER.into(), "v".into());
        store.set(KEY_PENDING_POLL_TOKEN.into(), "p".into());
        store.set(KEY_PENDING_CALLSIGN.into(), "W6JY".into());
        assert!(api.has_pending_verification());
        assert_eq!(api.pending_callsign().as_deref(), Some("W6JY"));

        api.cancel_pending_verification();
        assert!(!api.has_pending_verification());
        assert_eq!(store.get(KEY_PENDING_POLL_TOKEN.into()), None);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn transient_poll_errors_are_retried_but_client_errors_abort() {
        // Transport failure — the reported "error sending request for url
        // …/verify/poll" that surfaces when Android freezes the socket during
        // backgrounding. Produced through cw-net's real client (connection
        // refused) so the exact `HttpError::Network` variant is exercised.
        let transport = AuthClient::new(HttpClient::new().unwrap(), "http://127.0.0.1:1")
            .verify_poll("t", "v", None, None)
            .await
            .expect_err("a request to a dead port must be a transport error");
        assert!(matches!(transport, HttpError::Network(_)));
        assert!(poll_error_is_transient(&transport));

        // Server-side 5xx is worth another poll before the deadline.
        assert!(poll_error_is_transient(&HttpError::Http { status: 500, body: String::new() }));
        assert!(poll_error_is_transient(&HttpError::Http { status: 503, body: String::new() }));
        // A genuine client-side rejection won't resolve by retrying.
        assert!(!poll_error_is_transient(&HttpError::Http { status: 400, body: String::new() }));
        assert!(!poll_error_is_transient(&HttpError::Http { status: 403, body: String::new() }));
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn complete_from_link_marks_clicked_then_signs_in() {
        use wiremock::matchers::{method, path, query_param};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let server = MockServer::start().await;
        // The deep-link path must hit GET /verify/complete (mark clicked) with
        // the code from the tapped link.
        Mock::given(method("GET"))
            .and(path("/v1/auth/verify/complete"))
            .and(query_param("code", "code-xyz"))
            .respond_with(ResponseTemplate::new(200).set_body_string("<html>ok</html>"))
            .expect(1)
            .mount(&server)
            .await;
        // Then the reused poll completes now that the code is clicked.
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
                "access": "acc-1",
                "refresh": "cwr_1",
                "expiresIn": 900,
                "accountId": "acct-1",
            })))
            .mount(&server)
            .await;

        let store = Arc::new(MemStore { map: Mutex::new(HashMap::new()) });
        store.set(KEY_PENDING_POLL_TOKEN.into(), "poll-tok".into());
        store.set(KEY_PENDING_VERIFIER.into(), "verifier".into());
        let api =
            AuthApi::new(store, server.uri(), "android".into(), Some("Pixel".into())).unwrap();

        let outcome = api.complete_from_link("code-xyz".into()).await.unwrap();
        assert_eq!(outcome, FfiLinkOutcome::SignedIn);
        assert!(api.has_session());
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn complete_from_link_without_local_verification_acknowledges() {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let server = MockServer::start().await;
        // A device that didn't start sign-in still marks the link clicked so the
        // originating device's poll can finish — but it must NOT poll itself.
        Mock::given(method("GET"))
            .and(path("/v1/auth/verify/complete"))
            .respond_with(ResponseTemplate::new(200).set_body_string("ok"))
            .expect(1)
            .mount(&server)
            .await;
        let poll_guard = Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .respond_with(ResponseTemplate::new(201))
            .expect(0)
            .mount_as_scoped(&server)
            .await;

        let store = Arc::new(MemStore { map: Mutex::new(HashMap::new()) });
        // No KEY_PENDING_POLL_TOKEN — this device never started verification.
        let api =
            AuthApi::new(store, server.uri(), "android".into(), Some("Pixel".into())).unwrap();

        let outcome = api.complete_from_link("code-xyz".into()).await.unwrap();
        assert_eq!(outcome, FfiLinkOutcome::AcknowledgedRemotely);
        assert!(!api.has_session());
        drop(poll_guard); // verifies expect(0): the poll endpoint was never called
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn poll_retries_transient_failure_then_signs_in() {
        use wiremock::matchers::{method, path};
        use wiremock::{Mock, MockServer, ResponseTemplate};

        let server = MockServer::start().await;
        // First poll: a transient 503 — must NOT abort the sign-in.
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .respond_with(ResponseTemplate::new(503))
            .up_to_n_times(1)
            .mount(&server)
            .await;
        // Next poll: the link has been clicked → 201 issues the token pair.
        Mock::given(method("POST"))
            .and(path("/v1/auth/verify/poll"))
            .respond_with(ResponseTemplate::new(201).set_body_json(serde_json::json!({
                "access": "acc-1",
                "refresh": "cwr_1",
                "expiresIn": 900,
                "accountId": "acct-1",
            })))
            .mount(&server)
            .await;

        let store = Arc::new(MemStore { map: Mutex::new(HashMap::new()) });
        store.set(KEY_PENDING_POLL_TOKEN.into(), "poll-tok".into());
        store.set(KEY_PENDING_VERIFIER.into(), "verifier".into());
        let api =
            AuthApi::new(store, server.uri(), "android".into(), Some("Pixel".into())).unwrap();

        // interval 0 keeps the retry immediate; timeout is generous.
        let outcome = api.poll_for_completion(30, 0).await.unwrap();
        assert_eq!(
            outcome,
            FfiAuthOutcome::SignedIn,
            "a transient poll failure must not abort the sign-in"
        );
        assert!(api.has_session());
        assert!(!api.has_pending_verification(), "success clears the pending verification");
    }
}
