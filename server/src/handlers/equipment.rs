use axum::extract::{Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use sqlx::PgPool;

use crate::db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::equipment::{
    CatalogQuery, CatalogResponse, CreateEquipmentRequest, CreateSubmissionRequest,
    EquipmentEntryResponse, ReviewSubmissionRequest, SearchQuery, SearchResponse,
    SearchResultEntry, SubmissionListQuery, SubmissionResponse, UpdateEquipmentRequest,
};

use super::DataResponse;

/// GET /v1/equipment/catalog
/// Returns the full equipment catalog, or a delta if `since` is provided.
/// Supports ETag-based conditional requests via If-None-Match.
pub async fn get_catalog(
    State(pool): State<PgPool>,
    headers: HeaderMap,
    Query(query): Query<CatalogQuery>,
) -> Result<(HeaderMap, Json<CatalogResponse>), AppError> {
    // Compute ETag from catalog fingerprint
    let fingerprint = db::equipment::get_catalog_fingerprint(&pool).await?;
    let etag = format!("\"equipment-{}\"", fingerprint);

    // Check If-None-Match
    if let Some(inm) = headers.get(header::IF_NONE_MATCH) {
        if let Ok(val) = inm.to_str() {
            if val == etag {
                return Err(AppError::NotModified);
            }
        }
    }

    let (version, updated_at) = db::equipment::get_catalog_version(&pool).await?;
    let entries = db::equipment::get_catalog_entries(&pool, query.since).await?;

    let response = CatalogResponse {
        version,
        updated_at,
        entries: entries.into_iter().map(EquipmentEntryResponse::from).collect(),
    };

    let mut resp_headers = HeaderMap::new();
    resp_headers.insert(header::ETAG, etag.parse().unwrap());
    resp_headers.insert(
        header::CACHE_CONTROL,
        "public, max-age=86400".parse().unwrap(),
    );

    Ok((resp_headers, Json(response)))
}

/// GET /v1/equipment/search?q={query}&category={category}&limit={limit}
/// Server-side fuzzy search for equipment entries.
pub async fn search_equipment(
    State(pool): State<PgPool>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<SearchResponse>, AppError> {
    if query.q.trim().is_empty() {
        return Err(AppError::Validation {
            message: "q parameter is required".to_string(),
        });
    }

    let limit = query.limit.unwrap_or(5).min(20).max(1);

    let rows =
        db::equipment::search_equipment(&pool, &query.q, query.category.as_deref(), limit).await?;

    let results = rows
        .into_iter()
        .map(|r| {
            let score = r.score.unwrap_or(0.0);
            let matched_field = r.matched_field.clone().unwrap_or_else(|| "name".to_string());
            SearchResultEntry {
                entry: EquipmentEntryResponse {
                    id: r.id,
                    name: r.name,
                    manufacturer: r.manufacturer,
                    category: r.category,
                    bands: r.bands,
                    modes: r.modes,
                    max_power_watts: r.max_power_watts,
                    portability: r.portability,
                    weight_grams: r.weight_grams,
                    description: r.description,
                    aliases: r.aliases,
                    image_url: r.image_url,
                    antenna_connector: r.antenna_connector,
                    power_connector: r.power_connector,
                    key_jack: r.key_jack,
                    mic_jack: r.mic_jack,
                },
                confidence: (score * 100.0).round() / 100.0,
                matched_field,
            }
        })
        .collect();

    Ok(Json(SearchResponse { results }))
}

/// POST /v1/admin/equipment (admin)
/// Create a new equipment catalog entry.
pub async fn create_equipment(
    State(pool): State<PgPool>,
    Json(req): Json<CreateEquipmentRequest>,
) -> Result<(StatusCode, Json<DataResponse<EquipmentEntryResponse>>), AppError> {
    validate_equipment_fields(&req.category, &req.portability)?;

    let entry = db::equipment::create_entry(&pool, &req).await?;

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: EquipmentEntryResponse::from(entry),
        }),
    ))
}

/// PUT /v1/admin/equipment/:id (admin)
/// Update an existing equipment catalog entry.
pub async fn update_equipment(
    State(pool): State<PgPool>,
    Path(id): Path<String>,
    Json(req): Json<UpdateEquipmentRequest>,
) -> Result<Json<DataResponse<EquipmentEntryResponse>>, AppError> {
    if let Some(ref cat) = req.category {
        validate_category(cat)?;
    }
    if let Some(ref port) = req.portability {
        validate_portability(port)?;
    }

    let entry = db::equipment::update_entry(&pool, &id, &req)
        .await?
        .ok_or(AppError::EquipmentNotFound { equipment_id: id })?;

    Ok(Json(DataResponse {
        data: EquipmentEntryResponse::from(entry),
    }))
}

