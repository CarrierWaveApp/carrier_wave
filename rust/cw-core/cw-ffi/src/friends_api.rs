//! Async friends + activity-feed API over UniFFI.
//!
//! `FriendsApi` wraps `cw_net::FriendsClient` and the encrypted store, mirroring
//! `ClubsApi`: it fetches from the activities server, reconciles the social graph
//! into the local `friendship` cache (delete-not-returned), and exposes the
//! presentation-only activity feed on demand. iOS's `FriendsSyncService` +
//! `ActivitiesClient` move into Rust here, so both platforms share the path and
//! the host only supplies a bearer token.
//!
//! Locking discipline matches the rest of the store surface: network I/O with
//! **no** lock held, then a single short critical section applies the writes and
//! the change notification fires after the lock is released — no `MutexGuard`
//! across an `.await`.

use std::sync::Arc;

use cw_net::{
    FeedResponseWire, FriendWire, FriendsClient, HttpClient, PendingRequestsWire,
};
use cw_store::{Friendship, Store, STATUS_ACCEPTED, STATUS_PENDING};

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};

// ---------------------------------------------------------------------------
// FFI DTOs
// ---------------------------------------------------------------------------

/// Outcome of a [`FriendsApi::sync_friends`] call.
#[derive(uniffi::Record)]
pub struct FfiFriendsSummary {
    pub friend_count: i64,
    pub incoming_request_count: i64,
}

/// A user-search hit.
#[derive(uniffi::Record)]
pub struct FfiUserSearchResult {
    pub user_id: String,
    pub callsign: String,
    pub display_name: Option<String>,
}

/// A validated friend suggestion (a known-registered callsign).
#[derive(uniffi::Record)]
pub struct FfiFriendSuggestion {
    pub user_id: String,
    pub callsign: String,
}

/// A shareable friend-invite link.
#[derive(uniffi::Record)]
pub struct FfiInviteLink {
    pub token: String,
    pub url: String,
    /// Unix seconds, UTC.
    pub expires_at: i64,
}

/// One page of the activity feed.
#[derive(uniffi::Record)]
pub struct FfiFeedPage {
    pub items: Vec<FfiFeedItem>,
    pub has_more: bool,
    pub next_cursor: Option<String>,
}

/// A single feed item. `details_json` carries the opaque per-activity payload
/// verbatim (the host decodes what it needs to render).
#[derive(uniffi::Record)]
pub struct FfiFeedItem {
    pub id: String,
    pub callsign: String,
    pub user_id: String,
    pub display_name: Option<String>,
    pub activity_type: String,
    /// Unix seconds, UTC.
    pub timestamp: i64,
    pub details_json: String,
}

// ---------------------------------------------------------------------------
// Object
// ---------------------------------------------------------------------------

/// Async friends API bound to a [`FieldStore`] and an activities-server base URL.
#[derive(uniffi::Object)]
pub struct FriendsApi {
    client: FriendsClient,
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl FriendsApi {
    /// Build an API against `base_url`, writing into `store`.
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(FriendsApi { client: FriendsClient::new(http, base_url), store })
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl FriendsApi {
    /// Fetch accepted friends + pending requests and reconcile the local cache to
    /// the server set (departed friends / withdrawn requests are removed).
    pub async fn sync_friends(&self, bearer: String) -> Result<FfiFriendsSummary, CwError> {
        // Network — no lock held.
        let friends = self.client.get_friends(&bearer).await?;
        let pending = self.client.get_pending_requests(&bearer).await?;

        // Apply under one lock, in one transaction (one fsync for the whole
        // reconcile instead of one per row — see `Store::in_transaction`).
        let (friend_count, incoming_request_count) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| apply_friends(&store, &friends, &pending))?;
            (store.friendship_count()?, store.incoming_request_count()?)
        };

        self.store
            .notify(FfiStoreChange { table: FfiStoreTable::Friendship, kind: FfiChangeKind::Upsert });

        Ok(FfiFriendsSummary { friend_count, incoming_request_count })
    }

    /// Search registered users by callsign (≥2 chars). Not persisted.
    pub async fn search_users(
        &self,
        bearer: String,
        query: String,
    ) -> Result<Vec<FfiUserSearchResult>, CwError> {
        let results = self.client.search_users(&bearer, &query).await?;
        Ok(results
            .into_iter()
            .map(|user| FfiUserSearchResult {
                user_id: user.user_id,
                callsign: user.callsign,
                display_name: user.display_name,
            })
            .collect())
    }

    /// Send a friend request to a user. The caller should re-sync afterwards to
    /// reflect the new outgoing pending request.
    pub async fn send_request(&self, bearer: String, to_user_id: String) -> Result<(), CwError> {
        self.client.send_request(&bearer, &to_user_id).await?;
        Ok(())
    }

