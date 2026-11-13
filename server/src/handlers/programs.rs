use axum::{extract::State, http::StatusCode};
use sqlx::PgPool;

use crate::db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::{
    CreateProgramRequest, ProgramListResponse, ProgramResponse, UpdateProgramRequest,
};

use super::DataResponse;

/// GET /v1/programs — list all active programs.
pub async fn list_programs(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<ProgramListResponse>>, AppError> {
    let programs = db::list_programs(&pool).await?;
    let version = db::get_programs_version(&pool).await?;

    let response = ProgramListResponse {
        programs: programs.into_iter().map(ProgramResponse::from).collect(),
        version,
    };

    Ok(Json(DataResponse { data: response }))
}

/// GET /v1/programs/:slug — get a single program by slug.
pub async fn get_program(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
) -> Result<Json<DataResponse<ProgramResponse>>, AppError> {
    let program = db::get_program(&pool, &slug)
        .await?
        .ok_or(AppError::ProgramNotFound { slug })?;

    Ok(Json(DataResponse {
        data: program.into(),
    }))
}

/// GET /v1/admin/programs — list all programs (including inactive).
pub async fn admin_list_programs(
    State(pool): State<PgPool>,
) -> Result<Json<DataResponse<ProgramListResponse>>, AppError> {
    let programs = db::list_all_programs(&pool).await?;
    let version = db::get_programs_version(&pool).await?;

    let response = ProgramListResponse {
        programs: programs.into_iter().map(ProgramResponse::from).collect(),
        version,
    };

    Ok(Json(DataResponse { data: response }))
}

/// GET /v1/admin/programs/:slug — get any program by slug (including inactive).
pub async fn admin_get_program(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
) -> Result<Json<DataResponse<ProgramResponse>>, AppError> {
    let program = db::get_any_program(&pool, &slug)
        .await?
        .ok_or(AppError::ProgramNotFound { slug })?;

    Ok(Json(DataResponse {
        data: program.into(),
    }))
}

/// POST /v1/admin/programs — create a new program.
pub async fn create_program(
    State(pool): State<PgPool>,
    Json(req): Json<CreateProgramRequest>,
) -> Result<(StatusCode, Json<DataResponse<ProgramResponse>>), AppError> {
    let program = db::create_program(&pool, &req).await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: program.into(),
        }),
    ))
}

/// PUT /v1/admin/programs/:slug — update an existing program.
pub async fn update_program(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
    Json(req): Json<UpdateProgramRequest>,
) -> Result<Json<DataResponse<ProgramResponse>>, AppError> {
    let program = db::update_program(&pool, &slug, &req)
        .await?
        .ok_or(AppError::ProgramNotFound { slug })?;

    Ok(Json(DataResponse {
        data: program.into(),
    }))
}

/// DELETE /v1/admin/programs/:slug — delete a program.
pub async fn delete_program(
    State(pool): State<PgPool>,
    Path(slug): Path<String>,
) -> Result<StatusCode, AppError> {
    let deleted = db::delete_program(&pool, &slug).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::ProgramNotFound { slug })
    }
}
