//! Club — mirrors `Club.swift` (the SwiftData `@Model`).
//!
//! Cache of the user's amateur-radio clubs as served by `/v1/clubs`. A plain
//! value type; the FFI exposes this, not a live row. Membership rows live in
//! [`crate::club_member`].

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// A club the operator belongs to. Field names port the stored properties of
/// the SwiftData `Club` model; computed helpers (`memberCount`, `isMember`) are
/// expressed as store queries instead.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Club {
    /// Primary key. The server's club UUID, stringified (lowercase hyphenated).
    /// Mirrors `Club.serverId`.
    pub id: String,
    pub name: String,
    pub callsign: Option<String>,
    /// Mirrors `Club.clubDescription`.
    pub description: Option<String>,
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
    pub has_logo: bool,
    /// Server-provided member count — avoids a `COUNT(*)` join just to render a
    /// list row (mirrors `Club.cachedMemberCount`).
    pub cached_member_count: i64,
    /// Unix seconds, UTC. When this club row was last refreshed from the server.
    pub last_synced_at: i64,
}

/// DDL for `club` and its index. Registered by the migration runner.
pub(crate) const CLUB_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS club (
    id                   TEXT    PRIMARY KEY NOT NULL,
    name                 TEXT    NOT NULL,
    callsign             TEXT,
    description          TEXT,
    notes_url            TEXT,
    notes_title          TEXT,
    has_logo             INTEGER NOT NULL DEFAULT 0,
    cached_member_count  INTEGER NOT NULL DEFAULT 0,
    last_synced_at       INTEGER NOT NULL    -- unix seconds, UTC
);

CREATE INDEX IF NOT EXISTS idx_club_name ON club(name);
"#;

/// Bounded query parameters for `fetch_clubs`.
#[derive(Debug, Clone, Default)]
pub struct ClubFilter {
    /// When set, only clubs the given callsign is a member of (case-insensitive).
    pub callsign_member: Option<String>,
}

