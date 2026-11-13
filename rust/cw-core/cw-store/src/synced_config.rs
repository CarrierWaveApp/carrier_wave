//! `SyncedConfig` entity — small, per-type configuration blobs that ride the
//! shared E2E sync dirty/push/pull journal (last-writer-wins on `modified_at`).
//!
//! Mirrors the `radio_macro.rs` synced-entity pattern: a `cloud_dirty_flag`
//! drives the journal, `modified_at` backs the CAR-245 "skip if locally newer"
//! guard, and the id column is the single-column primary key `clear_dirty`
//! lists. Unlike the local-only `sync_kv` bookkeeping table, these rows are a
//! registered synced entity (`syncedConfig`) so cross-device edits converge.
//!
//! Each `config_type` (e.g. `"bragSheet"`) is one logical config; the `id` is
//! derived from the `config_type` so a given config is a single, stable row.

use crate::error::Result;
use crate::Store;
use rusqlite::{params, OptionalExtension};

/// DDL for `synced_config`. Registered by the migration runner (schema v12).
pub(crate) const SYNCED_CONFIG_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS synced_config (
    id                TEXT    NOT NULL PRIMARY KEY,
    config_type       TEXT    NOT NULL,
    data              TEXT    NOT NULL,
    cloud_dirty_flag  INTEGER NOT NULL DEFAULT 0,
    modified_at       INTEGER
);
CREATE INDEX IF NOT EXISTS idx_synced_config_cloud_dirty_flag
    ON synced_config (cloud_dirty_flag);
CREATE UNIQUE INDEX IF NOT EXISTS idx_synced_config_config_type
    ON synced_config (config_type);
"#;

/// A single synced configuration row. `id` is derived from `config_type` (one
/// row per config type); `data` is an opaque JSON blob owned by the caller.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncedConfig {
    /// Primary key — the row's stable id (derived from `config_type`).
    pub id: String,
    /// Logical config identifier (e.g. `"bragSheet"`).
    pub config_type: String,
    /// Opaque JSON payload.
    pub data: String,
    /// Sync journal dirty flag.
    pub cloud_dirty_flag: bool,
    /// Unix seconds of the last local edit — LWW key + CAR-245 guard.
    pub modified_at: Option<i64>,
}

/// Derive the stable primary-key id for a `config_type`. A config type maps to
/// exactly one row, so the id is deterministic — every device computes the same
/// id for the same config, so LWW converges on the same row. The id is a fixed
/// `synced-config:` prefix plus the config type, so it is stable, unique per
/// type, and human-legible.
pub fn synced_config_id(config_type: &str) -> String {
    format!("synced-config:{config_type}")
}

