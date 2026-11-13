//! WebSDR (KiwiSDR) proxy endpoints backing the logbook viewer's Spots page.
//!
//! The browser cannot fetch the public KiwiSDR directory cross-origin, cannot
//! probe an arbitrary receiver's `/status`, and cannot open a plain `ws://`
//! socket from an `https://` page — so all three hop through here:
//!
//! - `GET /v1/websdr/directory` — the Skywavelinux directory JS, fetched
//!   server-side and cached in memory for an hour. Returned as the **raw JS
//!   text** (the browser parses it with the shared WASM
//!   `parse_kiwi_directory`, keeping parsing identical to the iOS client).
//! - `GET /v1/websdr/status?host=&port=` — one receiver `/status` fetch with
//!   a 5 s timeout.
//! - `GET /v1/websdr/stream?host=&port=` — a transparent WebSocket byte pipe
//!   to `ws://host:port/{unix_ts}/SND`. The browser speaks the KiwiSDR
//!   protocol through it; nothing is interpreted here.
//!
//! All targets are validated against SSRF: hostname syntax, a sane-port
//! allowlist, and DNS resolution must yield only public unicast addresses.

use std::net::IpAddr;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::Query;
use axum::http::{header, Uri};
use axum::response::{IntoResponse, Response};
use axum::Extension;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio_tungstenite::tungstenite::error::ProtocolError;
use tokio_tungstenite::tungstenite::Error as UpstreamError;
use tokio_tungstenite::tungstenite::Message as UpstreamMessage;

use crate::error::AppError;

const DIRECTORY_URL: &str = "https://rx.skywavelinux.com/kiwisdr_com.js";
const DIRECTORY_TTL: Duration = Duration::from_secs(3600);
const STATUS_TIMEOUT: Duration = Duration::from_secs(5);
const UPSTREAM_CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const WARMUP_TIMEOUT: Duration = Duration::from_secs(4);
const MAX_REDIRECTS: usize = 3;

/// KiwiSDR web assets fetched before opening the audio socket. Modern firmware
/// (rx_sound.cpp `EXT_API_DECISION_SECS`) classifies a client that opened only
/// the websocket — without fetching web assets from the same IP — as a
/// "non-Kiwi app" and kicks it with `MSG too_busy` at exactly 10 s. Fetching a
/// handful of assets first (as a browser loading the UI does) pushes the
/// receiver's per-IP `web_served` counter past its threshold (3), so the audio
/// connection is treated as the Kiwi UI and allowed to stream. Without this the
/// stream dies after ~10 s on any receiver that limits the external API.
const WARMUP_ASSETS: [&str; 4] = ["/", "/kiwisdr.min.js", "/config/config.js", "/status"];

/// Shared HTTP client + in-memory directory cache, layered as an `Extension`.
#[derive(Clone)]
pub struct WebSdrState {
    http: reqwest::Client,
    /// Redirect-free client for discovering websocket redirect hops — the
    /// default client would follow them invisibly and we need the Location.
    probe: reqwest::Client,
    directory: Arc<tokio::sync::Mutex<Option<(Instant, String)>>>,
}

impl WebSdrState {
    pub fn new() -> Self {
        Self {
            http: reqwest::Client::builder()
                // SECURITY (CAR-314): validate_target() only checks the initial
                // host/port. reqwest's default policy follows up to 10 redirects,
                // none re-validated, turning any anonymous status/warm-up fetch
                // into a full-read SSRF against loopback / metadata / LAN targets.
                // Disable redirect following entirely — WebSDR status endpoints
                // answer 200 directly, and any hop would have to be re-validated
                // like connect_following_redirects() already does for websockets.
                .redirect(reqwest::redirect::Policy::none())
                .timeout(Duration::from_secs(15))
                .user_agent("carrier-wave-activities-server")
                .build()
                .expect("reqwest client"),
            probe: reqwest::Client::builder()
                .redirect(reqwest::redirect::Policy::none())
                .timeout(STATUS_TIMEOUT)
                .user_agent("carrier-wave-activities-server")
                .build()
                .expect("reqwest client"),
            directory: Arc::new(tokio::sync::Mutex::new(None)),
        }
    }
}

impl Default for WebSdrState {
    fn default() -> Self {
        Self::new()
    }
}

