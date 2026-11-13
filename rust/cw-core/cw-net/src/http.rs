//! Shared HTTP transport for `cw-net`. Wraps `reqwest::Client` with our error
//! mapping, a consistent User-Agent, and the small handful of helpers each
//! service client needs. Each service module (`sota`, `donki`, `hamqsl`, …)
//! exposes its own typed client built on top of this.
//!
//! Live HTTP isn't tested in-crate — the network behavior is exercised once
//! the FFI is wired into the iOS/macOS apps. The pure parsing/rate-limit/
//! cache logic *is* covered here.

use std::time::Duration;

use reqwest::header::{HeaderMap, HeaderValue, ACCEPT, RETRY_AFTER, USER_AGENT};
use reqwest::Method;
use thiserror::Error;

/// Shared User-Agent. Matches the Swift clients ("CarrierWave/1.0") so server
/// logs stay grouped.
pub const USER_AGENT_VALUE: &str = "CarrierWave/1.0";

/// Whole-request budget for [`HttpClient::new`].
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(20);
/// Connection-establishment cap, so a long [`HttpClient::with_timeout`]
/// budget still fails fast on an unreachable host. Equal to the default
/// budget, so default clients behave exactly as before.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);

// 429 retry policy (idempotent requests only). The activities server's
// `tower_governor` limiter answers 429 with a `Retry-After` header; we honor it
// and fall back to jittered exponential backoff when it's absent.
const MAX_RETRIES: u32 = 3;
const BASE_BACKOFF: Duration = Duration::from_millis(500);
const MAX_BACKOFF: Duration = Duration::from_secs(8);
/// Ceiling on total time spent sleeping across retries — past this we give up
/// and surface the 429 rather than hang a user-facing fetch.
const MAX_TOTAL_BACKOFF: Duration = Duration::from_secs(30);
/// Clamp a hostile/huge `Retry-After` so the header can't stall us for minutes.
const MAX_RETRY_AFTER: Duration = Duration::from_secs(60);

/// Only idempotent methods may be retried — replaying a POST (register, spot
/// post, telemetry) risks duplicate server-side side effects.
fn is_retryable_method(method: &Method) -> bool {
    matches!(
        *method,
        Method::GET | Method::HEAD | Method::PUT | Method::DELETE | Method::OPTIONS | Method::TRACE
    )
}

/// Parse a `Retry-After` header — either delta-seconds or an HTTP date — into a
/// delay, clamped to [`MAX_RETRY_AFTER`]. `None` when the header is absent or
/// unparseable (caller falls back to backoff).
fn retry_after_delay(headers: &HeaderMap) -> Option<Duration> {
    let raw = headers.get(RETRY_AFTER)?.to_str().ok()?.trim().to_string();
    if let Ok(secs) = raw.parse::<u64>() {
        return Some(Duration::from_secs(secs).min(MAX_RETRY_AFTER));
    }
    let when = chrono::DateTime::parse_from_rfc2822(&raw).ok()?;
    let secs = (when.with_timezone(&chrono::Utc) - chrono::Utc::now()).num_seconds();
    Some(Duration::from_secs(secs.max(0) as u64).min(MAX_RETRY_AFTER))
}

/// Exponential backoff (500ms, 1s, 2s, …, capped) with equal jitter, so a fleet
/// of clients unblocked at once don't resynchronize onto the limiter.
fn backoff_delay(attempt: u32) -> Duration {
    let exp = BASE_BACKOFF.saturating_mul(1u32 << attempt.min(16)).min(MAX_BACKOFF);
    let jitter = 0.5 + rand::random::<f64>() * 0.5; // [0.5, 1.0]
    exp.mul_f64(jitter)
}

