//! The SessionSpot entity + its bounded query API.
//! Mirrors CarrierWaveData/Models/SessionSpot.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// A spot received during an active logging session.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionSpot {
    pub id: String,
    /// FK to the owning `LoggingSession.id` (stored as UUID string).
    pub logging_session_id: String,
    pub callsign: String,
    pub frequency_k_hz: f64,
    pub mode: String,
    /// Unix seconds, UTC.
    pub timestamp: i64,
    pub source: String,
    pub snr: Option<i64>,
    pub wpm: Option<i64>,
    pub spotter: Option<String>,
    pub spotter_grid: Option<String>,
    pub park_ref: Option<String>,
    pub park_name: Option<String>,
    pub comments: Option<String>,
    pub region: String,
    pub distance_meters: Option<f64>,
    pub bearing_degrees: Option<f64>,
    /// Whether this row has un-synced local changes (sync journal flag).
    pub cloud_dirty_flag: bool,
}

/// DDL for the `session_spot` table and its supporting indexes.
pub(crate) const SESSION_SPOT_DDL: &str = r#"
    CREATE TABLE IF NOT EXISTS session_spot (
        id                  TEXT PRIMARY KEY NOT NULL,
        logging_session_id  TEXT NOT NULL,
        callsign            TEXT NOT NULL,
        frequency_k_hz      REAL NOT NULL,
        mode                TEXT NOT NULL,
        timestamp           INTEGER NOT NULL,
        source              TEXT NOT NULL,
        snr                 INTEGER,
        wpm                 INTEGER,
        spotter             TEXT,
        spotter_grid        TEXT,
        park_ref            TEXT,
        park_name           TEXT,
        comments            TEXT,
        region              TEXT NOT NULL,
        distance_meters     REAL,
        bearing_degrees     REAL,
        cloud_dirty_flag    INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_ss_logging_session_id ON session_spot(logging_session_id);
    CREATE INDEX IF NOT EXISTS idx_ss_timestamp         ON session_spot(timestamp);
    CREATE INDEX IF NOT EXISTS idx_ss_cloud_dirty_flag  ON session_spot(cloud_dirty_flag);
    CREATE INDEX IF NOT EXISTS idx_ss_callsign          ON session_spot(callsign);
    CREATE INDEX IF NOT EXISTS idx_ss_source            ON session_spot(source);
"#;

/// Bounded query parameters for `session_spot`.
#[derive(Debug, Clone, Default)]
pub struct SessionSpotFilter {
    pub logging_session_id: Option<String>,
    /// Only spots at/after this unix-seconds timestamp.
    pub since: Option<i64>,
    /// When `true`, restrict to rows with `cloud_dirty_flag` set — the outbound
    /// sync pass's "records with un-synced local changes" set.
    pub dirty_only: bool,
}

impl Store {
    /// Insert or replace a `SessionSpot` record.
    pub fn upsert_session_spot(&self, spot: &SessionSpot) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO session_spot (
                id, logging_session_id, callsign, frequency_k_hz, mode, timestamp, source,
                snr, wpm, spotter, spotter_grid, park_ref, park_name, comments,
                region, distance_meters, bearing_degrees, cloud_dirty_flag
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
            ON CONFLICT(id) DO UPDATE SET
                logging_session_id=excluded.logging_session_id,
                callsign=excluded.callsign,
                frequency_k_hz=excluded.frequency_k_hz,
                mode=excluded.mode,
                timestamp=excluded.timestamp,
                source=excluded.source,
                snr=excluded.snr,
                wpm=excluded.wpm,
                spotter=excluded.spotter,
                spotter_grid=excluded.spotter_grid,
                park_ref=excluded.park_ref,
                park_name=excluded.park_name,
                comments=excluded.comments,
                region=excluded.region,
                distance_meters=excluded.distance_meters,
                bearing_degrees=excluded.bearing_degrees,
                cloud_dirty_flag=excluded.cloud_dirty_flag
            "#,
            params![
                spot.id,
                spot.logging_session_id,
                spot.callsign,
                spot.frequency_k_hz,
                spot.mode,
                spot.timestamp,
                spot.source,
                spot.snr,
                spot.wpm,
                spot.spotter,
                spot.spotter_grid,
                spot.park_ref,
                spot.park_name,
                spot.comments,
                spot.region,
                spot.distance_meters,
                spot.bearing_degrees,
                spot.cloud_dirty_flag as i64,
            ],
        )?;
        Ok(())
    }

    /// Total count of `session_spot` rows.
    pub fn session_spot_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM session_spot", [], |row| row.get(0))?)
    }

    /// Fetch a single `SessionSpot` by `id`, or `None` if absent.
    /// Delete a `session_spot` row by id. Idempotent — a missing id succeeds.
    pub fn delete_session_spot(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM session_spot WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_session_spot(&self, id: &str) -> Result<Option<SessionSpot>> {
        let sql = "SELECT id, logging_session_id, callsign, frequency_k_hz, mode, timestamp, \
            source, snr, wpm, spotter, spotter_grid, park_ref, park_name, comments, \
            region, distance_meters, bearing_degrees, cloud_dirty_flag \
            FROM session_spot WHERE id = ?";
        Ok(self
            .conn
            .query_row(sql, params![id], Self::row_to_session_spot)
            .optional()?)
    }

    /// Bounded, paginated fetch with optional filters.
    /// `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_session_spots(
        &self,
        filter: &SessionSpotFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<SessionSpot>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded {
                requested: limit,
                max: MAX_FETCH_LIMIT,
            });
        }

        let mut sql = String::from(
            "SELECT id, logging_session_id, callsign, frequency_k_hz, mode, timestamp, \
            source, snr, wpm, spotter, spotter_grid, park_ref, park_name, comments, \
            region, distance_meters, bearing_degrees, cloud_dirty_flag \
            FROM session_spot WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(session_id) = &filter.logging_session_id {
            sql.push_str(" AND logging_session_id = ?");
            args.push(Box::new(session_id.clone()));
        }
        if let Some(since) = filter.since {
            sql.push_str(" AND timestamp >= ?");
            args.push(Box::new(since));
        }
        if filter.dirty_only {
            sql.push_str(" AND cloud_dirty_flag = 1");
        }
        sql.push_str(" ORDER BY timestamp DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_session_spot)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_session_spot(row: &rusqlite::Row<'_>) -> rusqlite::Result<SessionSpot> {
        Ok(SessionSpot {
            id: row.get(0)?,
            logging_session_id: row.get(1)?,
            callsign: row.get(2)?,
            frequency_k_hz: row.get(3)?,
            mode: row.get(4)?,
            timestamp: row.get(5)?,
            source: row.get(6)?,
            snr: row.get(7)?,
            wpm: row.get(8)?,
            spotter: row.get(9)?,
            spotter_grid: row.get(10)?,
            park_ref: row.get(11)?,
            park_name: row.get(12)?,
            comments: row.get(13)?,
            region: row.get(14)?,
            distance_meters: row.get(15)?,
            bearing_degrees: row.get(16)?,
            cloud_dirty_flag: row.get::<_, i64>(17)? != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, session_id: &str, callsign: &str, when: i64) -> SessionSpot {
        SessionSpot {
            id: id.to_string(),
            logging_session_id: session_id.to_string(),
            callsign: callsign.to_string(),
            frequency_k_hz: 14_074.0,
            mode: "FT8".to_string(),
            timestamp: when,
            source: "pota".to_string(),
            snr: Some(-10),
            wpm: None,
            spotter: Some("W1AW".to_string()),
            spotter_grid: Some("FN31".to_string()),
            park_ref: Some("K-1234".to_string()),
            park_name: Some("Test Park".to_string()),
            comments: None,
            region: "North America".to_string(),
            distance_meters: Some(1_500.0),
            bearing_degrees: Some(45.0),
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn upsert_count_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_session_spot(&sample("s1", "sess-a", "W1AW", 1000))
            .unwrap();
        store
            .upsert_session_spot(&sample("s2", "sess-a", "K2ABC", 2000))
            .unwrap();
        store
            .upsert_session_spot(&sample("s3", "sess-b", "W6JY", 3000))
            .unwrap();
        assert_eq!(store.session_spot_count().unwrap(), 3);

        let spot = store.fetch_session_spot("s1").unwrap().unwrap();
        assert_eq!(spot.callsign, "W1AW");
        assert_eq!(spot.snr, Some(-10));
    }

    #[test]
    fn fetch_by_session() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_session_spot(&sample("s1", "sess-a", "W1AW", 1000))
            .unwrap();
        store
            .upsert_session_spot(&sample("s2", "sess-a", "K2ABC", 2000))
            .unwrap();
        store
            .upsert_session_spot(&sample("s3", "sess-b", "W6JY", 3000))
            .unwrap();

        let filter = SessionSpotFilter {
            logging_session_id: Some("sess-a".into()),
            since: None,
            dirty_only: false,
        };
        let rows = store.fetch_session_spots(&filter, 100, 0).unwrap();
        assert_eq!(rows.len(), 2);
        // Newest first.
        assert_eq!(rows[0].id, "s2");
    }

    #[test]
    fn fetch_since_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_session_spot(&sample("s1", "sess-a", "W1AW", 1000))
            .unwrap();
        store
            .upsert_session_spot(&sample("s2", "sess-a", "K2ABC", 2000))
            .unwrap();

        let filter = SessionSpotFilter {
            logging_session_id: None,
            since: Some(1500),
            dirty_only: false,
        };
        let rows = store.fetch_session_spots(&filter, 100, 0).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "s2");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_session_spot(&sample("s1", "sess-a", "W1AW", 1000))
            .unwrap();
        let mut updated = sample("s1", "sess-a", "W1AW", 1000);
        updated.comments = Some("edited".into());
        updated.cloud_dirty_flag = true;
        store.upsert_session_spot(&updated).unwrap();
        assert_eq!(store.session_spot_count().unwrap(), 1);
        let spot = store.fetch_session_spot("s1").unwrap().unwrap();
        assert_eq!(spot.comments.as_deref(), Some("edited"));
        assert!(spot.cloud_dirty_flag);
    }

    #[test]
    fn dirty_only_restricts_to_dirty_rows() {
        let store = Store::open_in_memory("k").unwrap();
        let clean = sample("s1", "sess-a", "W1AW", 1000); // cloud_dirty_flag = false
        let mut dirty = sample("s2", "sess-a", "K2ABC", 2000);
        dirty.cloud_dirty_flag = true;
        store.upsert_session_spot(&clean).unwrap();
        store.upsert_session_spot(&dirty).unwrap();

        let filter = SessionSpotFilter { dirty_only: true, ..Default::default() };
        let rows = store.fetch_session_spots(&filter, 100, 0).unwrap();
        assert_eq!(rows.iter().map(|s| s.id.clone()).collect::<Vec<_>>(), vec!["s2"]);
    }

    #[test]
    fn missing_id_returns_none() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(store.fetch_session_spot("no-such-id").unwrap().is_none());
    }

    #[test]
    fn fetch_limit_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_session_spots(&SessionSpotFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
