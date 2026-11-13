use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::event::{
    AdminListEventsQuery, CreateEventRequest, EventDayRequest, EventDayRow, EventListItem,
    EventRow, ListEventsQuery, SubmitterStats, UpdateEventRequest,
};

/// List approved events near a location with optional filters.
pub async fn list_events_near(
    pool: &PgPool,
    query: &ListEventsQuery,
) -> Result<(Vec<EventListItem>, i64), AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);
    let radius_meters = query.radius_km * 1000.0;
    let include_past = query.include_past.unwrap_or(false);

    let events = sqlx::query_as::<_, EventListItem>(
        r#"
        SELECT id, name, event_type, start_date, end_date, timezone,
               venue_name, city, state, country, latitude, longitude,
               cost, submitted_by, status, created_at,
               ST_Distance(location, ST_MakePoint($1, $2)::geography) AS distance_meters
        FROM events
        WHERE status = 'approved'
          AND ($3::bool OR start_date >= NOW())
          AND ST_DWithin(location, ST_MakePoint($1, $2)::geography, $4)
          AND ($5::text IS NULL OR event_type = $5)
          AND ($6::timestamptz IS NULL OR start_date >= $6)
          AND ($7::timestamptz IS NULL OR start_date <= $7)
        ORDER BY start_date ASC
        LIMIT $8 OFFSET $9
        "#,
    )
    .bind(query.lon)
    .bind(query.lat)
    .bind(include_past)
    .bind(radius_meters)
    .bind(&query.event_type)
    .bind(query.from_date)
    .bind(query.to_date)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let total: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*)
        FROM events
        WHERE status = 'approved'
          AND ($3::bool OR start_date >= NOW())
          AND ST_DWithin(location, ST_MakePoint($1, $2)::geography, $4)
          AND ($5::text IS NULL OR event_type = $5)
          AND ($6::timestamptz IS NULL OR start_date >= $6)
          AND ($7::timestamptz IS NULL OR start_date <= $7)
        "#,
    )
    .bind(query.lon)
    .bind(query.lat)
    .bind(include_past)
    .bind(radius_meters)
    .bind(&query.event_type)
    .bind(query.from_date)
    .bind(query.to_date)
    .fetch_one(pool)
    .await?;

    Ok((events, total.0))
}

/// Get a single event by ID.
pub async fn get_event(pool: &PgPool, id: Uuid) -> Result<Option<EventRow>, AppError> {
    let event = sqlx::query_as::<_, EventRow>(
        r#"
        SELECT id, name, description, event_type, start_date, end_date, timezone,
               venue_name, address, city, state, country, latitude, longitude,
               cost, url, submitted_by, status, reviewed_by, reviewed_at,
               rejection_reason, created_at, updated_at
        FROM events
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    Ok(event)
}

/// Create a new event with pending status.
pub async fn create_event(
    pool: &PgPool,
    req: &CreateEventRequest,
    callsign: &str,
) -> Result<EventRow, AppError> {
    let event = sqlx::query_as::<_, EventRow>(
        r#"
        INSERT INTO events (
            name, description, event_type, start_date, end_date, timezone,
            venue_name, address, city, state, country, latitude, longitude,
            location, cost, url, submitted_by
        )
        VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13,
            ST_SetSRID(ST_MakePoint($13, $12), 4326)::geography,
            $14, $15, $16
        )
        RETURNING id, name, description, event_type, start_date, end_date, timezone,
                  venue_name, address, city, state, country, latitude, longitude,
                  cost, url, submitted_by, status, reviewed_by, reviewed_at,
                  rejection_reason, created_at, updated_at
        "#,
    )
    .bind(&req.name)
    .bind(&req.description)
    .bind(&req.event_type)
    .bind(req.start_date)
    .bind(req.end_date)
    .bind(&req.timezone)
    .bind(&req.venue_name)
    .bind(&req.address)
    .bind(&req.city)
    .bind(&req.state)
    .bind(&req.country)
    .bind(req.latitude)
    .bind(req.longitude)
    .bind(&req.cost)
    .bind(&req.url)
    .bind(callsign)
    .fetch_one(pool)
    .await?;

    Ok(event)
}