/// `reqwest::Error`'s `Display` stops at "error sending request for url (…)"
/// and hides the actual cause (DNS vs TLS vs refused vs timed out), which
/// makes user-reported screenshots of a network failure undiagnosable. Walk
/// the source chain so the real cause rides along in the message.
fn error_chain(error: &dyn std::error::Error) -> String {
    let mut out = error.to_string();
    let mut source = error.source();
    while let Some(cause) = source {
        out.push_str(": ");
        out.push_str(&cause.to_string());
        source = cause.source();
    }
    out
}

#[derive(Debug, Error)]
pub enum HttpError {
    #[error("Network error: {}", error_chain(.0))]
    Network(#[from] reqwest::Error),
    #[error("HTTP {status}: {body}")]
    Http { status: u16, body: String },
    #[error("Invalid URL: {0}")]
    InvalidUrl(String),
    #[error("JSON parse error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Response body was not UTF-8")]
    NotUtf8,
    #[error("Rate limit exceeded")]
    RateLimited,
    #[error("Parse error: {0}")]
    Parse(String),
}

/// Thin wrapper around `reqwest::Client` so we share configuration across
/// service modules. `cw-net` callers create one and hand references to each
/// service client they want.
#[derive(Debug, Clone)]
pub struct HttpClient {
    inner: reqwest::Client,
}

impl HttpClient {
    /// Build a client with the standard timeout and User-Agent.
    pub fn new() -> Result<Self, HttpError> {
        Self::with_timeout(DEFAULT_TIMEOUT)
    }

    /// Build a client whose whole-request budget (connect through the last
    /// body byte) is `timeout` instead of [`DEFAULT_TIMEOUT`]. For bulk
    /// downloads from slow, throttled servers — SatNOGS serves its 4 MB
    /// transmitter list at ~240 KB/s, which the 20 s default cuts off.
    pub fn with_timeout(timeout: Duration) -> Result<Self, HttpError> {
        let mut headers = HeaderMap::new();
        headers.insert(USER_AGENT, HeaderValue::from_static(USER_AGENT_VALUE));
        headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
        let inner = reqwest::Client::builder()
            .timeout(timeout)
            .connect_timeout(CONNECT_TIMEOUT.min(timeout))
            .default_headers(headers)
            .build()?;
        Ok(Self { inner })
    }

    pub fn inner(&self) -> &reqwest::Client {
        &self.inner
    }

    /// Execute a built request, retrying on `429 Too Many Requests` for
    /// idempotent methods only. Honors `Retry-After` (else jittered backoff),
    /// bounded by [`MAX_RETRIES`] and [`MAX_TOTAL_BACKOFF`]. Non-idempotent or
    /// non-cloneable requests are sent exactly once. Returns the final response
    /// (which may still be a 429 once retries are exhausted) — body/status
    /// handling stays with the caller.
    ///
    /// `force_retryable` lets a caller opt a `POST` that is *known
    /// side-effect-free* (replaying it has no server-side effect) into the
    /// same 429 backoff — e.g. the read-only `/v1/sota/zones` compute query,
    /// which is only a `POST` to carry its summit-list body.
    async fn execute_with_retry(
        &self,
        built: reqwest::Request,
        force_retryable: bool,
    ) -> Result<reqwest::Response, HttpError> {
        // `try_clone` is `None` for streaming bodies; ours are in-memory.
        let retryable =
            (force_retryable || is_retryable_method(built.method())) && built.try_clone().is_some();
        if !retryable {
            return Ok(self.inner.execute(built).await?);
        }
        let mut attempt: u32 = 0;
        let mut total_backoff = Duration::ZERO;
        loop {
            let req = built.try_clone().expect("retryable implies cloneable");
            let response = self.inner.execute(req).await?;
            if response.status().as_u16() == 429 && attempt < MAX_RETRIES {
                let delay =
                    retry_after_delay(response.headers()).unwrap_or_else(|| backoff_delay(attempt));
                if total_backoff.saturating_add(delay) > MAX_TOTAL_BACKOFF {
                    return Ok(response);
                }
                tokio::time::sleep(delay).await;
                total_backoff = total_backoff.saturating_add(delay);
                attempt += 1;
                continue;
            }
            return Ok(response);
        }
    }

