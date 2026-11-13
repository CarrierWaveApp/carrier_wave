//! WWFF reference directory — mirrors the Swift `WWFFReference` model that
//! `WWFFReferencesCache` parses from wwff.co's `wwff_directory.csv`. All
//! statuses are stored (active-only filtering happens at query time, like
//! iOS); a fresh download replaces the whole table.

use crate::error::Result;
use crate::Store;
use cw_domain::reference_csv::WwffReferenceRow;
use rusqlite::{params, OptionalExtension};

/// DDL for `wwff_reference`.
pub(crate) const WWFF_REFERENCE_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS wwff_reference (
    reference     TEXT NOT NULL PRIMARY KEY,
    name          TEXT NOT NULL,
    program       TEXT NOT NULL,
    status        TEXT NOT NULL,
    continent     TEXT,
    iota          TEXT,
    grid          TEXT,
    latitude      REAL,
    longitude     REAL,
    iucn_category TEXT,
    country       TEXT,
    region        TEXT,
    dxcc_entity   INTEGER
);
"#;

impl Store {
    /// Replace the entire directory with a fresh download (~60k rows) in one
    /// transaction.
    pub fn replace_wwff_references(&self, references: &[WwffReferenceRow]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute("DELETE FROM wwff_reference", [])?;
        {
            let mut stmt = tx.prepare(
                r#"
                INSERT INTO wwff_reference
                    (reference, name, program, status, continent, iota, grid,
                     latitude, longitude, iucn_category, country, region, dxcc_entity)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
                ON CONFLICT(reference) DO UPDATE SET
                    name          = excluded.name,
                    program       = excluded.program,
                    status        = excluded.status,
                    continent     = excluded.continent,
                    iota          = excluded.iota,
                    grid          = excluded.grid,
                    latitude      = excluded.latitude,
                    longitude     = excluded.longitude,
                    iucn_category = excluded.iucn_category,
                    country       = excluded.country,
                    region        = excluded.region,
                    dxcc_entity   = excluded.dxcc_entity
                "#,
            )?;
            for reference in references {
                stmt.execute(params![
                    reference.reference,
                    reference.name,
                    reference.program,
                    reference.status,
                    reference.continent,
                    reference.iota,
                    reference.grid,
                    reference.latitude,
                    reference.longitude,
                    reference.iucn_category,
                    reference.country,
                    reference.region,
                    reference.dxcc_entity,
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Total count of cached WWFF references (all statuses).
    pub fn wwff_reference_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM wwff_reference", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch ordered by reference — the host-cache
    /// hydration path. `limit` must be ≤ [`crate::MAX_FETCH_LIMIT`].
    pub fn fetch_wwff_references_page(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<WwffReferenceRow>> {
        if limit > crate::MAX_FETCH_LIMIT {
            return Err(crate::StoreError::FetchLimitExceeded {
                requested: limit,
                max: crate::MAX_FETCH_LIMIT,
            });
        }
        let mut stmt = self.conn.prepare(
            "SELECT reference, name, program, status, continent, iota, grid, \
                    latitude, longitude, iucn_category, country, region, dxcc_entity \
             FROM wwff_reference ORDER BY reference LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_wwff_reference)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Fetch a single reference by code. Returns `None` if not cached.
    pub fn fetch_wwff_reference(&self, reference: &str) -> Result<Option<WwffReferenceRow>> {
        Ok(self
            .conn
            .query_row(
                "SELECT reference, name, program, status, continent, iota, grid, \
                        latitude, longitude, iucn_category, country, region, dxcc_entity \
                 FROM wwff_reference WHERE reference = ?1",
                params![reference],
                Self::row_to_wwff_reference,
            )
            .optional()?)
    }

    /// References with coordinates inside a lat/lon bounding box, capped at
    /// `limit`. A cheap pre-filter for the map viewport query: the caller
    /// applies any exact radius/sort refinement in the geo layer, so the box
    /// just bounds how many rows this scan touches. Rows without coordinates
    /// are excluded.
    ///
    /// Ordered by `reference` (stable, deterministic) — `wwff_reference` has
    /// no popularity/activation-count column, so reference is the most
    /// sensible stable ordering for a capped subset.
    pub fn fetch_wwff_references_in_box(
        &self,
        min_lat: f64,
        max_lat: f64,
        min_lon: f64,
        max_lon: f64,
        limit: i64,
    ) -> Result<Vec<WwffReferenceRow>> {
        let mut stmt = self.conn.prepare(
            "SELECT reference, name, program, status, continent, iota, grid, \
                    latitude, longitude, iucn_category, country, region, dxcc_entity \
             FROM wwff_reference \
             WHERE latitude IS NOT NULL AND longitude IS NOT NULL \
               AND latitude BETWEEN ?1 AND ?2 AND longitude BETWEEN ?3 AND ?4 \
             ORDER BY reference \
             LIMIT ?5",
        )?;
        let rows = stmt.query_map(
            params![min_lat, max_lat, min_lon, max_lon, limit],
            Self::row_to_wwff_reference,
        )?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    fn row_to_wwff_reference(row: &rusqlite::Row<'_>) -> rusqlite::Result<WwffReferenceRow> {
        Ok(WwffReferenceRow {
            reference: row.get(0)?,
            name: row.get(1)?,
            program: row.get(2)?,
            status: row.get(3)?,
            continent: row.get(4)?,
            iota: row.get(5)?,
            grid: row.get(6)?,
            latitude: row.get(7)?,
            longitude: row.get(8)?,
            iucn_category: row.get(9)?,
            country: row.get(10)?,
            region: row.get(11)?,
            dxcc_entity: row.get(12)?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(reference: &str, status: &str) -> WwffReferenceRow {
        WwffReferenceRow {
            reference: reference.to_string(),
            name: "Yellowstone NP".to_string(),
            program: "KFF".to_string(),
            status: status.to_string(),
            continent: Some("NA".to_string()),
            iota: None,
            grid: Some("DN44".to_string()),
            latitude: Some(44.6),
            longitude: Some(-110.5),
            iucn_category: Some("II".to_string()),
            country: Some("United States".to_string()),
            region: Some("Wyoming".to_string()),
            dxcc_entity: Some(291),
        }
    }

    #[test]
    fn replace_and_fetch_keeps_all_statuses() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .replace_wwff_references(&[sample("KFF-0059", "active"), sample("KFF-9999", "deleted")])
            .unwrap();
        assert_eq!(store.wwff_reference_count().unwrap(), 2);
        let deleted = store.fetch_wwff_reference("KFF-9999").unwrap().unwrap();
        assert_eq!(deleted.status, "deleted");

        store.replace_wwff_references(&[sample("KFF-0059", "active")]).unwrap();
        assert_eq!(store.wwff_reference_count().unwrap(), 1);
        assert!(store.fetch_wwff_reference("KFF-9999").unwrap().is_none());
    }

    #[test]
    fn fetch_in_box_includes_only_references_inside_with_coordinates() {
        let store = Store::open_in_memory("k").unwrap();
        let mut inside = sample("KFF-0059", "active");
        inside.latitude = Some(44.6);
        inside.longitude = Some(-110.5);
        let mut outside = sample("KFF-0060", "active");
        outside.latitude = Some(10.0);
        outside.longitude = Some(-110.5);
        let mut no_coords = sample("KFF-0061", "active");
        no_coords.latitude = None;
        no_coords.longitude = None;
        store.replace_wwff_references(&[inside, outside, no_coords]).unwrap();

        let rows = store
            .fetch_wwff_references_in_box(44.0, 45.0, -111.0, -110.0, 100)
            .unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].reference, "KFF-0059");
    }

    #[test]
    fn fetch_in_box_respects_limit() {
        let store = Store::open_in_memory("k").unwrap();
        let mut a = sample("KFF-0059", "active");
        a.latitude = Some(44.6);
        a.longitude = Some(-110.5);
        let mut b = sample("KFF-0060", "active");
        b.latitude = Some(44.65);
        b.longitude = Some(-110.55);
        store.replace_wwff_references(&[a, b]).unwrap();

        let rows = store
            .fetch_wwff_references_in_box(44.0, 45.0, -111.0, -110.0, 1)
            .unwrap();
        assert_eq!(rows.len(), 1);
    }

    /// The capped subset must be deterministic, not an arbitrary row order —
    /// `fetch_wwff_references_in_box` orders by `reference` (the table has no
    /// popularity column).
    #[test]
    fn fetch_in_box_orders_by_reference() {
        let store = Store::open_in_memory("k").unwrap();
        let mut c = sample("KFF-0061", "active");
        c.latitude = Some(44.6);
        c.longitude = Some(-110.5);
        let mut a = sample("KFF-0059", "active");
        a.latitude = Some(44.61);
        a.longitude = Some(-110.51);
        let mut b = sample("KFF-0060", "active");
        b.latitude = Some(44.62);
        b.longitude = Some(-110.52);
        // Insert out of order to prove the ordering comes from the query, not
        // insertion order.
        store.replace_wwff_references(&[c, a, b]).unwrap();

        let rows = store
            .fetch_wwff_references_in_box(44.0, 45.0, -111.0, -110.0, 100)
            .unwrap();
        let refs: Vec<&str> = rows.iter().map(|wwff| wwff.reference.as_str()).collect();
        assert_eq!(refs, vec!["KFF-0059", "KFF-0060", "KFF-0061"]);
    }
}
