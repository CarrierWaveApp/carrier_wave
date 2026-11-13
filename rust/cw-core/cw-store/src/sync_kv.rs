//! A tiny string key/value table for sync bookkeeping (ETags, cursors).
//!
//! Not a synced entity — purely local sync state the Rust core owns so the
//! host platforms don't each have to persist things like the clubs/membership
//! `ETag`s themselves.

use crate::error::Result;
use crate::Store;
use rusqlite::{params, OptionalExtension};

/// DDL for `sync_kv`. Registered by the migration runner.
pub(crate) const SYNC_KV_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS sync_kv (
    key   TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);
"#;

impl Store {
    /// Read a sync-state value, or `None` if the key is absent.
    pub fn kv_get(&self, key: &str) -> Result<Option<String>> {
        let mut stmt = self.conn.prepare("SELECT value FROM sync_kv WHERE key = ?1")?;
        Ok(stmt.query_row(params![key], |row| row.get::<_, String>(0)).optional()?)
    }

    /// Insert or replace a sync-state value.
    pub fn kv_set(&self, key: &str, value: &str) -> Result<()> {
        self.conn.execute(
            "INSERT INTO sync_kv (key, value) VALUES (?1, ?2) \
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    /// Delete a sync-state value. Idempotent.
    pub fn kv_delete(&self, key: &str) -> Result<()> {
        self.conn.execute("DELETE FROM sync_kv WHERE key = ?1", params![key])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn get_set_delete_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();
        assert_eq!(store.kv_get("clubs_etag").unwrap(), None);
        store.kv_set("clubs_etag", "\"clubs-1\"").unwrap();
        assert_eq!(store.kv_get("clubs_etag").unwrap().as_deref(), Some("\"clubs-1\""));
        store.kv_set("clubs_etag", "\"clubs-2\"").unwrap();
        assert_eq!(store.kv_get("clubs_etag").unwrap().as_deref(), Some("\"clubs-2\""));
        store.kv_delete("clubs_etag").unwrap();
        assert_eq!(store.kv_get("clubs_etag").unwrap(), None);
        // Idempotent delete.
        store.kv_delete("clubs_etag").unwrap();
    }
}