    /// Send a request, fail loudly on non-2xx, and return the response body
    /// as bytes. Smaller helpers below build on this. Retries idempotent 429s.
    pub async fn send_bytes(&self, request: reqwest::RequestBuilder) -> Result<Vec<u8>, HttpError> {
        self.send_bytes_impl(request, false).await
    }

    /// Like [`send_bytes`], but retries `429`s even for a `POST`. ONLY for
    /// requests with no server-side side effects — replaying must be safe.
    /// The SOTA activation-zone client uses this: `POST /v1/sota/zones` is a
    /// read-only compute/enqueue query, so it should ride the server's
    /// `Retry-After` backoff instead of aborting a bulk refresh on the first
    /// rate-limit hit.
    pub async fn send_bytes_retrying(
        &self,
        request: reqwest::RequestBuilder,
    ) -> Result<Vec<u8>, HttpError> {
        self.send_bytes_impl(request, true).await
    }

    async fn send_bytes_impl(
        &self,
        request: reqwest::RequestBuilder,
        force_retryable: bool,
    ) -> Result<Vec<u8>, HttpError> {
        let response = self.execute_with_retry(request.build()?, force_retryable).await?;
        let status = response.status();
        let bytes = response.bytes().await?;
        if !status.is_success() {
            let body = String::from_utf8_lossy(&bytes).into_owned();
            return Err(HttpError::Http {
                status: status.as_u16(),
                body,
            });
        }
        Ok(bytes.to_vec())
    }

    /// GET a URL and return the body as a UTF-8 string. Used for HTML/XML
    /// payloads.
    pub async fn get_text(&self, url: &str, accept: &'static str) -> Result<String, HttpError> {
        let request = self
            .inner
            .get(url)
            .header(ACCEPT, HeaderValue::from_static(accept));
        let bytes = self.send_bytes(request).await?;
        String::from_utf8(bytes).map_err(|_| HttpError::NotUtf8)
    }

    /// ETag-conditional GET returning the body as a UTF-8 string. Sends
    /// `If-None-Match` when `etag` is given and reports a `304 Not Modified`
    /// as [`Conditional::NotModified`] so callers keep their cached copy.
    pub async fn get_text_conditional(
        &self,
        url: &str,
        accept: &'static str,
        etag: Option<&str>,
    ) -> Result<crate::Conditional<String>, HttpError> {
        let mut request = self
            .inner
            .get(url)
            .header(ACCEPT, HeaderValue::from_static(accept));
        if let Some(etag) = etag {
            request = request.header("If-None-Match", etag);
        }
        let response = self.execute_with_retry(request.build()?, false).await?;
        let status = response.status();
        if status == reqwest::StatusCode::NOT_MODIFIED {
            return Ok(crate::Conditional::NotModified);
        }
        let new_etag = response
            .headers()
            .get(reqwest::header::ETAG)
            .and_then(|value| value.to_str().ok())
            .map(str::to_string);
        let bytes = response.bytes().await?;
        if !status.is_success() {
            let body = String::from_utf8_lossy(&bytes).into_owned();
            return Err(HttpError::Http {
                status: status.as_u16(),
                body,
            });
        }
        let text = String::from_utf8(bytes.to_vec()).map_err(|_| HttpError::NotUtf8)?;
        Ok(crate::Conditional::Modified { data: text, etag: new_etag })
    }

    /// GET a URL and deserialize the JSON response into `T`.
    pub async fn get_json<T: serde::de::DeserializeOwned>(&self, url: &str) -> Result<T, HttpError> {
        let request = self.inner.get(url);
        let bytes = self.send_bytes(request).await?;
        Ok(serde_json::from_slice(&bytes)?)
    }

