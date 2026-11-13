//! Structured logging and per-request correlation (CAR-156, audit T4-2/T4-10).
//!
//! Two pieces:
//!
//! * [`init_tracing`] installs the global `tracing` subscriber. The format is
//!   chosen by `LOG_FORMAT` (see [`LogFormat`]); the default `json` emits one
//!   flattened object per line with `timestamp`, `level`, `target`, `message`,
//!   the event's own fields, and the enclosing span's fields under `span`.
//! * [`instrument`] wraps a router with the request-correlation stack:
//!   `X-Request-Id` is honoured when a client (or nginx) supplies it and
//!   generated as a UUID v4 otherwise, echoed on every response — including
//!   ones produced by outer layers such as the rate limiter — and every
//!   request runs inside an `info_span!("request", request_id, method, path,
//!   route)` so any log line emitted by a handler carries the id. One
//!   completion line per request records `status` and `latency_ms`.
//!
//! The Prometheus middleware in [`crate::metrics`] is independent and stays
//! mounted on the `/v1` sub-router; this stack sits on the outermost router so
//! it also covers static assets, `/metrics`, share links and 404s.
//!
//! Field reference and shipping guidance: `server/docs/logging.md`.

use std::time::Instant;

use axum::{
    extract::{MatchedPath, Request},
    middleware::{self, Next},
    response::Response,
    Router,
};
use tower_http::request_id::{MakeRequestUuid, PropagateRequestIdLayer, SetRequestIdLayer};
use tracing::{field, Instrument, Subscriber};
use tracing_subscriber::{
    fmt::{self, MakeWriter},
    layer::SubscriberExt,
    util::SubscriberInitExt,
    EnvFilter, Layer, Registry,
};

pub use crate::config::LogFormat;

/// Header carrying the correlation id, in both directions.
pub const REQUEST_ID_HEADER: &str = "x-request-id";

/// Longest client-supplied request id we will copy into the log record. Longer
/// values are truncated (the header is still echoed back untouched) so a
/// hostile caller can't pad every log line.
const MAX_LOGGED_REQUEST_ID: usize = 128;

/// Default `RUST_LOG` when the environment doesn't set one. The crate was
/// renamed from `challenges_server` long ago; the old default silently
/// filtered our own logs out.
const DEFAULT_FILTER: &str = "info,activities_server=debug";

/// Install the global subscriber. `RUST_LOG` still controls the filter.
///
/// Must be called exactly once, before anything logs. Emits a startup line
/// naming the active format so operators can confirm the env took effect; an
/// unrecognised `LOG_FORMAT` value is reported as a warning while the JSON
/// default stays in force.
pub fn init_tracing(format: LogFormat, unrecognized: Option<&str>) {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| DEFAULT_FILTER.into());
    subscriber(format, filter, std::io::stdout).init();

    if let Some(raw) = unrecognized {
        tracing::warn!(
            env = LogFormat::ENV_VAR,
            value = raw,
            fallback = format.as_str(),
            "unrecognised LOG_FORMAT; expected json|pretty|compact"
        );
    }
    tracing::info!(log_format = format.as_str(), "logging initialised");
}

/// Build the subscriber [`init_tracing`] installs, writing to `writer`.
/// Separate from `init_tracing` so tests can capture output in a buffer via
/// `tracing::subscriber::set_default` without touching the global default.
///
/// JSON shape (`flatten_event`): the event's own fields sit at the top level
/// next to `timestamp`/`level`/`target`/`message`; the enclosing span's
/// fields are nested under `span` (`with_current_span`), and the full span
/// ancestry list is omitted to keep lines short.
pub fn subscriber<W>(
    format: LogFormat,
    filter: EnvFilter,
    writer: W,
) -> impl Subscriber + Send + Sync + 'static
where
    W: for<'w> MakeWriter<'w> + Send + Sync + 'static,
{
    let fmt_layer: Box<dyn Layer<Registry> + Send + Sync> = match format {
        LogFormat::Json => fmt::layer()
            .json()
            .flatten_event(true)
            .with_current_span(true)
            .with_span_list(false)
            .with_target(true)
            .with_writer(writer)
            .boxed(),
        LogFormat::Pretty => fmt::layer().pretty().with_writer(writer).boxed(),
        LogFormat::Compact => fmt::layer().compact().with_writer(writer).boxed(),
    };

    // The boxed fmt layer is typed over the bare `Registry`, so it goes on
    // first; the `EnvFilter` layered on top still gates every event globally.
    tracing_subscriber::registry().with(fmt_layer).with(filter)
}