/// GET /v1/websdr/directory — the raw Skywavelinux directory JS, cached ~1 h.
pub async fn websdr_directory(
    Extension(state): Extension<WebSdrState>,
) -> Result<Response, AppError> {
    // Hold the lock across the refetch so concurrent cache misses collapse
    // into a single upstream request (the directory is ~1 MB).
    let mut cache = state.directory.lock().await;
    if let Some((fetched_at, body)) = cache.as_ref() {
        if fetched_at.elapsed() < DIRECTORY_TTL {
            return Ok(js_response(body.clone()));
        }
    }

    let body = state
        .http
        .get(DIRECTORY_URL)
        .send()
        .await
        .and_then(|resp| resp.error_for_status())
        .map_err(|e| AppError::Internal(format!("websdr directory fetch failed: {e}")))?
        .text()
        .await
        .map_err(|e| AppError::Internal(format!("websdr directory read failed: {e}")))?;

    *cache = Some((Instant::now(), body.clone()));
    Ok(js_response(body))
}

fn js_response(body: String) -> Response {
    (
        [(header::CONTENT_TYPE, "application/javascript; charset=utf-8")],
        body,
    )
        .into_response()
}

#[derive(Deserialize)]
pub struct TargetQuery {
    pub host: String,
    pub port: u16,
}

/// GET /v1/websdr/status?host=&port= — proxy one KiwiSDR `/status` fetch.
pub async fn websdr_status(
    Extension(state): Extension<WebSdrState>,
    Query(target): Query<TargetQuery>,
) -> Result<Response, AppError> {
    validate_target(&target.host, target.port).await?;

    let url = format!("http://{}:{}/status", target.host, target.port);
    let body = state
        .http
        .get(&url)
        .timeout(STATUS_TIMEOUT)
        .send()
        .await
        .and_then(|resp| resp.error_for_status())
        .map_err(|e| AppError::Internal(format!("websdr status fetch failed: {e}")))?
        .text()
        .await
        .map_err(|e| AppError::Internal(format!("websdr status read failed: {e}")))?;

    Ok(([(header::CONTENT_TYPE, "text/plain; charset=utf-8")], body).into_response())
}

/// GET /v1/websdr/stream?host=&port= — WebSocket bridge to the receiver's
/// `/{unix_ts}/SND` audio endpoint. Bytes are piped both directions
/// untouched; either side closing tears down the other.
pub async fn websdr_stream(
    ws: WebSocketUpgrade,
    Extension(state): Extension<WebSdrState>,
    Query(target): Query<TargetQuery>,
) -> Result<Response, AppError> {
    validate_target(&target.host, target.port).await?;

    let unix_ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    // Modern KiwiSDR firmware serves the stream under /ws/kiwi/; legacy
    // firmware uses the bare timestamp path. The legacy path on modern
    // firmware completes the handshake but never attaches a stream (silence),
    // so try modern first and only fall back when the handshake is rejected.
    let modern_url = format!(
        "ws://{}:{}/ws/kiwi/{}/SND",
        target.host, target.port, unix_ts
    );
    let legacy_url = format!("ws://{}:{}/{}/SND", target.host, target.port, unix_ts);
    let base = format!("http://{}:{}", target.host, target.port);

    Ok(ws.on_upgrade(move |browser| bridge(browser, state, base, modern_url, legacy_url)))
}

/// Fetch a few of the receiver's web assets from this server's IP so the
/// KiwiSDR classifies the impending audio connection as its own UI rather than
/// a non-Kiwi app (see [`WARMUP_ASSETS`]). Best-effort: failures are ignored,
/// and all requests race a short overall deadline so we still connect promptly.
async fn warm_up_served_counter(http: &reqwest::Client, base: &str) {
    let fetches = WARMUP_ASSETS.iter().map(|path| {
        let url = format!("{base}{path}");
        let http = http.clone();
        async move {
            let _ = http.get(&url).timeout(WARMUP_TIMEOUT).send().await;
        }
    });
    let _ = tokio::time::timeout(WARMUP_TIMEOUT, futures_util::future::join_all(fetches)).await;
}

type UpstreamSocket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

