//! SOTA activation zones — GeoJSON polygons served by the activities
//! server's `POST /v1/sota/zones`, mirroring the iOS `SOTAZonesCache` disk
//! file. Zones accumulate across refreshes (the server computes them
//! lazily, so each pass may resolve summits that were pending before);
//! rows upsert rather than replace.

use crate::error::Result;
use crate::Store;
use rusqlite::{params, OptionalExtension};

/// One summit's activation zone.
#[derive(Debug, Clone, PartialEq)]
pub struct SotaZoneRow {
    /// Summit code, e.g. "W4C/CM-001".
    pub code: String,
    pub altitude_m: i64,
    /// The zone geometry as a GeoJSON `Polygon`/`MultiPolygon` string,
    /// verbatim from the server feature.
    pub geometry_geojson: String,
}

/// DDL for `sota_zone`.
pub(crate) const SOTA_ZONE_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS sota_zone (
    code             TEXT    NOT NULL PRIMARY KEY,
    altitude_m       INTEGER NOT NULL,
    geometry_geojson TEXT    NOT NULL
);
"#;

impl Store {
    /// Upsert a batch of zones in one transaction.
    pub fn upsert_sota_zones(&self, zones: &[SotaZoneRow]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        {
            let mut stmt = tx.prepare(
                r#"
                INSERT INTO sota_zone (code, altitude_m, geometry_geojson)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(code) DO UPDATE SET
                    altitude_m       = excluded.altitude_m,
                    geometry_geojson = excluded.geometry_geojson
                "#,
            )?;
            for zone in zones {
                stmt.execute(params![zone.code, zone.altitude_m, zone.geometry_geojson])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Total count of cached zones.
    pub fn sota_zone_count(&self) -> Result<i64> {
        Ok(self.conn.query_row("SELECT COUNT(*) FROM sota_zone", [], |row| row.get(0))?)
    }

    /// Fetch one summit's zone. Returns `None` if the server hasn't computed
    /// it (or it was never requested).
    pub fn fetch_sota_zone(&self, code: &str) -> Result<Option<SotaZoneRow>> {
        Ok(self
            .conn
            .query_row(
                "SELECT code, altitude_m, geometry_geojson FROM sota_zone WHERE code = ?1",
                params![code],
                |row| {
                    Ok(SotaZoneRow {
                        code: row.get(0)?,
                        altitude_m: row.get(1)?,
                        geometry_geojson: row.get(2)?,
                    })
                },
            )
            .optional()?)
    }

    /// Bounded, paginated fetch ordered by code — the host-cache hydration
    /// path. `limit` must be ≤ [`crate::MAX_FETCH_LIMIT`].
    pub fn fetch_sota_zones_page(&self, limit: i64, offset: i64) -> Result<Vec<SotaZoneRow>> {
        if limit > crate::MAX_FETCH_LIMIT {
            return Err(crate::StoreError::FetchLimitExceeded {
                requested: limit,
                max: crate::MAX_FETCH_LIMIT,
            });
        }
        let mut stmt = self.conn.prepare(
            "SELECT code, altitude_m, geometry_geojson FROM sota_zone \
             ORDER BY code LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], |row| {
            Ok(SotaZoneRow {
                code: row.get(0)?,
                altitude_m: row.get(1)?,
                geometry_geojson: row.get(2)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Codes that already have a cached zone — lets a refresh skip
    /// re-requesting resolved summits.
    pub fn sota_zone_codes(&self) -> Result<Vec<String>> {
        let mut stmt = self.conn.prepare("SELECT code FROM sota_zone")?;
        let rows = stmt.query_map([], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Fetch `(code, geometry_geojson)` for the codes in `codes` that have a
    /// cached zone. Pure cached read — no network. Codes not in the cache
    /// are simply absent from the result (same "absent means missing"
    /// semantics as `fetch_callbook_locations`); codes are matched verbatim,
    /// not case-folded (SOTA codes are already normalized).
    pub fn sota_zones_for_summits(&self, codes: &[String]) -> Result<Vec<(String, String)>> {
        if codes.is_empty() {
            return Ok(Vec::new());
        }

        let placeholders = std::iter::repeat("?").take(codes.len()).collect::<Vec<_>>().join(", ");
        let sql = format!(
            "SELECT code, geometry_geojson FROM sota_zone WHERE code IN ({placeholders})"
        );

        let mut stmt = self.conn.prepare(&sql)?;
        let args: Vec<&dyn rusqlite::types::ToSql> =
            codes.iter().map(|c| c as &dyn rusqlite::types::ToSql).collect();
        let rows = stmt.query_map(args.as_slice(), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    #[test]
    fn upsert_accumulates_across_batches() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_sota_zones(&[SotaZoneRow {
                code: "W4C/CM-001".to_string(),
                altitude_m: 2_037,
                geometry_geojson: r#"{"type":"Polygon","coordinates":[]}"#.to_string(),
            }])
            .unwrap();
        store
            .upsert_sota_zones(&[SotaZoneRow {
                code: "W4C/CM-002".to_string(),
                altitude_m: 1_800,
                geometry_geojson: r#"{"type":"MultiPolygon","coordinates":[]}"#.to_string(),
            }])
            .unwrap();
        assert_eq!(store.sota_zone_count().unwrap(), 2);
        let zone = store.fetch_sota_zone("W4C/CM-001").unwrap().unwrap();
        assert_eq!(zone.altitude_m, 2_037);
        let mut codes = store.sota_zone_codes().unwrap();
        codes.sort();
        assert_eq!(codes, vec!["W4C/CM-001", "W4C/CM-002"]);
    }

    #[test]
    fn zones_for_summits_returns_present_and_omits_absent() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_sota_zones(&[SotaZoneRow {
                code: "W4C/CM-001".to_string(),
                altitude_m: 2_037,
                geometry_geojson: r#"{"type":"Polygon","coordinates":[]}"#.to_string(),
            }])
            .unwrap();

        let result = store
            .sota_zones_for_summits(&["W4C/CM-001".to_string(), "W4C/CM-999".to_string()])
            .unwrap();
        assert_eq!(
            result,
            vec![("W4C/CM-001".to_string(), r#"{"type":"Polygon","coordinates":[]}"#.to_string())]
        );
    }

    #[test]
    fn zones_for_summits_empty_codes_returns_empty() {
        let store = Store::open_in_memory("k").unwrap();
        let result = store.sota_zones_for_summits(&[]).unwrap();
        assert!(result.is_empty());
    }
}
