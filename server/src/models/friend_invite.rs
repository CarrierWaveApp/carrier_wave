use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct FriendInvite {
    pub id: Uuid,
    pub token: String,
    pub user_id: Uuid,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub used_at: Option<DateTime<Utc>>,
    pub used_by_user_id: Option<Uuid>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendInviteResponse {
    pub token: String,
    pub url: String,
    pub expires_at: DateTime<Utc>,
}

impl FriendInvite {
    pub fn into_response(self, base_url: &str) -> FriendInviteResponse {
        FriendInviteResponse {
            url: format!("{}/invite/{}", base_url, self.token),
            token: self.token,
            expires_at: self.expires_at,
        }
    }
}
