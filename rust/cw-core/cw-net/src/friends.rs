//! Carrier Wave activities-server **friends + activity feed** API.
//!
//! Mirrors the server response types in `server/src/models/{friend_request,
//! friend_invite,user,activity}.rs` and the iOS `ActivitiesClient+Friends.swift`
//! / `+Activities.swift` DTOs (camelCase JSON, every endpoint wrapped in a
//! `{ "data": … }` envelope). Like the rest of `cw-net`, the host owns the
//! bearer token and hands it in per call — nothing here touches the keychain.
//!
//! The friends graph is reconciled into the store (see `cw-ffi::friends_api`);
//! the activity feed is presentation-only and fetched on demand (same as the
//! club activity feed).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::http::{HttpClient, HttpError};

/// The `{ "data": … }` envelope every activities endpoint returns.
#[derive(Debug, Deserialize)]
struct DataResponse<T> {
    data: T,
}

// ---------------------------------------------------------------------------
// Wire models (mirror server camelCase JSON)
// ---------------------------------------------------------------------------

/// A user-search hit (`UserSearchResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserSearchResultWire {
    pub user_id: String,
    pub callsign: String,
    pub display_name: Option<String>,
}

/// An accepted friend (`FriendResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendWire {
    pub friendship_id: String,
    pub callsign: String,
    pub user_id: String,
    pub accepted_at: DateTime<Utc>,
}

/// A pending friend request, either direction (`FriendRequestResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendRequestWire {
    pub id: String,
    pub from_user_id: String,
    pub from_callsign: String,
    pub to_user_id: String,
    pub to_callsign: String,
    pub status: String,
    pub requested_at: DateTime<Utc>,
}

/// Incoming + outgoing pending requests (`PendingRequestsResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingRequestsWire {
    pub incoming: Vec<FriendRequestWire>,
    pub outgoing: Vec<FriendRequestWire>,
}

/// A validated friend suggestion (`FriendSuggestionResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FriendSuggestionWire {
    pub user_id: String,
    pub callsign: String,
}

/// A shareable friend-invite link (`FriendInviteResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InviteLinkWire {
    pub token: String,
    pub url: String,
    pub expires_at: DateTime<Utc>,
}

/// One page of the activity feed (`FeedResponse`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedResponseWire {
    pub items: Vec<FeedItemWire>,
    pub pagination: FeedPaginationWire,
}

/// One feed item (`FeedItemResponse`). `details` is the opaque per-activity blob
/// carried through verbatim.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedItemWire {
    pub id: String,
    pub callsign: String,
    pub user_id: String,
    pub display_name: Option<String>,
    pub activity_type: String,
    pub timestamp: DateTime<Utc>,
    #[serde(default)]
    pub details: serde_json::Value,
}

/// Cursor pagination for the feed (`FeedPagination`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeedPaginationWire {
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

// ---------------------------------------------------------------------------
// Request bodies
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CreateFriendRequestBody {
    #[serde(skip_serializing_if = "Option::is_none")]
    to_user_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    invite_token: Option<String>,
}

