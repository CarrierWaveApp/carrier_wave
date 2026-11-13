use axum::extract::{Extension, Path, State};
use axum::http::StatusCode;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::{Achievement, AwardAchievementRequest, UserAchievement};

use super::challenges::DataResponse;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AchievementCatalogResponse {
    pub achievements: Vec<Achievement>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserAchievementsResponse {
    pub callsign: String,
    pub awards: Vec<UserAchievement>,
}

/// GET /v1/achievements — public catalog (excludes secret achievements).
pub async fn list_achievements_catalog(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<AchievementCatalogResponse>>, AppError> {
    let achievements = db::list_achievements(&pool, false).await?;
    Ok(Json(DataResponse {
        data: AchievementCatalogResponse { achievements },
    }))
}

/// GET /v1/users/:callsign/achievements — awards for a callsign.
pub async fn list_user_achievements(
    State(pool): State<PgPool>,
    Path(callsign): Path<String>,
) -> Result<Json<DataResponse<UserAchievementsResponse>>, AppError> {
    let callsign = callsign.to_uppercase();
    let awards = db::list_awards_for_callsign(&pool, &callsign).await?;
    Ok(Json(DataResponse {
        data: UserAchievementsResponse { callsign, awards },
    }))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SignalAchievementRequest {
    pub id: String,
    pub evidence: Option<serde_json::Value>,
}

/// POST /v1/users/me/achievements/signal — client-emitted ecosystem-usage signal.
///
/// Validates the achievement exists and is `award_method = 'signal'` so a
/// compromised client can't claim manual or auto badges. Records the award
/// for the authenticated callsign.
pub async fn report_signal(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<SignalAchievementRequest>,
) -> Result<(StatusCode, Json<DataResponse<UserAchievement>>), AppError> {
    let achievement = db::get_achievement(&pool, &body.id).await?.ok_or(AppError::Validation {
        message: format!("Unknown achievement: {}", body.id),
    })?;

    if achievement.award_method != "signal" {
        return Err(AppError::Validation {
            message: format!(
                "Achievement '{}' is not signal-awardable",
                body.id
            ),
        });
    }

    let award = db::award_achievement(
        &pool,
        &auth.callsign,
        &body.id,
        Some("signal"),
        body.evidence.as_ref(),
    )
    .await?;

    // Cross-platform: if iOS and macOS signals have both arrived, also award.
    crate::achievements::cross_platform_check(&pool, &auth.callsign).await;

    Ok((StatusCode::CREATED, Json(DataResponse { data: award })))
}

/// POST /v1/admin/achievements/:id/award — manually award to a callsign.
pub async fn admin_award_achievement(
    State(pool): State<PgPool>,
    Path(achievement_id): Path<String>,
    Json(body): Json<AwardAchievementRequest>,
) -> Result<(StatusCode, Json<DataResponse<UserAchievement>>), AppError> {
    if db::get_achievement(&pool, &achievement_id).await?.is_none() {
        return Err(AppError::Validation {
            message: format!("Unknown achievement: {achievement_id}"),
        });
    }

    let callsign = body.callsign.trim().to_uppercase();
    if callsign.is_empty() {
        return Err(AppError::Validation {
            message: "callsign is required".to_string(),
        });
    }

    let award = db::award_achievement(
        &pool,
        &callsign,
        &achievement_id,
        body.awarded_by.as_deref(),
        body.evidence.as_ref(),
    )
    .await?;

    Ok((StatusCode::CREATED, Json(DataResponse { data: award })))
}

/// DELETE /v1/admin/achievements/:id/award/:callsign — revoke an award.
pub async fn admin_revoke_achievement(
    State(pool): State<PgPool>,
    Path((achievement_id, callsign)): Path<(String, String)>,
) -> Result<StatusCode, AppError> {
    let callsign = callsign.to_uppercase();
    let removed = db::revoke_achievement(&pool, &callsign, &achievement_id).await?;
    if removed {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Ok(StatusCode::NOT_FOUND)
    }
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchAwardRequest {
    pub callsigns: Vec<String>,
    pub awarded_by: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BatchAwardResponse {
    pub awarded: usize,
    pub skipped: Vec<String>,
}

/// POST /v1/admin/achievements/:id/award/batch — bulk-award to many callsigns.
pub async fn admin_batch_award(
    State(pool): State<PgPool>,
    Path(achievement_id): Path<String>,
    Json(body): Json<BatchAwardRequest>,
) -> Result<Json<DataResponse<BatchAwardResponse>>, AppError> {
    if db::get_achievement(&pool, &achievement_id).await?.is_none() {
        return Err(AppError::Validation {
            message: format!("Unknown achievement: {achievement_id}"),
        });
    }

    let mut awarded = 0;
    let mut skipped = Vec::new();
    for raw in &body.callsigns {
        let callsign = raw.trim().to_uppercase();
        if callsign.is_empty() {
            skipped.push(raw.clone());
            continue;
        }
        match db::award_achievement(
            &pool,
            &callsign,
            &achievement_id,
            body.awarded_by.as_deref(),
            None,
        )
        .await
        {
            Ok(_) => awarded += 1,
            Err(_) => skipped.push(callsign),
        }
    }

    Ok(Json(DataResponse {
        data: BatchAwardResponse { awarded, skipped },
    }))
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BackfillResponse {
    pub callsigns_processed: usize,
}

/// POST /v1/admin/achievements/backfill — run every batch evaluator against
/// every callsign that's ever produced an activity. Idempotent.
pub async fn admin_backfill_achievements(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<BackfillResponse>>, AppError> {
    let callsigns = crate::achievements::all_callsigns(&pool).await?;
    let total = callsigns.len();

    for callsign in &callsigns {
        let ctx = crate::achievements::EvalCtx {
            pool: &pool,
            callsign,
            triggering: None,
        };
        crate::achievements::evaluate_batch(&ctx).await;
    }

    Ok(Json(DataResponse {
        data: BackfillResponse {
            callsigns_processed: total,
        },
    }))
}
