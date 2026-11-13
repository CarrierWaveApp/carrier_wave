use chrono::{DateTime, Utc};
use rand::Rng;
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::InviteToken;

fn generate_invite_token() -> String {
    let mut rng = rand::thread_rng();
    let chars: Vec<char> = (0..24)
        .map(|_| {
            let idx = rng.gen_range(0..36);
            if idx < 10 {
                (b'0' + idx) as char
            } else {
                (b'a' + idx - 10) as char
            }
        })
        .collect();
    format!("inv_{}", chars.into_iter().collect::<String>())
}

pub async fn create_invite(
    pool: &PgPool,
    challenge_id: Uuid,
    max_uses: Option<i32>,
    expires_at: Option<DateTime<Utc>>,
) -> Result<InviteToken, AppError> {
    let token = generate_invite_token();

    let invite = sqlx::query_as::<_, InviteToken>(
        r#"
        INSERT INTO invite_tokens (token, challenge_id, max_uses, expires_at)
        VALUES ($1, $2, $3, $4)
        RETURNING token, challenge_id, max_uses, use_count, expires_at, created_at
        "#,
    )
    .bind(&token)
    .bind(challenge_id)
    .bind(max_uses)
    .bind(expires_at)
    .fetch_one(pool)
    .await?;

    Ok(invite)
}

pub async fn list_invites(pool: &PgPool, challenge_id: Uuid) -> Result<Vec<InviteToken>, AppError> {
    let invites = sqlx::query_as::<_, InviteToken>(
        r#"
        SELECT token, challenge_id, max_uses, use_count, expires_at, created_at
        FROM invite_tokens
        WHERE challenge_id = $1
        ORDER BY created_at DESC
        "#,
    )
    .bind(challenge_id)
    .fetch_all(pool)
    .await?;

    Ok(invites)
}

pub async fn get_invite(pool: &PgPool, token: &str) -> Result<Option<InviteToken>, AppError> {
    let invite = sqlx::query_as::<_, InviteToken>(
        r#"
        SELECT token, challenge_id, max_uses, use_count, expires_at, created_at
        FROM invite_tokens
        WHERE token = $1
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?;

    Ok(invite)
}

/// Atomically redeem one use of an invite token, enforcing the challenge match,
/// expiry, and `max_uses` cap in a single conditional UPDATE so concurrent
/// redemptions cannot race past the cap (CAR-311). Returns `Ok(())` only if a
/// use was consumed; otherwise the token is missing, for another challenge,
/// expired, or exhausted.
pub async fn redeem_invite(
    pool: &PgPool,
    token: &str,
    challenge_id: Uuid,
) -> Result<(), AppError> {
    let result = sqlx::query(
        r#"
        UPDATE invite_tokens
        SET use_count = use_count + 1
        WHERE token = $1
          AND challenge_id = $2
          AND (expires_at IS NULL OR expires_at > now())
          AND (max_uses IS NULL OR use_count < max_uses)
        "#,
    )
    .bind(token)
    .bind(challenge_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::InviteExhausted);
    }
    Ok(())
}

/// Give back a use previously reserved by [`redeem_invite`] when the action it
/// was reserved for (e.g. the challenge join) ultimately failed. Best-effort;
/// never drives `use_count` below zero.
pub async fn release_invite(
    pool: &PgPool,
    token: &str,
    challenge_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        UPDATE invite_tokens
        SET use_count = GREATEST(use_count - 1, 0)
        WHERE token = $1 AND challenge_id = $2
        "#,
    )
    .bind(token)
    .bind(challenge_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn delete_invite(pool: &PgPool, token: &str) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM invite_tokens WHERE token = $1")
        .bind(token)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}
