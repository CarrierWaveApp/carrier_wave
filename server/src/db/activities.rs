use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

use crate::error::AppError;
use crate::models::activity::{Activity, FeedItemRow};

/// Insert a new activity and return the created row.
pub async fn insert_activity(
    pool: &PgPool,
    user_id: Uuid,
    callsign: &str,
    activity_type: &str,
    timestamp: DateTime<Utc>,
    details: &serde_json::Value,
) -> Result<Activity, AppError> {
    let activity = sqlx::query_as::<_, Activity>(
        r#"
        INSERT INTO activities (user_id, callsign, activity_type, timestamp, details)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id, user_id, callsign, activity_type, timestamp, details, created_at
        "#,
    )
    .bind(user_id)
    .bind(callsign)
    .bind(activity_type)
    .bind(timestamp)
    .bind(details)
    .fetch_one(pool)
    .await?;

    Ok(activity)
}

/// Delete an activity by ID, verifying ownership.
/// Returns Ok(()) on success, or ActivityNotFound if not found or not owned.
pub async fn delete_activity(
    pool: &PgPool,
    activity_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let result = sqlx::query(
        r#"
        DELETE FROM activities
        WHERE id = $1 AND user_id = $2
        "#,
    )
    .bind(activity_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(AppError::ActivityNotFound { activity_id });
    }

    Ok(())
}

/// Get the activity feed for a user: activities from their friends,
/// cursor-paginated by created_at DESC.
pub async fn get_feed_for_user(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    before: Option<DateTime<Utc>>,
) -> Result<Vec<FeedItemRow>, AppError> {
    let limit = limit.clamp(1, 100);

    let rows = if let Some(cursor) = before {
        sqlx::query_as::<_, FeedItemRow>(
            r#"
            SELECT a.id, a.callsign, a.user_id, a.activity_type,
                   a.timestamp, a.details, a.created_at
            FROM activities a
            JOIN friendships f ON f.friend_id = a.user_id
            WHERE f.user_id = $1
              AND a.created_at < $2
            ORDER BY a.created_at DESC
            LIMIT $3
            "#,
        )
        .bind(user_id)
        .bind(cursor)
        .bind(limit)
        .fetch_all(pool)
        .await?
    } else {
        sqlx::query_as::<_, FeedItemRow>(
            r#"
            SELECT a.id, a.callsign, a.user_id, a.activity_type,
                   a.timestamp, a.details, a.created_at
            FROM activities a
            JOIN friendships f ON f.friend_id = a.user_id
            WHERE f.user_id = $1
            ORDER BY a.created_at DESC
            LIMIT $2
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .fetch_all(pool)
        .await?
    };

    Ok(rows)
}
