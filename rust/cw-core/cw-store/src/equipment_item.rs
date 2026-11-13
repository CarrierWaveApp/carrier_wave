//! EquipmentItem entity — mirrors CarrierWaveData/Models/EquipmentInventory.swift (`@Model class EquipmentItem`).

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// A piece of equipment in the user's inventory, linked to a catalog entry.
///
/// `bands_json` and `modes_json` hold JSON-encoded `[String]` arrays.
/// `bands_json` / `modes_json` are stored as BLOB (matching Swift `Data`).
/// `connection_profile_json` is an optional JSON blob encoding `RadioConnectionProfile`.
/// `category_raw_value` and `portability_raw_value` store enum raw string values.
/// `acquired_date` and `created_at` are Unix-second timestamps.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EquipmentItem {
    /// UUID string — primary key.
    pub id: String,
    pub catalog_id: String,
    pub catalog_name: String,
    /// Raw value of `EquipmentCategory` enum (e.g. "radio", "antenna", "accessory").
    pub category_raw_value: String,
    pub nickname: Option<String>,
    pub notes: Option<String>,
    /// Unix seconds, UTC. `nil` in Swift → `None` here.
    pub acquired_date: Option<i64>,
    pub is_retired: bool,
    /// JSON-encoded `[String]` band list (e.g. `["20m","40m"]`).
    pub bands_json: Vec<u8>,
    /// JSON-encoded `[String]` mode list (e.g. `["CW","SSB"]`).
    pub modes_json: Vec<u8>,
    pub max_power_watts: Option<i64>,
    /// Raw value of `PortabilityClass` enum (e.g. "portable", "mobile", "base").
    pub portability_raw_value: String,
    pub manufacturer: String,
    /// Unix seconds, UTC.
    pub created_at: i64,
    pub weight_ounces: Option<i64>,
    /// Optional JSON blob encoding `RadioConnectionProfile`.
    pub connection_profile_json: Option<Vec<u8>>,
}

/// DDL — create the table and supporting indexes.
pub(crate) const EQUIPMENT_ITEM_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS equipment_item (
    id                      TEXT    NOT NULL PRIMARY KEY,
    catalog_id              TEXT    NOT NULL,
    catalog_name            TEXT    NOT NULL,
    category_raw_value      TEXT    NOT NULL,
    nickname                TEXT,
    notes                   TEXT,
    acquired_date           INTEGER,
    is_retired              INTEGER NOT NULL DEFAULT 0,
    bands_json              BLOB    NOT NULL,
    modes_json              BLOB    NOT NULL,
    max_power_watts         INTEGER,
    portability_raw_value   TEXT    NOT NULL,
    manufacturer            TEXT    NOT NULL,
    created_at              INTEGER NOT NULL,
    weight_ounces           INTEGER,
    connection_profile_json BLOB
);
CREATE INDEX IF NOT EXISTS idx_equipment_item_catalog_id
    ON equipment_item (catalog_id);
CREATE INDEX IF NOT EXISTS idx_equipment_item_category_raw_value
    ON equipment_item (category_raw_value);
CREATE INDEX IF NOT EXISTS idx_equipment_item_is_retired
    ON equipment_item (is_retired);
"#;

/// Sort order for [`Store::fetch_equipment_items`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum EquipmentSort {
    /// Newest first (default — preserves the original behavior).
    #[default]
    CreatedAtDesc,
    /// Case-insensitive alphabetical by display name (nickname, else catalog
    /// name) — what the equipment picker wants.
    NameAsc,
}

/// Filter parameters for [`Store::fetch_equipment_items`].
#[derive(Debug, Clone, Default)]
pub struct EquipmentItemFilter {
    /// Match on `category_raw_value` (exact).
    pub category_raw_value: Option<String>,
    /// When `Some(true)`, return only retired items; `Some(false)` only active.
    pub is_retired: Option<bool>,
    /// Result ordering.
    pub sort: EquipmentSort,
}