#[derive(Debug, Serialize)]
struct SuggestionsBody {
    callsigns: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ReportActivityBody {
    #[serde(rename = "type")]
    activity_type: String,
    timestamp: DateTime<Utc>,
    details: serde_json::Value,
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Async client for the activities-server friends + feed endpoints.
#[derive(Debug, Clone)]
pub struct FriendsClient {
    http: HttpClient,
    base_url: String,
}

impl FriendsClient {
    /// Build a client against `base_url`. A trailing slash is trimmed.
    pub fn new(http: HttpClient, base_url: impl Into<String>) -> Self {
        let base_url = base_url.into().trim_end_matches('/').to_string();
        Self { http, base_url }
    }

    /// `GET /v1/users/search?q=` — find registered users by callsign (≥2 chars).
    pub async fn search_users(
        &self,
        bearer: &str,
        query: &str,
    ) -> Result<Vec<UserSearchResultWire>, HttpError> {
        let mut url = self.url("/v1/users/search");
        url.query_pairs_mut().append_pair("q", query);
        self.get_data(url.as_str(), bearer).await
    }

    /// `GET /v1/friends` — accepted friends.
    pub async fn get_friends(&self, bearer: &str) -> Result<Vec<FriendWire>, HttpError> {
        self.get_data(self.url("/v1/friends").as_str(), bearer).await
    }

    /// `GET /v1/friends/requests/pending` — incoming + outgoing pending requests.
    pub async fn get_pending_requests(
        &self,
        bearer: &str,
    ) -> Result<PendingRequestsWire, HttpError> {
        self.get_data(self.url("/v1/friends/requests/pending").as_str(), bearer).await
    }

    /// `POST /v1/friends/requests` with `toUserId` — send a friend request.
    pub async fn send_request(
        &self,
        bearer: &str,
        to_user_id: &str,
    ) -> Result<FriendRequestWire, HttpError> {
        let body = CreateFriendRequestBody {
            to_user_id: Some(to_user_id.to_string()),
            invite_token: None,
        };
        self.post_data(self.url("/v1/friends/requests").as_str(), bearer, &body).await
    }

    /// `POST /v1/friends/requests` with `inviteToken` — accept an invite link.
    pub async fn send_request_with_invite(
        &self,
        bearer: &str,
        invite_token: &str,
    ) -> Result<FriendRequestWire, HttpError> {
        let body = CreateFriendRequestBody {
            to_user_id: None,
            invite_token: Some(invite_token.to_string()),
        };
        self.post_data(self.url("/v1/friends/requests").as_str(), bearer, &body).await
    }

    /// `POST /v1/friends/requests/:id/accept`.
    pub async fn accept_request(&self, bearer: &str, request_id: &str) -> Result<(), HttpError> {
        let url = self.url(&format!("/v1/friends/requests/{request_id}/accept"));
        self.post_empty(url.as_str(), bearer).await
    }

    /// `POST /v1/friends/requests/:id/decline`.
    pub async fn decline_request(&self, bearer: &str, request_id: &str) -> Result<(), HttpError> {
        let url = self.url(&format!("/v1/friends/requests/{request_id}/decline"));
        self.post_empty(url.as_str(), bearer).await
    }

    /// `DELETE /v1/friends/:id` — remove an accepted friend.
    pub async fn remove_friend(&self, bearer: &str, friendship_id: &str) -> Result<(), HttpError> {
        let url = self.url(&format!("/v1/friends/{friendship_id}"));
        let request = self.http.inner().delete(url.as_str()).bearer_auth(bearer);
        self.http.send_bytes(request).await?;
        Ok(())
    }

    /// `POST /v1/friends/suggestions` — validate which callsigns are registered.
    pub async fn get_suggestions(
        &self,
        bearer: &str,
        callsigns: Vec<String>,
    ) -> Result<Vec<FriendSuggestionWire>, HttpError> {
        let body = SuggestionsBody { callsigns };
        self.post_data(self.url("/v1/friends/suggestions").as_str(), bearer, &body).await
    }

    /// `GET /v1/friends/invite-link` — a fresh shareable invite.
    pub async fn get_invite_link(&self, bearer: &str) -> Result<InviteLinkWire, HttpError> {
        self.get_data(self.url("/v1/friends/invite-link").as_str(), bearer).await
    }

    /// `GET /v1/feed` — the friends activity feed, cursor-paginated.
    pub async fn get_feed(
        &self,
        bearer: &str,
        filter: Option<&str>,
        before: Option<&str>,
        limit: i64,
    ) -> Result<FeedResponseWire, HttpError> {
        let mut url = self.url("/v1/feed");
        {
            let mut pairs = url.query_pairs_mut();
            pairs.append_pair("limit", &limit.to_string());
            if let Some(filter) = filter {
                pairs.append_pair("filter", filter);
            }
            if let Some(before) = before {
                pairs.append_pair("before", before);
            }
        }
        self.get_data(url.as_str(), bearer).await
    }

    /// `POST /v1/activities` — report one of the operator's own activities.
    pub async fn report_activity(
        &self,
        bearer: &str,
        activity_type: &str,
        timestamp: DateTime<Utc>,
        details: serde_json::Value,
    ) -> Result<(), HttpError> {
        let body = ReportActivityBody { activity_type: activity_type.to_string(), timestamp, details };
        let request =
            self.http.inner().post(self.url("/v1/activities").as_str()).bearer_auth(bearer).json(&body);
        self.http.send_bytes(request).await?;
        Ok(())
    }

    /// `DELETE /v1/activities/:id` — retract a reported activity.
    pub async fn delete_activity(&self, bearer: &str, activity_id: &str) -> Result<(), HttpError> {
        let url = self.url(&format!("/v1/activities/{activity_id}"));
        let request = self.http.inner().delete(url.as_str()).bearer_auth(bearer);
        self.http.send_bytes(request).await?;
        Ok(())
    }

    // --- internals ---------------------------------------------------------

    fn url(&self, path: &str) -> url::Url {
        url::Url::parse(&format!("{}{}", self.base_url, path))
            .unwrap_or_else(|_| url::Url::parse(&self.base_url).expect("valid base url"))
    }

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

    async fn post_data<B: Serialize, T: serde::de::DeserializeOwned>(
        &self,
        url: &str,
        bearer: &str,
        body: &B,
    ) -> Result<T, HttpError> {
        let request = self.http.inner().post(url).bearer_auth(bearer).json(body);
        let bytes = self.http.send_bytes(request).await?;
        let env: DataResponse<T> = serde_json::from_slice(&bytes)?;
        Ok(env.data)
    }

    /// POST with no body and no decoded response (accept/decline → 200/204).
    async fn post_empty(&self, url: &str, bearer: &str) -> Result<(), HttpError> {
        let request = self.http.inner().post(url).bearer_auth(bearer);
        self.http.send_bytes(request).await?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_user_search_envelope() {
        let json = r#"{
            "data": [
                { "userId": "11111111-1111-1111-1111-111111111111", "callsign": "W1AW", "displayName": "ARRL HQ" },
                { "userId": "22222222-2222-2222-2222-222222222222", "callsign": "N2XYZ", "displayName": null }
            ]
        }"#;
        let env: DataResponse<Vec<UserSearchResultWire>> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.len(), 2);
        assert_eq!(env.data[0].callsign, "W1AW");
        assert_eq!(env.data[0].display_name.as_deref(), Some("ARRL HQ"));
        assert_eq!(env.data[1].display_name, None);
    }

    #[test]
    fn parses_friends_with_dates() {
        let json = r#"{
            "data": [
                {
                    "friendshipId": "ffffffff-0000-0000-0000-000000000001",
                    "callsign": "W1AW",
                    "userId": "11111111-1111-1111-1111-111111111111",
                    "acceptedAt": "2026-06-27T12:00:00Z"
                }
            ]
        }"#;
        let env: DataResponse<Vec<FriendWire>> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data[0].callsign, "W1AW");
        assert_eq!(env.data[0].friendship_id, "ffffffff-0000-0000-0000-000000000001");
        let expected = DateTime::parse_from_rfc3339("2026-06-27T12:00:00Z").unwrap();
        assert_eq!(env.data[0].accepted_at.timestamp(), expected.timestamp());
    }

    #[test]
    fn parses_pending_requests() {
        let json = r#"{
            "data": {
                "incoming": [
                    {
                        "id": "aaaa1111-0000-0000-0000-000000000001",
                        "fromUserId": "11111111-1111-1111-1111-111111111111",
                        "fromCallsign": "W1AW",
                        "toUserId": "99999999-9999-9999-9999-999999999999",
                        "toCallsign": "W6JY",
                        "status": "pending",
                        "requestedAt": "2026-06-27T10:00:00Z"
                    }
                ],
                "outgoing": []
            }
        }"#;
        let env: DataResponse<PendingRequestsWire> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.incoming.len(), 1);
        assert_eq!(env.data.incoming[0].from_callsign, "W1AW");
        assert!(env.data.outgoing.is_empty());
    }

    #[test]
    fn parses_invite_link() {
        let json = r#"{
            "data": { "token": "abc123", "url": "https://cw.app/invite/abc123", "expiresAt": "2026-07-01T00:00:00Z" }
        }"#;
        let env: DataResponse<InviteLinkWire> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.token, "abc123");
        assert_eq!(env.data.url, "https://cw.app/invite/abc123");
    }

    #[test]
    fn parses_feed_with_opaque_details() {
        let json = r#"{
            "data": {
                "items": [
                    {
                        "id": "33333333-3333-3333-3333-333333333333",
                        "callsign": "W1AW",
                        "userId": "11111111-1111-1111-1111-111111111111",
                        "displayName": "ARRL HQ",
                        "activityType": "activation",
                        "timestamp": "2026-06-27T10:00:00Z",
                        "details": { "park": "K-1234", "qsos": 55 }
                    }
                ],
                "pagination": { "hasMore": true, "nextCursor": "2026-06-27T09:00:00Z" }
            }
        }"#;
        let env: DataResponse<FeedResponseWire> = serde_json::from_str(json).unwrap();
        assert_eq!(env.data.items.len(), 1);
        assert_eq!(env.data.items[0].activity_type, "activation");
        assert_eq!(env.data.items[0].details["park"], "K-1234");
        assert!(env.data.pagination.has_more);
        assert_eq!(env.data.pagination.next_cursor.as_deref(), Some("2026-06-27T09:00:00Z"));
    }
}
