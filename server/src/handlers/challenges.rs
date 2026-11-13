use axum::{
    extract::{Query, State},
    http::{header, HeaderMap, StatusCode},
};

use crate::extractors::{Json, Path};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::models::{
    ChallengeListItem, ChallengeResponse, CreateChallengeRequest, ListChallengesQuery,
};

#[derive(Serialize)]
pub struct DataResponse<T> {
    pub data: T,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListChallengesResponse {
    pub challenges: Vec<ChallengeListItem>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}

pub async fn list_challenges(
    State(pool): State<PgPool>,
    Query(query): Query<ListChallengesQuery>,
) -> Result<Json<DataResponse<ListChallengesResponse>>, AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let (challenges, total) = db::list_challenges(&pool, &query).await?;

    Ok(Json(DataResponse {
        data: ListChallengesResponse {
            challenges,
            total,
            limit,
            offset,
        },
    }))
}

pub async fn get_challenge(
    State(pool): State<PgPool>,
    Path(id): Path<Uuid>,
) -> Result<(HeaderMap, Json<DataResponse<ChallengeResponse>>), AppError> {
    let challenge = db::get_challenge(&pool, id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id: id })?;

    let mut headers = HeaderMap::new();
    headers.insert(
        "X-Challenge-Version",
        challenge.version.to_string().parse().unwrap(),
    );

    let etag = format!(
        "\"{}:{}\"",
        challenge.version,
        challenge.updated_at.timestamp()
    );
    headers.insert(header::ETAG, etag.parse().unwrap());

    Ok((
        headers,
        Json(DataResponse {
            data: challenge.into(),
        }),
    ))
}

pub async fn create_challenge(
    State(pool): State<PgPool>,
    Json(req): Json<CreateChallengeRequest>,
) -> Result<(StatusCode, Json<DataResponse<ChallengeResponse>>), AppError> {
    let challenge = db::create_challenge(&pool, &req).await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: challenge.into(),
        }),
    ))
}

pub async fn update_challenge(
    State(pool): State<PgPool>,
    Path(id): Path<Uuid>,
    Json(req): Json<CreateChallengeRequest>,
) -> Result<Json<DataResponse<ChallengeResponse>>, AppError> {
    let challenge = db::update_challenge(&pool, id, &req)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id: id })?;

    Ok(Json(DataResponse {
        data: challenge.into(),
    }))
}

pub async fn delete_challenge(
    State(pool): State<PgPool>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::delete_challenge(&pool, id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::ChallengeNotFound { challenge_id: id })
    }
}