    /// Accept a friend invite link by its token.
    pub async fn send_request_with_invite(
        &self,
        bearer: String,
        invite_token: String,
    ) -> Result<(), CwError> {
        self.client.send_request_with_invite(&bearer, &invite_token).await?;
        Ok(())
    }

    /// Accept an incoming pending request.
    pub async fn accept_request(&self, bearer: String, request_id: String) -> Result<(), CwError> {
        self.client.accept_request(&bearer, &request_id).await?;
        Ok(())
    }

    /// Decline an incoming pending request.
    pub async fn decline_request(&self, bearer: String, request_id: String) -> Result<(), CwError> {
        self.client.decline_request(&bearer, &request_id).await?;
        Ok(())
    }

    /// Remove an accepted friend by friendship id.
    pub async fn remove_friend(&self, bearer: String, friendship_id: String) -> Result<(), CwError> {
        self.client.remove_friend(&bearer, &friendship_id).await?;
        Ok(())
    }

    /// Validate which of `callsigns` are registered users (suggestion candidates).
    pub async fn get_suggestions(
        &self,
        bearer: String,
        callsigns: Vec<String>,
    ) -> Result<Vec<FfiFriendSuggestion>, CwError> {
        let suggestions = self.client.get_suggestions(&bearer, callsigns).await?;
        Ok(suggestions
            .into_iter()
            .map(|sugg| FfiFriendSuggestion { user_id: sugg.user_id, callsign: sugg.callsign })
            .collect())
    }

    /// Generate a fresh shareable friend-invite link.
    pub async fn get_invite_link(&self, bearer: String) -> Result<FfiInviteLink, CwError> {
        let invite = self.client.get_invite_link(&bearer).await?;
        Ok(FfiInviteLink {
            token: invite.token,
            url: invite.url,
            expires_at: invite.expires_at.timestamp(),
        })
    }

    /// Fetch a page of the friends activity feed. Not persisted. `filter` is the
    /// server filter string (`"friends"` or `"club:<uuid>"`); `before` is an RFC
    /// 3339 cursor from a prior page's `next_cursor`.
    pub async fn fetch_feed(
        &self,
        bearer: String,
        filter: Option<String>,
        before: Option<String>,
        limit: i64,
    ) -> Result<FfiFeedPage, CwError> {
        let page =
            self.client.get_feed(&bearer, filter.as_deref(), before.as_deref(), limit).await?;
        Ok(feed_page_from_wire(page))
    }

    /// Report one of the operator's own activities to the feed. `details_json` is
    /// the opaque payload carried through verbatim.
    pub async fn report_activity(
        &self,
        bearer: String,
        activity_type: String,
        timestamp: i64,
        details_json: String,
    ) -> Result<(), CwError> {
        let details: serde_json::Value =
            serde_json::from_str(&details_json).map_err(|err| CwError::Network {
                reason: format!("invalid activity details JSON: {err}"),
            })?;
        let when = chrono::DateTime::from_timestamp(timestamp, 0).unwrap_or_else(chrono::Utc::now);
        self.client.report_activity(&bearer, &activity_type, when, details).await?;
        Ok(())
    }

