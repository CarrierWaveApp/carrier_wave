//! RoveStop — a park stop within a rove (multi-park) activation session.
//!
//! Normalises what iOS stored as a Swift-`JSONEncoder` `[RoveStop]` blob on
//! `logging_session.rove_stops_data` into a structured, portable table. The blob
//! encoded `Date` as a 2001-reference-epoch double with camelCase keys — a
//! Swift-specific format neither Rust nor Android could manipulate. Here stops
//! are their own rows keyed by `logging_session_id`, with Unix-seconds timestamps,
//! so the POTA UTC-midnight split (and Android) can read/rewrite them directly.
//!
//! Mirrors the fields of `RoveStop` in `LoggingSession+Types.swift`
//! (`id`/`parkReference`/`startedAt`/`endedAt`/`myGrid`/`qsoCount`/`notes`), plus
//! the owning-session FK the array form left implicit.

use crate::error::Result;
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use serde::{Deserialize, Serialize};

/// One park stop within a rove activation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RoveStop {
    /// Primary key — UUID string (the Swift `RoveStop.id`).
    pub id: String,
    /// FK to the owning `LoggingSession.id`.
    pub logging_session_id: String,
    pub park_reference: String,
    /// Unix seconds, UTC.
    pub started_at: i64,
    /// Unix seconds, UTC. Nil while the stop is still open.
    pub ended_at: Option<i64>,
    pub my_grid: Option<String>,
    pub qso_count: i64,
    pub notes: Option<String>,
    /// Sync-journal dirty flag.
    pub cloud_dirty_flag: bool,
}

