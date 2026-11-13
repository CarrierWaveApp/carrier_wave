use chrono::{Duration, Utc};
use rand::Rng;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::FriendInvite;

fn generate_friend_invite_token() -> String {
    const CHARSET: &[u8] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut rng = rand::thread_rng();

    let token: String = (0..24)
        .map(|_| {
            let idx = rng.gen_range(0..CHARSET.len());
            CHARSET[idx] as char
        })
        .collect();

    format!("inv_{}", token)
}

pub async fn create_friend_invite(
    pool: &PgPool,
    user_id: Uuid,
    expiry_days: i64,
) -> Result<FriendInvite, AppError> {
    let token = generate_friend_invite_token();
    let expires_at = Utc::now() + Duration::days(expiry_days);

    let invite = sqlx::query_as::<_, FriendInvite>(
        r#"
        INSERT INTO friend_invites (token, user_id, expires_at)
        VALUES ($1, $2, $3)
        RETURNING id, token, user_id, created_at, expires_at, used_at, used_by_user_id
        "#,
    )
    .bind(&token)
    .bind(user_id)
    .bind(expires_at)
    .fetch_one(pool)
    .await?;

    Ok(invite)
}

pub async fn get_friend_invite(
    pool: &PgPool,
    token: &str,
) -> Result<Option<FriendInvite>, AppError> {
    let invite = sqlx::query_as::<_, FriendInvite>(
        r#"
        SELECT id, token, user_id, created_at, expires_at, used_at, used_by_user_id
        FROM friend_invites
        WHERE token = $1
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?;

    Ok(invite)
}

pub async fn get_valid_friend_invite(
    pool: &PgPool,
    token: &str,
) -> Result<Option<FriendInvite>, AppError> {
    let invite = sqlx::query_as::<_, FriendInvite>(
        r#"
        SELECT id, token, user_id, created_at, expires_at, used_at, used_by_user_id
        FROM friend_invites
        WHERE token = $1
          AND expires_at > now()
          AND used_at IS NULL
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?;

    Ok(invite)
}

pub async fn mark_invite_used(
    pool: &PgPool,
    token: &str,
    used_by_user_id: Uuid,
) -> Result<Option<FriendInvite>, AppError> {
    let invite = sqlx::query_as::<_, FriendInvite>(
        r#"
        UPDATE friend_invites
        SET used_at = now(), used_by_user_id = $2
        WHERE token = $1
        RETURNING id, token, user_id, created_at, expires_at, used_at, used_by_user_id
        "#,
    )
    .bind(token)
    .bind(used_by_user_id)
    .fetch_optional(pool)
    .await?;

    Ok(invite)
}

#[allow(dead_code)]
pub async fn cleanup_expired_invites(pool: &PgPool) -> Result<u64, AppError> {
    let result = sqlx::query(
        r#"
        DELETE FROM friend_invites
        WHERE expires_at < now() - INTERVAL '30 days'
           OR used_at < now() - INTERVAL '30 days'
        "#,
    )
    .execute(pool)
    .await?;

    Ok(result.rows_affected())
}
