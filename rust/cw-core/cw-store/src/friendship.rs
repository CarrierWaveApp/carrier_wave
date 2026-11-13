//! Friendship — mirrors `Friendship.swift` (the iOS SwiftData `@Model`).
//!
//! Local cache of the operator's social graph as served by `/v1/friends` and
//! `/v1/friends/requests/pending`. One row per *other party*, keyed by their
//! user id. The four UI states iOS encodes as `status × isOutgoing`:
//!
//! - accepted friend       → `status = "accepted"`
//! - outgoing pending       → `status = "pending"`, `is_outgoing = true`
//! - incoming pending       → `status = "pending"`, `is_outgoing = false`
//! - declined               → not stored (reconciled away)
//!
//! A plain value type; the FFI exposes this, not a live row. The activity feed
//! is *not* persisted (presentation-only, fetched on demand — same choice as the
//! club activity feed).

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// Status string for an accepted friendship.
pub const STATUS_ACCEPTED: &str = "accepted";
/// Status string for a pending friend request (either direction).
pub const STATUS_PENDING: &str = "pending";

/// A friendship or pending friend request with another operator. Field names
/// port the stored properties of the SwiftData `Friendship` model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Friendship {
    /// Primary key — the *other* user's server UUID, stringified.
    pub friend_user_id: String,
    pub friend_callsign: String,
    /// [`STATUS_ACCEPTED`] or [`STATUS_PENDING`].
    pub status: String,
    /// For a pending request: `true` if we sent it, `false` if it's incoming.
    /// Irrelevant (stored `false`) for accepted friendships.
    pub is_outgoing: bool,
    /// The friend-request UUID — present for pending rows, used to accept/decline.
    pub request_id: Option<String>,
    /// The friendship UUID — present for accepted rows, used to remove.
    pub friendship_id: Option<String>,
    /// Unix seconds, UTC. When the request was first made.
    pub requested_at: i64,
    /// Unix seconds, UTC. When the friendship was accepted (accepted rows only).
    pub accepted_at: Option<i64>,
}

/// DDL for `friendship` and its index. Registered by the migration runner.
pub(crate) const FRIENDSHIP_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS friendship (
    friend_user_id   TEXT    PRIMARY KEY NOT NULL,
    friend_callsign  TEXT    NOT NULL,
    status           TEXT    NOT NULL,
    is_outgoing      INTEGER NOT NULL DEFAULT 0,
    request_id       TEXT,
    friendship_id    TEXT,
    requested_at     INTEGER NOT NULL,   -- unix seconds, UTC
    accepted_at      INTEGER
);

CREATE INDEX IF NOT EXISTS idx_friendship_callsign ON friendship(friend_callsign);
CREATE INDEX IF NOT EXISTS idx_friendship_status ON friendship(status);
"#;

/// Bounded query parameters for `fetch_friendships`.
#[derive(Debug, Clone, Default)]
pub struct FriendshipFilter {
    /// When set, only rows with this status ([`STATUS_ACCEPTED`]/[`STATUS_PENDING`]).
    pub status: Option<String>,
}

