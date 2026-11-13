//! Cumulative-count evaluators (batch path).
//!
//!   * qso-100 / qso-1000 / qso-10000 — sum of `details.qsoCount` across all
//!     `sessionCompleted` activities the callsign has reported.
//!   * dxcc-10 / dxcc-100 — count distinct `details.entityName` across
//!     `newDXCCEntity` activities.

use serde_json::json;

use crate::error::AppError;

use super::{Award, EvalCtx};

pub async fn evaluate(ctx: &EvalCtx<'_>) -> Result<Vec<Award>, AppError> {
    let mut awards = Vec::new();

    let qso_total = total_qsos(ctx).await?;
    if qso_total >= 100 {
        awards.push(threshold_award("qso-100", qso_total));
    }
    if qso_total >= 1000 {
        awards.push(threshold_award("qso-1000", qso_total));
    }
    if qso_total >= 10000 {
        awards.push(threshold_award("qso-10000", qso_total));
    }

    let dxcc = distinct_dxcc(ctx).await?;
    if dxcc >= 10 {
        awards.push(Award {
            achievement_id: "dxcc-10",
            evidence: json!({ "entities": dxcc }),
        });
    }
    if dxcc >= 100 {
        awards.push(Award {
            achievement_id: "dxcc-100",
            evidence: json!({ "entities": dxcc }),
        });
    }

    Ok(awards)
}

fn threshold_award(id: &'static str, total: i64) -> Award {
    Award {
        achievement_id: id,
        evidence: json!({ "qsoCount": total }),
    }
}

async fn total_qsos(ctx: &EvalCtx<'_>) -> Result<i64, AppError> {
    let row: (Option<i64>,) = sqlx::query_as(
        r#"
        -- CAR-323: sum(bigint) returns NUMERIC in Postgres, which this crate has
        -- no sqlx decoder for (no bigdecimal/rust_decimal feature). Cast the
        -- aggregate back to bigint so it decodes into i64 instead of failing at
        -- runtime for every callsign. Matches db/sync.rs:291's house style.
        SELECT COALESCE(SUM((details->>'qsoCount')::bigint), 0)::bigint
        FROM activities
        WHERE callsign = $1
          AND activity_type = 'sessionCompleted'
          AND details ? 'qsoCount'
        "#,
    )
    .bind(ctx.callsign)
    .fetch_one(ctx.pool)
    .await?;

    Ok(row.0.unwrap_or(0))
}

async fn distinct_dxcc(ctx: &EvalCtx<'_>) -> Result<i64, AppError> {
    let row: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(DISTINCT details->>'entityName')
        FROM activities
        WHERE callsign = $1
          AND activity_type = 'newDXCCEntity'
          AND details->>'entityName' IS NOT NULL
        "#,
    )
    .bind(ctx.callsign)
    .fetch_one(ctx.pool)
    .await?;

    Ok(row.0)
}
