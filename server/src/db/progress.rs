use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::{LeaderboardEntry, LeaderboardQuery, Progress, ReportProgressRequest};

pub async fn get_progress(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<Option<Progress>, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let progress = sqlx::query_as::<_, Progress>(
        r#"
        SELECT id, challenge_id, callsign, completed_goals, current_value,
               score, current_tier, last_qso_date, updated_at
        FROM progress
        WHERE challenge_id = $1 AND callsign = $2
        "#,
    )
    .bind(challenge_id)
    .bind(&callsign_upper)
    .fetch_optional(pool)
    .await?;

    Ok(progress)
}

pub async fn upsert_progress(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
    req: &ReportProgressRequest,
    score: i32,
    current_tier: Option<&str>,
) -> Result<Progress, AppError> {
    let id = Uuid::new_v4();
    let callsign_upper = callsign.to_uppercase();
    let completed_goals = serde_json::to_value(&req.completed_goals)?;

    let progress = sqlx::query_as::<_, Progress>(
        r#"
        INSERT INTO progress (id, challenge_id, callsign, completed_goals, current_value, score, current_tier, last_qso_date)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (challenge_id, callsign) DO UPDATE
        SET completed_goals = $4, current_value = $5, score = $6,
            current_tier = $7, last_qso_date = $8, updated_at = now()
        RETURNING id, challenge_id, callsign, completed_goals, current_value,
                  score, current_tier, last_qso_date, updated_at
        "#,
    )
    .bind(id)
    .bind(challenge_id)
    .bind(&callsign_upper)
    .bind(&completed_goals)
    .bind(req.current_value)
    .bind(score)
    .bind(current_tier)
    .bind(req.last_qso_date)
    .fetch_one(pool)
    .await?;

    Ok(progress)
}

pub async fn get_rank(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<Option<i64>, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let row: Option<(Option<i64>,)> = sqlx::query_as(
        r#"
        SELECT rank FROM (
            SELECT callsign, RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank
            FROM progress
            WHERE challenge_id = $1
        ) ranked
        WHERE callsign = $2
        "#,
    )
    .bind(challenge_id)
    .bind(&callsign_upper)
    .fetch_optional(pool)
    .await?;

    Ok(row.and_then(|r| r.0))
}

pub async fn get_leaderboard(
    pool: &PgPool,
    challenge_id: Uuid,
    query: &LeaderboardQuery,
) -> Result<(Vec<LeaderboardEntry>, i64), AppError> {
    let limit = query.limit.unwrap_or(100).min(100);
    let offset = query.offset.unwrap_or(0);

    let entries = sqlx::query_as::<_, LeaderboardEntry>(
        r#"
        SELECT
            RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank,
            callsign,
            score,
            current_tier,
            CASE WHEN score > 0 THEN updated_at ELSE NULL END as completed_at
        FROM progress
        WHERE challenge_id = $1
        ORDER BY score DESC, updated_at ASC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(challenge_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let total: (i64,) = sqlx::query_as(r#"SELECT COUNT(*) FROM progress WHERE challenge_id = $1"#)
        .bind(challenge_id)
        .fetch_one(pool)
        .await?;

    Ok((entries, total.0))
}

pub async fn get_leaderboard_around(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
    range: i64,
) -> Result<Vec<LeaderboardEntry>, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let entries = sqlx::query_as::<_, LeaderboardEntry>(
        r#"
        WITH ranked AS (
            SELECT
                RANK() OVER (ORDER BY score DESC, updated_at ASC) as rank,
                callsign,
                score,
                current_tier,
                CASE WHEN score > 0 THEN updated_at ELSE NULL END as completed_at
            FROM progress
            WHERE challenge_id = $1
        )
        SELECT
            rank,
            callsign,
            score,
            current_tier,
            completed_at
        FROM ranked
        WHERE rank BETWEEN
            (SELECT rank FROM ranked WHERE callsign = $2) - $3
            AND
            (SELECT rank FROM ranked WHERE callsign = $2) + $3
        ORDER BY rank
        "#,
    )
    .bind(challenge_id)
    .bind(&callsign_upper)
    .bind(range)
    .fetch_all(pool)
    .await?;

    Ok(entries)
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        AppError::Internal(e.to_string())
    }
}
