use axum::{
    extract::{Extension, State},
    http::StatusCode,
};

use crate::extractors::{Json, Path};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::models::{JoinChallengeRequest, JoinChallengeResponse};

use super::DataResponse;

pub async fn join_challenge(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    auth: Option<Extension<AuthContext>>,
    Json(req): Json<JoinChallengeRequest>,
) -> Result<(StatusCode, Json<DataResponse<JoinChallengeResponse>>), AppError> {
    let challenge = db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    if !challenge.is_active {
        return Err(AppError::ChallengeEnded);
    }

    let requires_token = challenge
        .invite_config
        .as_ref()
        .and_then(|cfg| cfg.get("requiresToken"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);

    // SECURITY (CAR-311): an invite-gated challenge previously accepted ANY
    // non-null invite_token (including "") and never verified that the token
    // belonged to this challenge, was unexpired, or was under max_uses. Validate
    // the token up front for a precise error; the authoritative, race-safe cap is
    // enforced by redeem_invite just before the join below.
    let validated_token: Option<String> = if requires_token {
        let token = req
            .invite_token
            .as_deref()
            .map(str::trim)
            .filter(|t| !t.is_empty())
            .ok_or(AppError::InviteRequired)?;

        let invite = db::invites::get_invite(&pool, token)
            .await?
            .filter(|inv| inv.challenge_id == challenge_id)
            .ok_or(AppError::InviteRequired)?;
        if invite.expires_at.is_some_and(|exp| exp <= chrono::Utc::now()) {
            return Err(AppError::InviteExpired);
        }
        if invite.max_uses.is_some_and(|max| invite.use_count >= max) {
            return Err(AppError::InviteExhausted);
        }
        Some(token.to_string())
    } else {
        None
    };

    let (participant, is_new) =
        db::get_or_create_participant(&pool, &req.callsign, req.device_name.as_deref()).await?;

    // SECURITY (CAR-302 / CAR-305 / CAR-315): if the callsign already exists this
    // is not onboarding. The handler previously rotated the participant's
    // device_token and returned it to *any* caller — an unauthenticated
    // account-takeover + lockout primitive. Never rotate or disclose a token for
    // an existing callsign; require the caller to already be authenticated as
    // that exact callsign before letting them act on its behalf.
    if !is_new {
        let authed_as_callsign = auth
            .as_ref()
            .map(|Extension(ctx)| ctx.callsign.eq_ignore_ascii_case(req.callsign.trim()))
            .unwrap_or(false);
        if !authed_as_callsign {
            return Err(AppError::Forbidden);
        }
    }

    // Reserve the invite use atomically (the real cap enforcement), then join.
    // If the join fails, hand the reserved use back so a failed attempt doesn't
    // permanently burn a slot.
    if let Some(token) = &validated_token {
        db::invites::redeem_invite(&pool, token, challenge_id).await?;
    }

    let stored_token = validated_token
        .as_deref()
        .or(req.invite_token.as_deref());

    let participation = match db::join_challenge(&pool, challenge_id, &req.callsign, stored_token)
        .await
    {
        Ok(p) => p,
        Err(err) => {
            if let Some(token) = &validated_token {
                let _ = db::invites::release_invite(&pool, token, challenge_id).await;
            }
            return Err(err);
        }
    };

    let historical_allowed = challenge
        .configuration
        .get("historicalQsosAllowed")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: JoinChallengeResponse {
                participation_id: participation.id,
                // Only disclose a token when this call minted a new participant.
                device_token: if is_new {
                    Some(participant.device_token)
                } else {
                    None
                },
                joined_at: participation.joined_at,
                status: participation.status,
                historical_allowed,
            },
        }),
    ))
}

pub async fn leave_challenge(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Extension(auth): Extension<AuthContext>,
) -> Result<StatusCode, AppError> {
    let callsign_upper = auth.callsign.to_uppercase();

    // CAR-336: verify active participation BEFORE deleting progress, in one
    // transaction. Previously the progress row (score, completed goals, tier) was
    // deleted unconditionally and only then was participation checked — so a
    // non-participant, an already-left user, or a double-tapped Leave button
    // permanently lost their progress and still got a 403 saying nothing happened.
    let mut tx = pool.begin().await?;

    let left = sqlx::query(
        "UPDATE challenge_participants SET status = 'left' \
         WHERE challenge_id = $1 AND callsign = $2 AND status = 'active'",
    )
    .bind(challenge_id)
    .bind(&callsign_upper)
    .execute(&mut *tx)
    .await?;

    if left.rows_affected() == 0 {
        tx.rollback().await?;
        return Err(AppError::NotParticipating);
    }

    sqlx::query("DELETE FROM progress WHERE challenge_id = $1 AND callsign = $2")
        .bind(challenge_id)
        .bind(&callsign_upper)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}
