//! ClubMember — mirrors `ClubMember.swift` (the SwiftData `@Model`).
//!
//! A membership row keyed by `(club_id, callsign)` — the same natural key the
//! server enforces (`UNIQUE(club_id, callsign)`). The operator-entered
//! [`ClubMember::number`] is **local-only**: server sync touches `role`,
//! `last_seen_at`, `last_grid`, and `is_carrier_wave_user`, never `number`.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use serde::{Deserialize, Serialize};

/// One operator's membership in one club.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ClubMember {
    /// FK to `club.id`.
    pub club_id: String,
    pub callsign: String,
    /// `"member"` or `"admin"`.
    pub role: String,
    /// Unix seconds, UTC. Last time the member was seen active (server-enriched).
    pub last_seen_at: Option<i64>,
    pub last_grid: Option<String>,
    /// Whether this member has a Carrier Wave account (server-enriched).
    pub is_carrier_wave_user: bool,
    /// Operator-entered member number within this club (e.g. SKCC #12345).
    /// **Local-only** — never overwritten by server sync.
    pub number: Option<String>,
}

impl ClubMember {
    /// Build a member row carrying only the fields a server sync provides
    /// (`number` left `None`). Convenience for sync paths and tests.
    pub fn server_member(club_id: &str, callsign: &str, role: &str) -> Self {
        ClubMember {
            club_id: club_id.to_string(),
            callsign: callsign.to_string(),
            role: role.to_string(),
            last_seen_at: None,
            last_grid: None,
            is_carrier_wave_user: false,
            number: None,
        }
    }
}

/// DDL for `club_member` and its indexes. Registered by the migration runner.
pub(crate) const CLUB_MEMBER_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS club_member (
    club_id              TEXT    NOT NULL,
    callsign             TEXT    NOT NULL,
    role                 TEXT    NOT NULL DEFAULT 'member',
    last_seen_at         INTEGER,            -- unix seconds, UTC
    last_grid            TEXT,
    is_carrier_wave_user INTEGER NOT NULL DEFAULT 0,
    number               TEXT,               -- local-only, preserved across sync
    PRIMARY KEY (club_id, callsign)
);

CREATE INDEX IF NOT EXISTS idx_club_member_callsign ON club_member(callsign);
CREATE INDEX IF NOT EXISTS idx_club_member_club_id  ON club_member(club_id);
"#;

/// Bounded query parameters for `fetch_club_members`.
#[derive(Debug, Clone, Default)]
pub struct ClubMemberFilter {
    pub club_id: Option<String>,
    /// Case-insensitive callsign match.
    pub callsign: Option<String>,
}

