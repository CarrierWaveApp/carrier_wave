use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;
use uuid::Uuid;

#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct User {
    pub id: Uuid,
    pub callsign: String,
    pub created_at: DateTime<Utc>,
}

#[allow(dead_code)]
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserResponse {
    pub id: Uuid,
    pub callsign: String,
}

impl From<User> for UserResponse {
    fn from(user: User) -> Self {
        Self {
            id: user.id,
            callsign: user.callsign,
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UserSearchResponse {
    pub user_id: Uuid,
    pub callsign: String,
    pub display_name: Option<String>,
}

impl From<User> for UserSearchResponse {
    fn from(user: User) -> Self {
        Self {
            user_id: user.id,
            callsign: user.callsign,
            display_name: None,
        }
    }
}

#[derive(Debug, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterRequest {
    pub callsign: String,
    pub device_name: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RegisterResponse {
    pub user_id: Uuid,
    /// SECURITY (CAR-304 / CAR-313): only present when this call *created* a new
    /// participant. `/v1/register` is unauthenticated, so returning the existing
    /// device token for an already-registered callsign let anyone mint a working
    /// credential for any operator. For an existing callsign the field is omitted
    /// entirely; clients that have lost their token must recover via the verified
    /// magic-link flow (`/v1/auth/*`), not by re-registering.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_token: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdminStatsResponse {
    pub total_users: i64,
    pub users_last_7_days: i64,
    pub users_last_30_days: i64,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct UserCountByHour {
    pub hour: DateTime<Utc>,
    pub count: i64,
}