impl Store {
    /// Insert or replace an equipment item by `id`.
    pub fn upsert_equipment_item(&self, item: &EquipmentItem) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO equipment_item (
                id, catalog_id, catalog_name, category_raw_value, nickname, notes,
                acquired_date, is_retired, bands_json, modes_json, max_power_watts,
                portability_raw_value, manufacturer, created_at, weight_ounces,
                connection_profile_json
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
            ON CONFLICT(id) DO UPDATE SET
                catalog_id              = excluded.catalog_id,
                catalog_name            = excluded.catalog_name,
                category_raw_value      = excluded.category_raw_value,
                nickname                = excluded.nickname,
                notes                   = excluded.notes,
                acquired_date           = excluded.acquired_date,
                is_retired              = excluded.is_retired,
                bands_json              = excluded.bands_json,
                modes_json              = excluded.modes_json,
                max_power_watts         = excluded.max_power_watts,
                portability_raw_value   = excluded.portability_raw_value,
                manufacturer            = excluded.manufacturer,
                created_at              = excluded.created_at,
                weight_ounces           = excluded.weight_ounces,
                connection_profile_json = excluded.connection_profile_json
            "#,
            params![
                item.id,
                item.catalog_id,
                item.catalog_name,
                item.category_raw_value,
                item.nickname,
                item.notes,
                item.acquired_date,
                item.is_retired as i64,
                item.bands_json,
                item.modes_json,
                item.max_power_watts,
                item.portability_raw_value,
                item.manufacturer,
                item.created_at,
                item.weight_ounces,
                item.connection_profile_json,
            ],
        )?;
        Ok(())
    }

    /// Total count of equipment items in the store.
    pub fn equipment_item_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM equipment_item", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch with optional category/retired filtering.
    pub fn fetch_equipment_items(
        &self,
        filter: &EquipmentItemFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<EquipmentItem>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }

        let mut sql = String::from(
            "SELECT id, catalog_id, catalog_name, category_raw_value, nickname, notes, \
             acquired_date, is_retired, bands_json, modes_json, max_power_watts, \
             portability_raw_value, manufacturer, created_at, weight_ounces, \
             connection_profile_json \
             FROM equipment_item WHERE 1=1",
        );
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();

        if let Some(cat) = &filter.category_raw_value {
            sql.push_str(" AND category_raw_value = ?");
            args.push(Box::new(cat.clone()));
        }
        if let Some(retired) = filter.is_retired {
            sql.push_str(" AND is_retired = ?");
            args.push(Box::new(retired as i64));
        }
        match filter.sort {
            EquipmentSort::CreatedAtDesc => sql.push_str(" ORDER BY created_at DESC"),
            EquipmentSort::NameAsc => {
                sql.push_str(" ORDER BY COALESCE(nickname, catalog_name) COLLATE NOCASE ASC");
            }
        }
        sql.push_str(" LIMIT ? OFFSET ?");
        args.push(Box::new(limit));
        args.push(Box::new(offset));

        let mut stmt = self.conn.prepare(&sql)?;
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();
        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_equipment_item)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single equipment item by `id`. Returns `None` if not found.
    /// Delete an `equipment_item` row by id. Idempotent — a missing id succeeds.
    pub fn delete_equipment_item(&self, id: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM equipment_item WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn fetch_equipment_item(&self, id: &str) -> Result<Option<EquipmentItem>> {
        Ok(self
            .conn
            .query_row(
                "SELECT id, catalog_id, catalog_name, category_raw_value, nickname, notes, \
                 acquired_date, is_retired, bands_json, modes_json, max_power_watts, \
                 portability_raw_value, manufacturer, created_at, weight_ounces, \
                 connection_profile_json \
                 FROM equipment_item WHERE id = ?1",
                params![id],
                Self::row_to_equipment_item,
            )
            .optional()?)
    }

    fn row_to_equipment_item(row: &rusqlite::Row<'_>) -> rusqlite::Result<EquipmentItem> {
        Ok(EquipmentItem {
            id: row.get(0)?,
            catalog_id: row.get(1)?,
            catalog_name: row.get(2)?,
            category_raw_value: row.get(3)?,
            nickname: row.get(4)?,
            notes: row.get(5)?,
            acquired_date: row.get(6)?,
            is_retired: row.get::<_, i64>(7)? != 0,
            bands_json: row.get(8)?,
            modes_json: row.get(9)?,
            max_power_watts: row.get(10)?,
            portability_raw_value: row.get(11)?,
            manufacturer: row.get(12)?,
            created_at: row.get(13)?,
            weight_ounces: row.get(14)?,
            connection_profile_json: row.get(15)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(id: &str, catalog_id: &str, category: &str) -> EquipmentItem {
        EquipmentItem {
            id: id.to_string(),
            catalog_id: catalog_id.to_string(),
            catalog_name: "IC-7300".to_string(),
            category_raw_value: category.to_string(),
            nickname: None,
            notes: None,
            acquired_date: None,
            is_retired: false,
            bands_json: b"[\"20m\",\"40m\"]".to_vec(),
            modes_json: b"[\"CW\",\"SSB\"]".to_vec(),
            max_power_watts: Some(100),
            portability_raw_value: "base".to_string(),
            manufacturer: "Icom".to_string(),
            created_at: 1_700_000_000,
            weight_ounces: Some(240),
            connection_profile_json: None,
        }
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let item = sample("id-1", "icom-ic7300", "radio");
        store.upsert_equipment_item(&item).unwrap();
        let fetched = store.fetch_equipment_item("id-1").unwrap().unwrap();
        assert_eq!(fetched, item);
    }

    #[test]
    fn count_and_filter() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_equipment_item(&sample("a", "cat-a", "radio")).unwrap();
        store.upsert_equipment_item(&sample("b", "cat-b", "antenna")).unwrap();
        assert_eq!(store.equipment_item_count().unwrap(), 2);

        let radios = store
            .fetch_equipment_items(
                &EquipmentItemFilter { category_raw_value: Some("radio".into()), ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(radios.len(), 1);
        assert_eq!(radios[0].id, "a");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_equipment_item(&sample("id-1", "cat-a", "radio")).unwrap();
        let mut updated = sample("id-1", "cat-a", "radio");
        updated.nickname = Some("My Rig".to_string());
        updated.is_retired = true;
        store.upsert_equipment_item(&updated).unwrap();
        assert_eq!(store.equipment_item_count().unwrap(), 1);
        let fetched = store.fetch_equipment_item("id-1").unwrap().unwrap();
        assert_eq!(fetched.nickname.as_deref(), Some("My Rig"));
        assert!(fetched.is_retired);
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store
            .fetch_equipment_items(&EquipmentItemFilter::default(), MAX_FETCH_LIMIT + 1, 0)
            .unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }

    #[test]
    fn name_asc_sort_is_alphabetical_case_insensitive() {
        let store = Store::open_in_memory("k").unwrap();
        // Insert out of alphabetical order; created_at ascending so default (desc)
        // order would be the reverse of alphabetical.
        let mut zebra = sample("z", "cat-z", "radio");
        zebra.catalog_name = "Zebra".into();
        zebra.created_at = 1;
        let mut apple = sample("a", "cat-a", "radio");
        apple.catalog_name = "apple".into(); // lowercase — NOCASE must still lead
        apple.created_at = 2;
        store.upsert_equipment_item(&zebra).unwrap();
        store.upsert_equipment_item(&apple).unwrap();

        let by_name = store
            .fetch_equipment_items(
                &EquipmentItemFilter { sort: EquipmentSort::NameAsc, ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(by_name.iter().map(|i| i.catalog_name.as_str()).collect::<Vec<_>>(), ["apple", "Zebra"]);

        // Nickname wins over catalog_name for display sort.
        let mut nick = sample("n", "cat-n", "radio");
        nick.catalog_name = "ZZZ".into();
        nick.nickname = Some("aaa".into());
        store.upsert_equipment_item(&nick).unwrap();
        let by_name = store
            .fetch_equipment_items(
                &EquipmentItemFilter { sort: EquipmentSort::NameAsc, ..Default::default() },
                100,
                0,
            )
            .unwrap();
        assert_eq!(by_name[0].id, "n"); // nickname "aaa" leads
    }
}
