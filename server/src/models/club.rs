use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// Database row types
// ---------------------------------------------------------------------------

/// Database row for the clubs table.
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct Club {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
    pub logo_content_type: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Database row for the club_members table.
#[allow(dead_code)]
#[derive(Debug, Clone, FromRow)]
pub struct ClubMember {
    pub id: Uuid,
    pub club_id: Uuid,
    pub callsign: String,
    pub role: String,
    pub joined_at: DateTime<Utc>,
}

// ---------------------------------------------------------------------------
// API response types
// ---------------------------------------------------------------------------

/// Summary response for club list views (includes member count).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubResponse {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes_title: Option<String>,
    pub has_logo: bool,
    pub member_count: i64,
    /// When the roster was last reconciled against `notes_url` (admin list only).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub roster_synced_at: Option<DateTime<Utc>>,
    /// `ok` or `error: …` from that attempt (admin list only).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub roster_sync_status: Option<String>,
}

/// Combined club + members response for the sync endpoint.
/// Returns all clubs with full member details in a single payload.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubSyncResponse {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes_title: Option<String>,
    pub has_logo: bool,
    pub member_count: i64,
    pub members: Vec<ClubMemberResponse>,
}

/// Detailed response for a single club (includes full member list).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubDetailResponse {
    pub id: Uuid,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes_title: Option<String>,
    pub has_logo: bool,
    pub members: Vec<ClubMemberResponse>,
}

/// Response for a single club member with enriched presence data.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubMemberResponse {
    pub callsign: String,
    pub role: String,
    pub joined_at: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_seen_at: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_grid: Option<String>,
    pub is_carrier_wave_user: bool,
}

/// Real-time status for a club member.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemberStatusResponse {
    pub callsign: String,
    pub status: MemberOnlineStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spot_info: Option<SpotInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_seen_at: Option<DateTime<Utc>>,
}

/// Online status classification for a club member.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum MemberOnlineStatus {
    OnAir,
    RecentlyActive,
    Inactive,
}

/// Spot information attached to a member status.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotInfo {
    pub frequency: f64,
    pub mode: Option<String>,
    pub source: String,
    pub spotted_at: DateTime<Utc>,
}

// ---------------------------------------------------------------------------
// API request types
// ---------------------------------------------------------------------------

/// Request body for POST /v1/clubs.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateClubRequest {
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
}

/// Request body for PATCH /v1/clubs/:id.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateClubRequest {
    pub name: Option<String>,
    #[serde(default, deserialize_with = "deserialize_optional_nullable")]
    pub callsign: Option<Option<String>>,
    #[serde(default, deserialize_with = "deserialize_optional_nullable")]
    pub description: Option<Option<String>>,
    #[serde(
        default,
        deserialize_with = "deserialize_optional_nullable",
        alias = "notes_url"
    )]
    pub notes_url: Option<Option<String>>,
    #[serde(
        default,
        deserialize_with = "deserialize_optional_nullable",
        alias = "notes_title"
    )]
    pub notes_title: Option<Option<String>>,
}

/// Request body for PUT /v1/clubs/:id/notes.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateClubNotesRequest {
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
}

/// Request body for POST /v1/clubs/:id/members.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddMembersRequest {
    pub members: Vec<AddMemberEntry>,
}

/// A single member entry in an add-members request.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AddMemberEntry {
    pub callsign: String,
    #[serde(default = "default_member_role")]
    pub role: String,
}

fn default_member_role() -> String {
    "member".to_string()
}

/// Deserialize a field as `Option<Option<T>>` where:
/// - field missing → `None` (don't update)
/// - field is `null` → `Some(None)` (set to NULL)
/// - field is a value → `Some(Some(value))` (set to value)
fn deserialize_optional_nullable<'de, T, D>(deserializer: D) -> Result<Option<Option<T>>, D::Error>
where
    T: Deserialize<'de>,
    D: serde::Deserializer<'de>,
{
    Option::<T>::deserialize(deserializer).map(Some)
}

/// Request body for PATCH /v1/clubs/:id/members/:callsign.
#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateMemberRoleRequest {
    pub role: String,
}

/// Compact membership response: club name → list of callsigns.
/// Used by iOS to build the in-memory callsign lookup cache.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubMembershipEntry {
    pub name: String,
    pub callsigns: Vec<String>,
}

/// Response for POST /v1/admin/clubs/:id/import-notes.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportNotesResponse {
    /// Callsigns added to the roster.
    pub imported: usize,
    /// Callsigns already on the roster.
    pub skipped: usize,
    /// `member`-role callsigns dropped because they left the notes file.
    pub removed: usize,
    /// The added callsigns.
    pub callsigns: Vec<String>,
    /// The removed callsigns.
    pub removed_callsigns: Vec<String>,
}
