use axum::extract::{Extension, State};

use crate::extractors::{Json, Path};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::models::{Progress, ProgressResponse, ReportProgressRequest, ReportProgressResponse};

use super::DataResponse;

pub async fn report_progress(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Extension(auth): Extension<AuthContext>,
    Json(req): Json<ReportProgressRequest>,
) -> Result<Json<DataResponse<ReportProgressResponse>>, AppError> {
    let challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let _participation = db::get_participation(&pool, challenge_id, &auth.callsign)
        .await?
        .ok_or(AppError::NotParticipating)?;

    let score = calculate_score(&challenge.configuration, &req);
    let current_tier = determine_tier(&challenge.configuration, score);

    let _progress = db::upsert_progress(
        &pool,
        challenge_id,
        &auth.callsign,
        &req,
        score,
        current_tier.as_deref(),
    )
    .await?;

    let rank = db::get_rank(&pool, challenge_id, &auth.callsign)
        .await?
        .unwrap_or(0);

    let percentage = calculate_percentage(&challenge.configuration, &req);
    let new_badges = vec![];

    Ok(Json(DataResponse {
        data: ReportProgressResponse {
            accepted: true,
            server_progress: ProgressResponse {
                completed_goals: req.completed_goals,
                current_value: req.current_value,
                percentage,
                score,
                rank,
                current_tier,
            },
            new_badges,
        },
    }))
}

pub async fn get_progress(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<ProgressResponse>>, AppError> {
    let challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let progress = db::get_progress(&pool, challenge_id, &auth.callsign)
        .await?
        .ok_or(AppError::NotParticipating)?;

    let rank = db::get_rank(&pool, challenge_id, &auth.callsign)
        .await?
        .unwrap_or(0);

    let completed_goals: Vec<String> =
        serde_json::from_value(progress.completed_goals.clone()).unwrap_or_default();

    let percentage = calculate_percentage_from_progress(&challenge.configuration, &progress);

    Ok(Json(DataResponse {
        data: ProgressResponse {
            completed_goals,
            current_value: progress.current_value,
            percentage,
            score: progress.score,
            rank,
            current_tier: progress.current_tier,
        },
    }))
}

fn calculate_score(config: &serde_json::Value, req: &ReportProgressRequest) -> i32 {
    let scoring = config.get("scoring");
    let method = scoring
        .and_then(|s| s.get("method"))
        .and_then(|m| m.as_str())
        .unwrap_or("count");

    match method {
        "percentage" => {
            let total = get_total_goals(config);
            if total > 0 {
                (req.completed_goals.len() as f64 / total as f64 * 100.0) as i32
            } else {
                0
            }
        }
        "count" => req.completed_goals.len() as i32,
        "points" => req.current_value,
        _ => req.completed_goals.len() as i32,
    }
}

fn calculate_percentage(config: &serde_json::Value, req: &ReportProgressRequest) -> f64 {
    let goals = config.get("goals");
    let goal_type = goals
        .and_then(|g| g.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("collection");

    match goal_type {
        "collection" => {
            let total = get_total_goals(config);
            if total > 0 {
                req.completed_goals.len() as f64 / total as f64 * 100.0
            } else {
                0.0
            }
        }
        "cumulative" => {
            let target = goals
                .and_then(|g| g.get("targetValue"))
                .and_then(|t| t.as_i64())
                .unwrap_or(100) as f64;
            if target > 0.0 {
                req.current_value as f64 / target * 100.0
            } else {
                0.0
            }
        }
        _ => 0.0,
    }
}

fn calculate_percentage_from_progress(config: &serde_json::Value, progress: &Progress) -> f64 {
    let goals = config.get("goals");
    let goal_type = goals
        .and_then(|g| g.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("collection");

    match goal_type {
        "collection" => {
            let total = get_total_goals(config);
            let completed: Vec<String> =
                serde_json::from_value(progress.completed_goals.clone()).unwrap_or_default();
            if total > 0 {
                completed.len() as f64 / total as f64 * 100.0
            } else {
                0.0
            }
        }
        "cumulative" => {
            let target = goals
                .and_then(|g| g.get("targetValue"))
                .and_then(|t| t.as_i64())
                .unwrap_or(100) as f64;
            if target > 0.0 {
                progress.current_value as f64 / target * 100.0
            } else {
                0.0
            }
        }
        _ => 0.0,
    }
}

fn get_total_goals(config: &serde_json::Value) -> usize {
    config
        .get("goals")
        .and_then(|g| g.get("items"))
        .and_then(|i| i.as_array())
        .map(|a| a.len())
        .unwrap_or(0)
}

fn determine_tier(config: &serde_json::Value, score: i32) -> Option<String> {
    let tiers = config.get("tiers")?.as_array()?;
    let mut current_tier: Option<&serde_json::Value> = None;

    for tier in tiers {
        let threshold = tier.get("threshold")?.as_i64()? as i32;
        if score >= threshold {
            current_tier = Some(tier);
        }
    }

    current_tier
        .and_then(|t| t.get("id"))
        .and_then(|id| id.as_str())
        .map(String::from)
}
