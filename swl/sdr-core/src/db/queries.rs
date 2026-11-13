use chrono::{DateTime, Utc};
use rusqlite::params;
use uuid::Uuid;

use super::Database;
use crate::db::models::{
    CaptureRow, RecordingRow, SdrRow, SegmentRow, TranscriptionRow, UploadedRecordingRow,
};
use crate::error::DbError;

// ── SDR CRUD ───────────────────────────────────────────────────────

impl Database {
    pub fn upsert_sdr(&self, sdr: &SdrRow) -> Result<(), DbError> {
        self.conn().execute(
            "INSERT INTO sdrs (id, driver, label, serial, url, sample_rate, antenna, last_seen, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
             ON CONFLICT(id) DO UPDATE SET
               driver = excluded.driver,
               label = excluded.label,
               serial = excluded.serial,
               url = excluded.url,
               sample_rate = excluded.sample_rate,
               antenna = excluded.antenna,
               last_seen = excluded.last_seen",
            params![
                sdr.id,
                sdr.driver,
                sdr.label,
                sdr.serial,
                sdr.url,
                sdr.sample_rate,
                sdr.antenna,
                sdr.last_seen.to_rfc3339(),
                sdr.created_at.to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn get_sdr(&self, id: &str) -> Result<SdrRow, DbError> {
        self.conn()
            .query_row(
                "SELECT id, driver, label, serial, url, sample_rate, antenna, last_seen, created_at
                 FROM sdrs WHERE id = ?1",
                params![id],
                |row| {
                    Ok(SdrRow {
                        id: row.get(0)?,
                        driver: row.get(1)?,
                        label: row.get(2)?,
                        serial: row.get(3)?,
                        url: row.get(4)?,
                        sample_rate: row.get(5)?,
                        antenna: row.get(6)?,
                        last_seen: parse_dt(row.get::<_, String>(7)?),
                        created_at: parse_dt(row.get::<_, String>(8)?),
                    })
                },
            )
            .map_err(|_| DbError::NotFound(format!("sdr {id}")))
    }

    pub fn list_sdrs(&self) -> Result<Vec<SdrRow>, DbError> {
        let mut stmt = self.conn().prepare(
            "SELECT id, driver, label, serial, url, sample_rate, antenna, last_seen, created_at
             FROM sdrs ORDER BY id",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(SdrRow {
                id: row.get(0)?,
                driver: row.get(1)?,
                label: row.get(2)?,
                serial: row.get(3)?,
                url: row.get(4)?,
                sample_rate: row.get(5)?,
                antenna: row.get(6)?,
                last_seen: parse_dt(row.get::<_, String>(7)?),
                created_at: parse_dt(row.get::<_, String>(8)?),
            })
        })?;
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    // ── Capture CRUD ────────────────────────────────────────────────

    pub fn insert_capture(&self, cap: &CaptureRow) -> Result<(), DbError> {
        self.conn().execute(
            "INSERT INTO captures (id, sdr_id, center_frequency, bandwidth, sample_rate, consumer_count, started_at, stopped_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                cap.id.to_string(),
                cap.sdr_id,
                cap.center_frequency,
                cap.bandwidth,
                cap.sample_rate,
                cap.consumer_count,
                cap.started_at.to_rfc3339(),
                cap.stopped_at.map(|t| t.to_rfc3339()),
            ],
        )?;
        Ok(())
    }

    pub fn get_capture(&self, id: Uuid) -> Result<CaptureRow, DbError> {
        let id_str = id.to_string();
        self.conn()
            .query_row(
                "SELECT id, sdr_id, center_frequency, bandwidth, sample_rate, consumer_count, started_at, stopped_at
                 FROM captures WHERE id = ?1",
                params![id_str],
                |row| {
                    Ok(CaptureRow {
                        id: parse_uuid(row.get::<_, String>(0)?),
                        sdr_id: row.get(1)?,
                        center_frequency: row.get(2)?,
                        bandwidth: row.get(3)?,
                        sample_rate: row.get(4)?,
                        consumer_count: row.get(5)?,
                        started_at: parse_dt(row.get::<_, String>(6)?),
                        stopped_at: row
                            .get::<_, Option<String>>(7)?
                            .map(parse_dt),
                    })
                },
            )
            .map_err(|_| DbError::NotFound(format!("capture {id}")))
    }

