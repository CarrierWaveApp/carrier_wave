use axum::extract::{Query, State};
use sqlx::PgPool;

use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::metrickit_telemetry::{
    MetricKitQuery, MetricKitRequest, MetricKitResponse, MetricKitSummaryResponse,
};

use super::DataResponse;

/// Max raw payload size (5 MB) — MetricKit payloads can be large
const MAX_PAYLOAD_BYTES: usize = 5 * 1024 * 1024;

/// POST /v1/metrics
/// Ingest a MetricKit metric payload (anonymous, no auth required).
pub async fn ingest_metrics(
    State(pool): State<PgPool>,
    Json(body): Json<MetricKitRequest>,
) -> Result<Json<MetricKitResponse>, AppError> {
    validate_metadata(&body)?;
    validate_payload_size(&body)?;

    db::metrickit_telemetry::insert_payload(&pool, "metrics", &body.metadata, &body.payload)
        .await?;

    Ok(Json(MetricKitResponse { accepted: true }))
}

/// POST /v1/diagnostics
/// Ingest a MetricKit diagnostic payload (anonymous, no auth required).
pub async fn ingest_diagnostics(
    State(pool): State<PgPool>,
    Json(body): Json<MetricKitRequest>,
) -> Result<Json<MetricKitResponse>, AppError> {
    validate_metadata(&body)?;
    validate_payload_size(&body)?;

    db::metrickit_telemetry::insert_payload(&pool, "diagnostics", &body.metadata, &body.payload)
        .await?;

    Ok(Json(MetricKitResponse { accepted: true }))
}

/// GET /v1/admin/metrickit
/// Get MetricKit telemetry summary (admin only).
pub async fn get_metrickit_summary(
    State(pool): State<PgPool>,
    Query(query): Query<MetricKitQuery>,
) -> Result<Json<DataResponse<MetricKitSummaryResponse>>, AppError> {
    let days = query.days.unwrap_or(7).clamp(1, 90);

    if let Some(ref pt) = query.payload_type {
        if pt != "metrics" && pt != "diagnostics" {
            return Err(AppError::Validation {
                message: format!("Invalid payload type: {pt}"),
            });
        }
    }

    let summary = db::metrickit_telemetry::get_summary(
        &pool,
        days,
        query.payload_type.as_deref(),
        query.device_model.as_deref(),
        query.app_version.as_deref(),
    )
    .await?;

    Ok(Json(DataResponse { data: summary }))
}

fn validate_metadata(body: &MetricKitRequest) -> Result<(), AppError> {
    if body.metadata.app_version.len() > 32 {
        return Err(AppError::Validation {
            message: "app_version too long".to_string(),
        });
    }
    if body.metadata.build_number.len() > 32 {
        return Err(AppError::Validation {
            message: "build_number too long".to_string(),
        });
    }
    if body.metadata.device_model.len() > 64 {
        return Err(AppError::Validation {
            message: "device_model too long".to_string(),
        });
    }
    if body.metadata.os_version.len() > 32 {
        return Err(AppError::Validation {
            message: "os_version too long".to_string(),
        });
    }
    if body.metadata.locale.len() > 32 {
        return Err(AppError::Validation {
            message: "locale too long".to_string(),
        });
    }
    Ok(())
}

fn validate_payload_size(body: &MetricKitRequest) -> Result<(), AppError> {
    let size = body.payload.to_string().len();
    if size > MAX_PAYLOAD_BYTES {
        return Err(AppError::Validation {
            message: format!("Payload too large ({size} bytes, max {MAX_PAYLOAD_BYTES})"),
        });
    }
    Ok(())
}