/// Connect to a receiver websocket URL, manually following HTTP redirects
/// (tungstenite refuses non-101 responses). Receivers behind the kiwisdr.com
/// proxy need this: `NNNN.proxy.kiwisdr.com:8073` answers the handshake with
/// an frp 307 to an `NNNN.proxy2.kiwisdr.com` host, whose lighttpd 307s once
/// more to port 8073 — only the final hop completes the handshake. Every
/// redirect target is re-checked against the SSRF rules before connecting.
async fn connect_following_redirects(
    probe: &reqwest::Client,
    start_url: String,
) -> Result<UpstreamSocket, &'static str> {
    let mut url = start_url;
    for _ in 0..=MAX_REDIRECTS {
        let attempt = tokio::time::timeout(
            UPSTREAM_CONNECT_TIMEOUT,
            tokio_tungstenite::connect_async(&url),
        )
        .await;
        let error = match attempt {
            Ok(Ok((socket, _))) => return Ok(socket),
            Ok(Err(e)) => e,
            Err(_) => return Err("MSG cw_proxy_error=connect_timeout"),
        };

        let location = match &error {
            UpstreamError::Http(response) if response.status().is_redirection() => response
                .headers()
                .get("location")
                .and_then(|value| value.to_str().ok())
                .map(String::from),
            // The frp redirector answers with an HTTP/1.0 307, which
            // tungstenite rejects before exposing the response — rediscover
            // the Location with a plain HTTP request.
            UpstreamError::Protocol(ProtocolError::WrongHttpVersion) => {
                probe_redirect_location(probe, &url).await
            }
            _ => None,
        };
        let next = location
            .and_then(|loc| resolve_ws_redirect(&url, &loc))
            .map(|next| preserve_path_case(&url, next));
        let Some(next) = next else {
            tracing::debug!("websdr bridge: connect failed for {url}: {error}");
            return Err("MSG cw_proxy_error=connect_failed");
        };
        let Some((host, port)) = ws_host_port(&next) else {
            return Err("MSG cw_proxy_error=connect_failed");
        };
        if validate_target(&host, port).await.is_err() {
            tracing::debug!("websdr bridge: redirect to blocked target {next}");
            return Err("MSG cw_proxy_error=redirect_blocked");
        }
        tracing::debug!("websdr bridge: following redirect {url} -> {next}");
        url = next;
    }
    tracing::debug!("websdr bridge: too many redirects");
    Err("MSG cw_proxy_error=connect_failed")
}

/// Re-issue a rejected websocket handshake as a plain HTTP GET to read the
/// redirect Location tungstenite couldn't surface. Returns None when the
/// response isn't a redirect.
async fn probe_redirect_location(probe: &reqwest::Client, ws_url: &str) -> Option<String> {
    let http_url = ws_url
        .strip_prefix("ws://")
        .map(|rest| format!("http://{rest}"))
        .or_else(|| {
            ws_url
                .strip_prefix("wss://")
                .map(|rest| format!("https://{rest}"))
        })?;
    let response = probe.get(&http_url).send().await.ok()?;
    if !response.status().is_redirection() {
        return None;
    }
    response
        .headers()
        .get("location")?
        .to_str()
        .ok()
        .map(String::from)
}

/// Turn a redirect `Location` into a ws(s) URL: absolute http(s)/ws(s) URLs
/// are normalized to the ws scheme, absolute paths are resolved against the
/// URL being redirected. Anything else is rejected.
fn resolve_ws_redirect(current: &str, location: &str) -> Option<String> {
    if location.starts_with("ws://") || location.starts_with("wss://") {
        return Some(location.to_string());
    }
    if let Some(rest) = location.strip_prefix("http://") {
        return Some(format!("ws://{rest}"));
    }
    if let Some(rest) = location.strip_prefix("https://") {
        return Some(format!("wss://{rest}"));
    }
    if location.starts_with('/') {
        let uri: Uri = current.parse().ok()?;
        let scheme = uri.scheme_str()?;
        let authority = uri.authority()?;
        return Some(format!("{scheme}://{authority}{location}"));
    }
    None
}

/// The kiwisdr.com frp redirector lowercases the URL path in its Location
/// header. The receiver completes a handshake for a lowercased stream name
/// (`/snd`) but never attaches the stream — silent audio. When a redirect
/// changes nothing about the path but its case, keep our casing.
fn preserve_path_case(current: &str, next: String) -> String {
    let (Ok(cur), Ok(new)) = (current.parse::<Uri>(), next.parse::<Uri>()) else {
        return next;
    };
    let cur_path = cur.path();
    let new_path = new.path();
    if cur_path == new_path || !cur_path.eq_ignore_ascii_case(new_path) {
        return next;
    }
    let Some(authority) = new.authority() else {
        return next;
    };
    let scheme = new.scheme_str().unwrap_or("ws");
    let query = new.query().map(|q| format!("?{q}")).unwrap_or_default();
    format!("{scheme}://{authority}{cur_path}{query}")
}

