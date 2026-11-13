use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::{Challenge, ChallengeListItem, CreateChallengeRequest, ListChallengesQuery};

pub async fn list_challenges(
    pool: &PgPool,
    query: &ListChallengesQuery,
) -> Result<(Vec<ChallengeListItem>, i64), AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let challenges = sqlx::query_as::<_, ChallengeListItem>(
        r#"
        SELECT
            c.id,
            c.name,
            c.description,
            c.category,
            c.challenge_type,
            c.is_active,
            COALESCE(COUNT(cp.id), 0) as participant_count
        FROM challenges c
        LEFT JOIN challenge_participants cp ON cp.challenge_id = c.id AND cp.status = 'active'
        WHERE ($1::text IS NULL OR c.category = $1)
          AND ($2::text IS NULL OR c.challenge_type = $2)
          AND ($3::bool IS NULL OR c.is_active = $3)
        GROUP BY c.id
        ORDER BY c.created_at DESC
        LIMIT $4 OFFSET $5
        "#,
    )
    .bind(&query.category)
    .bind(&query.challenge_type)
    .bind(query.active)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let total: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*)
        FROM challenges c
        WHERE ($1::text IS NULL OR c.category = $1)
          AND ($2::text IS NULL OR c.challenge_type = $2)
          AND ($3::bool IS NULL OR c.is_active = $3)
        "#,
    )
    .bind(&query.category)
    .bind(&query.challenge_type)
    .bind(query.active)
    .fetch_one(pool)
    .await?;

    Ok((challenges, total.0))
}

pub async fn get_challenge(pool: &PgPool, id: Uuid) -> Result<Option<Challenge>, AppError> {
    let challenge = sqlx::query_as::<_, Challenge>(
        r#"
        SELECT
            id, version, name, description, author, category, challenge_type,
            configuration, invite_config, hamalert_config, is_active,
            created_at, updated_at
        FROM challenges
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(challenge)
}

pub async fn create_challenge(
    pool: &PgPool,
    req: &CreateChallengeRequest,
) -> Result<Challenge, AppError> {
    let id = Uuid::new_v4();

    let challenge = sqlx::query_as::<_, Challenge>(
        r#"
        INSERT INTO challenges (id, name, description, author, category, challenge_type, configuration, invite_config, hamalert_config, is_active)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, COALESCE($10, true))
        RETURNING id, version, name, description, author, category, challenge_type,
                  configuration, invite_config, hamalert_config, is_active,
                  created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(&req.name)
    .bind(&req.description)
    .bind(&req.author)
    .bind(&req.category)
    .bind(&req.challenge_type)
    .bind(&req.configuration)
    .bind(&req.invite_config)
    .bind(&req.hamalert_config)
    .bind(req.is_active)
    .fetch_one(pool)
    .await?;

    Ok(challenge)
}

pub async fn update_challenge(
    pool: &PgPool,
    id: Uuid,
    req: &CreateChallengeRequest,
) -> Result<Option<Challenge>, AppError> {
    let challenge = sqlx::query_as::<_, Challenge>(
        r#"
        UPDATE challenges
        SET name = $2, description = $3, author = $4, category = $5,
            challenge_type = $6, configuration = $7, invite_config = $8,
            hamalert_config = $9, is_active = COALESCE($10, is_active),
            version = version + 1, updated_at = now()
        WHERE id = $1
        RETURNING id, version, name, description, author, category, challenge_type,
                  configuration, invite_config, hamalert_config, is_active,
                  created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(&req.name)
    .bind(&req.description)
    .bind(&req.author)
    .bind(&req.category)
    .bind(&req.challenge_type)
    .bind(&req.configuration)
    .bind(&req.invite_config)
    .bind(&req.hamalert_config)
    .bind(req.is_active)
    .fetch_optional(pool)
    .await?;

    Ok(challenge)
}

pub async fn delete_challenge(pool: &PgPool, id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM challenges WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}
