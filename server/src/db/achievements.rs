use sqlx::PgPool;

use crate::error::AppError;
use crate::models::{Achievement, UserAchievement};

pub async fn list_achievements(
    pool: &PgPool,
    include_secret: bool,
) -> Result<Vec<Achievement>, AppError> {
    let rows = sqlx::query_as::<_, Achievement>(
        r#"
        SELECT id, name, description, category, tier, icon_name, accent_hex,
               award_method, secret, sort_order
        FROM achievements
        WHERE ($1 OR NOT secret)
        ORDER BY sort_order ASC, id ASC
        "#,
    )
    .bind(include_secret)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

pub async fn get_achievement(
    pool: &PgPool,
    achievement_id: &str,
) -> Result<Option<Achievement>, AppError> {
    let row = sqlx::query_as::<_, Achievement>(
        r#"
        SELECT id, name, description, category, tier, icon_name, accent_hex,
               award_method, secret, sort_order
        FROM achievements WHERE id = $1
        "#,
    )
    .bind(achievement_id)
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

pub async fn list_awards_for_callsign(
    pool: &PgPool,
    callsign: &str,
) -> Result<Vec<UserAchievement>, AppError> {
    let rows = sqlx::query_as::<_, UserAchievement>(
        r#"
        SELECT id, callsign, achievement_id, awarded_at, awarded_by, evidence
        FROM user_achievements
        WHERE callsign = $1
        ORDER BY awarded_at DESC
        "#,
    )
    .bind(callsign)
    .fetch_all(pool)
    .await?;

    Ok(rows)
}

pub async fn award_achievement(
    pool: &PgPool,
    callsign: &str,
    achievement_id: &str,
    awarded_by: Option<&str>,
    evidence: Option<&serde_json::Value>,
) -> Result<UserAchievement, AppError> {
    let row = sqlx::query_as::<_, UserAchievement>(
        r#"
        INSERT INTO user_achievements (callsign, achievement_id, awarded_by, evidence)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (callsign, achievement_id) DO UPDATE
            SET awarded_by = EXCLUDED.awarded_by,
                evidence = COALESCE(EXCLUDED.evidence, user_achievements.evidence)
        RETURNING id, callsign, achievement_id, awarded_at, awarded_by, evidence
        "#,
    )
    .bind(callsign)
    .bind(achievement_id)
    .bind(awarded_by)
    .bind(evidence)
    .fetch_one(pool)
    .await?;

    Ok(row)
}

pub async fn revoke_achievement(
    pool: &PgPool,
    callsign: &str,
    achievement_id: &str,
) -> Result<bool, AppError> {
    let result = sqlx::query(
        "DELETE FROM user_achievements WHERE callsign = $1 AND achievement_id = $2",
    )
    .bind(callsign)
    .bind(achievement_id)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}