/// DELETE /v1/admin/equipment/:id (admin)
/// Delete an equipment catalog entry.
pub async fn delete_equipment(
    State(pool): State<PgPool>,
    Path(id): Path<String>,
) -> Result<StatusCode, AppError> {
    let deleted = db::equipment::delete_entry(&pool, &id).await?;
    if !deleted {
        return Err(AppError::EquipmentNotFound { equipment_id: id });
    }
    Ok(StatusCode::NO_CONTENT)
}

const VALID_CATEGORIES: &[&str] = &["radio", "antenna", "key", "microphone", "accessory"];
const VALID_PORTABILITIES: &[&str] = &["pocket", "backpack", "portable", "mobile", "base"];

fn validate_category(category: &str) -> Result<(), AppError> {
    if !VALID_CATEGORIES.contains(&category) {
        return Err(AppError::Validation {
            message: format!(
                "Invalid category. Must be one of: {}",
                VALID_CATEGORIES.join(", ")
            ),
        });
    }
    Ok(())
}

fn validate_portability(portability: &str) -> Result<(), AppError> {
    if !VALID_PORTABILITIES.contains(&portability) {
        return Err(AppError::Validation {
            message: format!(
                "Invalid portability. Must be one of: {}",
                VALID_PORTABILITIES.join(", ")
            ),
        });
    }
    Ok(())
}

// ==================== Submissions ====================

/// POST /v1/equipment/submissions
/// Submit custom equipment for admin review. Anonymous (API key only).
pub async fn submit_equipment(
    State(pool): State<PgPool>,
    headers: HeaderMap,
    Json(req): Json<CreateSubmissionRequest>,
) -> Result<(StatusCode, Json<SubmissionResponse>), AppError> {
    validate_equipment_fields(&req.category, &req.portability)?;

    let ip_str = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(',').next())
        .map(|s| s.trim().to_string());

    let app_version = headers
        .get("User-Agent")
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let submission = db::equipment::create_submission(
        &pool,
        &req,
        ip_str.as_deref(),
        app_version.as_deref(),
    )
    .await?;

    Ok((
        StatusCode::CREATED,
        Json(SubmissionResponse {
            id: submission.id,
            status: submission.status,
        }),
    ))
}

/// GET /v1/admin/equipment/submissions (admin)
/// List equipment submissions for review.
pub async fn list_equipment_submissions(
    State(pool): State<PgPool>,
    Query(query): Query<SubmissionListQuery>,
) -> Result<Json<Vec<SubmissionResponse>>, AppError> {
    let limit = query.limit.unwrap_or(50).min(200);
    let submissions =
        db::equipment::list_submissions(&pool, query.status.as_deref(), limit).await?;

    let responses: Vec<SubmissionResponse> = submissions
        .into_iter()
        .map(|sub| SubmissionResponse {
            id: sub.id,
            status: sub.status,
        })
        .collect();

    Ok(Json(responses))
}

/// PUT /v1/admin/equipment/submissions/:id/review (admin)
/// Approve or reject a submission.
pub async fn review_equipment_submission(
    State(pool): State<PgPool>,
    Path(submission_id): Path<uuid::Uuid>,
    Json(req): Json<ReviewSubmissionRequest>,
) -> Result<Json<SubmissionResponse>, AppError> {
    let status = match req.action.as_str() {
        "approve" => "approved",
        "reject" => "rejected",
        _ => {
            return Err(AppError::Validation {
                message: "Action must be 'approve' or 'reject'".to_string(),
            })
        }
    };

    let submission =
        db::equipment::review_submission(&pool, submission_id, status, req.catalog_id.as_deref())
            .await?
            .ok_or(AppError::EquipmentNotFound {
                equipment_id: submission_id.to_string(),
            })?;

    Ok(Json(SubmissionResponse {
        id: submission.id,
        status: submission.status,
    }))
}

fn validate_equipment_fields(category: &str, portability: &str) -> Result<(), AppError> {
    validate_category(category)?;
    validate_portability(portability)?;
    Ok(())
}
