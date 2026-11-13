//! WebSDRRecording entity — mirrors CarrierWaveData/Models/WebSDRRecording.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// Metadata for a WebSDR audio recording associated with a logging session.
///
/// `clip_bookmarks_data` holds JSON-encoded `[ClipBookmark]` (optional BLOB).
/// `parameter_changes_data` holds JSON-encoded `[SDRParameterEvent]` (optional BLOB).
/// `started_at` / `ended_at` / `created_at` are Unix-second timestamps.
/// `file_size_bytes` mirrors `Int64` in Swift → `i64` here.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WebSDRRecording {
    /// UUID string — primary key.
    pub id: String,
    /// UUID string of the owning logging session (or zeroed UUID for Tune In recordings).
    pub logging_session_id: String,
    pub kiwisdr_host: String,
    pub kiwisdr_name: String,
    /// Unix seconds, UTC.
    pub started_at: i64,
    /// Unix seconds, UTC. `None` until the recording is finished.
    pub ended_at: Option<i64>,
    pub frequency_k_hz: f64,
    pub mode: String,
    /// Relative path within app Documents (e.g. "WebSDRRecordings/uuid.caf").
    pub relative_file_path: String,
    /// File size in bytes.
    pub file_size_bytes: i64,
    /// Recording duration in seconds.
    pub duration_seconds: f64,
    pub is_complete: bool,
    pub spot_callsign: Option<String>,
    pub spot_park_ref: Option<String>,
    pub spot_park_name: Option<String>,
    pub spot_summit_code: Option<String>,
    pub spot_band: Option<String>,
    pub is_tune_in_recording: bool,
    /// JSON-encoded `[ClipBookmark]`.
    pub clip_bookmarks_data: Option<Vec<u8>>,
    /// JSON-encoded `[SDRParameterEvent]`.
    pub parameter_changes_data: Option<Vec<u8>>,
}

/// DDL for `websdr_recording`.
pub(crate) const WEBSDR_RECORDING_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS websdr_recording (
    id                      TEXT    NOT NULL PRIMARY KEY,
    logging_session_id      TEXT    NOT NULL,
    kiwisdr_host            TEXT    NOT NULL,
    kiwisdr_name            TEXT    NOT NULL,
    started_at              INTEGER NOT NULL,
    ended_at                INTEGER,
    frequency_k_hz          REAL    NOT NULL,
    mode                    TEXT    NOT NULL,
    relative_file_path      TEXT    NOT NULL,
    file_size_bytes         INTEGER NOT NULL,
    duration_seconds        REAL    NOT NULL,
    is_complete             INTEGER NOT NULL DEFAULT 0,
    spot_callsign           TEXT,
    spot_park_ref           TEXT,
    spot_park_name          TEXT,
    spot_summit_code        TEXT,
    spot_band               TEXT,
    is_tune_in_recording    INTEGER NOT NULL DEFAULT 0,
    clip_bookmarks_data     BLOB,
    parameter_changes_data  BLOB
);
CREATE INDEX IF NOT EXISTS idx_websdr_recording_logging_session_id
    ON websdr_recording (logging_session_id);
CREATE INDEX IF NOT EXISTS idx_websdr_recording_is_complete
    ON websdr_recording (is_complete);
CREATE INDEX IF NOT EXISTS idx_websdr_recording_started_at
    ON websdr_recording (started_at);
"#;

/// Filter parameters for [`Store::fetch_websdr_recordings`].
#[derive(Debug, Clone, Default)]
pub struct WebSDRRecordingFilter {
    /// Filter by owning session UUID string.
    pub logging_session_id: Option<String>,
    /// When `Some(true)`, return only complete recordings.
    pub is_complete: Option<bool>,
    /// When `true`, return only Tune In (standalone) recordings.
    pub is_tune_in_recording: Option<bool>,
}

