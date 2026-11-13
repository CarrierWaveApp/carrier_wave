use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Single error entry in the telemetry report
#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct UploadErrorEntry {
    pub service: String,
    pub category: String,
    pub message_hash: String,
    pub affected_count: i32,
    pub is_transient: bool,
    pub app_version: String,
    pub os_version: String,
}

/// Request body for POST /v1/telemetry/upload-errors
#[derive(Debug, Deserialize)]
pub struct ReportUploadErrorsRequest {
    pub errors: Vec<UploadErrorEntry>,
}

/// Response for the telemetry endpoint
#[derive(Debug, Serialize)]
pub struct ReportUploadErrorsResponse {
    pub accepted: usize,
}

/// Query params for GET /v1/admin/telemetry/upload-errors
#[derive(Debug, Deserialize)]
pub struct TelemetryQuery {
    /// Number of days to look back (default 7, max 90)
    pub days: Option<i32>,
    /// Filter by service
    pub service: Option<String>,
    /// Filter by category
    pub category: Option<String>,
}

/// Summary counts by service
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ServiceCount {
    pub service: String,
    pub error_count: i64,
    pub affected_qsos: i64,
}

/// Summary counts by category
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct CategoryCount {
    pub category: String,
    pub error_count: i64,
    pub affected_qsos: i64,
}

/// Errors per day for trend chart
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct DailyErrorCount {
    pub date: chrono::NaiveDate,
    pub error_count: i64,
    pub affected_qsos: i64,
}

/// A single recent error row
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct RecentError {
    pub service: String,
    pub category: String,
    pub message_hash: String,
    pub affected_count: i32,
    pub is_transient: bool,
    pub app_version: String,
    pub os_version: String,
    pub callsign: String,
    pub created_at: DateTime<Utc>,
}

/// Full admin telemetry response
#[derive(Debug, Serialize)]
pub struct TelemetrySummaryResponse {
    pub total_errors: i64,
    pub total_affected_qsos: i64,
    pub unique_callsigns: i64,
    pub by_service: Vec<ServiceCount>,
    pub by_category: Vec<CategoryCount>,
    pub daily_trend: Vec<DailyErrorCount>,
    pub recent_errors: Vec<RecentError>,
}
