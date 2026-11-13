use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct InviteToken {
    pub token: String,
    pub challenge_id: Uuid,
    pub max_uses: Option<i32>,
    pub use_count: i32,
    pub expires_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InviteResponse {
    pub token: String,
    pub url: String,
    pub max_uses: Option<i32>,
    pub use_count: i32,
    pub expires_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

impl InviteToken {
    pub fn into_response(self, base_url: &str) -> InviteResponse {
        InviteResponse {
            url: format!("{}/join/{}", base_url, self.token),
            token: self.token,
            max_uses: self.max_uses,
            use_count: self.use_count,
            expires_at: self.expires_at,
            created_at: self.created_at,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateInviteRequest {
    pub max_uses: Option<i32>,
    pub expires_at: Option<DateTime<Utc>>,
}