    /// POST a JSON body to `url`, ignore the response body, fail on non-2xx.
    pub async fn post_json_unit<B: serde::Serialize>(
        &self,
        url: &str,
        body: &B,
    ) -> Result<(), HttpError> {
        let request = self.inner.post(url).json(body);
        self.send_bytes(request).await?;
        Ok(())
    }

    /// POST a JSON body and decode the JSON response.
    pub async fn post_json<B: serde::Serialize, T: serde::de::DeserializeOwned>(
        &self,
        url: &str,
        body: &B,
        bearer: Option<&str>,
    ) -> Result<T, HttpError> {
        let mut request = self.inner.post(url).json(body);
        if let Some(token) = bearer {
            request = request.bearer_auth(token);
        }
        let bytes = self.send_bytes(request).await?;
        Ok(serde_json::from_slice(&bytes)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_constructs() {
        let _ = HttpClient::new().expect("client builds");
    }

    #[test]
    fn error_chain_includes_every_cause() {
        #[derive(Debug, Error)]
        #[error("outer opaque message")]
        struct Outer(#[source] Inner);
        #[derive(Debug, Error)]
        #[error("inner cause")]
        struct Inner(#[source] std::io::Error);

        let err = Outer(Inner(std::io::Error::other("root detail")));
        assert_eq!(error_chain(&err), "outer opaque message: inner cause: root detail");
    }

    #[tokio::test]
    async fn network_error_display_names_the_cause() {
        // Grab a port the OS just released so the connect is refused; the
        // formatted error must carry the refusal, not just reqwest's opaque
        // "error sending request" prefix.
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        drop(listener);

        let client = HttpClient::new().unwrap();
        let err = client
            .get_text(&format!("http://127.0.0.1:{port}/"), "text/plain")
            .await
            .expect_err("connect to a closed port must fail");
        let message = err.to_string();
        assert!(
            message.to_lowercase().contains("refused"),
            "cause chain missing from: {message}"
        );
    }

    #[test]
    fn only_idempotent_methods_retry() {
        assert!(is_retryable_method(&Method::GET));
        assert!(is_retryable_method(&Method::HEAD));
        assert!(is_retryable_method(&Method::PUT));
        assert!(is_retryable_method(&Method::DELETE));
        // POST is the one that would double-fire register/spot/telemetry.
        assert!(!is_retryable_method(&Method::POST));
        assert!(!is_retryable_method(&Method::PATCH));
    }

    #[test]
    fn retry_after_parses_delta_seconds() {
        let mut headers = HeaderMap::new();
        headers.insert(RETRY_AFTER, HeaderValue::from_static("3"));
        assert_eq!(retry_after_delay(&headers), Some(Duration::from_secs(3)));
    }

    #[test]
    fn retry_after_is_clamped() {
        let mut headers = HeaderMap::new();
        headers.insert(RETRY_AFTER, HeaderValue::from_static("99999"));
        assert_eq!(retry_after_delay(&headers), Some(MAX_RETRY_AFTER));
    }

    #[test]
    fn retry_after_absent_or_garbage_is_none() {
        assert_eq!(retry_after_delay(&HeaderMap::new()), None);
        let mut headers = HeaderMap::new();
        headers.insert(RETRY_AFTER, HeaderValue::from_static("soon-ish"));
        assert_eq!(retry_after_delay(&headers), None);
    }

    #[test]
    fn backoff_grows_and_stays_bounded() {
        // Equal jitter keeps each delay within [0.5x, 1.0x] of the capped base.
        for attempt in 0..6 {
            let delay = backoff_delay(attempt);
            assert!(delay <= MAX_BACKOFF, "attempt {attempt} exceeded cap");
            assert!(delay >= Duration::from_millis(250), "attempt {attempt} too small");
        }
    }

    // --- End-to-end retry loop against a mock server -----------------------
    // The retry lives entirely in this shared core, so both iOS and Android run
    // this exact code path — a passing loop test here is the cross-platform
    // proof, with the per-platform builds only proving the FFI binding loads.

    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    /// Accept one connection, drain the request, and write a canned response.
    /// `Connection: close` forces reqwest to open a fresh TCP connection per
    /// attempt, so one `accept()` == one client attempt.
    async fn serve_once(listener: &TcpListener, status_line: &str, extra: &str, body: &str) {
        let (mut socket, _) = listener.accept().await.unwrap();
        let mut buf = [0u8; 2048];
        let _ = socket.read(&mut buf).await;
        let response = format!(
            "{status_line}\r\nContent-Length: {}\r\nConnection: close\r\n{extra}\r\n{body}",
            body.len()
        );
        socket.write_all(response.as_bytes()).await.unwrap();
        let _ = socket.shutdown().await;
    }

    #[tokio::test]
    async fn get_retries_429_then_succeeds() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let accepts = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&accepts);

        let server = tokio::spawn(async move {
            // Two 429s (Retry-After: 0 keeps the test instant), then a 200.
            for _ in 0..2 {
                serve_once(&listener, "HTTP/1.1 429 Too Many Requests", "Retry-After: 0\r\n", "slow").await;
                counter.fetch_add(1, Ordering::SeqCst);
            }
            serve_once(&listener, "HTTP/1.1 200 OK", "", "ok").await;
            counter.fetch_add(1, Ordering::SeqCst);
        });

        let client = HttpClient::new().unwrap();
        let body = client
            .get_text(&format!("http://127.0.0.1:{port}/"), "text/plain")
            .await
            .expect("idempotent GET should retry through the 429s and succeed");
        server.await.unwrap();

        assert_eq!(body, "ok");
        assert_eq!(accepts.load(Ordering::SeqCst), 3, "expected 2 retries then success");
    }

    #[tokio::test]
    async fn post_is_not_retried_on_429() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();

        let server = tokio::spawn(async move {
            serve_once(&listener, "HTTP/1.1 429 Too Many Requests", "Retry-After: 0\r\n", "no").await;
            // A retry would show up as a second connection; assert none arrives.
            let second = tokio::time::timeout(Duration::from_millis(400), listener.accept()).await;
            second.is_err()
        });

        let client = HttpClient::new().unwrap();
        let err = client
            .post_json_unit(&format!("http://127.0.0.1:{port}/"), &serde_json::json!({"x": 1}))
            .await
            .expect_err("POST 429 must surface as an error, not be retried");
        match err {
            HttpError::Http { status, .. } => assert_eq!(status, 429),
            other => panic!("expected HTTP 429, got {other:?}"),
        }

        let no_second_connection = server.await.unwrap();
        assert!(no_second_connection, "POST must not be retried");
    }

    #[tokio::test]
    async fn forced_retryable_post_retries_429_then_succeeds() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let accepts = Arc::new(AtomicUsize::new(0));
        let counter = Arc::clone(&accepts);

        let server = tokio::spawn(async move {
            // Two 429s (Retry-After: 0 keeps it instant), then a 200 — the
            // side-effect-free `/v1/sota/zones` POST path (send_bytes_retrying)
            // must ride the backoff instead of aborting on the first 429.
            for _ in 0..2 {
                serve_once(&listener, "HTTP/1.1 429 Too Many Requests", "Retry-After: 0\r\n", "slow").await;
                counter.fetch_add(1, Ordering::SeqCst);
            }
            serve_once(&listener, "HTTP/1.1 200 OK", "", "ok").await;
            counter.fetch_add(1, Ordering::SeqCst);
        });

        let client = HttpClient::new().unwrap();
        let url = format!("http://127.0.0.1:{port}/");
        let bytes = client
            .send_bytes_retrying(client.inner().post(&url).json(&serde_json::json!({ "summits": [] })))
            .await
            .expect("forced-retryable POST should retry through the 429s and succeed");
        server.await.unwrap();

        assert_eq!(bytes, b"ok");
        assert_eq!(accepts.load(Ordering::SeqCst), 3, "expected 2 retries then success");
    }
}
