//! Run-event telemetry inserts (CAR-271 T6).
//!
//! Writes are append-only; row IDs are BIGSERIAL. The 90-day retention
//! job (T9) rolls these into `macro_run_aggregates` and deletes the
//! source rows.

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;

#[derive(Debug, Clone, serde::Deserialize)]
pub struct RunEventBody {
    pub success: bool,
    /// `Some(idx)` only when `success == false`.
    pub failed_step_index: Option<i32>,
    /// Caller-supplied diagnostic — short canonical token like
    /// "ptt-stuck-high", "timeout-waiting-on-readField", etc.
    pub error_code: Option<String>,
    /// Optional wall-clock timestamp from the device. Server-side we still
    /// stamp `occurred_at = NOW()` unless the device timestamp lands inside
    /// the last 48 hours (anti-skew safeguard).
    pub occurred_at: Option<DateTime<Utc>>,
}

pub async fn insert(
    pool: &PgPool,
    slug: &str,
    device_hash: &str,
    body: &RunEventBody,
) -> Result<(), AppError> {
    // Resolve slug → macro_id. Reject unknown slugs at the boundary so we
    // never accept telemetry for a macro that was never published.
    let macro_id: Option<(Uuid,)> = sqlx::query_as(
        "SELECT id FROM macros WHERE slug = $1 AND status = 'approved'",
    )
    .bind(slug)
    .fetch_optional(pool)
    .await?;
    let Some((macro_id,)) = macro_id else {
        return Err(AppError::Validation {
            message: format!("macro not found or not approved: {slug}"),
        });
    };

    // Anti-skew: only honour `occurred_at` if it's within 48 hours of now.
    let now = Utc::now();
    let occurred_at = match body.occurred_at {
        Some(ts)
            if (now - ts).num_hours().abs() <= 48 =>
        {
            ts
        }
        _ => now,
    };

    sqlx::query(
        "INSERT INTO macro_run_events \
            (macro_id, device_hash, success, failed_step_index, error_code, occurred_at) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(macro_id)
    .bind(device_hash)
    .bind(body.success)
    .bind(body.failed_step_index)
    .bind(body.error_code.as_deref())
    .bind(occurred_at)
    .execute(pool)
    .await?;

    Ok(())
}
