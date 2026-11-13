use axum::extract::{Query, State};
use axum::http::StatusCode;
use axum::Extension;
use uuid::Uuid;

use crate::auth::AuthContext;
use crate::db;
use crate::error::AppError;
use crate::extractors::{Json, Path};
use crate::models::event::{
    CreateEventRequest, EventResponse, ListEventsQuery, MyEventsQuery, UpdateEventRequest,
};
use sqlx::PgPool;

use super::DataResponse;

const MAX_PENDING_EVENTS: i64 = 10;
const VALID_EVENT_TYPES: &[&str] = &[
    "club_meeting",
    "swap_meet",
    "field_day",
    "special_event",
    "hamfest",
    "net",
    "other",
];

/// GET /v1/events
/// List approved events near a location.
pub async fn list_events(
    State(pool): State<PgPool>,
    Query(query): Query<ListEventsQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    if query.radius_km < 1.0 || query.radius_km > 500.0 {
        return Err(AppError::Validation {
            message: "radius_km must be between 1 and 500".to_string(),
        });
    }
    if query.lat < -90.0 || query.lat > 90.0 {
        return Err(AppError::Validation {
            message: "lat must be between -90 and 90".to_string(),
        });
    }
    if query.lon < -180.0 || query.lon > 180.0 {
        return Err(AppError::Validation {
            message: "lon must be between -180 and 180".to_string(),
        });
    }

    let (events, total) = db::events::list_events_near(&pool, &query).await?;

    Ok(Json(serde_json::json!({
        "data": {
            "events": events,
            "total": total,
            "limit": query.limit.unwrap_or(50).min(100),
            "offset": query.offset.unwrap_or(0)
        }
    })))
}

/// GET /v1/events/:id
/// Get a single approved event.
pub async fn get_event(
    State(pool): State<PgPool>,
    Path(event_id): Path<Uuid>,
) -> Result<Json<DataResponse<EventResponse>>, AppError> {
    let event = db::events::get_event(&pool, event_id)
        .await?
        .ok_or(AppError::EventNotFound { event_id })?;

    // Only show approved events to the public
    if event.status != "approved" {
        return Err(AppError::EventNotFound { event_id });
    }

    let days = db::events::get_event_days(&pool, event_id).await?;

    Ok(Json(DataResponse {
        data: EventResponse::from(event).with_days(days),
    }))
}

/// POST /v1/events
/// Submit a new event (auth required).
pub async fn create_event(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Json(req): Json<CreateEventRequest>,
) -> Result<(StatusCode, Json<DataResponse<EventResponse>>), AppError> {
    // Validate event type
    if !VALID_EVENT_TYPES.contains(&req.event_type.as_str()) {
        return Err(AppError::Validation {
            message: format!(
                "Invalid event_type. Must be one of: {}",
                VALID_EVENT_TYPES.join(", ")
            ),
        });
    }

    // Validate coordinates
    if req.latitude < -90.0 || req.latitude > 90.0 {
        return Err(AppError::Validation {
            message: "latitude must be between -90 and 90".to_string(),
        });
    }
    if req.longitude < -180.0 || req.longitude > 180.0 {
        return Err(AppError::Validation {
            message: "longitude must be between -180 and 180".to_string(),
        });
    }

    // Validate end_date > start_date
    if let Some(end_date) = req.end_date {
        if end_date <= req.start_date {
            return Err(AppError::Validation {
                message: "end_date must be after start_date".to_string(),
            });
        }
    }

    // Check pending event limit
    let pending_count = db::events::count_pending_events(&pool, &auth.callsign).await?;
    if pending_count >= MAX_PENDING_EVENTS {
        return Err(AppError::MaxPendingEvents);
    }

    let event = db::events::create_event(&pool, &req, &auth.callsign).await?;

    let days = if let Some(ref day_reqs) = req.days {
        db::events::replace_event_days(&pool, event.id, day_reqs).await?
    } else {
        Vec::new()
    };

    Ok((
        StatusCode::CREATED,
        Json(DataResponse {
            data: EventResponse::from(event).with_days(days),
        }),
    ))
}

/// PUT /v1/events/:id
/// Edit own event (auth required).
pub async fn update_event(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(event_id): Path<Uuid>,
    Json(req): Json<UpdateEventRequest>,
) -> Result<Json<DataResponse<EventResponse>>, AppError> {
    // Validate coordinates if provided
    if let Some(lat) = req.latitude {
        if lat < -90.0 || lat > 90.0 {
            return Err(AppError::Validation {
                message: "latitude must be between -90 and 90".to_string(),
            });
        }
    }
    if let Some(lon) = req.longitude {
        if lon < -180.0 || lon > 180.0 {
            return Err(AppError::Validation {
                message: "longitude must be between -180 and 180".to_string(),
            });
        }
    }

    // Validate event type if provided
    if let Some(ref event_type) = req.event_type {
        if !VALID_EVENT_TYPES.contains(&event_type.as_str()) {
            return Err(AppError::Validation {
                message: format!(
                    "Invalid event_type. Must be one of: {}",
                    VALID_EVENT_TYPES.join(", ")
                ),
            });
        }
    }

    let event = db::events::update_own_event(&pool, event_id, &auth.callsign, &req)
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

/// DELETE /v1/events/:id
/// Delete own event (auth required).
pub async fn delete_event(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Path(event_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    // Check the event exists and is owned by the user
    let event = db::events::get_event(&pool, event_id)
        .await?
        .ok_or(AppError::EventNotFound { event_id })?;

    if event.submitted_by != auth.callsign {
        return Err(AppError::EventNotOwned { event_id });
    }

    db::events::delete_own_event(&pool, event_id, &auth.callsign).await?;

    Ok(StatusCode::NO_CONTENT)
}

/// GET /v1/events/mine
/// List own submitted events, all statuses (auth required).
pub async fn list_my_events(
    State(pool): State<PgPool>,
    Extension(auth): Extension<AuthContext>,
    Query(query): Query<MyEventsQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let events = db::events::list_my_events(&pool, &auth.callsign, limit, offset).await?;

    Ok(Json(serde_json::json!({
        "data": {
            "events": events
        }
    })))
}
