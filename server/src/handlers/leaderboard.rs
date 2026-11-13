use axum::extract::{Query, State};

use crate::extractors::{Json, Path};
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::models::{LeaderboardQuery, LeaderboardResponse};

use super::DataResponse;

pub async fn get_leaderboard(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Query(query): Query<LeaderboardQuery>,
) -> Result<Json<DataResponse<LeaderboardResponse>>, AppError> {
    let _challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let (leaderboard, total) = if let Some(ref around) = query.around {
        let entries = db::get_leaderboard_around(&pool, challenge_id, around, 5).await?;
        let total: (i64,) =
            sqlx::query_as(r#"SELECT COUNT(*) FROM progress WHERE challenge_id = $1"#)
                .bind(challenge_id)
                .fetch_one(&pool)
                .await?;
        (entries, total.0)
    } else {
        db::get_leaderboard(&pool, challenge_id, &query).await?
    };

    let user_position = if let Some(ref around) = query.around {
        leaderboard.iter().find(|e| e.callsign == *around).cloned()
    } else {
        None
    };

    Ok(Json(DataResponse {
        data: LeaderboardResponse {
            leaderboard,
            total,
            user_position,
            last_updated: Utc::now(),
        },
    }))
}
