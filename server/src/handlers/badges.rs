use axum::{
    body::Body,
    extract::State,
    http::{header, Response, StatusCode},
};

use crate::extractors::{Json, Path};
use axum_extra::extract::Multipart;
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::models::BadgeResponse;

use super::challenges::DataResponse;

const MAX_BADGE_SIZE: usize = 1024 * 1024; // 1MB
const ALLOWED_CONTENT_TYPES: &[&str] = &["image/png", "image/svg+xml", "image/jpeg"];

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BadgeListResponse {
    pub badges: Vec<BadgeResponse>,
}

pub async fn upload_badge(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<DataResponse<BadgeResponse>>), AppError> {
    // Verify challenge exists
    db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let mut name: Option<String> = None;
    let mut tier_id: Option<String> = None;
    let mut image_data: Option<Vec<u8>> = None;
    let mut content_type: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|e| AppError::Validation {
            message: format!("Failed to read multipart field: {}", e),
        })?
    {
        let field_name = field.name().unwrap_or("").to_string();

        match field_name.as_str() {
            "name" => {
                name = Some(field.text().await.map_err(|e| AppError::Validation {
                    message: format!("Failed to read name field: {}", e),
                })?);
            }
            "tierId" => {
                let value = field.text().await.map_err(|e| AppError::Validation {
                    message: format!("Failed to read tierId field: {}", e),
                })?;
                if !value.is_empty() {
                    tier_id = Some(value);
                }
            }
            "image" => {
                let ct = field
                    .content_type()
                    .map(|s| s.to_string())
                    .unwrap_or_default();

                if !ALLOWED_CONTENT_TYPES.contains(&ct.as_str()) {
                    return Err(AppError::Validation {
                        message: format!("Invalid content type '{}'. Allowed: PNG, JPEG, SVG", ct),
                    });
                }

                let data = field.bytes().await.map_err(|e| AppError::Validation {
                    message: format!("Failed to read image data: {}", e),
                })?;

                if data.len() > MAX_BADGE_SIZE {
                    return Err(AppError::Validation {
                        message: format!(
                            "Image too large. Maximum size is {} bytes",
                            MAX_BADGE_SIZE
                        ),
                    });
                }

                content_type = Some(ct);
                image_data = Some(data.to_vec());
            }
            _ => {}
        }
    }

    let name = name.ok_or(AppError::Validation {
        message: "Missing required field: name".to_string(),
    })?;

    let image_data = image_data.ok_or(AppError::Validation {
        message: "Missing required field: image".to_string(),
    })?;

    let content_type = content_type.ok_or(AppError::Validation {
        message: "Missing image content type".to_string(),
    })?;

    let badge = db::create_badge(
        &pool,
        challenge_id,
        &name,
        tier_id.as_deref(),
        &image_data,
        &content_type,
    )
    .await?;

    // Use empty base URL for now - will be configured via env var
    let base_url = "";

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: badge.into_response(base_url),
        }),
    ))
}

pub async fn list_badges(
    State(pool): State<PgPool>,
    Path(challenge_id): Path<Uuid>,
) -> Result<Json<DataResponse<BadgeListResponse>>, AppError> {
    // Verify challenge exists
    db::get_challenge(&pool, challenge_id)
        .await?
        .ok_or(AppError::ChallengeNotFound { challenge_id })?;

    let badges = db::list_badges(&pool, challenge_id).await?;
    let base_url = "";

    Ok(Json(DataResponse {
        data: BadgeListResponse {
            badges: badges
                .into_iter()
                .map(|b| b.into_response(base_url))
                .collect(),
        },
    }))
}

pub async fn get_badge_image(
    State(pool): State<PgPool>,
    Path(badge_id): Path<Uuid>,
) -> Result<Response<Body>, AppError> {
    let badge = db::get_badge(&pool, badge_id)
        .await?
        .ok_or(AppError::BadgeNotFound { badge_id })?;

    let response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, badge.content_type)
        .header(header::CACHE_CONTROL, "public, max-age=86400")
        .body(Body::from(badge.image_data))
        .map_err(|e| AppError::Internal(e.to_string()))?;

    Ok(response)
}

pub async fn delete_badge(
    State(pool): State<PgPool>,
    Path(badge_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::delete_badge(&pool, badge_id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::BadgeNotFound { badge_id })
    }
}