    pub fn list_active_captures(&self) -> Result<Vec<CaptureRow>, DbError> {
        let mut stmt = self.conn().prepare(
            "SELECT id, sdr_id, center_frequency, bandwidth, sample_rate, consumer_count, started_at, stopped_at
             FROM captures WHERE stopped_at IS NULL ORDER BY started_at",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(CaptureRow {
                id: parse_uuid(row.get::<_, String>(0)?),
                sdr_id: row.get(1)?,
                center_frequency: row.get(2)?,
                bandwidth: row.get(3)?,
                sample_rate: row.get(4)?,
                consumer_count: row.get(5)?,
                started_at: parse_dt(row.get::<_, String>(6)?),
                stopped_at: row.get::<_, Option<String>>(7)?.map(parse_dt),
            })
        })?;
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    pub fn update_capture_stopped(
        &self,
        id: Uuid,
        stopped_at: DateTime<Utc>,
    ) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE captures SET stopped_at = ?1 WHERE id = ?2",
            params![stopped_at.to_rfc3339(), id_str],
        )?;
        Ok(())
    }

    pub fn update_capture_consumer_count(&self, id: Uuid, count: i64) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE captures SET consumer_count = ?1 WHERE id = ?2",
            params![count, id_str],
        )?;
        Ok(())
    }

    // ── Recording CRUD ──────────────────────────────────────────────

    pub fn insert_recording(&self, rec: &RecordingRow) -> Result<(), DbError> {
        self.conn().execute(
            "INSERT INTO recordings (id, capture_id, sdr_id, frequency, bandwidth, mode, status, started_at, stopped_at, retention_days)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                rec.id.to_string(),
                rec.capture_id.map(|u| u.to_string()),
                rec.sdr_id,
                rec.frequency,
                rec.bandwidth,
                rec.mode,
                rec.status,
                rec.started_at.to_rfc3339(),
                rec.stopped_at.map(|t| t.to_rfc3339()),
                rec.retention_days,
            ],
        )?;
        Ok(())
    }

    pub fn get_recording(&self, id: Uuid) -> Result<RecordingRow, DbError> {
        let id_str = id.to_string();
        self.conn()
            .query_row(
                "SELECT id, capture_id, sdr_id, frequency, bandwidth, mode, status, started_at, stopped_at, retention_days, created_at
                 FROM recordings WHERE id = ?1",
                params![id_str],
                |row| {
                    Ok(RecordingRow {
                        id: parse_uuid(row.get::<_, String>(0)?),
                        capture_id: row.get::<_, Option<String>>(1)?.map(parse_uuid),
                        sdr_id: row.get(2)?,
                        frequency: row.get(3)?,
                        bandwidth: row.get(4)?,
                        mode: row.get(5)?,
                        status: row.get(6)?,
                        started_at: parse_dt(row.get::<_, String>(7)?),
                        stopped_at: row.get::<_, Option<String>>(8)?.map(parse_dt),
                        retention_days: row.get(9)?,
                        created_at: parse_dt(row.get::<_, String>(10)?),
                    })
                },
            )
            .map_err(|_| DbError::NotFound(format!("recording {id}")))
    }

    pub fn list_recordings(&self, status: Option<&str>) -> Result<Vec<RecordingRow>, DbError> {
        let sql = match status {
            Some(_) => {
                "SELECT id, capture_id, sdr_id, frequency, bandwidth, mode, status, started_at, stopped_at, retention_days, created_at
                 FROM recordings WHERE status = ?1 ORDER BY started_at DESC"
            }
            None => {
                "SELECT id, capture_id, sdr_id, frequency, bandwidth, mode, status, started_at, stopped_at, retention_days, created_at
                 FROM recordings ORDER BY started_at DESC"
            }
        };
        let mut stmt = self.conn().prepare(sql)?;
        let rows = if let Some(s) = status {
            stmt.query_map(params![s], map_recording_row)?
        } else {
            stmt.query_map([], map_recording_row)?
        };
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    pub fn update_recording_status(
        &self,
        id: Uuid,
        status: &str,
        stopped_at: Option<DateTime<Utc>>,
    ) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE recordings SET status = ?1, stopped_at = ?2 WHERE id = ?3",
            params![status, stopped_at.map(|t| t.to_rfc3339()), id_str],
        )?;
        Ok(())
    }

    pub fn update_recording_frequency(&self, id: Uuid, frequency: i64) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE recordings SET frequency = ?1 WHERE id = ?2",
            params![frequency, id_str],
        )?;
        Ok(())
    }

    pub fn delete_recording(&self, id: Uuid) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "DELETE FROM transcriptions WHERE recording_id = ?1",
            params![id_str],
        )?;
        self.conn().execute(
            "DELETE FROM segments WHERE recording_id = ?1",
            params![id_str],
        )?;
        self.conn()
            .execute("DELETE FROM recordings WHERE id = ?1", params![id_str])?;
        Ok(())
    }

    // ── Segment CRUD ────────────────────────────────────────────────

    pub fn insert_segment(&self, seg: &SegmentRow) -> Result<(), DbError> {
        self.conn().execute(
            "INSERT INTO segments (id, recording_id, segment_number, file_path, duration_secs, file_size_bytes, sample_rate, started_at, ended_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                seg.id.to_string(),
                seg.recording_id.to_string(),
                seg.segment_number,
                seg.file_path,
                seg.duration_secs,
                seg.file_size_bytes,
                seg.sample_rate,
                seg.started_at.to_rfc3339(),
                seg.ended_at.to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn list_segments(&self, recording_id: Uuid) -> Result<Vec<SegmentRow>, DbError> {
        let rec_id = recording_id.to_string();
        let mut stmt = self.conn().prepare(
            "SELECT id, recording_id, segment_number, file_path, duration_secs, file_size_bytes, sample_rate, started_at, ended_at, created_at
             FROM segments WHERE recording_id = ?1 ORDER BY segment_number",
        )?;
        let rows = stmt.query_map(params![rec_id], |row| {
            Ok(SegmentRow {
                id: parse_uuid(row.get::<_, String>(0)?),
                recording_id: parse_uuid(row.get::<_, String>(1)?),
                segment_number: row.get(2)?,
                file_path: row.get(3)?,
                duration_secs: row.get(4)?,
                file_size_bytes: row.get(5)?,
                sample_rate: row.get(6)?,
                started_at: parse_dt(row.get::<_, String>(7)?),
                ended_at: parse_dt(row.get::<_, String>(8)?),
                created_at: parse_dt(row.get::<_, String>(9)?),
            })
        })?;
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    pub fn get_segment(
        &self,
        recording_id: Uuid,
        segment_number: i64,
    ) -> Result<SegmentRow, DbError> {
        let rec_id = recording_id.to_string();
        self.conn()
            .query_row(
                "SELECT id, recording_id, segment_number, file_path, duration_secs, file_size_bytes, sample_rate, started_at, ended_at, created_at
                 FROM segments WHERE recording_id = ?1 AND segment_number = ?2",
                params![rec_id, segment_number],
                |row| {
                    Ok(SegmentRow {
                        id: parse_uuid(row.get::<_, String>(0)?),
                        recording_id: parse_uuid(row.get::<_, String>(1)?),
                        segment_number: row.get(2)?,
                        file_path: row.get(3)?,
                        duration_secs: row.get(4)?,
                        file_size_bytes: row.get(5)?,
                        sample_rate: row.get(6)?,
                        started_at: parse_dt(row.get::<_, String>(7)?),
                        ended_at: parse_dt(row.get::<_, String>(8)?),
                        created_at: parse_dt(row.get::<_, String>(9)?),
                    })
                },
            )
            .map_err(|_| DbError::NotFound(format!("segment {recording_id}/{segment_number}")))
    }
    // ── Uploaded Recording CRUD ────────────────────────────────────

    pub fn insert_uploaded_recording(&self, rec: &UploadedRecordingRow) -> Result<(), DbError> {
        self.conn().execute(
            "INSERT INTO uploaded_recordings (id, original_filename, original_format, sample_rate, duration_secs, status, error_message, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                rec.id.to_string(),
                rec.original_filename,
                rec.original_format,
                rec.sample_rate,
                rec.duration_secs,
                rec.status,
                rec.error_message,
                rec.created_at.to_rfc3339(),
            ],
        )?;
        Ok(())
    }

    pub fn get_uploaded_recording(&self, id: Uuid) -> Result<UploadedRecordingRow, DbError> {
        let id_str = id.to_string();
        self.conn()
            .query_row(
                "SELECT id, original_filename, original_format, sample_rate, duration_secs, status, error_message, created_at
                 FROM uploaded_recordings WHERE id = ?1",
                params![id_str],
                |row| {
                    Ok(UploadedRecordingRow {
                        id: parse_uuid(row.get::<_, String>(0)?),
                        original_filename: row.get(1)?,
                        original_format: row.get(2)?,
                        sample_rate: row.get(3)?,
                        duration_secs: row.get(4)?,
                        status: row.get(5)?,
                        error_message: row.get(6)?,
                        created_at: parse_dt(row.get::<_, String>(7)?),
                    })
                },
            )
            .map_err(|_| DbError::NotFound(format!("uploaded_recording {id}")))
    }

    pub fn update_uploaded_recording_status(
        &self,
        id: Uuid,
        status: &str,
        sample_rate: Option<i64>,
        duration_secs: Option<f64>,
        error_message: Option<&str>,
    ) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE uploaded_recordings SET status = ?1, sample_rate = ?2, duration_secs = ?3, error_message = ?4 WHERE id = ?5",
            params![status, sample_rate, duration_secs, error_message, id_str],
        )?;
        Ok(())
    }

    // ── Transcription CRUD ────────────────────────────────────────

    pub fn insert_transcription(&self, tx: &TranscriptionRow) -> Result<(), DbError> {
        self.conn().execute(
            "INSERT INTO transcriptions (id, recording_id, text, status, wpm_estimate, char_count, error_message, started_at, completed_at, structured_transcript, progress, uploaded_recording_id)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            params![
                tx.id.to_string(),
                tx.recording_id.map(|u| u.to_string()),
                tx.text,
                tx.status,
                tx.wpm_estimate,
                tx.char_count,
                tx.error_message,
                tx.started_at.to_rfc3339(),
                tx.completed_at.map(|t| t.to_rfc3339()),
                tx.structured_transcript,
                tx.progress,
                tx.uploaded_recording_id.map(|u| u.to_string()),
            ],
        )?;
        Ok(())
    }

    pub fn get_transcription(&self, id: Uuid) -> Result<TranscriptionRow, DbError> {
        let id_str = id.to_string();
        self.conn()
            .query_row(
                "SELECT id, recording_id, text, status, wpm_estimate, char_count, error_message, started_at, completed_at, created_at, structured_transcript, progress, uploaded_recording_id
                 FROM transcriptions WHERE id = ?1",
                params![id_str],
                map_transcription_row,
            )
            .map_err(|_| DbError::NotFound(format!("transcription {id}")))
    }

    pub fn list_transcriptions(&self) -> Result<Vec<TranscriptionRow>, DbError> {
        let mut stmt = self.conn().prepare(
            "SELECT id, recording_id, text, status, wpm_estimate, char_count, error_message, started_at, completed_at, created_at, structured_transcript, progress, uploaded_recording_id
             FROM transcriptions ORDER BY created_at DESC",
        )?;
        let rows = stmt.query_map([], map_transcription_row)?;
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    #[allow(clippy::too_many_arguments)]
    pub fn update_transcription_status(
        &self,
        id: Uuid,
        status: &str,
        text: &str,
        wpm_estimate: Option<f64>,
        char_count: i64,
        error_message: Option<&str>,
        completed_at: Option<DateTime<Utc>>,
    ) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE transcriptions SET status = ?1, text = ?2, wpm_estimate = ?3, char_count = ?4, error_message = ?5, completed_at = ?6 WHERE id = ?7",
            params![
                status,
                text,
                wpm_estimate,
                char_count,
                error_message,
                completed_at.map(|t| t.to_rfc3339()),
                id_str,
            ],
        )?;
        Ok(())
    }

    /// Update a transcription with structured transcript data (for upload-based async flow).
    #[allow(clippy::too_many_arguments)]
    pub fn update_transcription_structured(
        &self,
        id: Uuid,
        status: &str,
        text: &str,
        wpm_estimate: Option<f64>,
        char_count: i64,
        error_message: Option<&str>,
        completed_at: Option<DateTime<Utc>>,
        structured_transcript: Option<&str>,
        progress: Option<f64>,
    ) -> Result<(), DbError> {
        let id_str = id.to_string();
        self.conn().execute(
            "UPDATE transcriptions SET status = ?1, text = ?2, wpm_estimate = ?3, \
             char_count = ?4, error_message = ?5, completed_at = ?6, \
             structured_transcript = ?7, progress = ?8 WHERE id = ?9",
            params![
                status,
                text,
                wpm_estimate,
                char_count,
                error_message,
                completed_at.map(|t| t.to_rfc3339()),
                structured_transcript,
                progress,
                id_str,
            ],
        )?;
        Ok(())
    }

    pub fn delete_transcription(&self, id: Uuid) -> Result<(), DbError> {
        let id_str = id.to_string();
        let rows = self
            .conn()
            .execute("DELETE FROM transcriptions WHERE id = ?1", params![id_str])?;
        if rows == 0 {
            return Err(DbError::NotFound(format!("transcription {id}")));
        }
        Ok(())
    }
}

