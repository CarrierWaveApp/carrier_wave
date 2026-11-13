//! Carrier Wave activities-server **clubs** API — wire models + async client.
//!
//! Mirrors the server response types in `server/src/models/club.rs` and the
//! iOS `ActivitiesClient+Clubs.swift` DTOs (the JSON keys are `camelCase`, and
//! every endpoint wraps its payload in a `{ "data": … }` envelope). Like every
//! other `cw-net` client, the host platform owns the bearer token and hands it
//! in per call — nothing here touches the keychain.
//!
//! Two endpoints are ETag-aware (`/v1/clubs` and `/v1/clubs/membership`): the
//! client sends `If-None-Match` and reports a `304 Not Modified` as
//! [`Conditional::NotModified`] so the caller can skip rebuilding its cache.

use chrono::{DateTime, Utc};
use reqwest::header::{ETAG, IF_NONE_MATCH};
use reqwest::StatusCode;
use serde::Deserialize;

use crate::http::{HttpClient, HttpError};

/// The `{ "data": … }` envelope every activities endpoint returns.
#[derive(Debug, Deserialize)]
struct DataResponse<T> {
    data: T,
}

/// Result of an ETag-conditional GET.
#[derive(Debug, Clone, PartialEq)]
pub enum Conditional<T> {
    /// Server returned fresh data (with the new ETag, if any).
    Modified { data: T, etag: Option<String> },
    /// `304 Not Modified` — the caller's cached copy is current.
    NotModified,
}

// ---------------------------------------------------------------------------
// Wire models (mirror server/src/models/club.rs, camelCase JSON)
// ---------------------------------------------------------------------------

/// One club's metadata — the `/v1/clubs` list element (`ClubResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubWire {
    /// Server club UUID, stringified.
    pub id: String,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
    /// Defaulted: a few legacy rows omit the key.
    #[serde(default)]
    pub has_logo: bool,
    pub member_count: i64,
}

/// One member of a club (`ClubMemberResponse`), with server presence enrichment.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubMemberWire {
    pub callsign: String,
    pub role: String,
    pub joined_at: Option<DateTime<Utc>>,
    pub last_seen_at: Option<DateTime<Utc>>,
    pub last_grid: Option<String>,
    #[serde(default)]
    pub is_carrier_wave_user: bool,
}

/// A single club with its full member list (`ClubDetailResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubDetailWire {
    pub id: String,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
    #[serde(default)]
    pub has_logo: bool,
    /// Omitted when the caller passes `includeMembers=false`.
    #[serde(default)]
    pub members: Option<Vec<ClubMemberWire>>,
}

/// Compact membership entry from `/v1/clubs/membership` (`ClubMembershipEntry`):
/// a club name and its member callsigns. Drives the callsign→clubs cache.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubMembershipEntryWire {
    pub name: String,
    pub callsigns: Vec<String>,
}

/// Real-time online status for a member (`MemberStatusResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MemberStatusWire {
    pub callsign: String,
    pub status: MemberOnlineStatusWire,
    pub spot_info: Option<SpotInfoWire>,
    pub last_seen_at: Option<DateTime<Utc>>,
}

/// Member online-status classification (`MemberOnlineStatus`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MemberOnlineStatusWire {
    OnAir,
    RecentlyActive,
    Inactive,
}

/// Spot attached to an on-air member (`SpotInfo`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SpotInfoWire {
    pub frequency: f64,
    pub mode: Option<String>,
    pub source: String,
    pub spotted_at: DateTime<Utc>,
}

/// One page of a club activity feed (`ClubActivityResponseDTO`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubActivityResponseWire {
    pub items: Vec<ClubActivityItemWire>,
    pub pagination: ClubActivityPaginationWire,
}

/// One activity-feed item. `details` is the same opaque per-activity blob the
/// app already treats as an untyped payload, carried through verbatim.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubActivityItemWire {
    pub id: String,
    pub callsign: String,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    #[serde(default)]
    pub details: serde_json::Value,
    pub created_at: DateTime<Utc>,
}

/// Cursor pagination for the activity feed (`ClubActivityPaginationDTO`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClubActivityPaginationWire {
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Async client for the activities-server clubs endpoints.
#[derive(Debug, Clone)]
pub struct ClubsClient {
    http: HttpClient,
    base_url: String,
}