/// DDL for the `rove_stop` table and its supporting indexes.
pub(crate) const ROVE_STOP_DDL: &str = r#"
    CREATE TABLE IF NOT EXISTS rove_stop (
        id                  TEXT PRIMARY KEY NOT NULL,
        logging_session_id  TEXT NOT NULL,
        park_reference      TEXT NOT NULL,
        started_at          INTEGER NOT NULL,   -- unix seconds, UTC
        ended_at            INTEGER,            -- unix seconds, UTC
        my_grid             TEXT,
        qso_count           INTEGER NOT NULL DEFAULT 0,
        notes               TEXT,
        cloud_dirty_flag    INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_rs_logging_session_id ON rove_stop(logging_session_id);
    CREATE INDEX IF NOT EXISTS idx_rs_started_at         ON rove_stop(started_at);
    CREATE INDEX IF NOT EXISTS idx_rs_cloud_dirty_flag   ON rove_stop(cloud_dirty_flag);
"#;

impl Store {
    /// Insert or replace a single `RoveStop` row.
    pub fn upsert_rove_stop(&self, stop: &RoveStop) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO rove_stop (
                id, logging_session_id, park_reference, started_at, ended_at,
                my_grid, qso_count, notes, cloud_dirty_flag
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(id) DO UPDATE SET
                logging_session_id = excluded.logging_session_id,
                park_reference     = excluded.park_reference,
                started_at         = excluded.started_at,
                ended_at           = excluded.ended_at,
                my_grid            = excluded.my_grid,
                qso_count          = excluded.qso_count,
                notes              = excluded.notes,
                cloud_dirty_flag   = excluded.cloud_dirty_flag
            "#,
            params![
                stop.id,
                stop.logging_session_id,
                stop.park_reference,
                stop.started_at,
                stop.ended_at,
                stop.my_grid,
                stop.qso_count,
                stop.notes,
                stop.cloud_dirty_flag as i64,
            ],
        )?;
        Ok(())
    }

    /// Total count of `rove_stop` rows.
    pub fn rove_stop_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM rove_stop", [], |row| row.get(0))?)
    }

    /// The rove stops for a session, chronological (rove stops are inherently
    /// time-ordered — each begins after the previous). `limit` capped at
    /// [`MAX_FETCH_LIMIT`]; a session's stops are a handful.
    pub fn fetch_rove_stops(&self, logging_session_id: &str) -> Result<Vec<RoveStop>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, logging_session_id, park_reference, started_at, ended_at, \
                my_grid, qso_count, notes, cloud_dirty_flag \
             FROM rove_stop WHERE logging_session_id = ?1 ORDER BY started_at ASC LIMIT ?2",
        )?;
        let rows = stmt.query_map(params![logging_session_id, MAX_FETCH_LIMIT], Self::row_to_rove_stop)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Delete every rove stop for a session. Idempotent.
    pub fn delete_rove_stops_for_session(&self, logging_session_id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM rove_stop WHERE logging_session_id = ?1",
            params![logging_session_id],
        )?;
        Ok(())
    }

    /// Replace a session's rove stops wholesale (the structured analogue of the
    /// iOS `roveStops` array setter): delete the session's existing stops, then
    /// insert `stops`. Each stop's `logging_session_id` is forced to `session_id`.
    pub fn replace_rove_stops(&self, logging_session_id: &str, stops: &[RoveStop]) -> Result<()> {
        self.delete_rove_stops_for_session(logging_session_id)?;
        for stop in stops {
            let mut owned = stop.clone();
            owned.logging_session_id = logging_session_id.to_string();
            self.upsert_rove_stop(&owned)?;
        }
        Ok(())
    }

    fn row_to_rove_stop(row: &rusqlite::Row<'_>) -> rusqlite::Result<RoveStop> {
        Ok(RoveStop {
            id: row.get(0)?,
            logging_session_id: row.get(1)?,
            park_reference: row.get(2)?,
            started_at: row.get(3)?,
            ended_at: row.get(4)?,
            my_grid: row.get(5)?,
            qso_count: row.get(6)?,
            notes: row.get(7)?,
            cloud_dirty_flag: row.get::<_, i64>(8)? != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, session: &str, park: &str, started_at: i64) -> RoveStop {
        RoveStop {
            id: id.to_string(),
            logging_session_id: session.to_string(),
            park_reference: park.to_string(),
            started_at,
            ended_at: Some(started_at + 3_600),
            my_grid: Some("CM87".to_string()),
            qso_count: 5,
            notes: None,
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn upsert_fetch_ordered_by_start() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_rove_stop(&sample("b", "s1", "US-2", 2_000)).unwrap();
        store.upsert_rove_stop(&sample("a", "s1", "US-1", 1_000)).unwrap();
        store.upsert_rove_stop(&sample("c", "s2", "US-9", 500)).unwrap();

        let stops = store.fetch_rove_stops("s1").unwrap();
        assert_eq!(stops.iter().map(|s| s.id.clone()).collect::<Vec<_>>(), vec!["a", "b"]);
        assert_eq!(stops[0].park_reference, "US-1"); // chronological
        assert_eq!(store.rove_stop_count().unwrap(), 3);
    }

    #[test]
    fn upsert_replaces_by_id() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_rove_stop(&sample("a", "s1", "US-1", 1_000)).unwrap();
        let mut edited = sample("a", "s1", "US-1", 1_000);
        edited.qso_count = 42;
        edited.cloud_dirty_flag = true;
        store.upsert_rove_stop(&edited).unwrap();
        let stops = store.fetch_rove_stops("s1").unwrap();
        assert_eq!(stops.len(), 1);
        assert_eq!(stops[0].qso_count, 42);
        assert!(stops[0].cloud_dirty_flag);
    }

    #[test]
    fn delete_for_session_scoped() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_rove_stop(&sample("a", "s1", "US-1", 1_000)).unwrap();
        store.upsert_rove_stop(&sample("c", "s2", "US-9", 500)).unwrap();
        store.delete_rove_stops_for_session("s1").unwrap();
        assert!(store.fetch_rove_stops("s1").unwrap().is_empty());
        assert_eq!(store.fetch_rove_stops("s2").unwrap().len(), 1); // other session intact
    }

    #[test]
    fn replace_swaps_the_whole_set_and_forces_session_fk() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_rove_stop(&sample("old", "s1", "US-1", 1_000)).unwrap();
        // Replacement stops carry a different session id — replace must rebind them.
        let replacement = vec![
            sample("n1", "other", "US-3", 3_000),
            sample("n2", "other", "US-4", 4_000),
        ];
        store.replace_rove_stops("s1", &replacement).unwrap();
        let stops = store.fetch_rove_stops("s1").unwrap();
        assert_eq!(stops.iter().map(|s| s.id.clone()).collect::<Vec<_>>(), vec!["n1", "n2"]);
        assert!(stops.iter().all(|s| s.logging_session_id == "s1")); // rebound
        assert!(store.fetch_rove_stops("old").unwrap().is_empty());
    }

    #[test]
    fn optional_fields_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let mut open_stop = sample("open", "s1", "US-1", 1_000);
        open_stop.ended_at = None; // still-open stop
        open_stop.my_grid = None;
        open_stop.notes = Some("windy".to_string());
        store.upsert_rove_stop(&open_stop).unwrap();
        let fetched = store.fetch_rove_stops("s1").unwrap().pop().unwrap();
        assert_eq!(fetched.ended_at, None);
        assert_eq!(fetched.my_grid, None);
        assert_eq!(fetched.notes.as_deref(), Some("windy"));
    }
}
