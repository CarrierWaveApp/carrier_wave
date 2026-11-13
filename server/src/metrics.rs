use std::time::Instant;

use axum::{extract::MatchedPath, http::Request, middleware::Next, response::IntoResponse};
use metrics_exporter_prometheus::PrometheusHandle;

// ─── GIS aggregator metric names ─────────────────────────────────────────────

pub const GIS_FETCH_TOTAL: &str = "gis_fetch_total";
pub const GIS_FETCH_DURATION_SECONDS: &str = "gis_fetch_duration_seconds";
pub const GIS_BOUNDARIES_CACHED_TOTAL: &str = "gis_boundaries_cached_total";
pub const GIS_TRAILS_CACHED_TOTAL: &str = "gis_trails_cached_total";
pub const GIS_BATCH_DURATION_SECONDS: &str = "gis_batch_duration_seconds";
pub const SYNC_LAST_COMPLETED_TIMESTAMP: &str = "sync_last_completed_timestamp";
pub const SYNC_ERRORS_TOTAL: &str = "sync_errors_total";

// ─── HTTP metric names ──────────────────────────────────────────────────────

pub const HTTP_REQUESTS_TOTAL: &str = "http_requests_total";
pub const HTTP_REQUEST_DURATION_SECONDS: &str = "http_request_duration_seconds";
pub const HTTP_REQUESTS_IN_FLIGHT: &str = "http_requests_in_flight";

// ─── Database pool metric names ─────────────────────────────────────────────

pub const DB_POOL_CONNECTIONS: &str = "db_pool_connections";
pub const DB_POOL_IDLE_CONNECTIONS: &str = "db_pool_idle_connections";
pub const DB_POOL_SIZE: &str = "db_pool_size";

// ─── RBN metric names ───────────────────────────────────────────────────────

pub const RBN_SPOTS_BUFFERED: &str = "rbn_spots_buffered";
pub const RBN_SPOTS_INGESTED_TOTAL: &str = "rbn_spots_ingested_total";
pub const RBN_SPOT_SNR: &str = "rbn_spot_snr";
pub const RBN_SPOT_WPM: &str = "rbn_spot_wpm";

/// Install the Prometheus metrics exporter and return a handle for rendering.
pub fn install() -> PrometheusHandle {
    metrics_exporter_prometheus::PrometheusBuilder::new()
        .install_recorder()
        .expect("failed to install Prometheus recorder")
}

/// Axum middleware that records HTTP request count, duration, and in-flight gauge.
pub async fn http_metrics(req: Request<axum::body::Body>, next: Next) -> impl IntoResponse {
    let method = req.method().clone().to_string();
    let path = req
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_string())
        .unwrap_or_else(|| "unknown".to_string());

    metrics::gauge!(HTTP_REQUESTS_IN_FLIGHT, "method" => method.clone(), "path" => path.clone())
        .increment(1.0);

    let start = Instant::now();
    let response = next.run(req).await;
    let elapsed = start.elapsed().as_secs_f64();
    let status = response.status().as_u16().to_string();

    metrics::counter!(HTTP_REQUESTS_TOTAL, "method" => method.clone(), "path" => path.clone(), "status" => status.clone())
        .increment(1);
    metrics::histogram!(HTTP_REQUEST_DURATION_SECONDS, "method" => method.clone(), "path" => path.clone(), "status" => status)
        .record(elapsed);
    metrics::gauge!(HTTP_REQUESTS_IN_FLIGHT, "method" => method, "path" => path).decrement(1.0);

    response
}

/// Spawn a background task that periodically records database pool metrics.
pub fn spawn_pool_metrics(pool: sqlx::PgPool) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(15));
        loop {
            interval.tick().await;
            metrics::gauge!(DB_POOL_SIZE).set(pool.size() as f64);
            metrics::gauge!(DB_POOL_CONNECTIONS)
                .set(pool.num_idle() as f64 + (pool.size() as f64 - pool.num_idle() as f64));
            metrics::gauge!(DB_POOL_IDLE_CONNECTIONS).set(pool.num_idle() as f64);
        }
    });
}

/// Spawn a background task that periodically records the RBN spot buffer size.
pub fn spawn_rbn_metrics(rbn_store: crate::rbn::SpotStore) {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(15));
        loop {
            interval.tick().await;
            metrics::gauge!(RBN_SPOTS_BUFFERED).set(rbn_store.len() as f64);
        }
    });
}