fn ws_host_port(url: &str) -> Option<(String, u16)> {
    let uri: Uri = url.parse().ok()?;
    let host = uri.host()?.to_string();
    let port = uri.port_u16().unwrap_or(match uri.scheme_str() {
        Some("wss") => 443,
        _ => 80,
    });
    Some((host, port))
}

async fn bridge(
    mut browser: WebSocket,
    state: WebSdrState,
    base: String,
    modern_url: String,
    legacy_url: String,
) {
    // Warm the receiver's per-IP web-served counter before connecting, or the
    // stream is kicked after ~10 s on API-limited receivers.
    warm_up_served_counter(&state.http, &base).await;

    let connected = match connect_following_redirects(&state.probe, modern_url).await {
        Ok(socket) => Ok(socket),
        Err(modern_err) => {
            tracing::debug!("websdr bridge: modern-path connect failed ({modern_err}), trying legacy");
            connect_following_redirects(&state.probe, legacy_url).await
        }
    };

    let upstream = match connected {
        Ok(socket) => socket,
        Err(error_msg) => {
            let _ = browser.send(Message::Text(error_msg.into())).await;
            let _ = browser.close().await;
            return;
        }
    };

    let (mut upstream_tx, mut upstream_rx) = upstream.split();
    let (mut browser_tx, mut browser_rx) = browser.split();

    let to_upstream = async {
        while let Some(Ok(msg)) = browser_rx.next().await {
            let forwarded = match msg {
                Message::Text(text) => UpstreamMessage::Text(text),
                Message::Binary(data) => UpstreamMessage::Binary(data),
                Message::Ping(data) => UpstreamMessage::Ping(data),
                Message::Pong(data) => UpstreamMessage::Pong(data),
                Message::Close(_) => break,
            };
            if upstream_tx.send(forwarded).await.is_err() {
                break;
            }
        }
        let _ = upstream_tx.send(UpstreamMessage::Close(None)).await;
    };

    let to_browser = async {
        while let Some(Ok(msg)) = upstream_rx.next().await {
            let forwarded = match msg {
                UpstreamMessage::Text(text) => Message::Text(text),
                UpstreamMessage::Binary(data) => Message::Binary(data),
                UpstreamMessage::Ping(data) => Message::Ping(data),
                UpstreamMessage::Pong(data) => Message::Pong(data),
                UpstreamMessage::Close(_) => break,
                UpstreamMessage::Frame(_) => continue,
            };
            if browser_tx.send(forwarded).await.is_err() {
                break;
            }
        }
        let _ = browser_tx.send(Message::Close(None)).await;
    };

    // Run both pumps until either side hangs up.
    tokio::select! {
        _ = to_upstream => {}
        _ = to_browser => {}
    }
}

/// Validate a proxy target: hostname syntax, sane port, and DNS resolution to
/// only public unicast addresses (anti-SSRF). Note: a DNS-rebinding attacker
/// controlling a domain's TTL could still flip the record between this check
/// and the connect; the target set (public KiwiSDR receivers) and the
/// unauthenticated internal surface make that an accepted residual risk.
async fn validate_target(host: &str, port: u16) -> Result<(), AppError> {
    validate_host_syntax(host)?;
    validate_port(port)?;

    // If the host is an IP literal, judge it directly (lookup_host would too,
    // but this gives a clearer error and skips the resolver).
    if let Ok(ip) = host.parse::<IpAddr>() {
        return if ip_is_public(ip) {
            Ok(())
        } else {
            Err(validation("host must be a public address"))
        };
    }

    let addrs = tokio::net::lookup_host((host, port))
        .await
        .map_err(|_| validation("host does not resolve"))?;
    let mut resolved_any = false;
    for addr in addrs {
        resolved_any = true;
        if !ip_is_public(addr.ip()) {
            return Err(validation("host resolves to a non-public address"));
        }
    }
    if resolved_any {
        Ok(())
    } else {
        Err(validation("host does not resolve"))
    }
}

fn validation(message: &str) -> AppError {
    AppError::Validation {
        message: message.to_string(),
    }
}

/// Hostnames (or IPv4 literals) only: label characters, dots, dashes. IPv6
/// literals are rejected (public KiwiSDRs are listed by hostname/IPv4).
fn validate_host_syntax(host: &str) -> Result<(), AppError> {
    if host.is_empty() || host.len() > 253 {
        return Err(validation("invalid host"));
    }
    let valid = host
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-');
    if !valid || host.starts_with('-') || host.starts_with('.') {
        return Err(validation("invalid host"));
    }
    Ok(())
}

