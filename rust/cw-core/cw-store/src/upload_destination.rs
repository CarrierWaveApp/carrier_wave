//! UploadDestination entity — mirrors CarrierWaveData/Models/UploadDestination.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// A configured upload destination (e.g. QRZ, LoTW, POTA).
///
/// `type_raw_value` stores the raw string of the `ServiceType` enum
/// (`@Attribute(originalName: "type")` in Swift — stored column is `type_raw_value`
/// on the Rust side to avoid the reserved word `type`).
/// `last_sync_at` is a Unix-second timestamp, optional until first sync.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UploadDestination {
    /// UUID string — primary key.
    pub id: String,
    /// Raw value of `ServiceType` enum (e.g. "qrz", "lotw", "pota").
    pub type_raw_value: String,
    pub is_enabled: bool,
    /// Unix seconds, UTC.
    pub last_sync_at: Option<i64>,
}

/// DDL for `upload_destination`.
pub(crate) const UPLOAD_DESTINATION_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS upload_destination (
    id              TEXT    NOT NULL PRIMARY KEY,
    type_raw_value  TEXT    NOT NULL,
    is_enabled      INTEGER NOT NULL DEFAULT 0,
    last_sync_at    INTEGER
);
CREATE INDEX IF NOT EXISTS idx_upload_destination_type_raw_value
    ON upload_destination (type_raw_value);
CREATE INDEX IF NOT EXISTS idx_upload_destination_is_enabled
    ON upload_destination (is_enabled);
"#;

impl Store {
    /// Insert or replace an upload destination by `id`.
    pub fn upsert_upload_destination(&self, dest: &UploadDestination) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO upload_destination (id, type_raw_value, is_enabled, last_sync_at)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(id) DO UPDATE SET
                type_raw_value = excluded.type_raw_value,
                is_enabled     = excluded.is_enabled,
                last_sync_at   = excluded.last_sync_at
            "#,
            params![
                dest.id,
                dest.type_raw_value,
                dest.is_enabled as i64,
                dest.last_sync_at,
            ],
        )?;
        Ok(())
    }

    /// Total count of upload destinations.
    pub fn upload_destination_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM upload_destination", [], |row| row.get(0))?)
    }

    /// Bounded fetch-all (table is tiny — no filter needed, but limit is still enforced).
    pub fn fetch_upload_destinations(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<UploadDestination>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let mut stmt = self.conn.prepare(
            "SELECT id, type_raw_value, is_enabled, last_sync_at \
             FROM upload_destination ORDER BY type_raw_value ASC LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_upload_destination)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single upload destination by `id`. Returns `None` if not found.
    /// Delete an `upload_destination` row by id. Idempotent — a missing id succeeds.
    pub fn delete_upload_destination(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM upload_destination WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_upload_destination(&self, id: &str) -> Result<Option<UploadDestination>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, type_raw_value, is_enabled, last_sync_at \
                 FROM upload_destination WHERE id = ?1",
                params![id],
                Self::row_to_upload_destination,
            )
            .optional()?)
    }

    fn row_to_upload_destination(row: &rusqlite::Row<'_>) -> rusqlite::Result<UploadDestination> {
        Ok(UploadDestination {
            id: row.get(0)?,
            type_raw_value: row.get(1)?,
            is_enabled: row.get::<_, i64>(2)? != 0,
            last_sync_at: row.get(3)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, type_raw: &str, enabled: bool) -> UploadDestination {
        UploadDestination {
            id: id.to_string(),
            type_raw_value: type_raw.to_string(),
            is_enabled: enabled,
            last_sync_at: None,
        }
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let dest = sample("d-1", "qrz", true);
        store.upsert_upload_destination(&dest).unwrap();
        let fetched = store.fetch_upload_destination("d-1").unwrap().unwrap();
        assert_eq!(fetched, dest);
    }

    #[test]
    fn count_and_fetch_all() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_upload_destination(&sample("d-1", "qrz", true)).unwrap();
        store.upsert_upload_destination(&sample("d-2", "lotw", false)).unwrap();
        assert_eq!(store.upload_destination_count().unwrap(), 2);

        let all = store.fetch_upload_destinations(100, 0).unwrap();
        assert_eq!(all.len(), 2);
        // Ordered by type_raw_value ASC → "lotw" before "qrz".
        assert_eq!(all[0].type_raw_value, "lotw");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_upload_destination(&sample("d-1", "qrz", false)).unwrap();
        let mut updated = sample("d-1", "qrz", true);
        updated.last_sync_at = Some(1_700_000_000);
        store.upsert_upload_destination(&updated).unwrap();
        assert_eq!(store.upload_destination_count().unwrap(), 1);
        let fetched = store.fetch_upload_destination("d-1").unwrap().unwrap();
        assert!(fetched.is_enabled);
        assert_eq!(fetched.last_sync_at, Some(1_700_000_000));
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store.fetch_upload_destinations(MAX_FETCH_LIMIT + 1, 0).unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
