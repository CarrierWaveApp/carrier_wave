use sqlx::PgPool;

use crate::error::AppError;
use crate::models::metrickit_telemetry::{
    MetricKitDailyCount, MetricKitMetadata, MetricKitPayloadRow, MetricKitSummaryResponse,
    MetricKitSummaryRow,
};

/// Insert a MetricKit payload (metrics or diagnostics).
pub async fn insert_payload(
    pool: &PgPool,
    payload_type: &str,
    metadata: &MetricKitMetadata,
    payload: &serde_json::Value,
) -> Result<(), AppError> {
    sqlx::query(
        r#"
        INSERT INTO metrickit_payloads
            (payload_type, app_version, build_number, device_model, os_version, locale, payload)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        "#,
    )
    .bind(payload_type)
    .bind(&metadata.app_version)
    .bind(&metadata.build_number)
    .bind(&metadata.device_model)
    .bind(&metadata.os_version)
    .bind(&metadata.locale)
    .bind(payload)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get MetricKit telemetry summary for admin dashboard.
pub async fn get_summary(
    pool: &PgPool,
    days: i32,
    payload_type: Option<&str>,
    device_model: Option<&str>,
    app_version: Option<&str>,
) -> Result<MetricKitSummaryResponse, AppError> {
    let total: (i64,) = sqlx::query_as(
        r#"
        SELECT COUNT(*) as total
        FROM metrickit_payloads
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR payload_type = $2)
          AND ($3::text IS NULL OR device_model = $3)
          AND ($4::text IS NULL OR app_version = $4)
        "#,
    )
    .bind(days)
    .bind(payload_type)
    .bind(device_model)
    .bind(app_version)
    .fetch_one(pool)
    .await?;

    let by_type_device = sqlx::query_as::<_, MetricKitSummaryRow>(
        r#"
        SELECT
            payload_type,
            app_version,
            device_model,
            os_version,
            COUNT(*) as payload_count
        FROM metrickit_payloads
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR payload_type = $2)
          AND ($3::text IS NULL OR device_model = $3)
          AND ($4::text IS NULL OR app_version = $4)
        GROUP BY payload_type, app_version, device_model, os_version
        ORDER BY payload_count DESC
        "#,
    )
    .bind(days)
    .bind(payload_type)
    .bind(device_model)
    .bind(app_version)
    .fetch_all(pool)
    .await?;

    let daily_trend = sqlx::query_as::<_, MetricKitDailyCount>(
        r#"
        SELECT
            created_at::date as date,
            COUNT(*) FILTER (WHERE payload_type = 'metrics') as metrics_count,
            COUNT(*) FILTER (WHERE payload_type = 'diagnostics') as diagnostics_count
        FROM metrickit_payloads
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR payload_type = $2)
          AND ($3::text IS NULL OR device_model = $3)
          AND ($4::text IS NULL OR app_version = $4)
        GROUP BY created_at::date
        ORDER BY date
        "#,
    )
    .bind(days)
    .bind(payload_type)
    .bind(device_model)
    .bind(app_version)
    .fetch_all(pool)
    .await?;

    let recent_payloads = sqlx::query_as::<_, MetricKitPayloadRow>(
        r#"
        SELECT id, payload_type, app_version, build_number, device_model,
               os_version, locale, payload, created_at
        FROM metrickit_payloads
        WHERE created_at > now() - make_interval(days => $1)
          AND ($2::text IS NULL OR payload_type = $2)
          AND ($3::text IS NULL OR device_model = $3)
          AND ($4::text IS NULL OR app_version = $4)
        ORDER BY created_at DESC
        LIMIT 50
        "#,
    )
    .bind(days)
    .bind(payload_type)
    .bind(device_model)
    .bind(app_version)
    .fetch_all(pool)
    .await?;

    Ok(MetricKitSummaryResponse {
        total_payloads: total.0,
        by_type_device,
        daily_trend,
        recent_payloads,
    })
}
