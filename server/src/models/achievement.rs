use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Achievement {
    pub id: String,
    pub name: String,
    pub description: String,
    pub category: String,
    pub tier: Option<String>,
    pub icon_name: String,
    pub accent_hex: Option<String>,
    pub award_method: String,
    pub secret: bool,
    pub sort_order: i32,
}

#[derive(Debug, Clone, FromRow, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserAchievement {
    pub id: Uuid,
    pub callsign: String,
    pub achievement_id: String,
    pub awarded_at: DateTime<Utc>,
    pub awarded_by: Option<String>,
    pub evidence: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AwardAchievementRequest {
    pub callsign: String,
    pub awarded_by: Option<String>,
    pub evidence: Option<serde_json::Value>,
}
