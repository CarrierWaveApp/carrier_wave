//! `gis_boundary_cache` — TTL-cached GeoJSON boundary geometry fetched from
//! the park/trail/admin boundary clients (see `cw-net::boundaries`), plus
//! SOTA activation zones. One row per `(kind, cache_key)`; `cache_key` is
//! whatever the caller's natural id is for that kind (park reference, trail
//! id, admin-region id, summit code) — never uppercased, since these are not
//! callsigns and case may be meaningful.
//!
//! All kinds share one TTL (boundaries change rarely). Cap enforcement
//! (`evict_gis`) is kind-specific and caller-driven: `"zone"` rows are
//! TTL-only in practice (SOTA zones are cheap and few), so callers should
//! either skip eviction for that kind or pass an effectively unbounded cap.

use crate::error::Result;
use crate::Store;
use rusqlite::params;

/// Shared TTL for all boundary kinds — 7 days. Boundaries (park/trail/admin
/// polygons, SOTA zones) change rarely, so a week-old cache entry is still
/// good.
pub const GIS_CACHE_TTL_SECS: i64 = 7 * 24 * 3_600;

/// Eviction cap for `"park"` boundary rows.
pub const GIS_CACHE_CAP_PARK: i64 = 150;
/// Eviction cap for `"trail"` boundary rows.
pub const GIS_CACHE_CAP_TRAIL: i64 = 100;
/// Eviction cap for `"admin"` boundary rows.
pub const GIS_CACHE_CAP_ADMIN: i64 = 150;

/// DDL for the `gis_boundary_cache` table.
pub(crate) const GIS_BOUNDARY_CACHE_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS gis_boundary_cache (
    kind        TEXT NOT NULL,
    cache_key   TEXT NOT NULL,
    geojson     TEXT NOT NULL,
    fetched_at  INTEGER NOT NULL,
    PRIMARY KEY (kind, cache_key)
);
"#;

