use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct Progress {
    pub id: Uuid,
    pub challenge_id: Uuid,
    pub callsign: String,
    pub completed_goals: serde_json::Value,
    pub current_value: i32,
    pub score: i32,
    pub current_tier: Option<String>,
    pub last_qso_date: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportProgressRequest {
    pub completed_goals: Vec<String>,
    pub current_value: i32,
    pub qualifying_qso_count: i32,
    pub last_qso_date: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProgressResponse {
    pub completed_goals: Vec<String>,
    pub current_value: i32,
    pub percentage: f64,
    pub score: i32,
    pub rank: i64,
    pub current_tier: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReportProgressResponse {
    pub accepted: bool,
    pub server_progress: ProgressResponse,
    pub new_badges: Vec<Uuid>,
}

#[derive(Debug, Serialize, Clone, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct LeaderboardEntry {
    pub rank: i64,
    pub callsign: String,
    pub score: i32,
    pub current_tier: Option<String>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeaderboardResponse {
    pub leaderboard: Vec<LeaderboardEntry>,
    pub total: i64,
    pub user_position: Option<LeaderboardEntry>,
    pub last_updated: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LeaderboardQuery {
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub around: Option<String>,
}