impl Store {
    /// Insert or replace a WebSDR recording by `id`.
    pub fn upsert_websdr_recording(&self, rec: &WebSDRRecording) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO websdr_recording (
                id, logging_session_id, kiwisdr_host, kiwisdr_name,
                started_at, ended_at, frequency_k_hz, mode,
                relative_file_path, file_size_bytes, duration_seconds, is_complete,
                spot_callsign, spot_park_ref, spot_park_name, spot_summit_code, spot_band,
                is_tune_in_recording, clip_bookmarks_data, parameter_changes_data
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20)
            ON CONFLICT(id) DO UPDATE SET
                logging_session_id     = excluded.logging_session_id,
                kiwisdr_host           = excluded.kiwisdr_host,
                kiwisdr_name           = excluded.kiwisdr_name,
                started_at             = excluded.started_at,
                ended_at               = excluded.ended_at,
                frequency_k_hz         = excluded.frequency_k_hz,
                mode                   = excluded.mode,
                relative_file_path     = excluded.relative_file_path,
                file_size_bytes        = excluded.file_size_bytes,
                duration_seconds       = excluded.duration_seconds,
                is_complete            = excluded.is_complete,
                spot_callsign          = excluded.spot_callsign,
                spot_park_ref          = excluded.spot_park_ref,
                spot_park_name         = excluded.spot_park_name,
                spot_summit_code       = excluded.spot_summit_code,
                spot_band              = excluded.spot_band,
                is_tune_in_recording   = excluded.is_tune_in_recording,
                clip_bookmarks_data    = excluded.clip_bookmarks_data,
                parameter_changes_data = excluded.parameter_changes_data
            "#,
            params![
                rec.id,
                rec.logging_session_id,
                rec.kiwisdr_host,
                rec.kiwisdr_name,
                rec.started_at,
                rec.ended_at,
                rec.frequency_k_hz,
                rec.mode,
                rec.relative_file_path,
                rec.file_size_bytes,
                rec.duration_seconds,
                rec.is_complete as i64,
                rec.spot_callsign,
                rec.spot_park_ref,
                rec.spot_park_name,
                rec.spot_summit_code,
                rec.spot_band,
                rec.is_tune_in_recording as i64,
                rec.clip_bookmarks_data,
                rec.parameter_changes_data,
            ],
        )?;
        Ok(())
    }

    /// Total count of WebSDR recordings.
    pub fn websdr_recording_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM websdr_recording", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch with optional filtering.
    pub fn fetch_websdr_recordings(
        &self,
        filter: &WebSDRRecordingFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<WebSDRRecording>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT id, logging_session_id, kiwisdr_host, kiwisdr_name, \
             started_at, ended_at, frequency_k_hz, mode, \
             relative_file_path, file_size_bytes, duration_seconds, is_complete, \
             spot_callsign, spot_park_ref, spot_park_name, spot_summit_code, spot_band, \
             is_tune_in_recording, clip_bookmarks_data, parameter_changes_data \
             FROM websdr_recording WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(session_id) = &filter.logging_session_id {
            sql.push_str(" AND logging_session_id = ?");
            args.push(Box::new(session_id.clone()));
        }
        if let Some(complete) = filter.is_complete {
            sql.push_str(" AND is_complete = ?");
            args.push(Box::new(complete as i64));
        }
        if let Some(tune_in) = filter.is_tune_in_recording {
            sql.push_str(" AND is_tune_in_recording = ?");
            args.push(Box::new(tune_in as i64));
        }
        sql.push_str(" ORDER BY started_at DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_websdr_recording)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single recording by `id`. Returns `None` if not found.
    /// Delete a `websdr_recording` row by id. Idempotent — a missing id succeeds.
    pub fn delete_websdr_recording(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM websdr_recording WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_websdr_recording(&self, id: &str) -> Result<Option<WebSDRRecording>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, logging_session_id, kiwisdr_host, kiwisdr_name, \
                 started_at, ended_at, frequency_k_hz, mode, \
                 relative_file_path, file_size_bytes, duration_seconds, is_complete, \
                 spot_callsign, spot_park_ref, spot_park_name, spot_summit_code, spot_band, \
                 is_tune_in_recording, clip_bookmarks_data, parameter_changes_data \
                 FROM websdr_recording WHERE id = ?1",
                params![id],
                Self::row_to_websdr_recording,
            )
            .optional()?)
    }

    fn row_to_websdr_recording(row: &rusqlite::Row<'_>) -> rusqlite::Result<WebSDRRecording> {
        Ok(WebSDRRecording {
            id: row.get(0)?,
            logging_session_id: row.get(1)?,
            kiwisdr_host: row.get(2)?,
            kiwisdr_name: row.get(3)?,
            started_at: row.get(4)?,
            ended_at: row.get(5)?,
            frequency_k_hz: row.get(6)?,
            mode: row.get(7)?,
            relative_file_path: row.get(8)?,
            file_size_bytes: row.get(9)?,
            duration_seconds: row.get(10)?,
            is_complete: row.get::<_, i64>(11)? != 0,
            spot_callsign: row.get(12)?,
            spot_park_ref: row.get(13)?,
            spot_park_name: row.get(14)?,
            spot_summit_code: row.get(15)?,
            spot_band: row.get(16)?,
            is_tune_in_recording: row.get::<_, i64>(17)? != 0,
            clip_bookmarks_data: row.get(18)?,
            parameter_changes_data: row.get(19)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, session_id: &str, started_at: i64) -> WebSDRRecording {
        WebSDRRecording {
            id: id.to_string(),
            logging_session_id: session_id.to_string(),
            kiwisdr_host: "kiwi.example.com:8073".to_string(),
            kiwisdr_name: "Example KiwiSDR".to_string(),
            started_at,
            ended_at: None,
            frequency_k_hz: 14_074.0,
            mode: "FT8".to_string(),
            relative_file_path: format!("WebSDRRecordings/{id}.caf"),
            file_size_bytes: 0,
            duration_seconds: 0.0,
            is_complete: false,
            spot_callsign: None,
            spot_park_ref: None,
            spot_park_name: None,
            spot_summit_code: None,
            spot_band: Some("20m".to_string()),
            is_tune_in_recording: false,
            clip_bookmarks_data: None,
            parameter_changes_data: None,
        }
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let rec = sample("rec-1", "sess-1", 1_700_000_000);
        store.upsert_websdr_recording(&rec).unwrap();
        let fetched = store.fetch_websdr_recording("rec-1").unwrap().unwrap();
        assert_eq!(fetched, rec);
    }

    #[test]
    fn count_and_session_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_websdr_recording(&sample("r1", "s1", 1000)).unwrap();
        store.upsert_websdr_recording(&sample("r2", "s1", 2000)).unwrap();
        store.upsert_websdr_recording(&sample("r3", "s2", 3000)).unwrap();
        assert_eq!(store.websdr_recording_count().unwrap(), 3);

        let for_s1 = store
            .fetch_websdr_recordings(
                &WebSDRRecordingFilter {
                    logging_session_id: Some("s1".into()),
                    ..Default::default()
                },
                100,
                0,
            )
            .unwrap();
        assert_eq!(for_s1.len(), 2);
        // Newest first.
        assert_eq!(for_s1[0].id, "r2");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_websdr_recording(&sample("r1", "s1", 1000)).unwrap();
        let mut updated = sample("r1", "s1", 1000);
        updated.is_complete = true;
        updated.duration_seconds = 120.0;
        updated.ended_at = Some(1100);
        store.upsert_websdr_recording(&updated).unwrap();
        assert_eq!(store.websdr_recording_count().unwrap(), 1);
        let fetched = store.fetch_websdr_recording("r1").unwrap().unwrap();
        assert!(fetched.is_complete);
        assert_eq!(fetched.duration_seconds, 120.0);
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_websdr_recordings(&WebSDRRecordingFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
