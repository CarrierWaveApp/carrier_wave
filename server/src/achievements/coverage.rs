//! Band/state/grid coverage evaluators (batch path).
//!
//! In the current activity schema only band coverage is reliably available
//! (via `newBand` activity reports). `was`, `wac`, and `grid-50` are
//! deferred until activity reports carry the underlying QSO state/grid.

use serde_json::json;

use crate::error::AppError;

use super::{Award, EvalCtx};

const HF_BANDS: &[&str] = &[
    "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
];

pub async fn evaluate(ctx: &EvalCtx<'_>) -> Result<Vec<Award>, AppError> {
    let bands = distinct_bands(ctx).await?;
    let hf_hit: Vec<&&str> = HF_BANDS
        .iter()
        .filter(|wanted| bands.iter().any(|seen| seen.eq_ignore_ascii_case(wanted)))
        .collect();

    if hf_hit.len() == HF_BANDS.len() {
        return Ok(vec![Award {
            achievement_id: "all-hf",
            evidence: json!({ "bands": HF_BANDS }),
        }]);
    }

    Ok(vec![])
}

async fn distinct_bands(ctx: &EvalCtx<'_>) -> Result<Vec<String>, AppError> {
    let rows: Vec<(Option<String>,)> = sqlx::query_as(
        r#"
        SELECT DISTINCT details->>'band'
        FROM activities
        WHERE callsign = $1
          AND activity_type IN ('newBand', 'sessionCompleted', 'newDXCCEntity')
          AND details->>'band' IS NOT NULL
        "#,
    )
    .bind(ctx.callsign)
    .fetch_all(ctx.pool)
    .await?;

    Ok(rows.into_iter().filter_map(|row| row.0).collect())
}