impl Store {
    /// Insert or replace one cached boundary. `kind` is a short vocabulary
    /// string ("park" | "trail" | "admin" | "zone"); `cache_key` is the
    /// caller's natural id for that kind and is stored verbatim (not
    /// case-folded).
    pub fn upsert_gis(&self, kind: &str, cache_key: &str, geojson: &str, fetched_at: i64) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO gis_boundary_cache (kind, cache_key, geojson, fetched_at)
            VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(kind, cache_key) DO UPDATE SET
                geojson    = excluded.geojson,
                fetched_at = excluded.fetched_at
            "#,
            params![kind, cache_key, geojson, fetched_at],
        )?;
        Ok(())
    }

    /// Fetch cached `(cache_key, geojson)` pairs for `kind` where
    /// `cache_key` is in `keys` and `fetched_at` is within the TTL window,
    /// i.e. `fetched_at > now - ttl_secs`. Keys with no row, or only an
    /// expired row, are simply absent from the result.
    pub fn fetch_gis(
        &self,
        kind: &str,
        keys: &[String],
        now: i64,
        ttl_secs: i64,
    ) -> Result<Vec<(String, String)>> {
        if keys.is_empty() {
            return Ok(Vec::new());
        }

        let placeholders = std::iter::repeat("?").take(keys.len()).collect::<Vec<_>>().join(", ");
        let sql = format!(
            "SELECT cache_key, geojson FROM gis_boundary_cache \
             WHERE kind = ? AND cache_key IN ({placeholders}) AND fetched_at > ?"
        );

        let mut stmt = self.conn.prepare(&sql)?;
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        args.push(Box::new(kind.to_string()));
        for key in keys {
            args.push(Box::new(key.clone()));
        }
        args.push(Box::new(now - ttl_secs));
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();

        let rows = stmt.query_map(arg_refs.as_slice(), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Delete the oldest-`fetched_at` rows for `kind` beyond `cap`, keeping
    /// the `cap` most recently fetched rows. A no-op if `kind` has `cap` or
    /// fewer rows.
    pub fn evict_gis(&self, kind: &str, cap: i64) -> Result<()> {
        self.conn.execute(
            r#"
            DELETE FROM gis_boundary_cache
            WHERE kind = ?1 AND cache_key NOT IN (
                SELECT cache_key FROM gis_boundary_cache
                WHERE kind = ?1
                ORDER BY fetched_at DESC
                LIMIT ?2
            )
            "#,
            params![kind, cap],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    #[test]
    fn upsert_and_fetch_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_gis("park", "US-1234", r#"{"type":"Polygon"}"#, 1_000).unwrap();

        let rows = store
            .fetch_gis("park", &["US-1234".to_string()], 1_100, 3_600)
            .unwrap();
        assert_eq!(rows, vec![("US-1234".to_string(), r#"{"type":"Polygon"}"#.to_string())]);
    }

    #[test]
    fn fetch_is_scoped_to_kind() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_gis("park", "SAME-KEY", r#"{"type":"Park"}"#, 1_000).unwrap();
        store.upsert_gis("trail", "SAME-KEY", r#"{"type":"Trail"}"#, 1_000).unwrap();

        let rows = store.fetch_gis("park", &["SAME-KEY".to_string()], 1_100, 3_600).unwrap();
        assert_eq!(rows, vec![("SAME-KEY".to_string(), r#"{"type":"Park"}"#.to_string())]);
    }

    #[test]
    fn fetch_expires_by_ttl() {
        let store = Store::open_in_memory("k").unwrap();
        let now = 1_000_000_000_i64;
        let eight_days_ago = now - 8 * 24 * 3_600;
        store.upsert_gis("park", "US-1234", r#"{"type":"Polygon"}"#, eight_days_ago).unwrap();

        let rows = store
            .fetch_gis("park", &["US-1234".to_string()], now, GIS_CACHE_TTL_SECS)
            .unwrap();
        assert!(rows.is_empty(), "row older than TTL must not be returned");

        let ten_day_ttl = 10 * 24 * 3_600;
        let rows = store.fetch_gis("park", &["US-1234".to_string()], now, ten_day_ttl).unwrap();
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn upsert_replaces_existing() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_gis("park", "US-1234", r#"{"v":1}"#, 1_000).unwrap();
        store.upsert_gis("park", "US-1234", r#"{"v":2}"#, 2_000).unwrap();

        let rows = store.fetch_gis("park", &["US-1234".to_string()], 2_100, 3_600).unwrap();
        assert_eq!(rows, vec![("US-1234".to_string(), r#"{"v":2}"#.to_string())]);
    }

    #[test]
    fn cache_key_is_not_case_folded() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_gis("trail", "at-trail-01", r#"{"v":1}"#, 1_000).unwrap();

        // Different case is a different key — no case-insensitive matching.
        let rows = store.fetch_gis("trail", &["AT-TRAIL-01".to_string()], 1_100, 3_600).unwrap();
        assert!(rows.is_empty());

        let rows = store.fetch_gis("trail", &["at-trail-01".to_string()], 1_100, 3_600).unwrap();
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn evict_keeps_newest_cap_rows() {
        let store = Store::open_in_memory("k").unwrap();
        // Insert cap(=3)+2 rows with increasing fetched_at.
        for i in 0..5 {
            store
                .upsert_gis("park", &format!("US-{i:04}"), "{}", 1_000 + i)
                .unwrap();
        }
        store.evict_gis("park", 3).unwrap();

        let remaining = store
            .fetch_gis(
                "park",
                &(0..5).map(|i| format!("US-{i:04}")).collect::<Vec<_>>(),
                10_000,
                100_000,
            )
            .unwrap();
        assert_eq!(remaining.len(), 3);
        let mut keys: Vec<&str> = remaining.iter().map(|(k, _)| k.as_str()).collect();
        keys.sort();
        // The 3 newest (highest fetched_at) are US-0002, US-0003, US-0004.
        assert_eq!(keys, vec!["US-0002", "US-0003", "US-0004"]);
    }

    #[test]
    fn evict_does_not_touch_other_kinds() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_gis("park", "US-0001", "{}", 1_000).unwrap();
        store.upsert_gis("trail", "AT-01", "{}", 1_000).unwrap();
        store.evict_gis("park", 0).unwrap();

        assert!(store.fetch_gis("park", &["US-0001".to_string()], 10_000, 100_000).unwrap().is_empty());
        assert_eq!(
            store.fetch_gis("trail", &["AT-01".to_string()], 10_000, 100_000).unwrap().len(),
            1
        );
    }

    /// Regression test for the v14 migration (`gis_boundary_cache`): the
    /// fresh-DB path is exercised by every other test in this module via
    /// `open_in_memory`, but the v13→v14 *upgrade* path — an existing store
    /// that predates the table — was untested. Simulate a v13 DB by dropping
    /// the table and rewinding `user_version`, then re-run the migration and
    /// confirm it's rebuilt and usable. Modeled on
    /// `callbook_location::tests::migration_recreates_table_when_upgrading_from_v12`.
    #[test]
    fn migration_recreates_table_when_upgrading_from_v13() {
        let store = Store::open_in_memory("k").unwrap();

        // Roll back to a pre-v14 DB: drop the table this migration adds and
        // rewind user_version to 13, as if the store had never seen v14.
        store.conn.execute_batch("DROP TABLE gis_boundary_cache;").unwrap();
        store.conn.pragma_update(None, "user_version", 13_i64).unwrap();

        // Re-run the migration path the store uses on open.
        crate::migrations::migrate(&store.conn).unwrap();

        let version: i64 =
            store.conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, crate::migrations::SCHEMA_VERSION);

        // Round-trip through the table to confirm it's not just present but usable.
        store.upsert_gis("zone", "W4C/CM-001", r#"{"type":"Polygon"}"#, 5_000).unwrap();
        let rows = store.fetch_gis("zone", &["W4C/CM-001".to_string()], 5_100, 3_600).unwrap();
        assert_eq!(rows.len(), 1);
    }
}
