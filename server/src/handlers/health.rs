use std::time::Duration;

use axum::{extract::State, http::StatusCode, Extension, Json};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;

use crate::rbn::SpotStore;

/// Upper bound on the `SELECT 1` probe (CAR-157). Long enough to ride out a
/// momentarily busy pool, short enough that a wedged database fails the probe
/// instead of hanging the load balancer's health check.
const DB_CHECK_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Serialize)]
pub struct HealthResponse {
    /// `"ok"` when every dependency check passed, `"error"` otherwise.
    pub status: &'static str,
    pub version: &'static str,
    /// `"ok"` when `SELECT 1` succeeded within [`DB_CHECK_TIMEOUT`], `"error"`
    /// otherwise.
    pub database: &'static str,
    /// Human-readable reason when `status` is `"error"`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rbn: Option<RbnHealth>,
}

#[derive(Serialize)]
pub struct RbnHealth {
    pub connected: bool,
    pub spots_in_store: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub oldest_spot: Option<DateTime<Utc>>,
    pub spots_per_minute: f64,
}

/// `GET /v1/health` — 200 when the process is up *and* Postgres answers a
/// trivial query; 503 when the database check fails or times out. The RBN
/// block is informational only and never affects the status code.
pub async fn health_check(
    State(pool): State<PgPool>,
    Extension(rbn_store): Extension<SpotStore>,
) -> (StatusCode, Json<HealthResponse>) {
    let (size, oldest) = rbn_store.health_info();
    let stats = rbn_store.stats(1);

    let rbn = if rbn_store.is_connected() || size > 0 {
        Some(RbnHealth {
            connected: rbn_store.is_connected(),
            spots_in_store: size,
            oldest_spot: oldest,
            spots_per_minute: stats.spots_per_minute,
        })
    } else {
        None
    };

    let database_error = check_database(&pool).await.err();
    let (status_code, status, database) = match database_error {
        None => (StatusCode::OK, "ok", "ok"),
        Some(_) => (StatusCode::SERVICE_UNAVAILABLE, "error", "error"),
    };

    (
        status_code,
        Json(HealthResponse {
            status,
            version: env!("CARGO_PKG_VERSION"),
            database,
            error: database_error,
            rbn,
        }),
    )
}

/// Cheap liveness probe against the pool. The underlying error is logged but
/// not returned to the (unauthenticated) caller — connection strings and host
/// names have no business in a public response body.
async fn check_database(pool: &PgPool) -> Result<(), &'static str> {
    match tokio::time::timeout(DB_CHECK_TIMEOUT, sqlx::query("SELECT 1").execute(pool)).await {
        Ok(Ok(_)) => Ok(()),
        Ok(Err(err)) => {
            tracing::warn!(error = %err, "health: database check failed");
            Err("database check failed")
        }
        Err(_) => {
            tracing::warn!(
                timeout_ms = DB_CHECK_TIMEOUT.as_millis() as u64,
                "health: database check timed out"
            );
            Err("database check timed out")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{body::Body, http::Request, routing::get, Router};
    use sqlx::postgres::PgPoolOptions;
    use tower::ServiceExt;

    fn router(pool: PgPool) -> Router {
        Router::new()
            .route("/health", get(health_check))
            .layer(Extension(SpotStore::new()))
            .with_state(pool)
    }

    async fn call(pool: PgPool) -> (StatusCode, serde_json::Value) {
        let response = router(pool)
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        (status, serde_json::from_slice(&bytes).unwrap())
    }

    /// No database required: a lazy pool pointed at a closed port fails the
    /// probe, which must surface as 503 + `database: "error"`.
    #[tokio::test]
    async fn unreachable_database_returns_503() {
        let pool = PgPoolOptions::new()
            .acquire_timeout(Duration::from_millis(200))
            .connect_lazy("postgres://health:health@127.0.0.1:1/health")
            .unwrap();

        let (status, body) = call(pool).await;
        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
        assert_eq!(body["status"], "error");
        assert_eq!(body["database"], "error");
        assert!(
            body["error"]
                .as_str()
                .is_some_and(|e| e.starts_with("database check")),
            "body should say the database check failed: {body}"
        );
    }

    /// Skips without `TEST_DATABASE_URL`.
    #[tokio::test]
    async fn reachable_database_returns_200() {
        let Ok(url) = std::env::var("TEST_DATABASE_URL") else {
            return;
        };
        let Ok(pool) = PgPool::connect(&url).await else {
            return;
        };

        let (status, body) = call(pool).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body["status"], "ok");
        assert_eq!(body["database"], "ok");
        assert!(body.get("error").is_none());
        assert_eq!(body["version"], env!("CARGO_PKG_VERSION"));
    }
}
