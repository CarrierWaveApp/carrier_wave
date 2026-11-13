use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::generate_device_token;
use crate::error::AppError;
use crate::models::{ChallengeParticipant, ChallengeParticipation, Participant};

pub async fn get_or_create_participant(
    pool: &PgPool,
    callsign: &str,
    device_name: Option<&str>,
) -> Result<(Participant, bool), AppError> {
    let callsign_upper = callsign.to_uppercase();

    let existing = sqlx::query_as::<_, Participant>(
        r#"
        SELECT id, callsign, device_token, device_name, created_at, last_seen_at
        FROM participants
        WHERE callsign = $1
        LIMIT 1
        "#,
    )
    .bind(&callsign_upper)
    .fetch_optional(pool)
    .await?;

    if let Some(p) = existing {
        return Ok((p, false));
    }

    let id = Uuid::new_v4();
    let device_token = generate_device_token();

    let participant = sqlx::query_as::<_, Participant>(
        r#"
        INSERT INTO participants (id, callsign, device_token, device_name)
        VALUES ($1, $2, $3, $4)
        RETURNING id, callsign, device_token, device_name, created_at, last_seen_at
        "#,
    )
    .bind(id)
    .bind(&callsign_upper)
    .bind(&device_token)
    .bind(device_name)
    .fetch_one(pool)
    .await?;

    Ok((participant, true))
}

#[allow(dead_code)]
pub async fn get_participant_by_token(
    pool: &PgPool,
    token: &str,
) -> Result<Option<Participant>, AppError> {
    let participant = sqlx::query_as::<_, Participant>(
        r#"
        SELECT id, callsign, device_token, device_name, created_at, last_seen_at
        FROM participants
        WHERE device_token = $1
        "#,
    )
    .bind(token)
    .fetch_optional(pool)
    .await?;

    Ok(participant)
}

pub async fn get_challenges_for_callsign(
    pool: &PgPool,
    callsign: &str,
) -> Result<Vec<ChallengeParticipation>, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let challenges = sqlx::query_as::<_, ChallengeParticipation>(
        r#"
        SELECT
            cp.id as participation_id,
            cp.challenge_id,
            c.name as challenge_name,
            cp.joined_at,
            cp.status
        FROM challenge_participants cp
        JOIN challenges c ON c.id = cp.challenge_id
        WHERE cp.callsign = $1 AND cp.status = 'active'
        ORDER BY cp.joined_at DESC
        "#,
    )
    .bind(&callsign_upper)
    .fetch_all(pool)
    .await?;

    Ok(challenges)
}

pub async fn join_challenge(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
    invite_token: Option<&str>,
) -> Result<ChallengeParticipant, AppError> {
    let id = Uuid::new_v4();
    let callsign_upper = callsign.to_uppercase();

    let participation = sqlx::query_as::<_, ChallengeParticipant>(
        r#"
        INSERT INTO challenge_participants (id, challenge_id, callsign, invite_token)
        VALUES ($1, $2, $3, $4)
        RETURNING id, challenge_id, callsign, invite_token, joined_at, status
        "#,
    )
    .bind(id)
    .bind(challenge_id)
    .bind(&callsign_upper)
    .bind(invite_token)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        if let sqlx::Error::Database(ref db_err) = e {
            if db_err.constraint() == Some("challenge_participants_challenge_id_callsign_key") {
                return AppError::AlreadyJoined;
            }
        }
        AppError::Database(e)
    })?;

    Ok(participation)
}

pub async fn get_participation(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<Option<ChallengeParticipant>, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let participation = sqlx::query_as::<_, ChallengeParticipant>(
        r#"
        SELECT id, challenge_id, callsign, invite_token, joined_at, status
        FROM challenge_participants
        WHERE challenge_id = $1 AND callsign = $2
        "#,
    )
    .bind(challenge_id)
    .bind(&callsign_upper)
    .fetch_optional(pool)
    .await?;

    Ok(participation)
}

// No longer called from the leave handler, which now runs the status update and
// the progress delete in one transaction (CAR-336). Retained as a standalone
// helper.
#[allow(dead_code)]
pub async fn leave_challenge(
    pool: &PgPool,
    challenge_id: Uuid,
    callsign: &str,
) -> Result<bool, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let result = sqlx::query(
        r#"
        UPDATE challenge_participants
        SET status = 'left'
        WHERE challenge_id = $1 AND callsign = $2 AND status = 'active'
        "#,
    )
    .bind(challenge_id)
    .bind(&callsign_upper)
    .execute(pool)
    .await?;

    Ok(result.rows_affected() > 0)
}

#[allow(dead_code)]
pub async fn revoke_tokens(pool: &PgPool, callsign: &str) -> Result<u64, AppError> {
    let callsign_upper = callsign.to_uppercase();

    let result = sqlx::query("DELETE FROM participants WHERE callsign = $1")
        .bind(&callsign_upper)
        .execute(pool)
        .await?;

    Ok(result.rows_affected())
}

// Retained for a future *authenticated* token-rotation endpoint. No longer
// called from the join flow: rotating and returning a token to an unauthenticated
// caller was an account-takeover primitive (CAR-302 / CAR-305 / CAR-315).
#[allow(dead_code)]
pub async fn refresh_participant_token(
    pool: &PgPool,
    callsign: &str,
) -> Result<Participant, AppError> {
    let callsign_upper = callsign.to_uppercase();
    let new_token = generate_device_token();

    let participant = sqlx::query_as::<_, Participant>(
        r#"
        UPDATE participants
        SET device_token = $1
        WHERE callsign = $2
        RETURNING id, callsign, device_token, device_name, created_at, last_seen_at
        "#,
    )
    .bind(&new_token)
    .bind(&callsign_upper)
    .fetch_one(pool)
    .await?;

    Ok(participant)
}
