//! `callbook_location` cache — batch QRZ/HamDB location lookups.
//! Replaces the iOS JSON-file cache backing the map's callsign→lat/lon
//! resolution. TTL-filtered fetch so stale rows are treated as absent
//! without needing a separate cleanup pass.

use crate::error::Result;
use crate::Store;
use rusqlite::params;

/// A cached callsign location, resolved via QRZ, HamDB, or grid-square
/// fallback.
#[derive(Debug, Clone, PartialEq)]
pub struct CallbookLocation {
    /// Uppercase, base call (skimmer suffix stripped by callers).
    pub callsign: String,
    pub latitude: f64,
    pub longitude: f64,
    pub grid: Option<String>,
    /// `"qrz"` | `"hamdb"` | `"grid"`.
    pub source: String,
    /// Unix seconds.
    pub fetched_at: i64,
}

/// DDL for the `callbook_location` table.
pub(crate) const CALLBOOK_LOCATION_DDL: &str = r#"
    CREATE TABLE IF NOT EXISTS callbook_location (
        callsign    TEXT PRIMARY KEY,
        latitude    REAL NOT NULL,
        longitude   REAL NOT NULL,
        grid        TEXT,
        source      TEXT NOT NULL,
        fetched_at  INTEGER NOT NULL
    );
"#;

impl Store {
    /// Insert or replace a cached callsign location. The callsign is
    /// uppercased on write so lookups can compare case-insensitively.
    pub fn upsert_callbook_location(&self, loc: &CallbookLocation) -> Result<()> {
        self.conn.execute(
            r#"
            INSERT INTO callbook_location (
                callsign, latitude, longitude, grid, source, fetched_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            ON CONFLICT(callsign) DO UPDATE SET
                latitude=excluded.latitude,
                longitude=excluded.longitude,
                grid=excluded.grid,
                source=excluded.source,
                fetched_at=excluded.fetched_at
            "#,
            params![
                loc.callsign.to_uppercase(),
                loc.latitude,
                loc.longitude,
                loc.grid,
                loc.source,
                loc.fetched_at,
            ],
        )?;
        Ok(())
    }

    /// Fetch cached locations for `callsigns` (matched case-insensitively)
    /// whose `fetched_at` is within the TTL window, i.e. `fetched_at > now -
    /// ttl_secs`. Callsigns with no row, or only an expired row, are simply
    /// absent from the result.
    pub fn fetch_callbook_locations(
        &self,
        callsigns: &[String],
        now: i64,
        ttl_secs: i64,
    ) -> Result<Vec<CallbookLocation>> {
        if callsigns.is_empty() {
            return Ok(Vec::new());
        }

        let placeholders = std::iter::repeat("UPPER(?)")
            .take(callsigns.len())
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "SELECT callsign, latitude, longitude, grid, source, fetched_at \
             FROM callbook_location \
             WHERE callsign IN ({placeholders}) AND fetched_at > ?"
        );

        let mut stmt = self.conn.prepare(&sql)?;
        let mut args: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        for call in callsigns {
            args.push(Box::new(call.to_uppercase()));
        }
        args.push(Box::new(now - ttl_secs));
        let arg_refs: Vec<&dyn rusqlite::types::ToSql> = args.iter().map(|b| b.as_ref()).collect();

        let rows = stmt.query_map(arg_refs.as_slice(), Self::row_to_callbook_location)?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_callbook_location(row: &rusqlite::Row<'_>) -> rusqlite::Result<CallbookLocation> {
        Ok(CallbookLocation {
            callsign: row.get(0)?,
            latitude: row.get(1)?,
            longitude: row.get(2)?,
            grid: row.get(3)?,
            source: row.get(4)?,
            fetched_at: row.get(5)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(callsign: &str, latitude: f64, fetched_at: i64) -> CallbookLocation {
        CallbookLocation {
            callsign: callsign.to_string(),
            latitude,
            longitude: -122.0,
            grid: Some("CM87".to_string()),
            source: "qrz".to_string(),
            fetched_at,
        }
    }

    #[test]
    fn upsert_and_fetch_roundtrip() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_callbook_location(&sample("W1AW", 41.7, 1_000)).unwrap();

        let rows = store
            .fetch_callbook_locations(&["w1aw".to_string()], 1_100, 3_600)
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].callsign, "W1AW");
        assert_eq!(rows[0].latitude, 41.7);
        assert_eq!(rows[0].longitude, -122.0);
        assert_eq!(rows[0].grid.as_deref(), Some("CM87"));
        assert_eq!(rows[0].source, "qrz");
        assert_eq!(rows[0].fetched_at, 1_000);
    }

    #[test]
    fn fetch_expires_by_ttl() {
        let store = Store::open_in_memory("k").unwrap();
        let now = 1_000_000_000_i64;
        let forty_days_ago = now - 40 * 24 * 3_600;
        store
            .upsert_callbook_location(&sample("K2ABC", 40.0, forty_days_ago))
            .unwrap();

        let thirty_day_ttl = 30 * 24 * 3_600;
        let rows = store
            .fetch_callbook_locations(&["K2ABC".to_string()], now, thirty_day_ttl)
            .unwrap();
        assert!(rows.is_empty(), "row older than TTL must not be returned");

        let sixty_day_ttl = 60 * 24 * 3_600;
        let rows = store
            .fetch_callbook_locations(&["K2ABC".to_string()], now, sixty_day_ttl)
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].callsign, "K2ABC");
    }

    #[test]
    fn upsert_replaces_existing() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_callbook_location(&sample("W6JY", 30.0, 1_000)).unwrap();
        store.upsert_callbook_location(&sample("W6JY", 35.5, 2_000)).unwrap();

        let rows = store
            .fetch_callbook_locations(&["W6JY".to_string()], 2_100, 3_600)
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].latitude, 35.5);
        assert_eq!(rows[0].fetched_at, 2_000);
    }

    /// Regression test for the v13 migration (`callbook_location`, added in
    /// eea82174): the fresh-DB path is exercised by every other test in this
    /// module via `open_in_memory`, but the v12→v13 *upgrade* path — an
    /// existing store that predates the table — was untested. Simulate a v12
    /// DB by dropping the table and rewinding `user_version`, then re-run the
    /// migration and confirm it's rebuilt and usable.
    #[test]
    fn migration_recreates_table_when_upgrading_from_v12() {
        let store = Store::open_in_memory("k").unwrap();

        // Roll back to a pre-v13 DB: drop the table this migration adds and
        // rewind user_version to 12, as if the store had never seen v13.
        store.conn.execute_batch("DROP TABLE callbook_location;").unwrap();
        store.conn.pragma_update(None, "user_version", 12_i64).unwrap();

        // Re-run the migration path the store uses on open.
        crate::migrations::migrate(&store.conn).unwrap();

        let version: i64 =
            store.conn.query_row("PRAGMA user_version", [], |row| row.get(0)).unwrap();
        assert_eq!(version, crate::migrations::SCHEMA_VERSION);

        // Round-trip through the table to confirm it's not just present but usable.
        store.upsert_callbook_location(&sample("N0CALL", 44.9, 5_000)).unwrap();
        let rows = store
            .fetch_callbook_locations(&["N0CALL".to_string()], 5_100, 3_600)
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].callsign, "N0CALL");
    }
}