impl Store {
    /// Upsert a membership row **from a server sync**: inserts new members and
    /// updates the server-owned fields, but preserves the local-only `number`
    /// on conflict (matches `ClubMember.swift`'s documented contract).
    pub fn upsert_club_member_from_server(&self, member: &ClubMember) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO club_member (
                club_id, callsign, role, last_seen_at, last_grid,
                is_carrier_wave_user, number
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            ON CONFLICT(club_id, callsign) DO UPDATE SET
                role                 = excluded.role,
                last_seen_at         = excluded.last_seen_at,
                last_grid            = excluded.last_grid,
                is_carrier_wave_user = excluded.is_carrier_wave_user
                -- number deliberately NOT updated: local-only.
            "#,
            params![
                member.club_id,
                member.callsign,
                member.role,
                member.last_seen_at,
                member.last_grid,
                member.is_carrier_wave_user as i64,
                member.number,
            ],
        )?;
        Ok(())
    }

    /// Set (or clear) the local-only member number for a `(club_id, callsign)`.
    /// Inserts a bare row if the membership isn't cached yet, so the operator can
    /// record a number before the next sync materializes the member.
    pub fn set_club_member_number(
        &self,
        club_id: &str,
        callsign: &str,
        number: Option<&str>,
    ) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO club_member (club_id, callsign, number)
            VALUES (?1, ?2, ?3)
            ON CONFLICT(club_id, callsign) DO UPDATE SET number = excluded.number
            "#,
            params![club_id, callsign, number],
        )?;
        Ok(())
    }

    /// Ensure a bare `(club_id, callsign)` membership link exists, without
    /// disturbing an existing row. Used by the compact `/v1/clubs/membership`
    /// sync, which knows only callsigns — it must not clobber the `role`,
    /// `last_grid`, etc. that a fuller `/v1/clubs/:id` detail sync provided,
    /// nor the local `number`. New links default to `role = 'member'`.
    pub fn insert_club_member_link(&self, club_id: &str, callsign: &str) -> Result<()> {
        self.conn.execute(
            "INSERT OR IGNORE INTO club_member (club_id, callsign) VALUES (?1, ?2)",
            params![club_id, callsign],
        )?;
        Ok(())
    }

    /// Delete members of `club_id` whose callsign is **not** in `keep_callsigns`
    /// (case-insensitive) — reconciling one club's roster to an authoritative
    /// member list. An empty `keep_callsigns` clears the club's roster.
    pub fn retain_club_members(&self, club_id: &str, keep_callsigns: &[String]) -> Result<()> {
        if keep_callsigns.is_empty() {
            self.conn
                .execute("DELETE FROM club_member WHERE club_id = ?1", params![club_id])?;
            return Ok(());
        }
        let placeholders = vec!["UPPER(?)"; keep_callsigns.len()].join(",");
        let mut args: Vec<&dyn rusqlite::types::ToSql> = Vec::with_capacity(keep_callsigns.len() + 1);
        args.push(&club_id as &dyn rusqlite::types::ToSql);
        for call in keep_callsigns {
            args.push(call as &dyn rusqlite::types::ToSql);
        }
        self.conn.execute(
            &format!(
                "DELETE FROM club_member WHERE club_id = ? AND UPPER(callsign) NOT IN ({placeholders})"
            ),
            args.as_slice(),
        )?;
        Ok(())
    }

    /// Total membership-row count across all clubs.
    pub fn club_member_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM club_member", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch. `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_club_members(
        &self,
        filter: &ClubMemberFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ClubMember>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT club_id, callsign, role, last_seen_at, last_grid, \
                    is_carrier_wave_user, number \
             FROM club_member WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(club_id) = &filter.club_id {
            sql.push_str(" AND club_id = ?");
            args.push(Box::new(club_id.clone()));
        }
        if let Some(callsign) = &filter.callsign {
            sql.push_str(" AND UPPER(callsign) = UPPER(?)");
            args.push(Box::new(callsign.clone()));
        }
        sql.push_str(" ORDER BY callsign ASC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_club_member)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Delete a single membership row. Idempotent.
    pub fn delete_club_member(&self, club_id: &str, callsign: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM club_member WHERE club_id = ?1 AND UPPER(callsign) = UPPER(?2)",
            params![club_id, callsign],
        )?;
        Ok(())
    }

    /// Club names the given callsign belongs to (case-insensitive), name-sorted.
    /// The portable equivalent of `ClubsSyncService.clubs(for:)`.
    pub fn clubs_for_callsign(&self, callsign: &str) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare(
            "SELECT c.name FROM club c \
             JOIN club_member m ON m.club_id = c.id \
             WHERE UPPER(m.callsign) = UPPER(?1) \
             ORDER BY c.name ASC",
        )?;
        let rows = stmt.query_map(params![callsign], |row| row.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Member callsigns in the named club (case-insensitive name match),
    /// callsign-sorted. The portable equivalent of
    /// `ClubsSyncService.callsigns(inClub:)`.
    pub fn callsigns_in_club(&self, club_name: &str) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare(
            "SELECT m.callsign FROM club_member m \
             JOIN club c ON m.club_id = c.id \
             WHERE UPPER(c.name) = UPPER(?1) \
             ORDER BY m.callsign ASC",
        )?;
        let rows = stmt.query_map(params![club_name], |row| row.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_club_member(row: &rusqlite::Row<'_>) -> rusqlite::Result<ClubMember> {
        Ok(ClubMember {
            club_id: row.get(0)?,
            callsign: row.get(1)?,
            role: row.get(2)?,
            last_seen_at: row.get(3)?,
            last_grid: row.get(4)?,
            is_carrier_wave_user: row.get::<_, i64>(5)? != 0,
            number: row.get(6)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::club::tests::sample_club;

    #[test]
    fn server_upsert_preserves_local_number() {
        let store = Store::open_in_memory("k").unwrap();
        // Operator records a number first.
        store.set_club_member_number("c", "W6JY", Some("12345")).unwrap();

        // Server sync arrives (no number, role/grid set). Must not clobber it.
        let mut synced = ClubMember::server_member("c", "W6JY", "admin");
        synced.last_grid = Some("CM87".to_string());
        synced.last_seen_at = Some(1_700_000_000);
        synced.is_carrier_wave_user = true;
        store.upsert_club_member_from_server(&synced).unwrap();

        let rows = store
            .fetch_club_members(
                &ClubMemberFilter { club_id: Some("c".into()), ..Default::default() },
                10,
                0,
            )
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].number.as_deref(), Some("12345"), "local number survives sync");
        assert_eq!(rows[0].role, "admin", "server fields updated");
        assert_eq!(rows[0].last_grid.as_deref(), Some("CM87"));
        assert!(rows[0].is_carrier_wave_user);
    }

    #[test]
    fn set_number_updates_only_number() {
        let store = Store::open_in_memory("k").unwrap();
        let mut member = ClubMember::server_member("c", "W6JY", "member");
        member.last_grid = Some("CM87".to_string());
        store.upsert_club_member_from_server(&member).unwrap();

        store.set_club_member_number("c", "W6JY", Some("999")).unwrap();
        let rows = store
            .fetch_club_members(&ClubMemberFilter { club_id: Some("c".into()), ..Default::default() }, 10, 0)
            .unwrap();
        assert_eq!(rows[0].number.as_deref(), Some("999"));
        assert_eq!(rows[0].last_grid.as_deref(), Some("CM87"), "other fields untouched");

        // Clearing the number works too.
        store.set_club_member_number("c", "W6JY", None).unwrap();
        let rows = store
            .fetch_club_members(&ClubMemberFilter { club_id: Some("c".into()), ..Default::default() }, 10, 0)
            .unwrap();
        assert_eq!(rows[0].number, None);
    }

    #[test]
    fn clubs_for_callsign_joins_and_sorts() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club(&sample_club("c1", "Zeta Club")).unwrap();
        store.upsert_club(&sample_club("c2", "Alpha Club")).unwrap();
        store.upsert_club_member_from_server(&ClubMember::server_member("c1", "W6JY", "member")).unwrap();
        store.upsert_club_member_from_server(&ClubMember::server_member("c2", "w6jy", "member")).unwrap();
        store.upsert_club_member_from_server(&ClubMember::server_member("c1", "N6ABC", "member")).unwrap();

        // Case-insensitive on the queried callsign; name-sorted.
        let clubs = store.clubs_for_callsign("w6jy").unwrap();
        assert_eq!(clubs, vec!["Alpha Club", "Zeta Club"]);

        let none = store.clubs_for_callsign("K7XYZ").unwrap();
        assert!(none.is_empty());
    }

    #[test]
    fn callsigns_in_club_joins_and_sorts() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club(&sample_club("c1", "SKCC")).unwrap();
        store.upsert_club_member_from_server(&ClubMember::server_member("c1", "W6JY", "member")).unwrap();
        store.upsert_club_member_from_server(&ClubMember::server_member("c1", "N6ABC", "admin")).unwrap();

        let calls = store.callsigns_in_club("skcc").unwrap();
        assert_eq!(calls, vec!["N6ABC", "W6JY"]);
    }

    #[test]
    fn delete_member_is_idempotent() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_club_member_from_server(&ClubMember::server_member("c", "W6JY", "member")).unwrap();
        assert_eq!(store.club_member_count().unwrap(), 1);
        store.delete_club_member("c", "w6jy").unwrap();
        assert_eq!(store.club_member_count().unwrap(), 0);
        store.delete_club_member("c", "W6JY").unwrap();
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_club_members(&ClubMemberFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
