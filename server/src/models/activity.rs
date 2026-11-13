use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Database row for an activity.
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct Activity {
    pub id: Uuid,
    pub user_id: Uuid,
    pub callsign: String,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    pub details: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

/// Request body for POST /v1/activities (matches iOS ReportActivityRequest).
#[derive(Debug, Deserialize)]
pub struct ReportActivityRequest {
    #[serde(rename = "type")]
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    pub details: serde_json::Value,
}

/// Response for a reported activity (matches iOS ReportedActivityDTO).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivityResponse {
    pub id: Uuid,
    pub callsign: String,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    pub details: serde_json::Value,
}

impl From<Activity> for ActivityResponse {
    fn from(a: Activity) -> Self {
        Self {
            id: a.id,
            callsign: a.callsign,
            activity_type: a.activity_type,
            timestamp: a.timestamp,
            details: a.details,
        }
    }
}

/// Feed item row from the feed query (activity + friend's display info).
#[derive(Debug, Clone, FromRow)]
pub struct FeedItemRow {
    pub id: Uuid,
    pub callsign: String,
    pub user_id: Uuid,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    pub details: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

/// Response for a feed item (matches iOS FeedItemDTO).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedItemResponse {
    pub id: Uuid,
    pub callsign: String,
    pub user_id: Uuid,
    pub display_name: Option<String>,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    pub details: serde_json::Value,
}

impl From<FeedItemRow> for FeedItemResponse {
    fn from(row: FeedItemRow) -> Self {
        Self {
            id: row.id,
            callsign: row.callsign,
            user_id: row.user_id,
            display_name: None,
            activity_type: row.activity_type,
            timestamp: row.timestamp,
            details: row.details,
        }
    }
}
