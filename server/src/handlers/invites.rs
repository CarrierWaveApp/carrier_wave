use axum::{extract::State, http::StatusCode};

use crate::extractors::{Json, Path};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::models::{CreateInviteRequest, InviteResponse};

use super::challenges::DataResponse;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InviteListResponse {
    pub invites: Vec<InviteResponse>,
}

pub async fn generate_invite(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    Json(req): Json<CreateInviteRequest>,
) -> Result<(StatusCode, Json<DataResponse<InviteResponse>>), AppError> {
    // Verify challenge exists
    db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let invite = db::create_invite(&pool, challenge_id, req.max_uses, req.expires_at).await?;
    let base_url = "";

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: invite.into_response(base_url),
        }),
    ))
}

pub async fn list_invites(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
) -> Result<Json<DataResponse<InviteListResponse>>, AppError> {
    // Verify challenge exists
    db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let invites = db::list_invites(&pool, challenge_id).await?;
    let base_url = "";

    Ok(Json(DataResponse {
        data: InviteListResponse {
            invites: invites
                .into_iter()
                .map(|i| i.into_response(base_url))
                .collect(),
        },
    }))
}

pub async fn revoke_invite(
    State(pool): State<PgPool>,
    Path(token): Path<String>,
) -> Result<StatusCode, AppError> {
    let deleted = db::delete_invite(&pool, &token).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::InviteNotFound { token })
    }
}