    /// Retract a previously reported activity by id.
    pub async fn delete_activity(&self, bearer: String, activity_id: String) -> Result<(), CwError> {
        self.client.delete_activity(&bearer, &activity_id).await?;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// Mapping helpers
// ---------------------------------------------------------------------------

fn feed_page_from_wire(page: FeedResponseWire) -> FfiFeedPage {
    FfiFeedPage {
        items: page
            .items
            .into_iter()
            .map(|item| FfiFeedItem {
                id: item.id,
                callsign: item.callsign,
                user_id: item.user_id,
                display_name: item.display_name,
                activity_type: item.activity_type,
                timestamp: item.timestamp.timestamp(),
                details_json: item.details.to_string(),
            })
            .collect(),
        has_more: page.pagination.has_more,
        next_cursor: page.pagination.next_cursor,
    }
}

fn friendship_from_friend(wire: &FriendWire) -> Friendship {
    let accepted = wire.accepted_at.timestamp();
    Friendship {
        friend_user_id: wire.user_id.clone(),
        friend_callsign: wire.callsign.clone(),
        status: STATUS_ACCEPTED.to_string(),
        is_outgoing: false,
        request_id: None,
        friendship_id: Some(wire.friendship_id.clone()),
        requested_at: accepted,
        accepted_at: Some(accepted),
    }
}

// ---------------------------------------------------------------------------
// Store application (extracted so the sync write path is testable without HTTP)
// ---------------------------------------------------------------------------

/// Upsert accepted friends + pending requests (keyed by the other party) and
/// reconcile away anyone no longer returned. For each pending request the *other*
/// party is `from` (incoming) or `to` (outgoing).
fn apply_friends(
    store: &Store,
    friends: &[FriendWire],
    pending: &PendingRequestsWire,
) -> Result<(), cw_store::StoreError> {
    let mut keep = Vec::new();

    for friend in friends {
        store.upsert_friendship(&friendship_from_friend(friend))?;
        keep.push(friend.user_id.clone());
    }

    for req in &pending.incoming {
        store.upsert_friendship(&Friendship {
            friend_user_id: req.from_user_id.clone(),
            friend_callsign: req.from_callsign.clone(),
            status: STATUS_PENDING.to_string(),
            is_outgoing: false,
            request_id: Some(req.id.clone()),
            friendship_id: None,
            requested_at: req.requested_at.timestamp(),
            accepted_at: None,
        })?;
        keep.push(req.from_user_id.clone());
    }

    for req in &pending.outgoing {
        store.upsert_friendship(&Friendship {
            friend_user_id: req.to_user_id.clone(),
            friend_callsign: req.to_callsign.clone(),
            status: STATUS_PENDING.to_string(),
            is_outgoing: true,
            request_id: Some(req.id.clone()),
            friendship_id: None,
            requested_at: req.requested_at.timestamp(),
            accepted_at: None,
        })?;
        keep.push(req.to_user_id.clone());
    }

    store.retain_friendships(&keep)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;
    use cw_net::FriendRequestWire;
    use cw_store::FriendshipFilter;

    fn friend(user_id: &str, callsign: &str) -> FriendWire {
        FriendWire {
            friendship_id: format!("f-{user_id}"),
            callsign: callsign.to_string(),
            user_id: user_id.to_string(),
            accepted_at: chrono::Utc.timestamp_opt(1_700_000_000, 0).unwrap(),
        }
    }

    fn request(id: &str, from_user: &str, from_call: &str, to_user: &str, to_call: &str) -> FriendRequestWire {
        FriendRequestWire {
            id: id.to_string(),
            from_user_id: from_user.to_string(),
            from_callsign: from_call.to_string(),
            to_user_id: to_user.to_string(),
            to_callsign: to_call.to_string(),
            status: "pending".to_string(),
            requested_at: chrono::Utc.timestamp_opt(1_700_000_000, 0).unwrap(),
        }
    }

    #[test]
    fn apply_friends_persists_friends_and_both_request_directions() {
        let store = Store::open_in_memory("k").unwrap();
        let pending = PendingRequestsWire {
            incoming: vec![request("r1", "u-in", "W1AW", "me", "W6JY")],
            outgoing: vec![request("r2", "me", "W6JY", "u-out", "N2XYZ")],
        };
        apply_friends(&store, &[friend("u-f", "K3ABC")], &pending).unwrap();

        assert_eq!(store.friendship_count().unwrap(), 3);
        assert_eq!(store.incoming_request_count().unwrap(), 1);

        // Incoming request stores the *sender* as the other party.
        let incoming = store.fetch_friendship("u-in").unwrap().unwrap();
        assert_eq!(incoming.friend_callsign, "W1AW");
        assert!(!incoming.is_outgoing);
        assert_eq!(incoming.request_id.as_deref(), Some("r1"));

        // Outgoing request stores the *recipient* as the other party.
        let outgoing = store.fetch_friendship("u-out").unwrap().unwrap();
        assert_eq!(outgoing.friend_callsign, "N2XYZ");
        assert!(outgoing.is_outgoing);

        // Accepted friend carries the friendship id.
        let accepted = store.fetch_friendship("u-f").unwrap().unwrap();
        assert_eq!(accepted.status, STATUS_ACCEPTED);
        assert_eq!(accepted.friendship_id.as_deref(), Some("f-u-f"));
    }

    #[test]
    fn apply_friends_reconciles_removed() {
        let store = Store::open_in_memory("k").unwrap();
        let empty = PendingRequestsWire { incoming: vec![], outgoing: vec![] };
        apply_friends(&store, &[friend("u1", "W1AW"), friend("u2", "N2XYZ")], &empty).unwrap();
        assert_eq!(store.friendship_count().unwrap(), 2);

        // Next sync: u2 unfriended, a new incoming request arrives.
        let pending = PendingRequestsWire {
            incoming: vec![request("r9", "u3", "K3ABC", "me", "W6JY")],
            outgoing: vec![],
        };
        apply_friends(&store, &[friend("u1", "W1AW")], &pending).unwrap();

        assert_eq!(store.friendship_count().unwrap(), 2);
        assert!(store.fetch_friendship("u2").unwrap().is_none(), "unfriended row removed");

        let accepted = store
            .fetch_friendships(&FriendshipFilter { status: Some(STATUS_ACCEPTED.into()) }, 10, 0)
            .unwrap();
        assert_eq!(accepted.len(), 1);
        assert_eq!(accepted[0].friend_user_id, "u1");
    }
}
