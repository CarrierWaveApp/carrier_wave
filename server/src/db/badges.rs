use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::{Badge, BadgeMetadata};

pub async fn create_badge(
    pool: &PgPool,
    challenge_id: Uuid,
    name: &str,
    tier_id: Option<&str>,
    image_data: &[u8],
    content_type: &str,
) -> Result<BadgeMetadata, AppError> {
    let id = Uuid::new_v4();

    let badge = sqlx::query_as::<_, BadgeMetadata>(
        r#"
        INSERT INTO badges (id, challenge_id, name, tier_id, image_data, content_type)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, challenge_id, name, tier_id, content_type, created_at
        "#,
    )
    .bind(id)
    .bind(challenge_id)
    .bind(name)
    .bind(tier_id)
    .bind(image_data)
    .bind(content_type)
    .fetch_one(pool)
    .await?;

    Ok(badge)
}

pub async fn list_badges(
    pool: &PgPool,
    challenge_id: Uuid,
) -> Result<Vec<BadgeMetadata>, AppError> {
    let badges = sqlx::query_as::<_, BadgeMetadata>(
        r#"
        SELECT id, challenge_id, name, tier_id, content_type, created_at
        FROM badges
        WHERE challenge_id = $1
        ORDER BY created_at ASC
        "#,
    )
    .bind(challenge_id)
    .fetch_all(pool)
    .await?;

    Ok(badges)
}

pub async fn get_badge(pool: &PgPool, badge_id: Uuid) -> Result<Option<Badge>, AppError> {
    let badge = sqlx::query_as::<_, Badge>(
        r#"
        SELECT id, challenge_id, name, tier_id, image_data, content_type, created_at
        FROM badges
        WHERE id = $1
        "#,
    )
    .bind(badge_id)
    .fetch_optional(pool)
    .await?;

    Ok(badge)
}

pub async fn delete_badge(pool: &PgPool, badge_id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM badges WHERE id = $1")
        .bind(badge_id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}
