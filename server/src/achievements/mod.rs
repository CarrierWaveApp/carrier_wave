//! Achievement evaluation engine.
//!
//! Catalog badges with `award_method = 'auto'` are granted by these
//! evaluators. Two paths run them:
//!
//!   * Inline — invoked synchronously after `report_activity` writes the
//!     activity row. Used for first-of-kind badges where instant feedback
//!     matters (first-qso, first-cw, etc.).
//!   * Batch — run periodically by `aggregators::achievements` against
//!     callsigns with recent activity. Used for cumulative thresholds
//!     (qso-100, dxcc-100, streak-7, …) where SQL aggregates are cheap
//!     and the evaluator doesn't need the triggering activity row.
//!
//! Awards are written via `db::award_achievement`, which is idempotent
//! thanks to `UNIQUE(callsign, achievement_id)` — re-running an
//! evaluator never duplicates a row.

pub mod anniversary;
pub mod counts;
pub mod coverage;
pub mod firsts;
pub mod quirky;
pub mod streaks;

use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::PgPool;

use crate::db;
use crate::error::AppError;

/// One evaluation of an achievement against a callsign's history.
#[derive(Debug, Clone, Serialize)]
pub struct Award {
    pub achievement_id: &'static str,
    pub evidence: serde_json::Value,
}

/// Context passed to evaluators.
pub struct EvalCtx<'a> {
    pub pool: &'a PgPool,
    pub callsign: &'a str,
    /// The activity that triggered evaluation, if any (inline path).
    pub triggering: Option<TriggeringActivity<'a>>,
}

#[derive(Debug, Clone)]
pub struct TriggeringActivity<'a> {
    pub activity_type: &'a str,
    pub timestamp: DateTime<Utc>,
    pub details: &'a serde_json::Value,
}

/// Evaluate every inline-path evaluator and persist awards.
///
/// Called after a successful `INSERT INTO activities`. Errors are logged
/// and swallowed — a failed evaluator must NEVER fail the activity write.
pub async fn evaluate_inline(ctx: &EvalCtx<'_>) {
    let results = vec![
        firsts::evaluate(ctx).await,
        quirky::evaluate(ctx).await,
    ];

    for result in results {
        match result {
            Ok(awards) => write_awards(ctx.pool, ctx.callsign, &awards).await,
            Err(err) => tracing::warn!(
                callsign = ctx.callsign,
                error = %err,
                "Inline achievement evaluator failed",
            ),
        }
    }
}

/// Evaluate every batch-path evaluator for a single callsign.
pub async fn evaluate_batch(ctx: &EvalCtx<'_>) {
    let results = vec![
        counts::evaluate(ctx).await,
        coverage::evaluate(ctx).await,
        streaks::evaluate(ctx).await,
        anniversary::evaluate(ctx).await,
    ];

    for result in results {
        match result {
            Ok(awards) => write_awards(ctx.pool, ctx.callsign, &awards).await,
            Err(err) => tracing::warn!(
                callsign = ctx.callsign,
                error = %err,
                "Batch achievement evaluator failed",
            ),
        }
    }
}

async fn write_awards(pool: &PgPool, callsign: &str, awards: &[Award]) {
    for award in awards {
        if let Err(err) = db::award_achievement(
            pool,
            callsign,
            award.achievement_id,
            Some("system"),
            Some(&award.evidence),
        )
        .await
        {
            tracing::warn!(
                callsign,
                achievement = award.achievement_id,
                error = %err,
                "Failed to write achievement award",
            );
        }
    }
}

/// Walk the activities table and return distinct callsigns with activity in the
/// last `days` days. Used by the batch sweeper to bound work.
pub async fn recently_active_callsigns(
    pool: &PgPool,
    days: i32,
) -> Result<Vec<String>, AppError> {
    let rows: Vec<(String,)> = sqlx::query_as(
        r#"
        SELECT DISTINCT callsign
        FROM activities
        WHERE created_at > now() - ($1 || ' days')::interval
        "#,
    )
    .bind(days.to_string())
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(|row| row.0).collect())
}

/// If the callsign holds both an iOS-flavored signal (watch-operator,
/// home-screen, pebble-pioneer) and the macOS sweep-user signal — and
/// both arrived within the past 7 days — also award `cross-platform`.
pub async fn cross_platform_check(pool: &PgPool, callsign: &str) {
    let row: Result<Option<(bool,)>, _> = sqlx::query_as(
        r#"
        SELECT EXISTS (
            SELECT 1 FROM user_achievements
            WHERE callsign = $1
              AND achievement_id = 'sweep-user'
              AND awarded_at > now() - interval '7 days'
        ) AND EXISTS (
            SELECT 1 FROM user_achievements
            WHERE callsign = $1
              AND achievement_id IN ('watch-operator', 'home-screen', 'pebble-pioneer')
              AND awarded_at > now() - interval '7 days'
        )
        "#,
    )
    .bind(callsign)
    .fetch_optional(pool)
    .await;

    let qualifies = matches!(row, Ok(Some((true,))));
    if !qualifies {
        return;
    }

    let award = Award {
        achievement_id: "cross-platform",
        evidence: serde_json::json!({ "windowDays": 7 }),
    };
    write_awards(pool, callsign, &[award]).await;
}

/// Walk every callsign that has ever produced an activity. Used by the
/// backfill admin endpoint.
pub async fn all_callsigns(pool: &PgPool) -> Result<Vec<String>, AppError> {
    let rows: Vec<(String,)> = sqlx::query_as(
        r#"SELECT DISTINCT callsign FROM activities"#,
    )
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(|row| row.0).collect())
}
