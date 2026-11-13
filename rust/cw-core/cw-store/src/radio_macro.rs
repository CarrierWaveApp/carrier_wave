//! RadioMacro entity — mirrors CarrierWaveData/Macros/RadioMacro.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// A user-authored radio macro stored in the encrypted SQLite store.
///
/// Step and arg payloads are stored as JSON blobs; `format` is a schema version
/// that callers must check at decode time.  `tags_csv` and `applies_to_csv`
/// mirror the Swift CSV-encoding pattern.  `cloud_dirty_flag` drives the sync
/// journal: `true` means un-synced local changes.
/// `created_at` / `updated_at` are Unix-second timestamps.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RadioMacro {
    /// UUID string — unique primary key (`@Attribute(.unique)` in Swift).
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub macro_description: Option<String>,
    /// Comma-separated tag strings (e.g. "cw,contest").
    pub tags_csv: String,
    /// Comma-separated `RadioCommandProtocol` raw values.
    pub applies_to_csv: String,
    pub author: Option<String>,
    /// JSON-encoded `[RadioMacroArg]`.
    pub args_json: Vec<u8>,
    /// JSON-encoded `[RadioMacroStep]`.
    pub steps_json: Vec<u8>,
    /// JSON-encoded `RadioMacroCapabilities`.
    pub capabilities_json: Vec<u8>,
    /// JSON-encoded `RegistryRef?` (empty `Vec` when absent).
    pub registry_json: Vec<u8>,
    /// `RadioMacroDocument.currentFormat` version integer.
    pub format: i64,
    pub sort_order: i64,
    /// Unix seconds, UTC.
    pub created_at: i64,
    /// Unix seconds, UTC.
    pub updated_at: i64,
    pub tombstoned: bool,
    pub tombstone_reason: Option<String>,
    /// Sync journal dirty flag.
    pub cloud_dirty_flag: bool,
}

