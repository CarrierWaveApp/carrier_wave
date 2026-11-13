//! Anniversary evaluator (batch path).
//!
//! Awards the "One Year On" badge once the callsign's row in `users` is
//! at least 365 days old. We pick `users.created_at` over
//! `participants.created_at` since `users` is the canonical identity row.

use serde_json::json;

use crate::error::AppError;

use super::{Award, EvalCtx};

pub async fn evaluate(ctx: &EvalCtx<'_>) -> Result<Vec<Award>, AppError> {
    let row: Option<(i64,)> = sqlx::query_as(
        r#"
        SELECT EXTRACT(EPOCH FROM (now() - created_at))::bigint
        FROM users
        WHERE callsign = $1
        "#,
    )
    .bind(ctx.callsign)
    .fetch_optional(ctx.pool)
    .await?;

    let Some((seconds,)) = row else {
        return Ok(vec![]);
    };

    if seconds >= 365 * 24 * 60 * 60 {
        return Ok(vec![Award {
            achievement_id: "anniversary",
            evidence: json!({ "ageSeconds": seconds }),
        }]);
    }

    Ok(vec![])
}
