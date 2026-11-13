//! SOTA summit reference data — mirrors the Swift `SOTASummit` model that
//! `SOTASummitsCache` parses from sotadata.org.uk's `summitslist.csv`.
//! Reference data, not a synced entity: a fresh download replaces the whole
//! table (expired summits are filtered at parse time and simply vanish).

use crate::error::Result;
use crate::Store;
use cw_domain::reference_csv::SotaSummitRow;
use rusqlite::{params, OptionalExtension};

/// DDL for `sota_summit`.
pub(crate) const SOTA_SUMMIT_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS sota_summit (
    code                 TEXT    NOT NULL PRIMARY KEY,
    name                 TEXT    NOT NULL,
    association_name     TEXT    NOT NULL,
    region_name          TEXT    NOT NULL,
    altitude_m           INTEGER NOT NULL,
    altitude_ft          INTEGER NOT NULL,
    latitude             REAL,
    longitude            REAL,
    points               INTEGER NOT NULL,
    bonus_points         INTEGER NOT NULL,
    activation_count     INTEGER NOT NULL,
    last_activation_date TEXT,
    last_activation_call TEXT,
    grid                 TEXT
);
"#;

impl Store {
    /// Replace the entire summit table with a fresh download (~180k rows) in
    /// one transaction.
    pub fn replace_sota_summits(&self, summits: &[SotaSummitRow]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute("DELETE FROM sota_summit", [])?;
        {
            let mut stmt = tx.prepare(
                r#"
                INSERT INTO sota_summit
                    (code, name, association_name, region_name, altitude_m, altitude_ft,
                     latitude, longitude, points, bonus_points, activation_count,
                     last_activation_date, last_activation_call, grid)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
                ON CONFLICT(code) DO UPDATE SET
                    name                 = excluded.name,
                    association_name     = excluded.association_name,
                    region_name          = excluded.region_name,
                    altitude_m           = excluded.altitude_m,
                    altitude_ft          = excluded.altitude_ft,
                    latitude             = excluded.latitude,
                    longitude            = excluded.longitude,
                    points               = excluded.points,
                    bonus_points         = excluded.bonus_points,
                    activation_count     = excluded.activation_count,
                    last_activation_date = excluded.last_activation_date,
                    last_activation_call = excluded.last_activation_call,
                    grid                 = excluded.grid
                "#,
            )?;
            for summit in summits {
                stmt.execute(params![
                    summit.code,
                    summit.name,
                    summit.association_name,
                    summit.region_name,
                    summit.altitude_m,
                    summit.altitude_ft,
                    summit.latitude,
                    summit.longitude,
                    summit.points,
                    summit.bonus_points,
                    summit.activation_count,
                    summit.last_activation_date,
                    summit.last_activation_call,
                    summit.grid,
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Total count of cached summits.
    pub fn sota_summit_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM sota_summit", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch ordered by code — the host-cache hydration
    /// path. `limit` must be ≤ [`crate::MAX_FETCH_LIMIT`].
    pub fn fetch_sota_summits_page(&self, limit: i64, offset: i64) -> Result<Vec<SotaSummitRow>> {
        if limit > crate::MAX_FETCH_LIMIT {
            return Err(crate::StoreError::FetchLimitExceeded {
                requested: limit,
                max: crate::MAX_FETCH_LIMIT,
            });
        }
        let mut stmt = self.conn.prepare(
            "SELECT code, name, association_name, region_name, altitude_m, altitude_ft, \
                    latitude, longitude, points, bonus_points, activation_count, \
                    last_activation_date, last_activation_call, grid \
             FROM sota_summit ORDER BY code LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_sota_summit)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Fetch a single summit by code. Returns `None` if not cached.
    pub fn fetch_sota_summit(&self, code: &str) -> Result<Option<SotaSummitRow>> {
        Ok(self
            .conn
            .query_row(
                "SELECT code, name, association_name, region_name, altitude_m, altitude_ft, \
                        latitude, longitude, points, bonus_points, activation_count, \
                        last_activation_date, last_activation_call, grid \
                 FROM sota_summit WHERE code = ?1",
                params![code],
                Self::row_to_sota_summit,
            )
            .optional()?)
    }

    /// Summits with coordinates inside a lat/lon bounding box, capped at `limit`.
    /// A cheap pre-filter for the map viewport query: the caller applies any
    /// exact radius/sort refinement in the geo layer, so the box just bounds
    /// how many rows this scan touches. Rows without coordinates are excluded.
    ///
    /// Ordered by `points DESC` (SOTA's own prominence score, derived from
    /// altitude banding — the natural "most notable summit" field), tiebroken
    /// by `code` for determinism, so a capped subset surfaces the
    /// highest-value summits first rather than an arbitrary row order.
    pub fn fetch_sota_summits_in_box(
        &self,
        min_lat: f64,
        max_lat: f64,
        min_lon: f64,
        max_lon: f64,
        limit: i64,
    ) -> Result<Vec<SotaSummitRow>> {
        let mut stmt = self.conn.prepare(
            "SELECT code, name, association_name, region_name, altitude_m, altitude_ft, \
                    latitude, longitude, points, bonus_points, activation_count, \
                    last_activation_date, last_activation_call, grid \
             FROM sota_summit \
             WHERE latitude IS NOT NULL AND longitude IS NOT NULL \
               AND latitude BETWEEN ?1 AND ?2 AND longitude BETWEEN ?3 AND ?4 \
             ORDER BY points DESC, code \
             LIMIT ?5",
        )?;
        let rows = stmt.query_map(
            params![min_lat, max_lat, min_lon, max_lon, limit],
            Self::row_to_sota_summit,
        )?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Stream every summit that has coordinates as `(code, lat, lon, altitude_m)` —
    /// the input the SOTA activation-zone bulk fetch needs.
    pub fn sota_summit_zone_inputs(&self) -> Result<Vec<(String, f64, f64, i64)>> {
        let mut stmt = self.conn.prepare(
            "SELECT code, latitude, longitude, altitude_m FROM sota_summit \
             WHERE latitude IS NOT NULL AND longitude IS NOT NULL",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    fn row_to_sota_summit(row: &rusqlite::Row<'_>) -> rusqlite::Result<SotaSummitRow> {
        Ok(SotaSummitRow {
            code: row.get(0)?,
            name: row.get(1)?,
            association_name: row.get(2)?,
            region_name: row.get(3)?,
            altitude_m: row.get(4)?,
            altitude_ft: row.get(5)?,
            latitude: row.get(6)?,
            longitude: row.get(7)?,
            points: row.get(8)?,
            bonus_points: row.get(9)?,
            activation_count: row.get(10)?,
            last_activation_date: row.get(11)?,
            last_activation_call: row.get(12)?,
            grid: row.get(13)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(code: &str) -> SotaSummitRow {
        SotaSummitRow {
            code: code.to_string(),
            name: "Mount Mitchell".to_string(),
            association_name: "USA - North Carolina".to_string(),
            region_name: "Western NC Mountains".to_string(),
            altitude_m: 2_037,
            altitude_ft: 6_684,
            latitude: Some(35.76),
            longitude: Some(-82.27),
            points: 10,
            bonus_points: 3,
            activation_count: 120,
            last_activation_date: Some("15/03/2024".to_string()),
            last_activation_call: Some("W6JY".to_string()),
            grid: None,
        }
    }

    #[test]
    fn replace_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store.replace_sota_summits(&[sample("W4C/CM-001"), sample("W4C/CM-002")]).unwrap();
        assert_eq!(store.sota_summit_count().unwrap(), 2);
        let summit = store.fetch_sota_summit("W4C/CM-001").unwrap().unwrap();
        assert_eq!(summit.points, 10);
        assert_eq!(summit.last_activation_call.as_deref(), Some("W6JY"));

        // A fresh download replaces everything — removed summits vanish.
        store.replace_sota_summits(&[sample("W4C/CM-002")]).unwrap();
        assert_eq!(store.sota_summit_count().unwrap(), 1);
        assert!(store.fetch_sota_summit("W4C/CM-001").unwrap().is_none());
    }

    #[test]
    fn zone_inputs_require_coordinates() {
        let store = Store::open_in_memory("k").unwrap();
        let mut no_coords = sample("W4C/CM-003");
        no_coords.latitude = None;
        no_coords.longitude = None;
        store.replace_sota_summits(&[sample("W4C/CM-001"), no_coords]).unwrap();
        let inputs = store.sota_summit_zone_inputs().unwrap();
        assert_eq!(inputs.len(), 1);
        assert_eq!(inputs[0].0, "W4C/CM-001");
        assert_eq!(inputs[0].3, 2_037);
    }

    #[test]
    fn fetch_in_box_includes_only_summits_inside_with_coordinates() {
        let store = Store::open_in_memory("k").unwrap();
        let mut inside = sample("W4C/CM-001");
        inside.latitude = Some(35.76);
        inside.longitude = Some(-82.27);
        let mut outside = sample("W4C/CM-002");
        outside.latitude = Some(50.0);
        outside.longitude = Some(-82.27);
        let mut no_coords = sample("W4C/CM-003");
        no_coords.latitude = None;
        no_coords.longitude = None;
        store.replace_sota_summits(&[inside, outside, no_coords]).unwrap();

        let rows = store
            .fetch_sota_summits_in_box(35.0, 36.0, -83.0, -82.0, 100)
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].code, "W4C/CM-001");
    }

    #[test]
    fn fetch_in_box_respects_limit() {
        let store = Store::open_in_memory("k").unwrap();
        let mut a = sample("W4C/CM-001");
        a.latitude = Some(35.76);
        a.longitude = Some(-82.27);
        let mut b = sample("W4C/CM-002");
        b.latitude = Some(35.80);
        b.longitude = Some(-82.30);
        store.replace_sota_summits(&[a, b]).unwrap();

        let rows = store
            .fetch_sota_summits_in_box(35.0, 36.0, -83.0, -82.0, 1)
            .unwrap();
        assert_eq!(rows.len(), 1);
    }

    /// The capped subset must be deterministic, not an arbitrary row order —
    /// `fetch_sota_summits_in_box` orders by `points DESC` (SOTA's own
    /// prominence score), tiebroken by `code`.
    #[test]
    fn fetch_in_box_orders_by_points_desc_then_code() {
        let store = Store::open_in_memory("k").unwrap();
        let mut low = sample("W4C/CM-002");
        low.points = 4;
        low.latitude = Some(35.76);
        low.longitude = Some(-82.27);
        let mut high = sample("W4C/CM-003");
        high.points = 10;
        high.latitude = Some(35.77);
        high.longitude = Some(-82.28);
        let mut tie_a = sample("W4C/CM-005");
        tie_a.points = 10;
        tie_a.latitude = Some(35.78);
        tie_a.longitude = Some(-82.29);
        let mut tie_b = sample("W4C/CM-001");
        tie_b.points = 10;
        tie_b.latitude = Some(35.79);
        tie_b.longitude = Some(-82.30);
        // Insert out of order to prove the ordering comes from the query.
        store.replace_sota_summits(&[low, high, tie_a, tie_b]).unwrap();

        let rows = store
            .fetch_sota_summits_in_box(35.0, 36.0, -83.0, -82.0, 100)
            .unwrap();
        let codes: Vec<&str> = rows.iter().map(|summit| summit.code.as_str()).collect();
        // points DESC first (the two 10-point summits before the 4-point one),
        // ties broken by code ascending.
        assert_eq!(codes, vec!["W4C/CM-001", "W4C/CM-003", "W4C/CM-005", "W4C/CM-002"]);
    }
}