/// DDL for `radio_macro`.
pub(crate) const RADIO_MACRO_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS radio_macro (
    id                  TEXT    NOT NULL PRIMARY KEY,
    name                TEXT    NOT NULL,
    icon                TEXT,
    macro_description   TEXT,
    tags_csv            TEXT    NOT NULL,
    applies_to_csv      TEXT    NOT NULL,
    author              TEXT,
    args_json           BLOB    NOT NULL,
    steps_json          BLOB    NOT NULL,
    capabilities_json   BLOB    NOT NULL,
    registry_json       BLOB    NOT NULL,
    format              INTEGER NOT NULL,
    sort_order          INTEGER NOT NULL,
    created_at          INTEGER NOT NULL,
    updated_at          INTEGER NOT NULL,
    tombstoned          INTEGER NOT NULL DEFAULT 0,
    tombstone_reason    TEXT,
    cloud_dirty_flag    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_radio_macro_tombstoned
    ON radio_macro (tombstoned);
CREATE INDEX IF NOT EXISTS idx_radio_macro_cloud_dirty_flag
    ON radio_macro (cloud_dirty_flag);
CREATE INDEX IF NOT EXISTS idx_radio_macro_sort_order
    ON radio_macro (sort_order);
"#;

/// Filter parameters for [`Store::fetch_radio_macros`].
#[derive(Debug, Clone, Default)]
pub struct RadioMacroFilter {
    /// When `Some(true)`, return only tombstoned macros; `Some(false)` only live.
    pub tombstoned: Option<bool>,
    /// When `true`, return only rows where `cloud_dirty_flag = 1`.
    pub dirty_only: bool,
}

impl Store {
    /// Insert or replace a radio macro by `id`.
    pub fn upsert_radio_macro(&self, mac: &RadioMacro) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO radio_macro (
                id, name, icon, macro_description, tags_csv, applies_to_csv, author,
                args_json, steps_json, capabilities_json, registry_json,
                format, sort_order, created_at, updated_at,
                tombstoned, tombstone_reason, cloud_dirty_flag
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
            ON CONFLICT(id) DO UPDATE SET
                name              = excluded.name,
                icon              = excluded.icon,
                macro_description = excluded.macro_description,
                tags_csv          = excluded.tags_csv,
                applies_to_csv    = excluded.applies_to_csv,
                author            = excluded.author,
                args_json         = excluded.args_json,
                steps_json        = excluded.steps_json,
                capabilities_json = excluded.capabilities_json,
                registry_json     = excluded.registry_json,
                format            = excluded.format,
                sort_order        = excluded.sort_order,
                created_at        = excluded.created_at,
                updated_at        = excluded.updated_at,
                tombstoned        = excluded.tombstoned,
                tombstone_reason  = excluded.tombstone_reason,
                cloud_dirty_flag  = excluded.cloud_dirty_flag
            "#,
            params![
                mac.id,
                mac.name,
                mac.icon,
                mac.macro_description,
                mac.tags_csv,
                mac.applies_to_csv,
                mac.author,
                mac.args_json,
                mac.steps_json,
                mac.capabilities_json,
                mac.registry_json,
                mac.format,
                mac.sort_order,
                mac.created_at,
                mac.updated_at,
                mac.tombstoned as i64,
                mac.tombstone_reason,
                mac.cloud_dirty_flag as i64,
            ],
        )?;
        Ok(())
    }

    /// Total count of radio macros (including tombstoned).
    pub fn radio_macro_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM radio_macro", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch with optional tombstone / dirty filtering.
    pub fn fetch_radio_macros(
        &self,
        filter: &RadioMacroFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<RadioMacro>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT id, name, icon, macro_description, tags_csv, applies_to_csv, author, \
             args_json, steps_json, capabilities_json, registry_json, \
             format, sort_order, created_at, updated_at, \
             tombstoned, tombstone_reason, cloud_dirty_flag \
             FROM radio_macro WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(ts) = filter.tombstoned {
            sql.push_str(" AND tombstoned = ?");
            args.push(Box::new(ts as i64));
        }
        if filter.dirty_only {
            sql.push_str(" AND cloud_dirty_flag = 1");
        }
        sql.push_str(" ORDER BY sort_order ASC, created_at ASC LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_radio_macro)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single radio macro by `id`. Returns `None` if not found.
    /// Delete a `radio_macro` row by id. Idempotent — a missing id succeeds.
    pub fn delete_radio_macro(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM radio_macro WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_radio_macro(&self, id: &str) -> Result<Option<RadioMacro>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, name, icon, macro_description, tags_csv, applies_to_csv, author, \
                 args_json, steps_json, capabilities_json, registry_json, \
                 format, sort_order, created_at, updated_at, \
                 tombstoned, tombstone_reason, cloud_dirty_flag \
                 FROM radio_macro WHERE id = ?1",
                params![id],
                Self::row_to_radio_macro,
            )
            .optional()?)
    }

    fn row_to_radio_macro(row: &rusqlite::Row<'_>) -> rusqlite::Result<RadioMacro> {
        Ok(RadioMacro {
            id: row.get(0)?,
            name: row.get(1)?,
            icon: row.get(2)?,
            macro_description: row.get(3)?,
            tags_csv: row.get(4)?,
            applies_to_csv: row.get(5)?,
            author: row.get(6)?,
            args_json: row.get(7)?,
            steps_json: row.get(8)?,
            capabilities_json: row.get(9)?,
            registry_json: row.get(10)?,
            format: row.get(11)?,
            sort_order: row.get(12)?,
            created_at: row.get(13)?,
            updated_at: row.get(14)?,
            tombstoned: row.get::<_, i64>(15)? != 0,
            tombstone_reason: row.get(16)?,
            cloud_dirty_flag: row.get::<_, i64>(17)? != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, name: &str, sort_order: i64) -> RadioMacro {
        RadioMacro {
            id: id.to_string(),
            name: name.to_string(),
            icon: Some("antenna".to_string()),
            macro_description: None,
            tags_csv: "cw,contest".to_string(),
            applies_to_csv: "".to_string(),
            author: None,
            args_json: b"[]".to_vec(),
            steps_json: b"[]".to_vec(),
            capabilities_json: b"{}".to_vec(),
            registry_json: b"{}".to_vec(),
            format: 1,
            sort_order,
            created_at: 1_700_000_000,
            updated_at: 1_700_000_000,
            tombstoned: false,
            tombstone_reason: None,
            cloud_dirty_flag: false,
        }
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let mac = sample("m-1", "CQ FT8", 0);
        store.upsert_radio_macro(&mac).unwrap();
        let fetched = store.fetch_radio_macro("m-1").unwrap().unwrap();
        assert_eq!(fetched, mac);
    }

    #[test]
    fn count_and_tombstone_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_radio_macro(&sample("m-1", "Live", 0)).unwrap();
        let mut dead = sample("m-2", "Dead", 1);
        dead.tombstoned = true;
        dead.tombstone_reason = Some("replaced".to_string());
        store.upsert_radio_macro(&dead).unwrap();
        assert_eq!(store.radio_macro_count().unwrap(), 2);

        let live = store
            .fetch_radio_macros(
                &RadioMacroFilter { tombstoned: Some(false), ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(live.len(), 1);
        assert_eq!(live[0].id, "m-1");
    }

    #[test]
    fn dirty_only_filter() {
        let store = Store::open_in_memory("k").unwrap();
        let mut dirty = sample("m-1", "Dirty", 0);
        dirty.cloud_dirty_flag = true;
        store.upsert_radio_macro(&dirty).unwrap();
        store.upsert_radio_macro(&sample("m-2", "Clean", 1)).unwrap();

        let dirties = store
            .fetch_radio_macros(&RadioMacroFilter { dirty_only: true, ..Default::default() }, 100, 0)
            .unwrap();
        assert_eq!(dirties.len(), 1);
        assert_eq!(dirties[0].id, "m-1");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_radio_macro(&sample("m-1", "Old Name", 0)).unwrap();
        let mut updated = sample("m-1", "New Name", 0);
        updated.cloud_dirty_flag = true;
        store.upsert_radio_macro(&updated).unwrap();
        assert_eq!(store.radio_macro_count().unwrap(), 1);
        let fetched = store.fetch_radio_macro("m-1").unwrap().unwrap();
        assert_eq!(fetched.name, "New Name");
        assert!(fetched.cloud_dirty_flag);
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_radio_macros(&RadioMacroFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
