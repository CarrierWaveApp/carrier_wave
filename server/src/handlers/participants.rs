use axum::extract::{Extension, State};

use crate::extractors::{Json, Path};
use sqlx::PgPool;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::models::{ChallengeParticipation, ParticipationResponse};

use super::DataResponse;

pub async fn get_participation_status(
    State(pool): State<PgPool>,
    Path((challenge_id, callsign)): Path<(Uuid, String)>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<ParticipationResponse>>, AppError> {
    // Verify the authenticated callsign matches the requested callsign
    if auth.callsign.to_uppercase() != callsign.to_uppercase() {
        return Err(AppError::Forbidden);
    }

    let participation = db::get_participation(&pool, challenge_id, &callsign)
        .await?
        .ok_or(AppError::NotParticipating)?;

    Ok(Json(DataResponse {
        data: ParticipationResponse {
            participation_id: participation.id,
            challenge_id: participation.challenge_id,
            joined_at: participation.joined_at,
            status: participation.status,
        },
    }))
}

pub async fn list_challenges_for_callsign(
    State(pool): State<PgPool>,
    Path(callsign): Path<String>,
    Extension(auth): Extension<AuthContext>,
) -> Result<Json<DataResponse<Vec<ChallengeParticipation>>>, AppError> {
    // Verify the authenticated callsign matches the requested callsign
    if auth.callsign.to_uppercase() != callsign.to_uppercase() {
        return Err(AppError::Forbidden);
    }

    let challenges = db::get_challenges_for_callsign(&pool, &callsign).await?;

    Ok(Json(DataResponse { data: challenges }))
}
