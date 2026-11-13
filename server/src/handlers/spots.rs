use axum::{
    extract::{Extension, Query, State},
    http::StatusCode,
};
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::spot::{
    CreateSelfSpotRequest, SpotResponse, SpotSource, SpotsListResponse, SpotsPagination,
};

use super::DataResponse;

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotsQuery {
    pub program: Option<String>,
    pub callsign: Option<String>,
    pub source: Option<SpotSource>,
    pub mode: Option<String>,
    pub state: Option<String>,
    pub max_age_minutes: Option<i64>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// GET /v1/spots — list active spots with optional filters.
pub async fn list_spots(
    State(pool): State<PgPool>,
    Query(params): Query<SpotsQuery>,
) -> Result<Json<DataResponse<SpotsListResponse>>, AppError> {
    let limit = params.limit.unwrap_or(100).clamp(1, 250);
    let max_age_minutes = params.max_age_minutes.unwrap_or(30).clamp(1, 1440);

    let cursor = params.cursor.as_deref().and_then(|s| {
        chrono::DateTime::parse_from_rfc3339(s)
            .ok()
            .map(|dt| dt.with_timezone(&chrono::Utc))
    });

    let db_params = db::spots::ListSpotsParams {
        program: params.program,
        callsign: params.callsign,
        source: params.source,
        mode: params.mode,
        state: params.state,
        max_age_minutes,
        limit,
        cursor,
    };

    let rows = db::list_spots(&pool, &db_params).await?;

    let has_more = rows.len() as i64 > limit;
    let truncated: Vec<_> = rows.into_iter().take(limit as usize).collect();

    let next_cursor = if has_more {
        truncated.last().map(|row| row.spotted_at.to_rfc3339())
    } else {
        None
    };

    let spots: Vec<SpotResponse> = truncated.into_iter().map(Into::into).collect();

    Ok(Json(DataResponse {
        data: SpotsListResponse {
            spots,
            pagination: SpotsPagination {
                has_more,
                next_cursor,
            },
        },
    }))
}

/// POST /v1/spots — create a self-spot (auth required).
pub async fn create_self_spot(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(req): Json<CreateSelfSpotRequest>,
) -> Result<(StatusCode, Json<DataResponse<SpotResponse>>), AppError> {
    // Verify program exists and has selfSpot capability
    let program =
        db::get_program(&pool, &req.program_slug)
            .await?
            .ok_or(AppError::ProgramNotFound {
                slug: req.program_slug.clone(),
            })?;

    if !program.capabilities.contains(&"selfSpot".to_string()) {
        return Err(AppError::CapabilityNotSupported {
            capability: "selfSpot".to_string(),
            program_slug: req.program_slug,
        });
    }

    let spot = db::insert_self_spot(
        &pool,
        &db::spots::InsertSelfSpotParams {
            participant_id: auth.participant_id,
            callsign: &auth.callsign,
            program_slug: &req.program_slug,
            frequency_khz: req.frequency_khz,
            mode: &req.mode,
            reference: req.reference.as_deref(),
            comments: req.comments.as_deref(),
        },
    )
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse { data: spot.into() }),
    ))
}

/// DELETE /v1/spots/:id — delete own self-spot (auth required).
pub async fn delete_own_spot(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(spot_id): Path<uuid::Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::delete_own_spot(&pool, spot_id, auth.participant_id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::SpotNotFound { spot_id })
    }
}

/// DELETE /v1/admin/spots/:id — admin delete any spot.
pub async fn admin_delete_spot(
    State(pool): State<PgPool>,
    Path(spot_id): Path<uuid::Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::admin_delete_spot(&pool, spot_id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::SpotNotFound { spot_id })
    }
}
