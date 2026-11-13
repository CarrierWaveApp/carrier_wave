use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};

/// Device metadata included with every MetricKit payload
#[derive(Debug, Deserialize)]
pub struct MetricKitMetadata {
    pub app_version: String,
    pub build_number: String,
    pub device_model: String,
    pub os_version: String,
    #[serde(default = "default_locale")]
    pub locale: String,
}

fn default_locale() -> String {
    "unknown".to_string()
}

/// Request body for POST /v1/metrics and /v1/diagnostics
/// The iOS app sends: { "metadata": {...}, "payload": <raw MetricKit JSON> }
#[derive(Debug, Deserialize)]
pub struct MetricKitRequest {
    pub metadata: MetricKitMetadata,
    pub payload: serde_json::Value,
}

/// Response for the ingestion endpoint
#[derive(Debug, Serialize)]
pub struct MetricKitResponse {
    pub accepted: bool,
}

/// Query params for GET /v1/admin/metrickit
#[derive(Debug, Deserialize)]
pub struct MetricKitQuery {
    /// Filter by payload type: "metrics" or "diagnostics"
    #[serde(rename = "type")]
    pub payload_type: Option<String>,
    /// Number of days to look back (default 7, max 90)
    pub days: Option<i32>,
    /// Filter by device model
    pub device_model: Option<String>,
    /// Filter by app version
    pub app_version: Option<String>,
}

/// Summary row for admin view
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct MetricKitSummaryRow {
    pub payload_type: String,
    pub app_version: String,
    pub device_model: String,
    pub os_version: String,
    pub payload_count: i64,
}

/// Daily payload counts for trend
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct MetricKitDailyCount {
    pub date: NaiveDate,
    pub metrics_count: i64,
    pub diagnostics_count: i64,
}

/// A recent payload row for admin detail view
#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct MetricKitPayloadRow {
    pub id: uuid::Uuid,
    pub payload_type: String,
    pub app_version: String,
    pub build_number: String,
    pub device_model: String,
    pub os_version: String,
    pub locale: String,
    pub payload: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

/// Full admin summary response
#[derive(Debug, Serialize)]
pub struct MetricKitSummaryResponse {
    pub total_payloads: i64,
    pub by_type_device: Vec<MetricKitSummaryRow>,
    pub daily_trend: Vec<MetricKitDailyCount>,
    pub recent_payloads: Vec<MetricKitPayloadRow>,
}
