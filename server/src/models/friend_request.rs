use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct FriendRequest {
    pub id: Uuid,
    pub from_user_id: Uuid,
    pub to_user_id: Uuid,
    pub status: String,
    pub requested_at: DateTime<Utc>,
    pub responded_at: Option<DateTime<Utc>>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct FriendRequestWithCallsigns {
    pub id: Uuid,
    pub from_user_id: Uuid,
    pub from_callsign: String,
    pub to_user_id: Uuid,
    pub to_callsign: String,
    pub status: String,
    pub requested_at: DateTime<Utc>,
    pub responded_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendRequestResponse {
    pub id: Uuid,
    pub from_user_id: Uuid,
    pub from_callsign: String,
    pub to_user_id: Uuid,
    pub to_callsign: String,
    pub status: String,
    pub requested_at: DateTime<Utc>,
}

impl From<FriendRequestWithCallsigns> for FriendRequestResponse {
    fn from(req: FriendRequestWithCallsigns) -> Self {
        Self {
            id: req.id,
            from_user_id: req.from_user_id,
            from_callsign: req.from_callsign,
            to_user_id: req.to_user_id,
            to_callsign: req.to_callsign,
            status: req.status,
            requested_at: req.requested_at,
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateFriendRequestBody {
    #[serde(default)]
    pub to_user_id: Option<Uuid>,
    #[serde(default)]
    pub invite_token: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct Friendship {
    pub id: Uuid,
    pub user_id: Uuid,
    pub friend_id: Uuid,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct FriendSuggestionsBody {
    pub callsigns: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendSuggestionResponse {
    pub user_id: Uuid,
    pub callsign: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendResponse {
    pub friendship_id: Uuid,
    pub callsign: String,
    pub user_id: Uuid,
    pub accepted_at: DateTime<Utc>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingRequestsResponse {
    pub incoming: Vec<FriendRequestResponse>,
    pub outgoing: Vec<FriendRequestResponse>,
}