fn map_transcription_row(row: &rusqlite::Row) -> rusqlite::Result<TranscriptionRow> {
    Ok(TranscriptionRow {
        id: parse_uuid(row.get::<_, String>(0)?),
        recording_id: row.get::<_, Option<String>>(1)?.map(parse_uuid),
        text: row.get(2)?,
        status: row.get(3)?,
        wpm_estimate: row.get(4)?,
        char_count: row.get(5)?,
        error_message: row.get(6)?,
        started_at: parse_dt(row.get::<_, String>(7)?),
        completed_at: row.get::<_, Option<String>>(8)?.map(parse_dt),
        created_at: parse_dt(row.get::<_, String>(9)?),
        structured_transcript: row.get(10)?,
        progress: row.get(11)?,
        uploaded_recording_id: row.get::<_, Option<String>>(12)?.map(parse_uuid),
    })
}

fn map_recording_row(row: &rusqlite::Row) -> rusqlite::Result<RecordingRow> {
    Ok(RecordingRow {
        id: parse_uuid(row.get::<_, String>(0)?),
        capture_id: row.get::<_, Option<String>>(1)?.map(parse_uuid),
        sdr_id: row.get(2)?,
        frequency: row.get(3)?,
        bandwidth: row.get(4)?,
        mode: row.get(5)?,
        status: row.get(6)?,
        started_at: parse_dt(row.get::<_, String>(7)?),
        stopped_at: row.get::<_, Option<String>>(8)?.map(parse_dt),
        retention_days: row.get(9)?,
        created_at: parse_dt(row.get::<_, String>(10)?),
    })
}