impl Store {
    /// Insert or replace a `friendship` row (keyed by the other party's user id).
    pub fn upsert_friendship(&self, friendship: &Friendship) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO friendship (
                friend_user_id, friend_callsign, status, is_outgoing,
                request_id, friendship_id, requested_at, accepted_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            ON CONFLICT(friend_user_id) DO UPDATE SET
                friend_callsign = excluded.friend_callsign,
                status          = excluded.status,
                is_outgoing     = excluded.is_outgoing,
                request_id      = excluded.request_id,
                friendship_id   = excluded.friendship_id,
                requested_at    = excluded.requested_at,
                accepted_at     = excluded.accepted_at
            "#,
            params![
                friendship.friend_user_id,
                friendship.friend_callsign,
                friendship.status,
                friendship.is_outgoing as i64,
                friendship.request_id,
                friendship.friendship_id,
                friendship.requested_at,
                friendship.accepted_at,
            ],
        )?;
        Ok(())
    }

    /// Total friendship/request row count.
    pub fn friendship_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM friendship", [], |row| row.get(0))?)
    }

    /// Count of incoming pending requests — drives the Friends tab badge.
    pub fn incoming_request_count(&self) -> Result<i64> {
        Ok(self.conn.query_row(
            "SELECT COUNT(*) FROM friendship WHERE status = ?1 AND is_outgoing = 0",
            params![STATUS_PENDING],
            |row| row.get(0),
        )?)
    }

    /// Bounded, paginated fetch ordered by callsign. `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_friendships(
        &self,
        filter: &FriendshipFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Friendship>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT friend_user_id, friend_callsign, status, is_outgoing, \
                    request_id, friendship_id, requested_at, accepted_at \
             FROM friendship WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(status) = &filter.status {
            sql.push_str(" AND status = ?");
            args.push(Box::new(status.clone()));
        }
        sql.push_str(" ORDER BY friend_callsign ASC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_friendship)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single friendship by the other party's user id. `None` if absent.
    pub fn fetch_friendship(&self, friend_user_id: &str) -> Result<Option<Friendship>> {
        let mut stmt = self.conn.prepare(
            "SELECT friend_user_id, friend_callsign, status, is_outgoing, \
                    request_id, friendship_id, requested_at, accepted_at \
             FROM friendship WHERE friend_user_id = ?1",
        )?;
        Ok(stmt.query_row(params![friend_user_id], Self::row_to_friendship).optional()?)
    }

    /// Delete every friendship whose `friend_user_id` is **not** in `keep_ids` —
    /// reconciling the local cache to the authoritative server set after a full
    /// friends+requests sync. An empty `keep_ids` clears all rows.
    pub fn retain_friendships(&self, keep_ids: &[String]) -> Result<()> {
        if keep_ids.is_empty() {
            self.conn.execute("DELETE FROM friendship", [])?;
            return Ok(());
        }
        let placeholders = vec!["?"; keep_ids.len()].join(",");
        let args: Vec<&dyn rusqlite::types::ToSql> =
            keep_ids.iter().map(|id| id as &dyn rusqlite::types::ToSql).collect();
        self.conn.execute(
            &format!("DELETE FROM friendship WHERE friend_user_id NOT IN ({placeholders})"),
            args.as_slice(),
        )?;
        Ok(())
    }

    /// Delete a single `friendship` row. Idempotent.
    pub fn delete_friendship(&self, friend_user_id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM friendship WHERE friend_user_id = ?1", params![friend_user_id])?;
        Ok(())
    }

    fn row_to_friendship(row: &rusqlite::Row<'_>) -> rusqlite::Result<Friendship> {
        Ok(Friendship {
            friend_user_id: row.get(0)?,
            friend_callsign: row.get(1)?,
            status: row.get(2)?,
            is_outgoing: row.get::<_, i64>(3)? != 0,
            request_id: row.get(4)?,
            friendship_id: row.get(5)?,
            requested_at: row.get(6)?,
            accepted_at: row.get(7)?,
        })
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) fn accepted(user_id: &str, callsign: &str) -> Friendship {
        Friendship {
            friend_user_id: user_id.to_string(),
            friend_callsign: callsign.to_string(),
            status: STATUS_ACCEPTED.to_string(),
            is_outgoing: false,
            request_id: None,
            friendship_id: Some(format!("f-{user_id}")),
            requested_at: 1_700_000_000,
            accepted_at: Some(1_700_000_100),
        }
    }

    pub(crate) fn incoming(user_id: &str, callsign: &str) -> Friendship {
        Friendship {
            friend_user_id: user_id.to_string(),
            friend_callsign: callsign.to_string(),
            status: STATUS_PENDING.to_string(),
            is_outgoing: false,
            request_id: Some(format!("r-{user_id}")),
            friendship_id: None,
            requested_at: 1_700_000_000,
            accepted_at: None,
        }
    }

    #[test]
    fn upsert_and_fetch_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_friendship(&accepted("u1", "W1AW")).unwrap();
        let fetched = store.fetch_friendship("u1").unwrap().expect("exists");
        assert_eq!(fetched.friend_callsign, "W1AW");
        assert_eq!(fetched.status, STATUS_ACCEPTED);
        assert_eq!(fetched.friendship_id.as_deref(), Some("f-u1"));
    }

    #[test]
    fn upsert_replaces_status() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_friendship(&incoming("u1", "W1AW")).unwrap();
        // The same person's request is accepted → status flips, request becomes friendship.
        store.upsert_friendship(&accepted("u1", "W1AW")).unwrap();
        assert_eq!(store.friendship_count().unwrap(), 1);
        let fetched = store.fetch_friendship("u1").unwrap().unwrap();
        assert_eq!(fetched.status, STATUS_ACCEPTED);
    }

    #[test]
    fn incoming_request_count_excludes_outgoing_and_accepted() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_friendship(&accepted("u1", "W1AW")).unwrap();
        store.upsert_friendship(&incoming("u2", "N2XYZ")).unwrap();
        let mut outgoing = incoming("u3", "K3ABC");
        outgoing.is_outgoing = true;
        store.upsert_friendship(&outgoing).unwrap();

        assert_eq!(store.incoming_request_count().unwrap(), 1);
    }

    #[test]
    fn fetch_filters_by_status() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_friendship(&accepted("u1", "W1AW")).unwrap();
        store.upsert_friendship(&incoming("u2", "N2XYZ")).unwrap();

        let friends = store
            .fetch_friendships(
                &FriendshipFilter { status: Some(STATUS_ACCEPTED.into()) },
                10,
                0,
            )
            .unwrap();
        assert_eq!(friends.len(), 1);
        assert_eq!(friends[0].friend_user_id, "u1");
    }

    #[test]
    fn retain_reconciles_removed() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_friendship(&accepted("u1", "W1AW")).unwrap();
        store.upsert_friendship(&accepted("u2", "N2XYZ")).unwrap();
        assert_eq!(store.friendship_count().unwrap(), 2);

        // u2 removed.
        store.retain_friendships(&["u1".to_string()]).unwrap();
        assert_eq!(store.friendship_count().unwrap(), 1);
        assert!(store.fetch_friendship("u2").unwrap().is_none());

        // Empty keep clears all.
        store.retain_friendships(&[]).unwrap();
        assert_eq!(store.friendship_count().unwrap(), 0);
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_friendships(&FriendshipFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
