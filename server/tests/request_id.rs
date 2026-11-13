//! Request-correlation middleware (CAR-156 / audit T4-10).
//!
//! Drives a small router through `observability::instrument` — the same
//! wrapper `main.rs` applies to the production router — and checks the
//! `X-Request-Id` contract: an incoming id is echoed verbatim, a missing one
//! is minted as a UUID, and responses produced by the 404 fallback still carry
//! the header. The JSON tests capture the subscriber's output in a buffer and
//! assert the completion line's exact field set. No database required.

use std::io;
use std::sync::{Arc, Mutex};

use activities_server::observability::{self, LogFormat, REQUEST_ID_HEADER};
use axum::{
    body::Body,
    http::{Request, StatusCode},
    routing::get,
    Router,
};
use serde_json::Value;
use tower::ServiceExt;
use tracing_subscriber::EnvFilter;
use uuid::Uuid;

fn app() -> Router {
    observability::instrument(
        Router::new()
            .route("/v1/ping", get(|| async { "pong" }))
            .route("/v1/health", get(|| async { "ok" }))
            .route(
                "/v1/teapot",
                get(|| async { (StatusCode::IM_A_TEAPOT, "short and stout") }),
            ),
    )
}

/// `MakeWriter` sink: every log line lands in a shared buffer.
#[derive(Clone, Default)]
struct Sink(Arc<Mutex<Vec<u8>>>);

impl Sink {
    fn lines(&self) -> Vec<Value> {
        let bytes = self.0.lock().unwrap();
        String::from_utf8(bytes.clone())
            .expect("utf8 log output")
            .lines()
            .map(|l| serde_json::from_str(l).unwrap_or_else(|e| panic!("not JSON: {e}: {l}")))
            .collect()
    }
}

impl io::Write for Sink {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// Install a JSON subscriber for the current thread only (tokio tests run on
/// a current-thread runtime, so the middleware future logs through it) and
/// return the sink to inspect afterwards.
fn capture_json() -> (Sink, tracing::subscriber::DefaultGuard) {
    let sink = Sink::default();
    let writer = sink.clone();
    let sub = observability::subscriber(LogFormat::Json, EnvFilter::new("debug"), move || {
        writer.clone()
    });
    let guard = tracing::subscriber::set_default(sub);
    (sink, guard)
}

fn completion_line(sink: &Sink) -> Value {
    sink.lines()
        .into_iter()
        .find(|v| v["message"] == "request completed")
        .expect("one 'request completed' line")
}

#[tokio::test]
async fn json_completion_line_carries_correlation_fields() {
    let (sink, _guard) = capture_json();

    let req = Request::builder()
        .uri("/v1/ping?token=do-not-log")
        .header(REQUEST_ID_HEADER, "corr-42")
        .body(Body::empty())
        .unwrap();
    let res = app().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    let line = completion_line(&sink);
    // Event envelope.
    assert!(line["timestamp"].is_string(), "{line}");
    assert_eq!(line["level"], "INFO", "{line}");
    assert_eq!(line["target"], "activities_server::observability", "{line}");
    // Flattened event fields.
    assert_eq!(line["status"], 200, "{line}");
    assert!(line["latency_ms"].is_number(), "{line}");
    // Enclosing `request` span.
    let span = &line["span"];
    assert_eq!(span["name"], "request", "{line}");
    assert_eq!(span["request_id"], "corr-42", "{line}");
    assert_eq!(span["method"], "GET", "{line}");
    assert_eq!(span["path"], "/v1/ping", "{line}");
    assert_eq!(span["route"], "/v1/ping", "{line}");

    // Query strings may carry tokens; only the path is logged.
    let raw = String::from_utf8(sink.0.lock().unwrap().clone()).unwrap();
    assert!(!raw.contains("do-not-log"), "query string leaked: {raw}");
}

#[tokio::test]
async fn health_and_metrics_completion_lines_are_debug() {
    let (sink, _guard) = capture_json();

    let req = Request::builder()
        .uri("/v1/health")
        .body(Body::empty())
        .unwrap();
    let res = app().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    let line = completion_line(&sink);
    assert_eq!(line["level"], "DEBUG", "{line}");
    assert_eq!(line["span"]["path"], "/v1/health", "{line}");
    // Generated id is still recorded in the span.
    let id = line["span"]["request_id"]
        .as_str()
        .expect("request_id string");
    assert!(
        Uuid::parse_str(id).is_ok(),
        "span request_id is a UUID: {line}"
    );
}

#[tokio::test]
async fn echoes_supplied_request_id() {
    let req = Request::builder()
        .uri("/v1/ping")
        .header(REQUEST_ID_HEADER, "client-trace-abc123")
        .body(Body::empty())
        .unwrap();

    let res = app().oneshot(req).await.unwrap();

    assert_eq!(res.status(), StatusCode::OK);
    assert_eq!(
        res.headers()
            .get(REQUEST_ID_HEADER)
            .and_then(|v| v.to_str().ok()),
        Some("client-trace-abc123")
    );
}

#[tokio::test]
async fn generates_uuid_when_absent() {
    let req = Request::builder()
        .uri("/v1/ping")
        .body(Body::empty())
        .unwrap();

    let res = app().oneshot(req).await.unwrap();

    assert_eq!(res.status(), StatusCode::OK);
    let id = res
        .headers()
        .get(REQUEST_ID_HEADER)
        .and_then(|v| v.to_str().ok())
        .expect("generated X-Request-Id on response");
    let parsed = Uuid::parse_str(id).expect("generated id is a UUID");
    assert_eq!(parsed.get_version(), Some(uuid::Version::Random));
}

#[tokio::test]
async fn each_request_gets_a_distinct_id() {
    let app = app();
    let mut seen = std::collections::HashSet::new();
    for _ in 0..5 {
        let req = Request::builder()
            .uri("/v1/ping")
            .body(Body::empty())
            .unwrap();
        let res = app.clone().oneshot(req).await.unwrap();
        let id = res.headers()[REQUEST_ID_HEADER]
            .to_str()
            .unwrap()
            .to_owned();
        assert!(seen.insert(id), "request ids must be unique per request");
    }
}

#[tokio::test]
async fn non_2xx_and_unmatched_routes_still_carry_the_header() {
    // Handler-produced error status.
    let req = Request::builder()
        .uri("/v1/teapot")
        .header(REQUEST_ID_HEADER, "teapot-1")
        .body(Body::empty())
        .unwrap();
    let res = app().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::IM_A_TEAPOT);
    assert_eq!(res.headers()[REQUEST_ID_HEADER], "teapot-1");

    // Router 404 fallback (no route matched) — the id is still minted/echoed
    // because the layers sit outside routing.
    let req = Request::builder().uri("/nope").body(Body::empty()).unwrap();
    let res = app().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::NOT_FOUND);
    let id = res.headers()[REQUEST_ID_HEADER].to_str().unwrap();
    assert!(Uuid::parse_str(id).is_ok(), "404s get a generated id too");
}