impl Store {
    /// Insert or replace the row for `config_type` with `data`. When `mark_dirty`
    /// is true the row is flagged for the outbound journal; otherwise the flag is
    /// cleared (used by inbound apply so pulled rows don't re-push). The id is
    /// derived from `config_type`, so a given config is always a single row.
    pub fn upsert_synced_config(
        &self,
        config_type: &str,
        data: &str,
        modified_at: Option<i64>,
        mark_dirty: bool,
    ) -> Result<()> {
        let id = synced_config_id(config_type);
        self.conn.execute(
            r#"
            INSERT INTO synced_config (id, config_type, data, cloud_dirty_flag, modified_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(id) DO UPDATE SET
                config_type      = excluded.config_type,
                data             = excluded.data,
                cloud_dirty_flag = excluded.cloud_dirty_flag,
                modified_at      = excluded.modified_at
            "#,
            params![id, config_type, data, mark_dirty as i64, modified_at],
        )?;
        Ok(())
    }

    /// Fetch the `data` blob for `config_type`, or `None` if absent.
    pub fn fetch_synced_config(&self, config_type: &str) -> Result<Option<String>> {
        let mut stmt =
            self.conn.prepare("SELECT data FROM synced_config WHERE config_type = ?1")?;
        Ok(stmt.query_row(params![config_type], |row| row.get::<_, String>(0)).optional()?)
    }

    /// Fetch the full row for `config_type`, or `None` if absent.
    pub fn fetch_synced_config_row(&self, config_type: &str) -> Result<Option<SyncedConfig>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, config_type, data, cloud_dirty_flag, modified_at \
                 FROM synced_config WHERE config_type = ?1",
                params![config_type],
                Self::row_to_synced_config,
            )
            .optional()?)
    }

    /// Every row with `cloud_dirty_flag = 1` — the outbound gather list. Ordered
    /// by `config_type` for a stable, content-addressable payload.
    pub fn fetch_dirty_synced_configs(&self) -> Result<Vec<SyncedConfig>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, config_type, data, cloud_dirty_flag, modified_at \
             FROM synced_config WHERE cloud_dirty_flag = 1 ORDER BY config_type ASC",
        )?;
        let rows = stmt.query_map([], Self::row_to_synced_config)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_synced_config(row: &rusqlite::Row<'_>) -> rusqlite::Result<SyncedConfig> {
        Ok(SyncedConfig {
            id: row.get(0)?,
            config_type: row.get(1)?,
            data: row.get(2)?,
            cloud_dirty_flag: row.get::<_, i64>(3)? != 0,
            modified_at: row.get(4)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        assert_eq!(store.fetch_synced_config("bragSheet").unwrap(), None);
        store.upsert_synced_config("bragSheet", "{\"a\":1}", Some(100), true).unwrap();
        assert_eq!(store.fetch_synced_config("bragSheet").unwrap().as_deref(), Some("{\"a\":1}"));

        let row = store.fetch_synced_config_row("bragSheet").unwrap().unwrap();
        assert_eq!(row.config_type, "bragSheet");
        assert_eq!(row.data, "{\"a\":1}");
        assert!(row.cloud_dirty_flag);
        assert_eq!(row.modified_at, Some(100));
        assert_eq!(row.id, synced_config_id("bragSheet"));
    }

    #[test]
    fn upsert_replaces_same_config_type() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_synced_config("bragSheet", "old", Some(1), true).unwrap();
        store.upsert_synced_config("bragSheet", "new", Some(2), false).unwrap();
        assert_eq!(store.fetch_synced_config("bragSheet").unwrap().as_deref(), Some("new"));
        // A single row — one config type, one row.
        let count: i64 =
            store.conn.query_row("SELECT COUNT(*) FROM synced_config", [], |r| r.get(0)).unwrap();
        assert_eq!(count, 1);
        // mark_dirty=false cleared the flag on the second write.
        assert!(!store.fetch_synced_config_row("bragSheet").unwrap().unwrap().cloud_dirty_flag);
    }

    #[test]
    fn dirty_gather_returns_only_dirty_rows() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_synced_config("bragSheet", "d1", Some(1), true).unwrap();
        store.upsert_synced_config("other", "clean", Some(2), false).unwrap();

        let dirty = store.fetch_dirty_synced_configs().unwrap();
        assert_eq!(dirty.len(), 1);
        assert_eq!(dirty[0].config_type, "bragSheet");
    }

    #[test]
    fn clear_dirty_uses_the_registry_arm() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_synced_config("bragSheet", "d1", Some(1), true).unwrap();
        let id = synced_config_id("bragSheet");

        assert_eq!(store.clear_dirty("syncedConfig", &[id], None).unwrap(), 1);
        assert!(store.fetch_dirty_synced_configs().unwrap().is_empty());
    }

    #[test]
    fn clear_dirty_keeps_rows_modified_after_snapshot() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_synced_config("bragSheet", "edited", Some(200), true).unwrap();
        let id = synced_config_id("bragSheet");
        // Snapshot at t=100; the row was edited at t=200 → keep it dirty.
        assert_eq!(store.clear_dirty("syncedConfig", &[id], Some(100)).unwrap(), 0);
        assert_eq!(store.fetch_dirty_synced_configs().unwrap().len(), 1);
    }

    #[test]
    fn mark_all_dirty_marks_every_row() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_synced_config("bragSheet", "a", Some(1), false).unwrap();
        store.upsert_synced_config("other", "b", Some(2), false).unwrap();
        assert_eq!(store.mark_all_dirty("syncedConfig").unwrap(), 2);
        assert_eq!(store.fetch_dirty_synced_configs().unwrap().len(), 2);
    }
}
