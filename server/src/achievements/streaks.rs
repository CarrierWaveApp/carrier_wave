//! Streak evaluators (batch path).
//!
//! The iOS app reports `dailyStreak` activities with a `streakDays` value
//! once a streak is reached. We award the milestone tiers based on the
//! highest streak length seen so far.

use serde_json::json;

use crate::error::AppError;

use super::{Award, EvalCtx};

pub async fn evaluate(ctx: &EvalCtx<'_>) -> Result<Vec<Award>, AppError> {
    let max_streak = max_streak_days(ctx).await?;
    let mut awards = Vec::new();

    if max_streak >= 7 {
        awards.push(streak_award("streak-7", max_streak));
    }
    if max_streak >= 30 {
        awards.push(streak_award("streak-30", max_streak));
    }
    if max_streak >= 365 {
        awards.push(streak_award("streak-365", max_streak));
    }

    Ok(awards)
}

fn streak_award(id: &'static str, days: i64) -> Award {
    Award {
        achievement_id: id,
        evidence: json!({ "streakDays": days }),
    }
}

async fn max_streak_days(ctx: &EvalCtx<'_>) -> Result<i64, AppError> {
    let row: (Option<i64>,) = sqlx::query_as(
        r#"
        -- CAR-324: `details` is arbitrary client JSON, so a `streakDays` that is a
        -- string, float, or out-of-range integer made the raw `::bigint` cast
        -- throw and permanently killed streak evaluation for the callsign. Only
        -- consider JSON numbers, cast via numeric so floats parse, floor to a
        -- whole day, and clamp so a huge value can't overflow bigint.
        SELECT MAX(LEAST(floor((details->>'streakDays')::numeric), 100000)::bigint)
        FROM activities
        WHERE callsign = $1
          AND activity_type IN ('dailyStreak', 'potaDailyStreak')
          AND jsonb_typeof(details->'streakDays') = 'number'
        "#,
    )
    .bind(ctx.callsign)
    .fetch_one(ctx.pool)
    .await?;

    Ok(row.0.unwrap_or(0))
}
