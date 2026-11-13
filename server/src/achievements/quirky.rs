//! Quirky inline evaluators.
//!
//! `night-owl` and `eyeball` are awarded inline when the triggering
//! activity matches. Solar-storm and qrp-dx are deferred — they need
//! data sources (space weather, power level) that aren't reliably in
//! activity details yet.

use chrono::Timelike;
use serde_json::json;

use crate::error::AppError;

use super::{Award, EvalCtx};

pub async fn evaluate(ctx: &EvalCtx<'_>) -> Result<Vec<Award>, AppError> {
    let Some(trig) = &ctx.triggering else {
        return Ok(vec![]);
    };

    let mut awards = Vec::new();

    if let Some(award) = night_owl(trig) {
        awards.push(award);
    }

    if let Some(award) = eyeball(ctx, trig).await? {
        awards.push(award);
    }

    Ok(awards)
}

fn night_owl(trig: &super::TriggeringActivity<'_>) -> Option<Award> {
    // Coarse: UTC hour 02-04 catches a deep-night window for callers in
    // ~half the world. Until activities carry a TZ field this is the
    // most honest computation we can do.
    let hour = trig.timestamp.hour();
    if (2..=4).contains(&hour) {
        Some(Award {
            achievement_id: "night-owl",
            evidence: json!({ "utcHour": hour }),
        })
    } else {
        None
    }
}

async fn eyeball(
    ctx: &EvalCtx<'_>,
    trig: &super::TriggeringActivity<'_>,
) -> Result<Option<Award>, AppError> {
    if trig.activity_type != "workedFriend" {
        return Ok(None);
    }
    let Some(worked) = trig.details.get("workedCallsign").and_then(|val| val.as_str()) else {
        return Ok(None);
    };

    // Eyeball QSO = the worked callsign is also a registered Carrier Wave user.
    let row: Option<(String,)> = sqlx::query_as(
        r#"SELECT callsign FROM users WHERE callsign = $1 LIMIT 1"#,
    )
    .bind(worked.to_uppercase())
    .fetch_optional(ctx.pool)
    .await?;

    if row.is_some() {
        Ok(Some(Award {
            achievement_id: "eyeball",
            evidence: json!({ "workedCallsign": worked.to_uppercase() }),
        }))
    } else {
        Ok(None)
    }
}
