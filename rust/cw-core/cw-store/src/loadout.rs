//! Loadout entity — a named, equipment-only station preset (radio/antenna/key/mic).
//!
//! The portable replacement for the iOS `SavedSessionTemplate` UserDefaults blob,
//! scoped to gear. A loadout is just a name plus up-to-four equipment display names
//! and an optional `radio_item_id` (an `equipment_item.id`) used to drive CAT
//! auto-connect. Local/observed only — not part of the cloud sync dirty journal.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// A named equipment preset. `radio`/`antenna`/`key`/`mic` are equipment display
/// names (nullable). `radio_item_id` links to an `equipment_item.id` for CAT.
/// `created_at`/`updated_at` are Unix-second timestamps, UTC.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Loadout {
    /// UUID string — primary key.
    pub id: String,
    pub name: String,
    pub radio: Option<String>,
    pub antenna: Option<String>,
    pub key: Option<String>,
    pub mic: Option<String>,
    /// `equipment_item.id` of the selected radio (for CAT auto-connect), if any.
    pub radio_item_id: Option<String>,
    /// Unix seconds, UTC.
    pub created_at: i64,
    /// Unix seconds, UTC.
    pub updated_at: i64,
}

/// DDL — create the table and supporting index.
pub(crate) const LOADOUT_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS loadout (
    id            TEXT    NOT NULL PRIMARY KEY,
    name          TEXT    NOT NULL,
    radio         TEXT,
    antenna       TEXT,
    key           TEXT,
    mic           TEXT,
    radio_item_id TEXT,
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_loadout_updated_at
    ON loadout (updated_at);
"#;

impl Store {
    /// Insert or replace a loadout by `id`.
    pub fn upsert_loadout(&self, item: &Loadout) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO loadout (
                id, name, radio, antenna, key, mic, radio_item_id, created_at, updated_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            ON CONFLICT(id) DO UPDATE SET
                name          = excluded.name,
                radio         = excluded.radio,
                antenna       = excluded.antenna,
                key           = excluded.key,
                mic           = excluded.mic,
                radio_item_id = excluded.radio_item_id,
                created_at    = excluded.created_at,
                updated_at    = excluded.updated_at
            "#,
            params![
                item.id,
                item.name,
                item.radio,
                item.antenna,
                item.key,
                item.mic,
                item.radio_item_id,
                item.created_at,
                item.updated_at,
            ],
        )?;
        Ok(())
    }

    /// Total count of loadouts in the store.
    pub fn loadout_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM loadout", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch, most-recently-edited first.
    pub fn fetch_loadouts(&self, limit: i64, offset: i64) -> Result<Vec<Loadout>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let mut stmt = self.conn.prepare(
            "SELECT id, name, radio, antenna, key, mic, radio_item_id, created_at, updated_at \
             FROM loadout ORDER BY updated_at DESC LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_loadout)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single loadout by `id`. Returns `None` if not found.
    pub fn fetch_loadout(&self, id: &str) -> Result<Option<Loadout>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, name, radio, antenna, key, mic, radio_item_id, created_at, updated_at \
                 FROM loadout WHERE id = ?1",
                params![id],
                Self::row_to_loadout,
            )
            .optional()?)
    }

    /// Delete a `loadout` row by id. Idempotent — a missing id succeeds.
    pub fn delete_loadout(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM loadout WHERE id = ?1", params![id])?;
        Ok(())
    }

    fn row_to_loadout(row: &rusqlite::Row<'_>) -> rusqlite::Result<Loadout> {
        Ok(Loadout {
            id: row.get(0)?,
            name: row.get(1)?,
            radio: row.get(2)?,
            antenna: row.get(3)?,
            key: row.get(4)?,
            mic: row.get(5)?,
            radio_item_id: row.get(6)?,
            created_at: row.get(7)?,
            updated_at: row.get(8)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, name: &str, updated_at: i64) -> Loadout {
        Loadout {
            id: id.to_string(),
            name: name.to_string(),
            radio: Some("KX2".to_string()),
            antenna: Some("EFHW 40-10".to_string()),
            key: Some("N0SA SOTA paddle".to_string()),
            mic: None,
            radio_item_id: Some("radio-uuid-1".to_string()),
            created_at: 1_700_000_000,
            updated_at,
        }
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let item = sample("id-1", "KX2 POTA", 1_700_000_100);
        store.upsert_loadout(&item).unwrap();
        let fetched = store.fetch_loadout("id-1").unwrap().unwrap();
        assert_eq!(fetched, item);
    }

    #[test]
    fn count_and_order_by_updated_desc() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_loadout(&sample("a", "Older", 1_700_000_100)).unwrap();
        store.upsert_loadout(&sample("b", "Newer", 1_700_000_200)).unwrap();
        assert_eq!(store.loadout_count().unwrap(), 2);
        let all = store.fetch_loadouts(100, 0).unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].id, "b"); // most-recently-edited first
        assert_eq!(all[1].id, "a");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_loadout(&sample("id-1", "KX2 POTA", 1_700_000_100)).unwrap();
        let mut updated = sample("id-1", "KX2 POTA", 1_700_000_100);
        updated.name = "Backpack CW".to_string();
        updated.antenna = None;
        store.upsert_loadout(&updated).unwrap();
        assert_eq!(store.loadout_count().unwrap(), 1);
        let fetched = store.fetch_loadout("id-1").unwrap().unwrap();
        assert_eq!(fetched.name, "Backpack CW");
        assert_eq!(fetched.antenna, None);
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store.fetch_loadouts(MAX_FETCH_LIMIT + 1, 0).unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn delete_is_idempotent() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_loadout(&sample("id-1", "KX2 POTA", 1_700_000_100)).unwrap();
        store.delete_loadout("id-1").unwrap();
        store.delete_loadout("id-1").unwrap(); // missing id → ok
        assert_eq!(store.loadout_count().unwrap(), 0);
    }
}
