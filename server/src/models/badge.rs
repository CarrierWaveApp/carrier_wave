use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct Badge {
    pub id: Uuid,
    pub challenge_id: Uuid,
    pub name: String,
    pub tier_id: Option<String>,
    pub image_data: Vec<u8>,
    pub content_type: String,
    pub created_at: DateTime<Utc>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct BadgeMetadata {
    pub id: Uuid,
    pub challenge_id: Uuid,
    pub name: String,
    pub tier_id: Option<String>,
    pub content_type: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BadgeResponse {
    pub id: Uuid,
    pub name: String,
    pub tier_id: Option<String>,
    pub image_url: String,
    pub content_type: String,
    pub created_at: DateTime<Utc>,
}

impl BadgeMetadata {
    pub fn into_response(self, base_url: &str) -> BadgeResponse {
        BadgeResponse {
            id: self.id,
            name: self.name,
            tier_id: self.tier_id,
            image_url: format!("{}/v1/badges/{}/image", base_url, self.id),
            content_type: self.content_type,
            created_at: self.created_at,
        }
    }
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateBadgeFields {
    pub name: String,
    pub tier_id: Option<String>,
}
