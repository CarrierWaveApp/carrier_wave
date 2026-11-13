use axum::extract::State;
use axum::http::StatusCode;
use sqlx::PgPool;

use crate::db;
use crate::error::AppError;
use crate::extractors::Json;
use crate::models::equipment_usage::{
    ReportEquipmentUsageRequest, ReportEquipmentUsageResponse,
};

/// POST /v1/telemetry/equipment-usage
/// Record anonymous equipment usage from session end.
/// No auth required — same pattern as MetricKit telemetry.
pub async fn report_equipment_usage(
    State(pool): State<PgPool>,
    Json(req): Json<ReportEquipmentUsageRequest>,
) -> Result<(StatusCode, Json<ReportEquipmentUsageResponse>), AppError> {
    if req.usage.is_empty() {
        return Ok((
            StatusCode::OK,
            Json(ReportEquipmentUsageResponse { accepted: 0 }),
        ));
    }

    // Cap batch size to prevent abuse
    let entries = if req.usage.len() > 50 {
        &req.usage[..50]
    } else {
        &req.usage
    };

    let accepted =
        db::equipment_usage::record_usage(&pool, entries, req.metadata.app_version.as_deref())
            .await?;

    Ok((
        StatusCode::CREATED,
        Json(ReportEquipmentUsageResponse { accepted }),
    ))
}
