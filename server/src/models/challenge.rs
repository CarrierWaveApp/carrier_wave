use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, FromRow)]
pub struct Challenge {
    pub id: Uuid,
    pub version: i32,
    pub name: String,
    pub description: String,
    pub author: Option<String>,
    pub category: String,
    pub challenge_type: String,
    pub configuration: serde_json::Value,
    pub invite_config: Option<serde_json::Value>,
    pub hamalert_config: Option<serde_json::Value>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeResponse {
    pub id: Uuid,
    pub version: i32,
    pub name: String,
    pub description: String,
    pub author: Option<String>,
    pub category: String,
    #[serde(rename = "type")]
    pub challenge_type: String,
    pub configuration: serde_json::Value,
    pub invite_config: Option<serde_json::Value>,
    pub hamalert_config: Option<serde_json::Value>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl From<Challenge> for ChallengeResponse {
    fn from(c: Challenge) -> Self {
        Self {
            id: c.id,
            version: c.version,
            name: c.name,
            description: c.description,
            author: c.author,
            category: c.category,
            challenge_type: c.challenge_type,
            configuration: c.configuration,
            invite_config: c.invite_config,
            hamalert_config: c.hamalert_config,
            is_active: c.is_active,
            created_at: c.created_at,
            updated_at: c.updated_at,
        }
    }
}

#[derive(Debug, Serialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeListItem {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub category: String,
    #[serde(rename = "type")]
    pub challenge_type: String,
    pub participant_count: i64,
    pub is_active: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateChallengeRequest {
    pub name: String,
    pub description: String,
    pub author: Option<String>,
    pub category: String,
    #[serde(rename = "type")]
    pub challenge_type: String,
    pub configuration: serde_json::Value,
    pub invite_config: Option<serde_json::Value>,
    pub hamalert_config: Option<serde_json::Value>,
    pub is_active: Option<bool>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ListChallengesQuery {
    pub category: Option<String>,
    #[serde(rename = "type")]
    pub challenge_type: Option<String>,
    pub active: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}