/// Wrap `router` with request-id generation/propagation and the per-request
/// span + completion log. Apply this last (outermost) so every response —
/// including rate-limit and CORS short-circuits — carries `X-Request-Id`.
///
/// Layer order, outermost first: `SetRequestId` (honour or mint the id) →
/// `PropagateRequestId` (copy it onto the response) → [`request_log`].
pub fn instrument<S>(router: Router<S>) -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    router
        .layer(middleware::from_fn(request_log))
        .layer(PropagateRequestIdLayer::x_request_id())
        .layer(SetRequestIdLayer::x_request_id(MakeRequestUuid))
}

/// Paths whose completion line is logged at DEBUG instead of INFO: they are
/// polled every few seconds by uptime checks and Prometheus and would drown
/// the real traffic at the production `RUST_LOG=info`.
fn is_quiet_path(path: &str) -> bool {
    matches!(path, "/v1/health" | "/metrics")
}

/// Axum middleware: open the `request` span and emit the completion line.
///
/// Expects `SetRequestIdLayer` to have run already (see [`instrument`]); if it
/// hasn't, `request_id` is logged as `-` rather than failing the request.
pub async fn request_log(req: Request, next: Next) -> Response {
    let method = req.method().clone();
    let path = req.uri().path().to_owned();
    // The matched route pattern (`/v1/challenges/:id`) when the request hit a
    // `Router::route`; absent for `nest_service`/`fallback_service` (static
    // assets) and unmatched paths.
    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_owned());
    let request_id = req
        .headers()
        .get(REQUEST_ID_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(truncate_request_id)
        .unwrap_or_else(|| "-".to_owned());

    let span = tracing::info_span!(
        "request",
        request_id = %request_id,
        method = %method,
        path = %path,
        route = field::Empty,
    );
    if let Some(route) = &route {
        span.record("route", route.as_str());
    }

    let quiet = is_quiet_path(&path);
    let start = Instant::now();

    async move {
        let response = next.run(req).await;
        let status = response.status().as_u16();
        // Rounded to microsecond precision so the JSON stays readable.
        let latency_ms = (start.elapsed().as_secs_f64() * 1_000_000.0).round() / 1000.0;
        if quiet {
            tracing::debug!(status, latency_ms, "request completed");
        } else {
            tracing::info!(status, latency_ms, "request completed");
        }
        response
    }
    .instrument(span)
    .await
}

fn truncate_request_id(raw: &str) -> String {
    if raw.len() <= MAX_LOGGED_REQUEST_ID {
        return raw.to_owned();
    }
    // Back off to a char boundary so we never split a multi-byte sequence.
    let mut end = MAX_LOGGED_REQUEST_ID;
    while !raw.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}…", &raw[..end])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quiet_paths_are_exactly_health_and_metrics() {
        assert!(is_quiet_path("/v1/health"));
        assert!(is_quiet_path("/metrics"));
        assert!(!is_quiet_path("/v1/healthz"));
        assert!(!is_quiet_path("/v1/challenges"));
        assert!(!is_quiet_path("/"));
    }

    #[test]
    fn truncates_long_request_ids_on_char_boundary() {
        let short = "abc-123";
        assert_eq!(truncate_request_id(short), short);

        let long = "x".repeat(MAX_LOGGED_REQUEST_ID + 10);
        let out = truncate_request_id(&long);
        assert_eq!(out.chars().count(), MAX_LOGGED_REQUEST_ID + 1);
        assert!(out.ends_with('…'));

        // 'é' is two bytes; make the boundary fall inside one.
        let tricky = format!(
            "{}é{}",
            "a".repeat(MAX_LOGGED_REQUEST_ID - 1),
            "b".repeat(20)
        );
        let out = truncate_request_id(&tricky);
        assert!(out.ends_with('…'));
        assert!(out.chars().count() <= MAX_LOGGED_REQUEST_ID + 1);
    }
}