impl Store {
    /// Insert or replace a `club` row.
    pub fn upsert_club(&self, club: &Club) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO club (
                id, name, callsign, description, notes_url, notes_title,
                has_logo, cached_member_count, last_synced_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(id) DO UPDATE SET
                name                = excluded.name,
                callsign            = excluded.callsign,
                description         = excluded.description,
                notes_url           = excluded.notes_url,
                notes_title         = excluded.notes_title,
                has_logo            = excluded.has_logo,
                cached_member_count = excluded.cached_member_count,
                last_synced_at      = excluded.last_synced_at
            "#,
            params![
                club.id,
                club.name,
                club.callsign,
                club.description,
                club.notes_url,
                club.notes_title,
                club.has_logo as i64,
                club.cached_member_count,
                club.last_synced_at,
            ],
        )?;
        Ok(())
    }

    /// Total club count.
    pub fn club_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM club", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch ordered by name. `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_clubs(&self, filter: &ClubFilter, limit: i64, offset: i64) -> Result<Vec<Club>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT id, name, callsign, description, notes_url, notes_title, \
                    has_logo, cached_member_count, last_synced_at \
             FROM club WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(callsign) = &filter.callsign_member {
            sql.push_str(
                " AND EXISTS (SELECT 1 FROM club_member m \
                  WHERE m.club_id = club.id AND UPPER(m.callsign) = UPPER(?))",
            );
            args.push(Box::new(callsign.clone()));
        }
        sql.push_str(" ORDER BY name ASC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_club)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single club by primary key. Returns `None` if not found.
    pub fn fetch_club(&self, id: &str) -> Result<Option<Club>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, name, callsign, description, notes_url, notes_title, \
                    has_logo, cached_member_count, last_synced_at \
             FROM club WHERE id = ?1",
        )?;
        Ok(stmt.query_row(params![id], Self::row_to_club).optional()?)
    }

    /// Delete every club (and its members) whose id is **not** in `keep_ids` —
    /// reconciling the local cache to the authoritative server list after a
    /// full `/v1/clubs` sync (the operator left any club no longer returned).
    /// An empty `keep_ids` clears all clubs.
    pub fn retain_clubs(&self, keep_ids: &[String]) -> Result<()> {
        if keep_ids.is_empty() {
            self.conn.execute("DELETE FROM club_member", [])?;
            self.conn.execute("DELETE FROM club", [])?;
            return Ok(());
        }
        let placeholders = vec!["?"; keep_ids.len()].join(",");
        let args: Vec<&dyn rusqlite::types::ToSql> =
            keep_ids.iter().map(|id| id as &dyn rusqlite::types::ToSql).collect();
        self.conn.execute(
            &format!("DELETE FROM club_member WHERE club_id NOT IN ({placeholders})"),
            args.as_slice(),
        )?;
        self.conn.execute(
            &format!("DELETE FROM club WHERE id NOT IN ({placeholders})"),
            args.as_slice(),
        )?;
        Ok(())
    }

    /// Delete a `club` row and all of its members. Idempotent.
    pub fn delete_club(&self, id: &str) -> Result<()> {
        // No ON DELETE CASCADE FK (club_member has no FK constraint), so clear
        // the members explicitly to avoid orphans.
        self.conn
            .execute("DELETE FROM club_member WHERE club_id = ?1", params![id])?;
        self.conn.execute("DELETE FROM club WHERE id = ?1", params![id])?;
        Ok(())
    }

    fn row_to_club(row: &rusqlite::Row<'_>) -> rusqlite::Result<Club> {
        Ok(Club {
            id: row.get(0)?,
            name: row.get(1)?,
            callsign: row.get(2)?,
            description: row.get(3)?,
            notes_url: row.get(4)?,
            notes_title: row.get(5)?,
            has_logo: row.get::<_, i64>(6)? != 0,
            cached_member_count: row.get(7)?,
            last_synced_at: row.get(8)?,
        })
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::club_member::ClubMember;

    pub(crate) fn sample_club(id: &str, name: &str) -> Club {
        Club {
            id: id.to_string(),
            name: name.to_string(),
            callsign: Some("W1AW".to_string()),
            description: Some("A radio club".to_string()),
            notes_url: None,
            notes_title: None,
            has_logo: false,
            cached_member_count: 0,
            last_synced_at: 1_700_000_000,
        }
    }

    #[test]
    fn upsert_and_fetch_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();
        let mut club = sample_club("club-1", "SKCC");
        club.has_logo = true;
        club.cached_member_count = 42;
        store.upsert_club(&club).unwrap();

        let fetched = store.fetch_club("club-1").unwrap().expect("club exists");
        assert_eq!(fetched.name, "SKCC");
        assert!(fetched.has_logo);
        assert_eq!(fetched.cached_member_count, 42);
        assert_eq!(fetched.callsign.as_deref(), Some("W1AW"));
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club(&sample_club("c", "Old Name")).unwrap();
        let mut updated = sample_club("c", "New Name");
        updated.cached_member_count = 7;
        store.upsert_club(&updated).unwrap();

        assert_eq!(store.club_count().unwrap(), 1);
        let fetched = store.fetch_club("c").unwrap().unwrap();
        assert_eq!(fetched.name, "New Name");
        assert_eq!(fetched.cached_member_count, 7);
    }

    #[test]
    fn fetch_orders_by_name() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club(&sample_club("b", "Zeta")).unwrap();
        store.upsert_club(&sample_club("a", "Alpha")).unwrap();
        let clubs = store.fetch_clubs(&ClubFilter::default(), 10, 0).unwrap();
        assert_eq!(clubs.len(), 2);
        assert_eq!(clubs[0].name, "Alpha");
        assert_eq!(clubs[1].name, "Zeta");
    }

    #[test]
    fn filter_by_callsign_member() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club(&sample_club("c1", "Has W6JY")).unwrap();
        store.upsert_club(&sample_club("c2", "No W6JY")).unwrap();
        store
            .upsert_club_member_from_server(&ClubMember::server_member("c1", "w6jy", "member"))
            .unwrap();

        let mine = store
            .fetch_clubs(
                &ClubFilter { callsign_member: Some("W6JY".to_string()) },
                10,
                0,
            )
            .unwrap();
        assert_eq!(mine.len(), 1);
        assert_eq!(mine[0].id, "c1");
    }

    #[test]
    fn delete_cascades_members() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club(&sample_club("c", "Club")).unwrap();
        store
            .upsert_club_member_from_server(&ClubMember::server_member("c", "W6JY", "member"))
            .unwrap();
        assert_eq!(store.club_member_count().unwrap(), 1);

        store.delete_club("c").unwrap();
        assert_eq!(store.club_count().unwrap(), 0);
        assert_eq!(store.club_member_count().unwrap(), 0, "members removed with the club");
        // Idempotent.
        store.delete_club("c").unwrap();
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_clubs(&ClubFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
