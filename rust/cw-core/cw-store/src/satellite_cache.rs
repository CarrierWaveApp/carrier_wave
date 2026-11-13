//! Satellite reference-data cache: one raw wire-JSON blob per kind
//! (`tle` / `transmitters` / `amsat`), replacing the iOS `SatNOGSClient`
//! JSON disk caches (6 h max age, stale fallback on network failure — see
//! `SatNOGSClient.swift`). Reads return the row regardless of age: the TTL
//! decision belongs to the caller (`cw-ffi::satellite_api`) so degrade-to-
//! stale works. Local/observed only — not part of the cloud sync journal.

use crate::error::Result;
use crate::Store;
use rusqlite::{params, OptionalExtension};

/// iOS `SatNOGSClient.cacheMaxAge`.
pub const SATELLITE_CACHE_TTL_SECS: i64 = 6 * 3_600;

pub(crate) const SATELLITE_DATA_CACHE_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS satellite_data_cache (
    kind       TEXT PRIMARY KEY NOT NULL,  -- 'tle' | 'transmitters' | 'amsat'
    payload    TEXT NOT NULL,              -- wire-shaped JSON, verbatim
    fetched_at INTEGER NOT NULL            -- unix seconds
);
"#;

impl Store {
    pub fn upsert_satellite_data(&self, kind: &str, payload: &str, fetched_at: i64) -> Result<()> {
        self.conn.execute(
            "INSERT INTO satellite_data_cache (kind, payload, fetched_at)
             VALUES (?1, ?2, ?3)
             ON CONFLICT(kind) DO UPDATE SET
                 payload = excluded.payload, fetched_at = excluded.fetched_at",
            params![kind, payload, fetched_at],
        )?;
        Ok(())
    }

    /// The cached blob for a kind — any age; caller applies the TTL.
    pub fn fetch_satellite_data(&self, kind: &str) -> Result<Option<(String, i64)>> {
        Ok(self
            .conn
            .query_row(
                "SELECT payload, fetched_at FROM satellite_data_cache WHERE kind = ?1",
                params![kind],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_and_replaces_per_kind() {
        let store = Store::open_in_memory("k").unwrap();
        assert!(store.fetch_satellite_data("tle").unwrap().is_none());

        store.upsert_satellite_data("tle", "[1]", 100).unwrap();
        store.upsert_satellite_data("amsat", "[2]", 200).unwrap();
        assert_eq!(
            store.fetch_satellite_data("tle").unwrap(),
            Some(("[1]".to_string(), 100))
        );

        // Upsert replaces in place — one row per kind.
        store.upsert_satellite_data("tle", "[3]", 300).unwrap();
        assert_eq!(
            store.fetch_satellite_data("tle").unwrap(),
            Some(("[3]".to_string(), 300))
        );
        assert_eq!(
            store.fetch_satellite_data("amsat").unwrap(),
            Some(("[2]".to_string(), 200))
        );
    }

    /// v16→v17 upgrade path: drop the table, rewind, re-migrate, round-trip.
    #[test]
    fn migration_recreates_table_when_upgrading_from_v16() {
        let store = Store::open_in_memory("k").unwrap();
        store.conn.execute_batch("DROP TABLE satellite_data_cache;").unwrap();
        store.conn.pragma_update(None, "user_version", 16_i64).unwrap();

        crate::migrations::migrate(&store.conn).unwrap();

        let version: i64 =
            store.conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, crate::migrations::SCHEMA_VERSION);
        store.upsert_satellite_data("tle", "[]", 1).unwrap();
        assert!(store.fetch_satellite_data("tle").unwrap().is_some());
    }
}
