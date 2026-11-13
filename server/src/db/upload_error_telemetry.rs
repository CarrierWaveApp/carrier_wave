use sqlx::PgPool;

use crate::error::AppError;
use crate::models::upload_error_telemetry::{
    CategoryCount, DailyErrorCount, RecentError, ServiceCount, TelemetrySummaryResponse,
    UploadErrorEntry,
};

/// Insert a batch of upload error telemetry entries for a callsign.
pub async fn insert_upload_errors(
    pool: &PgPool,
    callsign: &str,
    errors: &[UploadErrorEntry],
) -> Result<usize, AppError> {
    let mut count = 0;
    for entry in errors {
        sqlx::query(
            r#"
            INSERT INTO upload_error_telemetry
                (callsign, service, category, message_hash, affected_count, is_transient, app_version, os_version)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            "#,
        )
        .bind(callsign)
        .bind(&entry.service)
        .bind(&entry.category)
        .bind(&entry.message_hash)
        .bind(entry.affected_count)
        .bind(entry.is_transient)
        .bind(&entry.app_version)
        .bind(&entry.os_version)
        .execute(pool)
        .await?;
        count += 1;
    }
    Ok(count)
}

/// Get telemetry summary for admin dashboard.
pub async fn get_telemetry_summary(
    pool: &PgPool,
    days: i32,
    service_filter: Option<&str>,
    category_filter: Option<&str>,
) -> Result<TelemetrySummaryResponse, AppError> {
    // Totals
    let totals = sqlx::query_as::<_, (i64, i64, i64)>(
        r#"
        SELECT
            COUNT(*) as total_errors,
            COALESCE(SUM(affected_count), 0) as total_affected_qsos,
            COUNT(DISTINCT callsign) as unique_callsigns
        FROM upload_error_telemetry
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR service = $2)
          AND ($3::text IS NULL OR category = $3)
        "#,
    )
    .bind(days)
    .bind(service_filter)
    .bind(category_filter)
    .fetch_one(pool)
    .await?;

    // By service
    let by_service = sqlx::query_as::<_, ServiceCount>(
        r#"
        SELECT
            service,
            COUNT(*) as error_count,
            COALESCE(SUM(affected_count), 0) as affected_qsos
        FROM upload_error_telemetry
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR service = $2)
          AND ($3::text IS NULL OR category = $3)
        GROUP BY service
        ORDER BY error_count DESC
        "#,
    )
    .bind(days)
    .bind(service_filter)
    .bind(category_filter)
    .fetch_all(pool)
    .await?;

    // By category
    let by_category = sqlx::query_as::<_, CategoryCount>(
        r#"
        SELECT
            category,
            COUNT(*) as error_count,
            COALESCE(SUM(affected_count), 0) as affected_qsos
        FROM upload_error_telemetry
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR service = $2)
          AND ($3::text IS NULL OR category = $3)
        GROUP BY category
        ORDER BY error_count DESC
        "#,
    )
    .bind(days)
    .bind(service_filter)
    .bind(category_filter)
    .fetch_all(pool)
    .await?;

    // Daily trend
    let daily_trend = sqlx::query_as::<_, DailyErrorCount>(
        r#"
        SELECT
            created_at::date as date,
            COUNT(*) as error_count,
            COALESCE(SUM(affected_count), 0) as affected_qsos
        FROM upload_error_telemetry
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR service = $2)
          AND ($3::text IS NULL OR category = $3)
        GROUP BY created_at::date
        ORDER BY date
        "#,
    )
    .bind(days)
    .bind(service_filter)
    .bind(category_filter)
    .fetch_all(pool)
    .await?;

    // Recent errors (last 50)
    let recent_errors = sqlx::query_as::<_, RecentError>(
        r#"
        SELECT service, category, message_hash, affected_count, is_transient,
               app_version, os_version, callsign, created_at
        FROM upload_error_telemetry
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR service = $2)
          AND ($3::text IS NULL OR category = $3)
        ORDER BY created_at DESC
        LIMIT 50
        "#,
    )
    .bind(days)
    .bind(service_filter)
    .bind(category_filter)
    .fetch_all(pool)
    .await?;

    Ok(TelemetrySummaryResponse {
        total_errors: totals.0,
        total_affected_qsos: totals.1,
        unique_callsigns: totals.2,
        by_service,
        by_category,
        daily_trend,
        recent_errors,
    })
}
