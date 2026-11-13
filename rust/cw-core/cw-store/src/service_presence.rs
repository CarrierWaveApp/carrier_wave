//! The ServicePresence entity + its bounded query API.
//! Mirrors CarrierWaveData/Models/ServicePresence.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// A per-service upload/confirmation status record for a QSO.
/// The Swift `@Relationship var qso: QSO?` is represented as a plain FK column.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ServicePresence {
    pub id: String,
    /// Stored as the raw string value of the `ServiceType` enum.
    pub service_type_raw_value: String,
    pub is_present: bool,
    pub needs_upload: bool,
    pub upload_rejected: bool,
    /// App version+build string (e.g. "2.4.132") that rejected this record.
    pub rejected_at_build: Option<String>,
    pub is_submitted: bool,
    /// Unix seconds, UTC.
    pub last_confirmed_at: Option<i64>,
    pub park_reference: Option<String>,
    /// Whether this row has un-synced local changes (sync journal flag).
    pub cloud_dirty_flag: bool,
    /// Foreign key to the associated QSO's `id`.
    pub qso_id: Option<String>,
}

/// DDL for the `service_presence` table and its supporting indexes.
pub(crate) const SERVICE_PRESENCE_DDL: &str = r#"
    CREATE TABLE IF NOT EXISTS service_presence (
        id                      TEXT PRIMARY KEY NOT NULL,
        service_type_raw_value  TEXT NOT NULL,
        is_present              INTEGER NOT NULL DEFAULT 0,
        needs_upload            INTEGER NOT NULL DEFAULT 0,
        upload_rejected         INTEGER NOT NULL DEFAULT 0,
        rejected_at_build       TEXT,
        is_submitted            INTEGER NOT NULL DEFAULT 0,
        last_confirmed_at       INTEGER,
        park_reference          TEXT,
        cloud_dirty_flag        INTEGER NOT NULL DEFAULT 0,
        qso_id                  TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_sp_qso_id           ON service_presence(qso_id);
    CREATE INDEX IF NOT EXISTS idx_sp_service_type     ON service_presence(service_type_raw_value);
    CREATE INDEX IF NOT EXISTS idx_sp_needs_upload     ON service_presence(needs_upload);
    CREATE INDEX IF NOT EXISTS idx_sp_cloud_dirty_flag ON service_presence(cloud_dirty_flag);
    CREATE INDEX IF NOT EXISTS idx_sp_last_confirmed   ON service_presence(last_confirmed_at);
"#;

/// Bounded query parameters for `service_presence`.
#[derive(Debug, Clone, Default)]
pub struct ServicePresenceFilter {
    pub qso_id: Option<String>,
    pub service_type_raw_value: Option<String>,
    /// When `Some(true)`, only rows where `needs_upload = 1`.
    pub needs_upload: Option<bool>,
    /// When `true`, only rows where `cloud_dirty_flag = 1`.
    pub dirty_only: bool,
}

impl Store {
    /// Insert or replace a `ServicePresence` record.
    pub fn upsert_service_presence(&self, sp: &ServicePresence) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO service_presence (
                id, service_type_raw_value, is_present, needs_upload, upload_rejected,
                rejected_at_build, is_submitted, last_confirmed_at, park_reference,
                cloud_dirty_flag, qso_id
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
            ON CONFLICT(id) DO UPDATE SET
                service_type_raw_value=excluded.service_type_raw_value,
                is_present=excluded.is_present,
                needs_upload=excluded.needs_upload,
                upload_rejected=excluded.upload_rejected,
                rejected_at_build=excluded.rejected_at_build,
                is_submitted=excluded.is_submitted,
                last_confirmed_at=excluded.last_confirmed_at,
                park_reference=excluded.park_reference,
                cloud_dirty_flag=excluded.cloud_dirty_flag,
                qso_id=excluded.qso_id
            "#,
            params![
                sp.id,
                sp.service_type_raw_value,
                sp.is_present as i64,
                sp.needs_upload as i64,
                sp.upload_rejected as i64,
                sp.rejected_at_build,
                sp.is_submitted as i64,
                sp.last_confirmed_at,
                sp.park_reference,
                sp.cloud_dirty_flag as i64,
                sp.qso_id,
            ],
        )?;
        Ok(())
    }

    /// Total count of `service_presence` rows.
    pub fn service_presence_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM service_presence", [], |row| {
                row.get(0)
            })?)
    }

    /// Fetch a single `ServicePresence` by `id`, or `None` if absent.
    pub fn fetch_service_presence(&self, id: &str) -> Result<Option<ServicePresence>> {
        let sql = "SELECT id, service_type_raw_value, is_present, needs_upload, upload_rejected, \
            rejected_at_build, is_submitted, last_confirmed_at, park_reference, \
            cloud_dirty_flag, qso_id \
            FROM service_presence WHERE id = ?";
        Ok(self
            .conn
            .query_row(sql, params![id], Self::row_to_service_presence)
            .optional()?)
    }

    /// Bounded, paginated fetch with optional filters.
    /// `limit` must be ≤ [`MAX_FETCH_LIMIT`].
    pub fn fetch_service_presences(
        &self,
        filter: &ServicePresenceFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<ServicePresence>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded {
                requested: limit,
                max: MAX_FETCH_LIMIT,
            });
        }

        let mut sql = String::from(
            "SELECT id, service_type_raw_value, is_present, needs_upload, upload_rejected, \
            rejected_at_build, is_submitted, last_confirmed_at, park_reference, \
            cloud_dirty_flag, qso_id \
            FROM service_presence WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(qso_id) = &filter.qso_id {
            sql.push_str(" AND qso_id = ?");
            args.push(Box::new(qso_id.clone()));
        }
        if let Some(stype) = &filter.service_type_raw_value {
            sql.push_str(" AND service_type_raw_value = ?");
            args.push(Box::new(stype.clone()));
        }
        if let Some(needs_upload) = filter.needs_upload {
            sql.push_str(" AND needs_upload = ?");
            args.push(Box::new(needs_upload as i64));
        }
        if filter.dirty_only {
            sql.push_str(" AND cloud_dirty_flag = 1");
        }
        sql.push_str(" ORDER BY last_confirmed_at DESC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_service_presence)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch every `service_presence` row whose `qso_id` is in `qso_ids`.
    /// Used to project per-QSO presence onto a Logbook query page in one round
    /// trip. Empty input returns an empty vec (guards an empty `IN ()`). No
    /// ordering is imposed — callers group by `qso_id` and sort for display.
    pub fn fetch_service_presences_for_qsos(
        &self,
        qso_ids: &[String],
    ) -> Result<Vec<ServicePresence>> {
        if qso_ids.is_empty() {
            return Ok(Vec::new());
        }
        let placeholders = vec!["?"; qso_ids.len()].join(",");
        let sql = format!(
            "SELECT id, service_type_raw_value, is_present, needs_upload, upload_rejected, \
            rejected_at_build, is_submitted, last_confirmed_at, park_reference, \
            cloud_dirty_flag, qso_id \
            FROM service_presence WHERE qso_id IN ({placeholders})"
        );
        let mut stmt = self.conn.prepare(&sql)?;
        let args: Vec<&dyn rusqlite::types::ToSql> = qso_ids
            .iter()
            .map(|id| id as &dyn rusqlite::types::ToSql)
            .collect();
        let rows = stmt.query_map(args.as_slice(), Self::row_to_service_presence)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Delete a `service_presence` row by id. Idempotent — deleting a missing
    /// id succeeds (mirrors the QSO delete path the live mirror relies on).
    pub fn delete_service_presence(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM service_presence WHERE id = ?1", params![id])?;
        Ok(())
    }

    fn row_to_service_presence(row: &rusqlite::Row<'_>) -> rusqlite::Result<ServicePresence> {
        Ok(ServicePresence {
            id: row.get(0)?,
            service_type_raw_value: row.get(1)?,
            is_present: row.get::<_, i64>(2)? != 0,
            needs_upload: row.get::<_, i64>(3)? != 0,
            upload_rejected: row.get::<_, i64>(4)? != 0,
            rejected_at_build: row.get(5)?,
            is_submitted: row.get::<_, i64>(6)? != 0,
            last_confirmed_at: row.get(7)?,
            park_reference: row.get(8)?,
            cloud_dirty_flag: row.get::<_, i64>(9)? != 0,
            qso_id: row.get(10)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, stype: &str, qso_id: Option<&str>) -> ServicePresence {
        ServicePresence {
            id: id.to_string(),
            service_type_raw_value: stype.to_string(),
            is_present: true,
            needs_upload: false,
            upload_rejected: false,
            rejected_at_build: None,
            is_submitted: false,
            last_confirmed_at: Some(1_000_000),
            park_reference: Some("K-1234".to_string()),
            cloud_dirty_flag: false,
            qso_id: qso_id.map(|s| s.to_string()),
        }
    }

    #[test]
    fn upsert_count_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_service_presence(&sample("a", "qrz", Some("q1")))
            .unwrap();
        store
            .upsert_service_presence(&sample("b", "lotw", Some("q2")))
            .unwrap();
        assert_eq!(store.service_presence_count().unwrap(), 2);

        let result = store.fetch_service_presence("a").unwrap();
        assert!(result.is_some());
        let sp = result.unwrap();
        assert_eq!(sp.service_type_raw_value, "qrz");
        assert_eq!(sp.qso_id.as_deref(), Some("q1"));
    }

    #[test]
    fn fetch_with_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_service_presence(&sample("a", "qrz", Some("q1")))
            .unwrap();
        store
            .upsert_service_presence(&sample("b", "lotw", Some("q2")))
            .unwrap();

        let filter = ServicePresenceFilter {
            qso_id: Some("q1".into()),
            ..Default::default()
        };
        let rows = store.fetch_service_presences(&filter, 100, 0).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].id, "a");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_service_presence(&sample("a", "qrz", None))
            .unwrap();
        let mut updated = sample("a", "qrz", None);
        updated.is_present = false;
        updated.needs_upload = true;
        store.upsert_service_presence(&updated).unwrap();
        assert_eq!(store.service_presence_count().unwrap(), 1);
        let sp = store.fetch_service_presence("a").unwrap().unwrap();
        assert!(!sp.is_present);
        assert!(sp.needs_upload);
    }

    #[test]
    fn missing_id_returns_none() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(store
            .fetch_service_presence("no-such-id")
            .unwrap()
            .is_none());
    }

    #[test]
    fn fetch_limit_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_service_presences(&ServicePresenceFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn fetch_for_qsos_batches_by_qso_id() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_service_presence(&sample("a", "qrz", Some("q1"))).unwrap();
        store.upsert_service_presence(&sample("b", "lotw", Some("q1"))).unwrap();
        store.upsert_service_presence(&sample("c", "pota", Some("q2"))).unwrap();
        store.upsert_service_presence(&sample("d", "qrz", Some("q3"))).unwrap();

        // empty input → empty output (guards empty IN ())
        assert!(store.fetch_service_presences_for_qsos(&[]).unwrap().is_empty());

        let rows = store
            .fetch_service_presences_for_qsos(&["q1".to_string(), "q2".to_string()])
            .unwrap();
        assert_eq!(rows.len(), 3);
        let mut ids: Vec<&str> = rows.iter().map(|sp| sp.id.as_str()).collect();
        ids.sort_unstable();
        assert_eq!(ids, vec!["a", "b", "c"]);
    }

    #[test]
    fn delete_service_presence_removes_row_and_is_idempotent() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_service_presence(&sample("a", "qrz", Some("q1"))).unwrap();
        assert_eq!(store.service_presence_count().unwrap(), 1);

        store.delete_service_presence("a").unwrap();
        assert_eq!(store.service_presence_count().unwrap(), 0);
        // idempotent: deleting a missing id is not an error
        store.delete_service_presence("a").unwrap();
        assert_eq!(store.service_presence_count().unwrap(), 0);
    }
}
