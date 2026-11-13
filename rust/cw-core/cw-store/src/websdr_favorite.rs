//! WebSDRFavorite entity — mirrors CarrierWaveData/Models/WebSDRFavorite.swift.

use crate::error::{Result, StoreError};
use crate::qso::MAX_FETCH_LIMIT;
use crate::Store;
use rusqlite::params;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// A favorited KiwiSDR receiver, synced via iCloud.
///
/// Primary key is `host_port` (e.g. "kiwi.example.com:8073") — Swift uses
/// `hostPort` as the natural unique key with no separate UUID field.
/// `added_date` is a Unix-second timestamp.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WebSDRFavorite {
    /// "host:port" string — natural primary key (no UUID in Swift source).
    pub host_port: String,
    pub display_name: String,
    pub location: String,
    pub antenna: Option<String>,
    /// Unix seconds, UTC.
    pub added_date: i64,
}

/// DDL for `websdr_favorite`.
pub(crate) const WEBSDR_FAVORITE_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS websdr_favorite (
    host_port    TEXT    NOT NULL PRIMARY KEY,
    display_name TEXT    NOT NULL,
    location     TEXT    NOT NULL,
    antenna      TEXT,
    added_date   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_websdr_favorite_added_date
    ON websdr_favorite (added_date);
"#;

impl Store {
    /// Insert or replace a WebSDR favorite by `host_port`.
    pub fn upsert_websdr_favorite(&self, fav: &WebSDRFavorite) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO websdr_favorite (host_port, display_name, location, antenna, added_date)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(host_port) DO UPDATE SET
                display_name = excluded.display_name,
                location     = excluded.location,
                antenna      = excluded.antenna,
                added_date   = excluded.added_date
            "#,
            params![fav.host_port, fav.display_name, fav.location, fav.antenna, fav.added_date,],
        )?;
        Ok(())
    }

    /// Total count of WebSDR favorites.
    pub fn websdr_favorite_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM websdr_favorite", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch of all favorites ordered by `added_date` descending.
    pub fn fetch_websdr_favorites(&self, limit: i64, offset: i64) -> Result<Vec<WebSDRFavorite>> {
        if limit > MAX_FETCH_LIMIT {
            return Err(StoreError::FetchLimitExceeded { requested: limit, max: MAX_FETCH_LIMIT });
        }
        let mut stmt = self.conn.prepare(
            "SELECT host_port, display_name, location, antenna, added_date \
             FROM websdr_favorite ORDER BY added_date DESC LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_websdr_favorite)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Fetch a single favorite by `host_port`. Returns `None` if not found.
    /// Delete a `websdr_favorite` row by its `host_port` key. Idempotent.
    pub fn delete_websdr_favorite(&self, host_port: &str) -> Result<()> {
        self.conn
            .execute("DELETE FROM websdr_favorite WHERE host_port = ?1", params![host_port])?;
        Ok(())
    }

    pub fn fetch_websdr_favorite(&self, host_port: &str) -> Result<Option<WebSDRFavorite>> {
        Ok(self
            .conn
            .query_row(
                "SELECT host_port, display_name, location, antenna, added_date \
                 FROM websdr_favorite WHERE host_port = ?1",
                params![host_port],
                Self::row_to_websdr_favorite,
            )
            .optional()?)
    }

    fn row_to_websdr_favorite(row: &rusqlite::Row<'_>) -> rusqlite::Result<WebSDRFavorite> {
        Ok(WebSDRFavorite {
            host_port: row.get(0)?,
            display_name: row.get(1)?,
            location: row.get(2)?,
            antenna: row.get(3)?,
            added_date: row.get(4)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(host_port: &str, name: &str, added_date: i64) -> WebSDRFavorite {
        WebSDRFavorite {
            host_port: host_port.to_string(),
            display_name: name.to_string(),
            location: "California, USA".to_string(),
            antenna: Some("Vertical".to_string()),
            added_date,
        }
    }

    #[test]
    fn delete_by_host_port() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_websdr_favorite(&sample("a:8073", "Alpha", 1000)).unwrap();
        store.upsert_websdr_favorite(&sample("b:8073", "Beta", 2000)).unwrap();
        store.delete_websdr_favorite("a:8073").unwrap();
        assert_eq!(store.websdr_favorite_count().unwrap(), 1);
        assert!(store.fetch_websdr_favorite("a:8073").unwrap().is_none());
        assert!(store.fetch_websdr_favorite("b:8073").unwrap().is_some());
    }

    #[test]
    fn upsert_and_fetch_round_trip() {
        let store = Store::open_in_memory("k").unwrap();
        let fav = sample("kiwi.example.com:8073", "Example KiwiSDR", 1_700_000_000);
        store.upsert_websdr_favorite(&fav).unwrap();
        let fetched = store.fetch_websdr_favorite("kiwi.example.com:8073").unwrap().unwrap();
        assert_eq!(fetched, fav);
    }

    #[test]
    fn count_and_ordered_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_websdr_favorite(&sample("a:8073", "Alpha", 1000)).unwrap();
        store.upsert_websdr_favorite(&sample("b:8073", "Beta", 2000)).unwrap();
        assert_eq!(store.websdr_favorite_count().unwrap(), 2);

        let all = store.fetch_websdr_favorites(100, 0).unwrap();
        assert_eq!(all.len(), 2);
        // Newest first.
        assert_eq!(all[0].host_port, "b:8073");
    }

    #[test]
    fn upsert_replaces() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_websdr_favorite(&sample("h:8073", "Old Name", 1000)).unwrap();
        let mut updated = sample("h:8073", "New Name", 1000);
        updated.antenna = None;
        store.upsert_websdr_favorite(&updated).unwrap();
        assert_eq!(store.websdr_favorite_count().unwrap(), 1);
        let fetched = store.fetch_websdr_favorite("h:8073").unwrap().unwrap();
        assert_eq!(fetched.display_name, "New Name");
        assert!(fetched.antenna.is_none());
    }

    #[test]
    fn fetch_limit_is_enforced() {
        let store = Store::open_in_memory("k").unwrap();
        let err = store.fetch_websdr_favorites(MAX_FETCH_LIMIT + 1, 0).unwrap_err();
        assert!(matches!(err, StoreError::FetchLimitExceeded { .. }));
    }
}
