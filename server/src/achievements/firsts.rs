//! Inline evaluators that award the "first time" badges.
//!
//! These run on every activity write. Each guard short-circuits when the
//! triggering activity isn't relevant, keeping the hot path cheap.

use serde_json::json;

use crate::error::AppError;

use super::{Award, EvalCtx};

const FIRST_QSO: &str = "first-qso";
const FIRST_CW: &str = "first-cw";
const FIRST_SSB: &str = "first-ssb";
const FIRST_FT8: &str = "first-ft8";
const POLYGLOT: &str = "mode-polyglot";

pub async fn evaluate(ctx: &EvalCtx<'_>) -> Result<Vec<Award>, AppError> {
    let Some(trig) = &ctx.triggering else {
        return Ok(vec![]);
    };

    let mut awards = Vec::new();

    if trig.activity_type == "sessionCompleted" {
        awards.push(Award {
            achievement_id: FIRST_QSO,
            evidence: json!({ "from": "sessionCompleted" }),
        });
    }

    let mode = trig
        .details
        .get("mode")
        .and_then(|val| val.as_str())
        .map(|raw| raw.to_uppercase())
        .unwrap_or_default();

    match mode.as_str() {
        "CW" => awards.push(Award {
            achievement_id: FIRST_CW,
            evidence: json!({ "mode": "CW" }),
        }),
        "SSB" | "USB" | "LSB" | "PHONE" => awards.push(Award {
            achievement_id: FIRST_SSB,
            evidence: json!({ "mode": mode }),
        }),
        "FT8" => awards.push(Award {
            achievement_id: FIRST_FT8,
            evidence: json!({ "mode": "FT8" }),
        }),
        _ => {}
    }

    if trig.activity_type == "newMode" {
        // Count distinct modes seen across newMode activities so far.
        let count = distinct_mode_count(ctx).await?;
        if count >= 5 {
            awards.push(Award {
                achievement_id: POLYGLOT,
                evidence: json!({ "modeCount": count }),
            });
        }
    }

    Ok(awards)
}

async fn distinct_mode_count(ctx: &EvalCtx<'_>) -> Result<i64, AppError> {
    let row: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(DISTINCT details->>'mode')
        FROM activities
        WHERE callsign = $1
          AND activity_type = 'newMode'
          AND details->>'mode' IS NOT NULL
        "#,
    )
    .bind(ctx.callsign)
    .fetch_one(ctx.pool)
    .await?;

    Ok(row.0)
}
