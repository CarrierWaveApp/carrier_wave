//! CloudSyncMetadata entity — mirrors CarrierWaveData/Models/CloudSyncMetadata.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// CloudKit sync bookkeeping record.
///
/// No single `@Attribute(.unique)` is declared in Swift source; the natural
/// composite uniqueness is `(entity_type, local_id)` — one CK record per
/// `(type, local UUID)` pair.  The DDL uses a `(entity_type, local_id)`
/// composite PRIMARY KEY.  `record_name` is the CKRecord name string from
/// CloudKit (unique per record in practice, indexed separately for fast lookup).
/// `encoded_system_fields` is the opaque CKRecord system-fields BLOB used by
/// the sync engine.
/// `last_synced_at` is a Unix-second timestamp, optional until first sync.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CloudSyncMetadata {
    /// Swift entity class name (e.g. "Qso", "RadioMacro").
    pub entity_type: String,
    /// UUID string of the local SwiftData record.
    pub local_id: String,
    /// CKRecord.recordName string.
    pub record_name: String,
    /// Opaque encoded CKRecord system fields blob.
    pub encoded_system_fields: Option<Vec<u8>>,
    /// Unix seconds, UTC.
    pub last_synced_at: Option<i64>,
}

/// DDL for `cloud_sync_metadata`.
///
/// Primary key is the composite `(entity_type, local_id)` — faithful to Swift
/// where there is no single unique field.  `record_name` gets its own unique
/// index because the sync engine looks up rows by CK record name on download.
pub(crate) const CLOUD_SYNC_METADATA_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS cloud_sync_metadata (
    entity_type           TEXT    NOT NULL,
    local_id              TEXT    NOT NULL,
    record_name           TEXT    NOT NULL,
    encoded_system_fields BLOB,
    last_synced_at        INTEGER,
    PRIMARY KEY (entity_type, local_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_cloud_sync_metadata_record_name
    ON cloud_sync_metadata (record_name);
CREATE INDEX IF NOT EXISTS idx_cloud_sync_metadata_entity_type
    ON cloud_sync_metadata (entity_type);
"#;

/// Filter parameters for [`Store::fetch_cloud_sync_metadatas`].
#[derive(Debug, Clone, Default)]
pub struct CloudSyncMetadataFilter {
    /// Restrict to a single entity type (e.g. "Qso").
    pub entity_type: Option<String>,
}

impl Store {
    /// Insert or replace a CloudSyncMetadata row by `(entity_type, local_id)`.
    pub fn upsert_cloud_sync_metadata(&self, meta: &CloudSyncMetadata) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO cloud_sync_metadata (
                entity_type, local_id, record_name, encoded_system_fields, last_synced_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(entity_type, local_id) DO UPDATE SET
                record_name           = excluded.record_name,
                encoded_system_fields = excluded.encoded_system_fields,
                last_synced_at        = excluded.last_synced_at
            "#,
            params![
                meta.entity_type,
                meta.local_id,
                meta.record_name,
                meta.encoded_system_fields,
                meta.last_synced_at,
            ],
        )?;
        Ok(())
    }

    /// Total count of cloud sync metadata rows.
    pub fn cloud_sync_metadata_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM cloud_sync_metadata", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch with optional entity-type filtering.
    pub fn fetch_cloud_sync_metadatas(
        &self,
        filter: &CloudSyncMetadataFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<CloudSyncMetadata>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT entity_type, local_id, record_name, encoded_system_fields, last_synced_at \
             FROM cloud_sync_metadata WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(et) = &filter.entity_type {
            sql.push_str(" AND entity_type = ?");
            args.push(Box::new(et.clone()));
        }
        sql.push_str(" ORDER BY entity_type ASC, local_id ASC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_cloud_sync_metadata)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single metadata row by `(entity_type, local_id)`. Returns `None` if not found.
    /// Delete a `cloud_sync_metadata` row by its `(entity_type, local_id)` key.
    /// Idempotent — a missing key succeeds.
    pub fn delete_cloud_sync_metadata(&self, entity_type: &str, local_id: &str) -> Result<()> {
        self.conn.execute(
            "DELETE FROM cloud_sync_metadata WHERE entity_type = ?1 AND local_id = ?2",
            params![entity_type, local_id],
        )?;
        Ok(())
    }

    /// Delete every `cloud_sync_metadata` row for one `entity_type`. Returns the
    /// number of rows removed. Backs `resetForLocalWipe`'s per-entity mapping
    /// teardown (drops the record-name↔id mappings so the next sync re-bootstraps).
    pub fn delete_cloud_sync_metadatas(&self, entity_type: &str) -> Result<i64> {
        let removed = self.conn.execute(
            "DELETE FROM cloud_sync_metadata WHERE entity_type = ?1",
            params![entity_type],
        )?;
        Ok(removed as i64)
    }

    pub fn fetch_cloud_sync_metadata(
        &self,
        entity_type: &str,
        local_id: &str,
    ) -> Result<Option<CloudSyncMetadata>> {
        Ok(self
            .conn
            .query_row(
                "SELECT entity_type, local_id, record_name, encoded_system_fields, last_synced_at \
                 FROM cloud_sync_metadata WHERE entity_type = ?1 AND local_id = ?2",
                params![entity_type, local_id],
                Self::row_to_cloud_sync_metadata,
            )
            .optional()?)
    }

    /// Fetch a metadata row by `record_name` (CloudKit record name). Returns `None` if not found.
    pub fn fetch_cloud_sync_metadata_by_record_name(
        &self,
        record_name: &str,
    ) -> Result<Option<CloudSyncMetadata>> {
        Ok(self
            .conn
            .query_row(
                "SELECT entity_type, local_id, record_name, encoded_system_fields, last_synced_at \
                 FROM cloud_sync_metadata WHERE record_name = ?1",
                params![record_name],
                Self::row_to_cloud_sync_metadata,
            )
            .optional()?)
    }

    fn row_to_cloud_sync_metadata(row: &rusqlite::Row<'_>) -> rusqlite::Result<CloudSyncMetadata> {
        Ok(CloudSyncMetadata {
            entity_type: row.get(0)?,
            local_id: row.get(1)?,
            record_name: row.get(2)?,
            encoded_system_fields: row.get(3)?,
            last_synced_at: row.get(4)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(entity_type: &str, local_id: &str, record_name: &str) -> CloudSyncMetadata {
        CloudSyncMetadata {
            entity_type: entity_type.to_string(),
            local_id: local_id.to_string(),
            record_name: record_name.to_string(),
            encoded_system_fields: None,
            last_synced_at: None,
        }
    }

    #[test]
    fn delete_by_composite_key() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_cloud_sync_metadata(&sample("Qso", "lu-1", "ck-1")).unwrap();
        store.upsert_cloud_sync_metadata(&sample("Qso", "lu-2", "ck-2")).unwrap();
        store.delete_cloud_sync_metadata("Qso", "lu-1").unwrap();
        assert!(store.fetch_cloud_sync_metadata("Qso", "lu-1").unwrap().is_none());
        assert!(store.fetch_cloud_sync_metadata("Qso", "lu-2").unwrap().is_some());
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let meta = sample("Qso", "local-uuid-1", "ck-record-abc");
        store.upsert_cloud_sync_metadata(&meta).unwrap();
        let fetched =
            store.fetch_cloud_sync_metadata("Qso", "local-uuid-1").unwrap().unwrap();
        assert_eq!(fetched, meta);
    }

    #[test]
    fn fetch_by_record_name() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_cloud_sync_metadata(&sample("RadioMacro", "lu-2", "ck-rm-001"))
            .unwrap();
        let fetched =
            store.fetch_cloud_sync_metadata_by_record_name("ck-rm-001").unwrap().unwrap();
        assert_eq!(fetched.entity_type, "RadioMacro");
        assert_eq!(fetched.local_id, "lu-2");
    }

    #[test]
    fn count_and_entity_type_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_cloud_sync_metadata(&sample("Qso", "lu-1", "ck-q-1")).unwrap();
        store.upsert_cloud_sync_metadata(&sample("Qso", "lu-2", "ck-q-2")).unwrap();
        store.upsert_cloud_sync_metadata(&sample("RadioMacro", "lu-3", "ck-m-1")).unwrap();
        assert_eq!(store.cloud_sync_metadata_count().unwrap(), 3);

        let qsos = store
            .fetch_cloud_sync_metadatas(
                &CloudSyncMetadataFilter { entity_type: Some("Qso".into()) },
                100,
                0,
            )
            .unwrap();
        assert_eq!(qsos.len(), 2);
    }

    #[test]
    fn delete_metadatas_by_entity_type() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_cloud_sync_metadata(&sample("Qso", "lu-1", "ck-q-1")).unwrap();
        store.upsert_cloud_sync_metadata(&sample("Qso", "lu-2", "ck-q-2")).unwrap();
        store.upsert_cloud_sync_metadata(&sample("RadioMacro", "lu-3", "ck-m-1")).unwrap();

        let removed = store.delete_cloud_sync_metadatas("Qso").unwrap();
        assert_eq!(removed, 2);
        assert_eq!(store.cloud_sync_metadata_count().unwrap(), 1);
        assert!(store.fetch_cloud_sync_metadata("RadioMacro", "lu-3").unwrap().is_some());

        // Idempotent — deleting an absent entity type removes nothing.
        assert_eq!(store.delete_cloud_sync_metadatas("Qso").unwrap(), 0);
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_cloud_sync_metadata(&sample("Qso", "lu-1", "ck-old"))
            .unwrap();
        let mut updated = sample("Qso", "lu-1", "ck-old");
        updated.last_synced_at = Some(1_700_000_000);
        updated.encoded_system_fields = Some(vec![0xDE, 0xAD]);
        store.upsert_cloud_sync_metadata(&updated).unwrap();
        assert_eq!(store.cloud_sync_metadata_count().unwrap(), 1);
        let fetched = store.fetch_cloud_sync_metadata("Qso", "lu-1").unwrap().unwrap();
        assert_eq!(fetched.last_synced_at, Some(1_700_000_000));
        assert_eq!(fetched.encoded_system_fields, Some(vec![0xDE, 0xAD]));
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_cloud_sync_metadatas(&CloudSyncMetadataFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