/// Update an event owned by the given callsign.
/// If the event was approved and key fields changed, resets status to pending.
pub async fn update_own_event(
    pool: &PgPool,
    id: Uuid,
    callsign: &str,
    req: &UpdateEventRequest,
) -> Result<Option<EventRow>, AppError> {
    // First fetch the existing event to check ownership and detect key-field changes
    let existing = sqlx::query_as::<_, EventRow>(
        r#"
        SELECT id, name, description, event_type, start_date, end_date, timezone,
               venue_name, address, city, state, country, latitude, longitude,
               cost, url, submitted_by, status, reviewed_by, reviewed_at,
               rejection_reason, created_at, updated_at
        FROM events
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await?;

    let existing = match existing {
        Some(e) => e,
        None => return Ok(None),
    };

    if existing.submitted_by != callsign {
        return Err(AppError::EventNotOwned { event_id: id });
    }

    // Determine if key fields changed (triggers re-review for approved events)
    let key_field_changed = existing.status == "approved"
        && (req.name.as_ref().is_some_and(|v| *v != existing.name)
            || req
                .description
                .as_ref()
                .is_some_and(|v| Some(v.clone()) != existing.description)
            || req
                .address
                .as_ref()
                .is_some_and(|v| *v != existing.address)
            || req
                .venue_name
                .as_ref()
                .is_some_and(|v| Some(v.clone()) != existing.venue_name)
            || req
                .latitude
                .as_ref()
                .is_some_and(|v| *v != existing.latitude)
            || req
                .longitude
                .as_ref()
                .is_some_and(|v| *v != existing.longitude));

    let new_status = if key_field_changed {
        "pending"
    } else {
        &existing.status
    };

    let event = sqlx::query_as::<_, EventRow>(
        r#"
        UPDATE events SET
            name = COALESCE($3, name),
            description = COALESCE($4, description),
            event_type = COALESCE($5, event_type),
            start_date = COALESCE($6, start_date),
            end_date = COALESCE($7, end_date),
            timezone = COALESCE($8, timezone),
            venue_name = COALESCE($9, venue_name),
            address = COALESCE($10, address),
            city = COALESCE($11, city),
            state = COALESCE($12, state),
            country = COALESCE($13, country),
            latitude = COALESCE($14, latitude),
            longitude = COALESCE($15, longitude),
            cost = COALESCE($16, cost),
            url = COALESCE($17, url),
            status = $18,
            reviewed_by = CASE WHEN $19 THEN NULL ELSE reviewed_by END,
            reviewed_at = CASE WHEN $19 THEN NULL ELSE reviewed_at END,
            updated_at = now()
        WHERE id = $1 AND submitted_by = $2
        RETURNING id, name, description, event_type, start_date, end_date, timezone,
                  venue_name, address, city, state, country, latitude, longitude,
                  cost, url, submitted_by, status, reviewed_by, reviewed_at,
                  rejection_reason, created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(callsign)
    .bind(&req.name)
    .bind(&req.description)
    .bind(&req.event_type)
    .bind(req.start_date)
    .bind(req.end_date)
    .bind(&req.timezone)
    .bind(&req.venue_name)
    .bind(&req.address)
    .bind(&req.city)
    .bind(&req.state)
    .bind(&req.country)
    .bind(req.latitude)
    .bind(req.longitude)
    .bind(&req.cost)
    .bind(&req.url)
    .bind(new_status)
    .bind(key_field_changed)
    .fetch_optional(pool)
    .await?;

    Ok(event)
}

/// Delete an event owned by the given callsign.
pub async fn delete_own_event(
    pool: &PgPool,
    id: Uuid,
    callsign: &str,
) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM events WHERE id = $1 AND submitted_by = $2")
        .bind(id)
        .bind(callsign)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}

/// List events submitted by a specific callsign (all statuses).
pub async fn list_my_events(
    pool: &PgPool,
    callsign: &str,
    limit: i64,
    offset: i64,
) -> Result<Vec<EventListItem>, AppError> {
    let events = sqlx::query_as::<_, EventListItem>(
        r#"
        SELECT id, name, event_type, start_date, end_date, timezone,
               venue_name, city, state, country, latitude, longitude,
               cost, submitted_by, status, created_at,
               NULL::double precision AS distance_meters
        FROM events
        WHERE submitted_by = $1
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(callsign)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(events)
}

/// Count pending events for a callsign (spam prevention).
pub async fn count_pending_events(pool: &PgPool, callsign: &str) -> Result<i64, AppError> {
    let (count,): (i64,) =
        sqlx::query_as("SELECT COUNT(*) FROM events WHERE submitted_by = $1 AND status = 'pending'")
            .bind(callsign)
            .fetch_one(pool)
            .await?;

    Ok(count)
}

/// Admin: list events with optional status filter.
pub async fn list_events_admin(
    pool: &PgPool,
    query: &AdminListEventsQuery,
) -> Result<(Vec<EventListItem>, i64), AppError> {
    let limit = query.limit.unwrap_or(50).min(100);
    let offset = query.offset.unwrap_or(0);

    let events = sqlx::query_as::<_, EventListItem>(
        r#"
        SELECT id, name, event_type, start_date, end_date, timezone,
               venue_name, city, state, country, latitude, longitude,
               cost, submitted_by, status, created_at,
               NULL::double precision AS distance_meters
        FROM events
        WHERE ($1::text IS NULL OR status = $1)
        ORDER BY created_at ASC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(&query.status)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    let total: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM events WHERE ($1::text IS NULL OR status = $1)",
    )
    .bind(&query.status)
    .fetch_one(pool)
    .await?;

    Ok((events, total.0))
}

/// Admin: update any event fields.
pub async fn admin_update_event(
    pool: &PgPool,
    id: Uuid,
    req: &UpdateEventRequest,
) -> Result<Option<EventRow>, AppError> {
    let event = sqlx::query_as::<_, EventRow>(
        r#"
        UPDATE events SET
            name = COALESCE($2, name),
            description = COALESCE($3, description),
            event_type = COALESCE($4, event_type),
            start_date = COALESCE($5, start_date),
            end_date = COALESCE($6, end_date),
            timezone = COALESCE($7, timezone),
            venue_name = COALESCE($8, venue_name),
            address = COALESCE($9, address),
            city = COALESCE($10, city),
            state = COALESCE($11, state),
            country = COALESCE($12, country),
            latitude = COALESCE($13, latitude),
            longitude = COALESCE($14, longitude),
            cost = COALESCE($15, cost),
            url = COALESCE($16, url),
            updated_at = now()
        WHERE id = $1
        RETURNING id, name, description, event_type, start_date, end_date, timezone,
                  venue_name, address, city, state, country, latitude, longitude,
                  cost, url, submitted_by, status, reviewed_by, reviewed_at,
                  rejection_reason, created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(&req.name)
    .bind(&req.description)
    .bind(&req.event_type)
    .bind(req.start_date)
    .bind(req.end_date)
    .bind(&req.timezone)
    .bind(&req.venue_name)
    .bind(&req.address)
    .bind(&req.city)
    .bind(&req.state)
    .bind(&req.country)
    .bind(req.latitude)
    .bind(req.longitude)
    .bind(&req.cost)
    .bind(&req.url)
    .fetch_optional(pool)
    .await?;

    Ok(event)
}

/// Admin: approve or reject an event.
pub async fn review_event(
    pool: &PgPool,
    id: Uuid,
    status: &str,
    reviewed_by: &str,
    reason: Option<&str>,
) -> Result<Option<EventRow>, AppError> {
    let event = sqlx::query_as::<_, EventRow>(
        r#"
        UPDATE events SET
            status = $2,
            reviewed_by = $3,
            reviewed_at = now(),
            rejection_reason = $4,
            updated_at = now()
        WHERE id = $1
        RETURNING id, name, description, event_type, start_date, end_date, timezone,
                  venue_name, address, city, state, country, latitude, longitude,
                  cost, url, submitted_by, status, reviewed_by, reviewed_at,
                  rejection_reason, created_at, updated_at
        "#,
    )
    .bind(id)
    .bind(status)
    .bind(reviewed_by)
    .bind(reason)
    .fetch_optional(pool)
    .await?;

    Ok(event)
}

/// Admin: hard delete any event.
pub async fn admin_delete_event(pool: &PgPool, id: Uuid) -> Result<bool, AppError> {
    let result = sqlx::query("DELETE FROM events WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await?;

    Ok(result.rows_affected() > 0)
}

/// Get submitter history stats for admin review.
pub async fn get_submitter_history(
    pool: &PgPool,
    callsign: &str,
) -> Result<SubmitterStats, AppError> {
    let stats = sqlx::query_as::<_, SubmitterStats>(
        r#"
        SELECT
            COUNT(*) AS total_submitted,
            COUNT(*) FILTER (WHERE status = 'approved') AS total_approved,
            COUNT(*) FILTER (WHERE status = 'rejected') AS total_rejected,
            COUNT(*) FILTER (WHERE status = 'pending') AS total_pending
        FROM events
        WHERE submitted_by = $1
        "#,
    )
    .bind(callsign)
    .fetch_one(pool)
    .await?;

    Ok(stats)
}

/// Fetch all days for a single event, ordered by date.
pub async fn get_event_days(pool: &PgPool, event_id: Uuid) -> Result<Vec<EventDayRow>, AppError> {
    let days = sqlx::query_as::<_, EventDayRow>(
        r#"
        SELECT id, event_id, date, start_time, end_time, created_at
        FROM event_days
        WHERE event_id = $1
        ORDER BY date ASC
        "#,
    )
    .bind(event_id)
    .fetch_all(pool)
    .await?;

    Ok(days)
}

/// Fetch days for multiple events at once (batch loader for list endpoints).
pub async fn get_event_days_batch(
    pool: &PgPool,
    event_ids: &[Uuid],
) -> Result<Vec<EventDayRow>, AppError> {
    let days = sqlx::query_as::<_, EventDayRow>(
        r#"
        SELECT id, event_id, date, start_time, end_time, created_at
        FROM event_days
        WHERE event_id = ANY($1)
        ORDER BY event_id, date ASC
        "#,
    )
    .bind(event_ids)
    .fetch_all(pool)
    .await?;

    Ok(days)
}

/// Replace all days for an event (delete + insert).
pub async fn replace_event_days(
    pool: &PgPool,
    event_id: Uuid,
    days: &[EventDayRequest],
) -> Result<Vec<EventDayRow>, AppError> {
    // Delete existing days
    sqlx::query("DELETE FROM event_days WHERE event_id = $1")
        .bind(event_id)
        .execute(pool)
        .await?;

    if days.is_empty() {
        return Ok(Vec::new());
    }

    // Insert new days
    let mut inserted = Vec::with_capacity(days.len());
    for day in days {
        let row = sqlx::query_as::<_, EventDayRow>(
            r#"
            INSERT INTO event_days (event_id, date, start_time, end_time)
            VALUES ($1, $2, $3, $4)
            RETURNING id, event_id, date, start_time, end_time, created_at
            "#,
        )
        .bind(event_id)
        .bind(day.date)
        .bind(day.start_time)
        .bind(day.end_time)
        .fetch_one(pool)
        .await?;

        inserted.push(row);
    }

    Ok(inserted)
}