fn parse_dt(s: String) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .unwrap_or_else(|_| Utc::now())
}

fn parse_uuid(s: String) -> Uuid {
    Uuid::parse_str(&s).unwrap_or_else(|_| Uuid::nil())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Database;
    use chrono::Utc;

    fn test_db() -> Database {
        Database::open_in_memory().unwrap()
    }

    #[test]
    fn sdr_roundtrip() {
        let db = test_db();
        let now = Utc::now();
        let sdr = SdrRow {
            id: "test-001".into(),
            driver: "rtlsdr".into(),
            label: Some("Test SDR".into()),
            serial: Some("00000001".into()),
            url: None,
            sample_rate: Some(2_400_000),
            antenna: Some("dipole".into()),
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let fetched = db.get_sdr("test-001").unwrap();
        assert_eq!(fetched.id, "test-001");
        assert_eq!(fetched.driver, "rtlsdr");
        assert_eq!(fetched.label.as_deref(), Some("Test SDR"));

        let all = db.list_sdrs().unwrap();
        assert_eq!(all.len(), 1);
    }

    #[test]
    fn sdr_upsert_updates() {
        let db = test_db();
        let now = Utc::now();
        let sdr = SdrRow {
            id: "test-001".into(),
            driver: "rtlsdr".into(),
            label: Some("Old Label".into()),
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let mut updated = sdr.clone();
        updated.label = Some("New Label".into());
        db.upsert_sdr(&updated).unwrap();

        let fetched = db.get_sdr("test-001").unwrap();
        assert_eq!(fetched.label.as_deref(), Some("New Label"));

        // Only one row
        assert_eq!(db.list_sdrs().unwrap().len(), 1);
    }

    #[test]
    fn recording_and_segment_roundtrip() {
        let db = test_db();
        let now = Utc::now();

        // Insert SDR first (foreign key)
        let sdr = SdrRow {
            id: "sdr-1".into(),
            driver: "mock".into(),
            label: None,
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let rec_id = Uuid::new_v4();
        let rec = RecordingRow {
            id: rec_id,
            capture_id: None,
            sdr_id: "sdr-1".into(),
            frequency: 7_030_000,
            bandwidth: 2_400,
            mode: "cw".into(),
            status: "active".into(),
            started_at: now,
            stopped_at: None,
            retention_days: 30,
            created_at: now,
        };
        db.insert_recording(&rec).unwrap();

        let fetched = db.get_recording(rec_id).unwrap();
        assert_eq!(fetched.frequency, 7_030_000);
        assert_eq!(fetched.status, "active");

        // Insert segment
        let seg_id = Uuid::new_v4();
        let seg = SegmentRow {
            id: seg_id,
            recording_id: rec_id,
            segment_number: 0,
            file_path: "/data/seg0.flac".into(),
            duration_secs: 300.0,
            file_size_bytes: 1_024_000,
            sample_rate: 48_000,
            started_at: now,
            ended_at: now,
            created_at: now,
        };
        db.insert_segment(&seg).unwrap();

        let segments = db.list_segments(rec_id).unwrap();
        assert_eq!(segments.len(), 1);
        assert_eq!(segments[0].file_path, "/data/seg0.flac");

        let seg0 = db.get_segment(rec_id, 0).unwrap();
        assert_eq!(seg0.id, seg_id);

        // Update status
        db.update_recording_status(rec_id, "stopped", Some(now))
            .unwrap();
        let updated = db.get_recording(rec_id).unwrap();
        assert_eq!(updated.status, "stopped");
        assert!(updated.stopped_at.is_some());

        // List by status
        let active = db.list_recordings(Some("active")).unwrap();
        assert_eq!(active.len(), 0);
        let stopped = db.list_recordings(Some("stopped")).unwrap();
        assert_eq!(stopped.len(), 1);
    }

    #[test]
    fn capture_roundtrip() {
        let db = test_db();
        let now = Utc::now();

        let sdr = SdrRow {
            id: "sdr-1".into(),
            driver: "mock".into(),
            label: None,
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let cap_id = Uuid::new_v4();
        let cap = CaptureRow {
            id: cap_id,
            sdr_id: "sdr-1".into(),
            center_frequency: 7_030_000,
            bandwidth: 200_000,
            sample_rate: 2_400_000,
            consumer_count: 1,
            started_at: now,
            stopped_at: None,
        };
        db.insert_capture(&cap).unwrap();

        let fetched = db.get_capture(cap_id).unwrap();
        assert_eq!(fetched.center_frequency, 7_030_000);

        let active = db.list_active_captures().unwrap();
        assert_eq!(active.len(), 1);

        db.update_capture_consumer_count(cap_id, 3).unwrap();
        let updated = db.get_capture(cap_id).unwrap();
        assert_eq!(updated.consumer_count, 3);

        db.update_capture_stopped(cap_id, now).unwrap();
        let stopped = db.list_active_captures().unwrap();
        assert_eq!(stopped.len(), 0);
    }

    #[test]
    fn transcription_roundtrip() {
        let db = test_db();
        let now = Utc::now();

        let sdr = SdrRow {
            id: "sdr-1".into(),
            driver: "mock".into(),
            label: None,
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let rec_id = Uuid::new_v4();
        let rec = RecordingRow {
            id: rec_id,
            capture_id: None,
            sdr_id: "sdr-1".into(),
            frequency: 7_030_000,
            bandwidth: 2_400,
            mode: "cw".into(),
            status: "stopped".into(),
            started_at: now,
            stopped_at: Some(now),
            retention_days: 30,
            created_at: now,
        };
        db.insert_recording(&rec).unwrap();

        let tx_id = Uuid::new_v4();
        let tx = TranscriptionRow {
            id: tx_id,
            recording_id: Some(rec_id),
            text: "CQ CQ DE W1AW".into(),
            status: "completed".into(),
            wpm_estimate: Some(15.0),
            char_count: 14,
            error_message: None,
            started_at: now,
            completed_at: Some(now),
            created_at: now,
            structured_transcript: None,
            progress: None,
            uploaded_recording_id: None,
        };
        db.insert_transcription(&tx).unwrap();

        let fetched = db.get_transcription(tx_id).unwrap();
        assert_eq!(fetched.text, "CQ CQ DE W1AW");
        assert_eq!(fetched.status, "completed");
        assert_eq!(fetched.char_count, 14);
        assert_eq!(fetched.wpm_estimate, Some(15.0));

        let all = db.list_transcriptions().unwrap();
        assert_eq!(all.len(), 1);

        // Update status
        db.update_transcription_status(
            tx_id,
            "completed",
            "CQ CQ DE W1AW K",
            Some(16.0),
            16,
            None,
            Some(now),
        )
        .unwrap();
        let updated = db.get_transcription(tx_id).unwrap();
        assert_eq!(updated.text, "CQ CQ DE W1AW K");
        assert_eq!(updated.char_count, 16);

        // Delete
        db.delete_transcription(tx_id).unwrap();
        assert!(db.get_transcription(tx_id).is_err());
    }

    #[test]
    fn delete_recording_cascades_transcriptions() {
        let db = test_db();
        let now = Utc::now();

        let sdr = SdrRow {
            id: "sdr-1".into(),
            driver: "mock".into(),
            label: None,
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let rec_id = Uuid::new_v4();
        let rec = RecordingRow {
            id: rec_id,
            capture_id: None,
            sdr_id: "sdr-1".into(),
            frequency: 7_030_000,
            bandwidth: 2_400,
            mode: "cw".into(),
            status: "stopped".into(),
            started_at: now,
            stopped_at: Some(now),
            retention_days: 0,
            created_at: now,
        };
        db.insert_recording(&rec).unwrap();

        let tx_id = Uuid::new_v4();
        let tx = TranscriptionRow {
            id: tx_id,
            recording_id: Some(rec_id),
            text: "TEST".into(),
            status: "completed".into(),
            wpm_estimate: Some(15.0),
            char_count: 4,
            error_message: None,
            started_at: now,
            completed_at: Some(now),
            created_at: now,
            structured_transcript: None,
            progress: None,
            uploaded_recording_id: None,
        };
        db.insert_transcription(&tx).unwrap();

        db.delete_recording(rec_id).unwrap();
        assert!(db.get_transcription(tx_id).is_err());
    }

    #[test]
    fn delete_recording_cascades_segments() {
        let db = test_db();
        let now = Utc::now();

        let sdr = SdrRow {
            id: "sdr-1".into(),
            driver: "mock".into(),
            label: None,
            serial: None,
            url: None,
            sample_rate: None,
            antenna: None,
            last_seen: now,
            created_at: now,
        };
        db.upsert_sdr(&sdr).unwrap();

        let rec_id = Uuid::new_v4();
        let rec = RecordingRow {
            id: rec_id,
            capture_id: None,
            sdr_id: "sdr-1".into(),
            frequency: 7_030_000,
            bandwidth: 2_400,
            mode: "cw".into(),
            status: "active".into(),
            started_at: now,
            stopped_at: None,
            retention_days: 0,
            created_at: now,
        };
        db.insert_recording(&rec).unwrap();

        let seg = SegmentRow {
            id: Uuid::new_v4(),
            recording_id: rec_id,
            segment_number: 0,
            file_path: "/tmp/seg.flac".into(),
            duration_secs: 60.0,
            file_size_bytes: 512_000,
            sample_rate: 48_000,
            started_at: now,
            ended_at: now,
            created_at: now,
        };
        db.insert_segment(&seg).unwrap();

        db.delete_recording(rec_id).unwrap();
        assert!(db.get_recording(rec_id).is_err());
        assert_eq!(db.list_segments(rec_id).unwrap().len(), 0);
    }
}
