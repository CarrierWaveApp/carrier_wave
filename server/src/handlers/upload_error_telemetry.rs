use axum::extract::{Query, State};
use axum::Extension;
use sqlx::PgPool;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::upload_error_telemetry::{
    ReportUploadErrorsRequest, ReportUploadErrorsResponse, TelemetryQuery,
    TelemetrySummaryResponse,
};

use super::DataResponse;

const MAX_ERRORS_PER_REPORT: usize = 50;

const VALID_SERVICES: &[&str] = &[
    "pota", "qrz", "clublog", "eqsl", "lotw", "hamqth",
];

const VALID_CATEGORIES: &[&str] = &[
    "authentication",
    "validation",
    "rate_limited",
    "maintenance",
    "network_timeout",
    "network_offline",
    "server_error",
    "rejected",
    "subscription_required",
];

/// POST /v1/telemetry/upload-errors
/// Report anonymized upload error telemetry.
pub async fn report_upload_errors(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(body): Json<ReportUploadErrorsRequest>,
) -> Result<Json<ReportUploadErrorsResponse>, AppError> {
    if body.errors.is_empty() {
        return Ok(Json(ReportUploadErrorsResponse { accepted: 0 }));
    }

    if body.errors.len() > MAX_ERRORS_PER_REPORT {
        return Err(AppError::Validation {
            message: format!(
                "Too many errors in report (max {})",
                MAX_ERRORS_PER_REPORT
            ),
        });
    }

    // Validate entries
    for entry in &body.errors {
        if !VALID_SERVICES.contains(&entry.service.as_str()) {
            return Err(AppError::Validation {
                message: format!("Unknown service: {}", entry.service),
            });
        }
        if !VALID_CATEGORIES.contains(&entry.category.as_str()) {
            return Err(AppError::Validation {
                message: format!("Unknown category: {}", entry.category),
            });
        }
        if entry.affected_count < 0 {
            return Err(AppError::Validation {
                message: "affected_count must be non-negative".to_string(),
            });
        }
        if entry.message_hash.len() > 64 {
            return Err(AppError::Validation {
                message: "message_hash too long".to_string(),
            });
        }
        if entry.app_version.len() > 32 {
            return Err(AppError::Validation {
                message: "app_version too long".to_string(),
            });
        }
        if entry.os_version.len() > 32 {
            return Err(AppError::Validation {
                message: "os_version too long".to_string(),
            });
        }
    }

    let accepted =
        db::upload_error_telemetry::insert_upload_errors(&pool, &auth.callsign, &body.errors)
            .await?;

    Ok(Json(ReportUploadErrorsResponse { accepted }))
}

/// GET /v1/admin/telemetry/upload-errors
/// Get upload error telemetry summary (admin only).
pub async fn get_telemetry_summary(
    State(pool): State<PgPool>,
    Query(query): Query<TelemetryQuery>,
) -> Result<Json<DataResponse<TelemetrySummaryResponse>>, AppError> {
    let days = query.days.unwrap_or(7).clamp(1, 90);

    let summary = db::upload_error_telemetry::get_telemetry_summary(
        &pool,
        days,
        query.service.as_deref(),
        query.category.as_deref(),
    )
    .await?;

    Ok(Json(DataResponse { data: summary }))
}