/// KiwiSDRs listen on 8073 by convention but are commonly remapped; allow
/// 80/443 and anything unprivileged. Everything else (SSH, SMTP, DBs, …) is
/// not a sane WebSDR port and is refused.
fn validate_port(port: u16) -> Result<(), AppError> {
    if port == 80 || port == 443 || port >= 1024 {
        Ok(())
    } else {
        Err(validation("invalid port"))
    }
}

/// Public-unicast check (stable-Rust stand-in for `IpAddr::is_global`).
fn ip_is_public(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => {
            let octets = v4.octets();
            !(v4.is_loopback()
                || v4.is_private()
                || v4.is_link_local()
                || v4.is_unspecified()
                || v4.is_broadcast()
                || v4.is_multicast()
                || v4.is_documentation()
                // 100.64.0.0/10 — carrier-grade NAT.
                || (octets[0] == 100 && (octets[1] & 0xC0) == 64)
                // 192.0.0.0/24 — IETF protocol assignments.
                || (octets[0] == 192 && octets[1] == 0 && octets[2] == 0)
                // 0.0.0.0/8 — "this network".
                || octets[0] == 0
                // 240.0.0.0/4 — reserved.
                || octets[0] >= 240)
        }
        IpAddr::V6(v6) => {
            // Judge IPv4-mapped addresses by their embedded IPv4 rules.
            if let Some(mapped) = v6.to_ipv4_mapped() {
                return ip_is_public(IpAddr::V4(mapped));
            }
            let segments = v6.segments();
            !(v6.is_loopback()
                || v6.is_unspecified()
                || v6.is_multicast()
                // fc00::/7 — unique local.
                || (segments[0] & 0xFE00) == 0xFC00
                // fe80::/10 — link local.
                || (segments[0] & 0xFFC0) == 0xFE80)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_ip_classification() {
        let public = ["8.8.8.8", "93.184.216.34", "2607:f8b0::1"];
        for ip in public {
            assert!(ip_is_public(ip.parse().unwrap()), "{ip} should be public");
        }

        let blocked = [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254", // cloud metadata
            "0.0.0.0",
            "100.64.0.1", // CGNAT
            "192.0.0.10",
            "255.255.255.255",
            "240.0.0.1",
            "224.0.0.1",
            "::1",
            "::",
            "fc00::1",
            "fe80::1",
            "ff02::1",
            "::ffff:127.0.0.1",  // IPv4-mapped loopback
            "::ffff:192.168.0.1",
        ];
        for ip in blocked {
            assert!(!ip_is_public(ip.parse().unwrap()), "{ip} should be blocked");
        }
    }

    #[test]
    fn port_allowlist() {
        for port in [80u16, 443, 1024, 8073, 8901, 65535] {
            assert!(validate_port(port).is_ok(), "port {port}");
        }
        for port in [0u16, 22, 25, 111, 1023] {
            assert!(validate_port(port).is_err(), "port {port}");
        }
    }

    #[test]
    fn host_syntax() {
        assert!(validate_host_syntax("kiwi.example.com").is_ok());
        assert!(validate_host_syntax("8.8.8.8").is_ok());
        assert!(validate_host_syntax("").is_err());
        assert!(validate_host_syntax("-bad.example.com").is_err());
        assert!(validate_host_syntax(".bad").is_err());
        assert!(validate_host_syntax("bad host").is_err());
        assert!(validate_host_syntax("evil.com/../../admin").is_err());
        assert!(validate_host_syntax("[::1]").is_err());
        assert!(validate_host_syntax(&"a".repeat(300)).is_err());
    }

    #[tokio::test]
    #[ignore = "hits a live kiwisdr.com proxy receiver"]
    async fn live_redirect_connect() {
        let _ = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::DEBUG)
            .try_init();
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let url = format!("ws://21832.proxy.kiwisdr.com:8073/ws/kiwi/{ts}/SND");
        let state = WebSdrState::new();
        let result = connect_following_redirects(&state.probe, url).await;
        let mut socket = match result {
            Ok(socket) => socket,
            Err(e) => panic!("connect failed: {e:?}"),
        };
        // A connect alone isn't proof — a case-mangled stream path completes
        // the handshake but never attaches the stream. Authenticate and
        // require an actual protocol reply.
        socket
            .send(UpstreamMessage::Text("SET auth t=kiwi p=#".into()))
            .await
            .expect("send auth");
        let reply = tokio::time::timeout(Duration::from_secs(10), socket.next())
            .await
            .expect("no reply within 10s — stream did not attach")
            .expect("socket ended")
            .expect("socket error");
        let text = String::from_utf8_lossy(&reply.into_data()).into_owned();
        assert!(text.starts_with("MSG"), "unexpected first frame: {text}");
    }

    #[test]
    fn redirect_resolution() {
        // The kiwisdr.com proxy chain: frp 307s to an http:// URL on proxy2
        // (implicit port 80), whose lighttpd 307s back to port 8073.
        assert_eq!(
            resolve_ws_redirect(
                "ws://21832.proxy.kiwisdr.com:8073/ws/kiwi/123/SND",
                "http://21832.proxy2.kiwisdr.com/ws/kiwi/123/snd",
            )
            .as_deref(),
            Some("ws://21832.proxy2.kiwisdr.com/ws/kiwi/123/snd")
        );
        assert_eq!(
            resolve_ws_redirect(
                "ws://21832.proxy2.kiwisdr.com/ws/kiwi/123/snd",
                "http://21832.proxy2.kiwisdr.com:8073/ws/kiwi/123/snd",
            )
            .as_deref(),
            Some("ws://21832.proxy2.kiwisdr.com:8073/ws/kiwi/123/snd")
        );
        // https → wss, ws(s) passed through, absolute paths resolved.
        assert_eq!(
            resolve_ws_redirect("ws://a.example:8073/x", "https://b.example/y").as_deref(),
            Some("wss://b.example/y")
        );
        assert_eq!(
            resolve_ws_redirect("ws://a.example:8073/x", "ws://b.example/y").as_deref(),
            Some("ws://b.example/y")
        );
        assert_eq!(
            resolve_ws_redirect("ws://a.example:8073/x", "/y/z").as_deref(),
            Some("ws://a.example:8073/y/z")
        );
        // Relative (non-absolute-path) and garbage locations are rejected.
        assert!(resolve_ws_redirect("ws://a.example:8073/x", "y/z").is_none());
        assert!(resolve_ws_redirect("ws://a.example:8073/x", "ftp://b.example/y").is_none());
    }

    #[test]
    fn path_case_preserved_across_redirects() {
        // frp lowercases /SND — keep our casing when only case changed.
        assert_eq!(
            preserve_path_case(
                "ws://21832.proxy.kiwisdr.com:8073/ws/kiwi/123/SND",
                "ws://21832.proxy2.kiwisdr.com/ws/kiwi/123/snd".to_string(),
            ),
            "ws://21832.proxy2.kiwisdr.com/ws/kiwi/123/SND"
        );
        // A genuinely different path is trusted as-is.
        assert_eq!(
            preserve_path_case(
                "ws://a.example/ws/kiwi/123/SND",
                "ws://a.example/other/path".to_string(),
            ),
            "ws://a.example/other/path"
        );
        // Identical path untouched (port-only hop).
        assert_eq!(
            preserve_path_case(
                "ws://a.example/ws/kiwi/123/SND",
                "ws://a.example:8073/ws/kiwi/123/SND".to_string(),
            ),
            "ws://a.example:8073/ws/kiwi/123/SND"
        );
    }

    #[test]
    fn host_port_extraction() {
        assert_eq!(
            ws_host_port("ws://kiwi.example:8073/ws/kiwi/1/SND"),
            Some(("kiwi.example".to_string(), 8073))
        );
        assert_eq!(
            ws_host_port("ws://kiwi.example/ws/kiwi/1/SND"),
            Some(("kiwi.example".to_string(), 80))
        );
        assert_eq!(
            ws_host_port("wss://kiwi.example/ws/kiwi/1/SND"),
            Some(("kiwi.example".to_string(), 443))
        );
        assert!(ws_host_port("not a url").is_none());
    }

    #[tokio::test]
    async fn target_validation_rejects_private_literals() {
        assert!(validate_target("127.0.0.1", 8073).await.is_err());
        assert!(validate_target("169.254.169.254", 8073).await.is_err());
        assert!(validate_target("192.168.1.10", 8073).await.is_err());
        // Documentation ranges (TEST-NET) are blocked too.
        assert!(validate_target("203.0.113.9", 8073).await.is_err());
        // Public literal with a sane port passes without a resolver hit.
        assert!(validate_target("8.8.8.8", 8073).await.is_ok());
        // Sane host, insane port.
        assert!(validate_target("8.8.8.8", 22).await.is_err());
    }
}