impl ClubsClient {
    /// Build a client against `base_url` (e.g. `https://activities.carrierwave.app`).
    /// A trailing slash is trimmed so path joins stay clean.
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        let base_url = base_url.into().trim_end_matches('/').to_string();
        Self { http, base_url }
    }

    /// `GET /v1/clubs` — the user's clubs (metadata, no members). `prior_callsigns`
    /// expands the result to clubs joined under previous calls (server v0.4.65+).
    /// ETag-aware.
    pub async fn get_my_clubs(
        &self,
        bearer: &str,
        prior_callsigns: &[String],
        etag: Option<&str>,
    ) -> Result<Conditional<Vec<ClubWire>>, HttpError> {
        let url = self.clubs_url("/v1/clubs", prior_callsigns);
        self.conditional_get(&url, bearer, etag).await
    }

    /// `GET /v1/clubs/membership` — compact club→callsigns cache. ETag-aware.
    pub async fn get_membership(
        &self,
        bearer: &str,
        prior_callsigns: &[String],
        etag: Option<&str>,
    ) -> Result<Conditional<Vec<ClubMembershipEntryWire>>, HttpError> {
        let url = self.clubs_url("/v1/clubs/membership", prior_callsigns);
        self.conditional_get(&url, bearer, etag).await
    }

    /// `GET /v1/clubs/:id` — one club with its members (when `include_members`).
    pub async fn get_club_details(
        &self,
        bearer: &str,
        club_id: &str,
        include_members: bool,
    ) -> Result<ClubDetailWire, HttpError> {
        let mut url = self.url(&format!("/v1/clubs/{club_id}"));
        url.query_pairs_mut()
            .append_pair("includeMembers", if include_members { "true" } else { "false" });
        self.get_data(url.as_str(), bearer).await
    }

    /// `GET /v1/clubs/:id/activity` — cursor-paginated activity feed.
    pub async fn get_activity(
        &self,
        bearer: &str,
        club_id: &str,
        cursor: Option<&str>,
        limit: i64,
    ) -> Result<ClubActivityResponseWire, HttpError> {
        let mut url = self.url(&format!("/v1/clubs/{club_id}/activity"));
        {
            let mut pairs = url.query_pairs_mut();
            pairs.append_pair("limit", &limit.to_string());
            if let Some(cursor) = cursor {
                pairs.append_pair("cursor", cursor);
            }
        }
        self.get_data(url.as_str(), bearer).await
    }

    /// `GET /v1/clubs/:id/status` — real-time member online status.
    pub async fn get_status(
        &self,
        bearer: &str,
        club_id: &str,
    ) -> Result<Vec<MemberStatusWire>, HttpError> {
        let url = self.url(&format!("/v1/clubs/{club_id}/status"));
        self.get_data(url.as_str(), bearer).await
    }

    // --- internals ---------------------------------------------------------

    /// Build a [`url::Url`] for `path` under the base URL.
    fn url(&self, path: &str) -> url::Url {
        // base_url is operator-supplied; parse-then-join keeps encoding correct.
        url::Url::parse(&format!("{}{}", self.base_url, path))
            .unwrap_or_else(|_| url::Url::parse(&self.base_url).expect("valid base url"))
    }

    /// A clubs URL with an optional `callsigns=` prior-call expansion param.
    fn clubs_url(&self, path: &str, prior_callsigns: &[String]) -> String {
        let mut url = self.url(path);
        if !prior_callsigns.is_empty() {
            let value = prior_callsigns
                .iter()
                .map(|call| call.to_uppercase())
                .collect::<Vec<_>>()
                .join(",");
            url.query_pairs_mut().append_pair("callsigns", &value);
        }
        url.to_string()
    }

    /// GET with bearer auth, decode the `{ data }` envelope into `T`. Fails on
    /// any non-2xx (no conditional handling).
    async fn get_data<T: serde::de::DeserializeOwned>(
        &self,
        url: &str,
        bearer: &str,
    ) -> Result<T, HttpError> {
        let request = self.http.inner().get(url).bearer_auth(bearer);
        let bytes = self.http.send_bytes(request).await?;
        let env: DataResponse<T> = serde_json::from_slice(&bytes)?;
        Ok(env.data)
    }

    /// GET with bearer auth + optional `If-None-Match`. Returns
    /// [`Conditional::NotModified`] on a 304, otherwise the decoded `{ data }`
    /// payload plus any response ETag.
    async fn conditional_get<T: serde::de::DeserializeOwned>(
        &self,
        url: &str,
        bearer: &str,
        etag: Option<&str>,
    ) -> Result<Conditional<T>, HttpError> {
        let mut request = self.http.inner().get(url).bearer_auth(bearer);
        if let Some(tag) = etag {
            request = request.header(IF_NONE_MATCH, tag);
        }
        let response = request.send().await?;
        let status = response.status();
        if status == StatusCode::NOT_MODIFIED {
            return Ok(Conditional::NotModified);
        }
        let new_etag = response
            .headers()
            .get(ETAG)
            .and_then(|val| val.to_str().ok())
            .map(str::to_string);
        let bytes = response.bytes().await?;
        if !status.is_success() {
            return Err(HttpError::Http {
                status: status.as_u16(),
                body: String::from_utf8_lossy(&bytes).into_owned(),
            });
        }
        let env: DataResponse<T> = serde_json::from_slice(&bytes)?;
        Ok(Conditional::Modified { data: env.data, etag: new_etag })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_clubs_list_envelope() {
        let json = r#"{
            "data": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "name": "SKCC",
                    "callsign": "K9SKC",
                    "description": "Straight Key Century Club",
                    "notesUrl": "https://example.com/notes",
                    "notesTitle": "SKCC Notes",
                    "hasLogo": true,
                    "memberCount": 42
                },
                {
                    "id": "22222222-2222-2222-2222-222222222222",
                    "name": "FISTS",
                    "callsign": null,
                    "description": null,
                    "hasLogo": false,
                    "memberCount": 7
                }
            ]
        }"#;
        let env: DataResponse<Vec<ClubWire>> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.len(), 2);
        assert_eq!(env.data[0].name, "SKCC");
        assert_eq!(env.data[0].notes_url.as_deref(), Some("https://example.com/notes"));
        assert!(env.data[0].has_logo);
        assert_eq!(env.data[0].member_count, 42);
        // Missing optional keys default cleanly.
        assert_eq!(env.data[1].callsign, None);
        assert!(!env.data[1].has_logo);
    }

    #[test]
    fn parses_membership_envelope() {
        let json = r#"{
            "data": [
                { "name": "SKCC", "callsigns": ["W6JY", "N6ABC"] },
                { "name": "FISTS", "callsigns": [] }
            ]
        }"#;
        let env: DataResponse<Vec<ClubMembershipEntryWire>> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.len(), 2);
        assert_eq!(env.data[0].name, "SKCC");
        assert_eq!(env.data[0].callsigns, vec!["W6JY", "N6ABC"]);
        assert!(env.data[1].callsigns.is_empty());
    }

    #[test]
    fn parses_club_detail_with_members_and_dates() {
        let json = r#"{
            "data": {
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "SKCC",
                "callsign": "K9SKC",
                "description": null,
                "hasLogo": false,
                "members": [
                    {
                        "callsign": "W6JY",
                        "role": "admin",
                        "joinedAt": "2024-01-02T03:04:05Z",
                        "lastSeenAt": "2026-06-27T12:00:00Z",
                        "lastGrid": "CM87",
                        "isCarrierWaveUser": true
                    },
                    {
                        "callsign": "N6ABC",
                        "role": "member",
                        "joinedAt": "2023-05-06T07:08:09Z",
                        "isCarrierWaveUser": false
                    }
                ]
            }
        }"#;
        let env: DataResponse<ClubDetailWire> = serde_json::from_str(json).unwrap();
        let members = env.data.members.unwrap();
        assert_eq!(members.len(), 2);
        assert_eq!(members[0].role, "admin");
        assert_eq!(members[0].last_grid.as_deref(), Some("CM87"));
        assert!(members[0].joined_at.is_some());
        assert!(members[0].is_carrier_wave_user);
        // Absent lastSeenAt/lastGrid → None.
        assert_eq!(members[1].last_seen_at, None);
        assert_eq!(members[1].last_grid, None);
    }

    #[test]
    fn parses_member_status() {
        let json = r#"{
            "data": [
                {
                    "callsign": "W6JY",
                    "status": "onAir",
                    "spotInfo": {
                        "frequency": 14062.5,
                        "mode": "CW",
                        "source": "RBN",
                        "spottedAt": "2026-06-27T12:34:56Z"
                    },
                    "lastSeenAt": "2026-06-27T12:34:56Z"
                },
                { "callsign": "N6ABC", "status": "inactive" }
            ]
        }"#;
        let env: DataResponse<Vec<MemberStatusWire>> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data[0].status, MemberOnlineStatusWire::OnAir);
        let spot = env.data[0].spot_info.as_ref().unwrap();
        assert_eq!(spot.frequency, 14062.5);
        assert_eq!(spot.mode.as_deref(), Some("CW"));
        assert_eq!(env.data[1].status, MemberOnlineStatusWire::Inactive);
        assert_eq!(env.data[1].spot_info, None);
    }

    #[test]
    fn parses_activity_feed_with_opaque_details() {
        let json = r#"{
            "data": {
                "items": [
                    {
                        "id": "33333333-3333-3333-3333-333333333333",
                        "callsign": "W6JY",
                        "activityType": "activation",
                        "timestamp": "2026-06-27T10:00:00Z",
                        "details": { "park": "K-1234", "qsos": 55 },
                        "createdAt": "2026-06-27T10:05:00Z"
                    }
                ],
                "pagination": { "hasMore": true, "nextCursor": "abc123" }
            }
        }"#;
        let env: DataResponse<ClubActivityResponseWire> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.items.len(), 1);
        assert_eq!(env.data.items[0].activity_type, "activation");
        // Opaque details survive verbatim.
        assert_eq!(env.data.items[0].details["park"], "K-1234");
        assert!(env.data.pagination.has_more);
        assert_eq!(env.data.pagination.next_cursor.as_deref(), Some("abc123"));
    }

    #[test]
    fn clubs_url_appends_uppercased_callsigns() {
        let client = ClubsClient::new(HttpClient::new().unwrap(), "https://example.com/");
        let url = client.clubs_url("/v1/clubs", &["w6jy".into(), "w6jsv".into()]);
        assert_eq!(url, "https://example.com/v1/clubs?callsigns=W6JY%2CW6JSV");
        // No prior calls → no query string, and the base trailing slash is trimmed.
        let plain = client.clubs_url("/v1/clubs/membership", &[]);
        assert_eq!(plain, "https://example.com/v1/clubs/membership");
    }
}
