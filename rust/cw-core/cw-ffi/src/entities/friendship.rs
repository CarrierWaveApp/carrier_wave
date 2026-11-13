//! FFI surface for `Friendship` (mirrors `cw-store`'s `Friendship`).

use crate::{CwError, FieldStore};
use cw_store::{Friendship, FriendshipFilter};

// ---------- DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiFriendship {
    /// The other party's server user id.
    pub friend_user_id: String,
    pub friend_callsign: String,
    /// `"accepted"` or `"pending"`.
    pub status: String,
    /// Pending only: `true` if we sent the request, `false` if incoming.
    pub is_outgoing: bool,
    pub request_id: Option<String>,
    pub friendship_id: Option<String>,
    /// Unix seconds, UTC.
    pub requested_at: i64,
    /// Unix seconds, UTC (accepted rows only).
    pub accepted_at: Option<i64>,
}

impl From<Friendship> for FfiFriendship {
    fn from(x: Friendship) -> Self {
        FfiFriendship {
            friend_user_id: x.friend_user_id,
            friend_callsign: x.friend_callsign,
            status: x.status,
            is_outgoing: x.is_outgoing,
            request_id: x.request_id,
            friendship_id: x.friendship_id,
            requested_at: x.requested_at,
            accepted_at: x.accepted_at,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiFriendshipFilter {
    /// When set, only rows with this status (`"accepted"`/`"pending"`).
    pub status: Option<String>,
}

impl From<FfiFriendshipFilter> for FriendshipFilter {
    fn from(f: FfiFriendshipFilter) -> Self {
        FriendshipFilter { status: f.status }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn friendship_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.friendship_count()?)
    }

    /// Count of incoming pending requests — drives the Friends tab badge.
    pub fn incoming_request_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.incoming_request_count()?)
    }

    pub fn fetch_friendships(
        &self,
        filter: FfiFriendshipFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiFriendship>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_friendships(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiFriendship::from).collect())
    }
}
