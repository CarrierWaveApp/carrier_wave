use axum::extract::{Query, State};
use axum::http::StatusCode;
use uuid::Uuid;

use crate::db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::event::{
    AdminListEventsQuery, EventResponse, ReviewEventRequest, SubmitterStats, UpdateEventRequest,
};
use sqlx::PgPool;

use super::DataResponse;

/// GET /v1/admin/events
/// List events with optional status filter (defaults to showing all).
pub async fn list_events_admin(
    State(pool): State<PgPool>,
    Query(query): Query<AdminListEventsQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let (events, total) = db::events::list_events_admin(&pool, &query).await?;

    Ok(Json(serde_json::json!({
        "data": {
            "events": events,
            "total": total,
            "limit": query.limit.unwrap_or(50).min(100),
            "offset": query.offset.unwrap_or(0)
        }
    })))
}

/// GET /v1/admin/events/:id
/// Get any event regardless of status.
pub async fn admin_get_event(
    State(pool): State<PgPool>,
    Path(event_id): Path<Uuid>,
) -> Result<Json<DataResponse<EventResponse>>, AppError> {
    let event = db::events::get_event(&pool, event_id)
        .await?
        .ok_or(AppError::EventNotFound { event_id })?;

    let days = db::events::get_event_days(&pool, event_id).await?;

    Ok(Json(DataResponse {
        data: EventResponse::from(event).with_days(days),
    }))
}

/// PUT /v1/admin/events/:id
/// Admin edit any event fields (fix typos, adjust coordinates before approving).
pub async fn admin_update_event(
    State(pool): State<PgPool>,
    Path(event_id): Path<Uuid>,
    Json(req): Json<UpdateEventRequest>,
) -> Result<Json<DataResponse<EventResponse>>, AppError> {
    let event = db::events::admin_update_event(&pool, event_id, &req)
        .await?
        .ok_or(AppError::EventNotFound { event_id })?;

    if let Some(ref day_reqs) = req.days {
        db::events::replace_event_days(&pool, event_id, day_reqs).await?;
    }

    let days = db::events::get_event_days(&pool, event_id).await?;

    Ok(Json(DataResponse {
        data: EventResponse::from(event).with_days(days),
    }))
}

/// PUT /v1/admin/events/:id/review
/// Approve or reject an event.
pub async fn review_event(
    State(pool): State<PgPool>,
    Path(event_id): Path<Uuid>,
    Json(req): Json<ReviewEventRequest>,
) -> Result<Json<DataResponse<EventResponse>>, AppError> {
    let status = match req.action.as_str() {
        "approve" => "approved",
        "reject" => "rejected",
        _ => {
            return Err(AppError::InvalidEventReview {
                message: "action must be 'approve' or 'reject'".to_string(),
            })
        }
    };

    if status == "rejected" && req.reason.is_none() {
        return Err(AppError::Validation {
            message: "reason is required when rejecting an event".to_string(),
        });
    }

    let event = db::events::review_event(
        &pool,
        event_id,
        status,
        "admin",
        req.reason.as_deref(),
    )
    .await?
    .ok_or(AppError::EventNotFound { event_id })?;

    let days = db::events::get_event_days(&pool, event_id).await?;

    Ok(Json(DataResponse {
        data: EventResponse::from(event).with_days(days),
    }))
}

/// DELETE /v1/admin/events/:id
/// Hard delete any event.
pub async fn admin_delete_event(
    State(pool): State<PgPool>,
    Path(event_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let deleted = db::events::admin_delete_event(&pool, event_id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::EventNotFound { event_id })
    }
}

/// GET /v1/admin/events/submitter/:callsign
/// Get submitter history stats.
pub async fn get_submitter_history(
    State(pool): State<PgPool>,
    Path(callsign): Path<String>,
) -> Result<Json<DataResponse<SubmitterStats>>, AppError> {
    let stats = db::events::get_submitter_history(&pool, &callsign).await?;

    Ok(Json(DataResponse { data: stats }))
}
