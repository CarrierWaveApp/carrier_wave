//! POST /v1/macros/:slug/run-event — authenticated run telemetry (CAR-271 T6).
//!
//! Wired under the `require_auth` middleware in `main.rs`, so by the time
//! we get here the `AuthContext` extension is guaranteed present and we
//! have a verified `device_token` to feed the HMAC.
//!
//! Per-token rate-limit: 60 events/minute. Excess returns 429. The
//! limiter state is shared across all telemetry handlers via an
//! `Arc<RateLimiter<...>>` injected as an extension.

use std::num::NonZeroU32;
use std::sync::Arc;

use axum::extract::{Extension, State};
use axum::http::StatusCode;
use governor::clock::DefaultClock;
use governor::state::keyed::DashMapStateStore;
use governor::{Quota, RateLimiter};
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::db::macro_telemetry::{insert, RunEventBody};
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::macros::telemetry::device_hash;

/// Per-token rate limiter — bound to AppState via `.layer(Extension(...))`.
pub type TelemetryRateLimiter =
    RateLimiter<String, DashMapStateStore<String>, DefaultClock>;

/// Build a 60/minute keyed limiter. Keys are device tokens (`String`).
pub fn build_rate_limiter() -> Arc<TelemetryRateLimiter> {
    let quota = Quota::per_minute(NonZeroU32::new(60).expect("60 > 0"));
    Arc::new(RateLimiter::keyed(quota))
}

/// HMAC secret pulled from env, with a deterministic default for local dev
/// and tests. Production overrides via `MACROS_TELEMETRY_SECRET`.
pub fn hmac_secret() -> String {
    std::env::var("MACROS_TELEMETRY_SECRET")
        .unwrap_or_else(|_| "dev-macros-telemetry-secret".to_string())
}

pub async fn run_event(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Extension(limiter): Extension<Arc<TelemetryRateLimiter>>,
    Path(slug): Path<String>,
    Json(body): Json<RunEventBody>,
) -> Result<StatusCode, AppError> {
    // Per-token rate gate.
    let key = format!("dt:{}", auth.participant_id);
    if limiter.check_key(&key).is_err() {
        return Err(AppError::RateLimited);
    }

    // The device token isn't surfaced past auth middleware. We use the
    // participant UUID as the stable "token" for hashing — it has the same
    // shape (single per-device identifier) and is the row we just touched
    // in `validate_token`.
    let token_for_hash = auth.participant_id.to_string();
    let hash = device_hash(
        chrono::Utc::now().date_naive(),
        &hmac_secret(),
        &token_for_hash,
        &slug,
    );

    insert(&pool, &slug, &hash, &body).await?;
    Ok(StatusCode::NO_CONTENT)
}
