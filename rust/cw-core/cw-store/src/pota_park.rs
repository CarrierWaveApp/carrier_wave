//! POTA park reference data — mirrors CarrierWave/Services/POTAParksCache.swift's
//! `POTAPark`. Unlike the other tables this is **not** a synced `@Model`; it is
//! reference data downloaded from pota.app, written through to cw-store so Rust
//! aggregates (POTA awards / state rollups) can resolve `qso.park` → name/states
//! without the Swift cache. `location_desc` (e.g. "US-WY,US-MT") is the state source.

use crate::error::Result;
use crate::Store;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

/// Full park metadata. `reference` ("US-1234") is the natural primary key.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct PotaPark {
    pub reference: String,
    pub name: String,
    /// Region string, e.g. "US-WY" or multi-state "US-WY,US-MT". State source.
    pub location_desc: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    /// DXCC entity id (291 = USA).
    pub entity_id: i64,
    pub is_active: bool,
}

/// DDL for `pota_park`.
pub(crate) const POTA_PARK_DDL: &str = r#"
CREATE TABLE IF NOT EXISTS pota_park (
    reference     TEXT    NOT NULL PRIMARY KEY,
    name          TEXT    NOT NULL,
    location_desc TEXT    NOT NULL,
    latitude      REAL,
    longitude     REAL,
    grid          TEXT,
    entity_id     INTEGER NOT NULL,
    is_active     INTEGER NOT NULL
);
"#;

impl Store {
    /// Insert-or-replace a batch of parks in a single transaction. Used by the
    /// `POTAParksCache` download write-through (tens of thousands of rows), so the
    /// whole batch commits atomically and fast.
    pub fn upsert_pota_parks(&self, parks: &[PotaPark]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        Self::upsert_pota_parks_tx(&tx, parks)?;
        tx.commit()?;
        Ok(())
    }

    fn upsert_pota_parks_tx(
        tx: &rusqlite::Transaction<'_>,
        parks: &[PotaPark],
    ) -> Result<()> {
        {
            let mut stmt = tx.prepare(
                r#"
                INSERT INTO pota_park
                    (reference, name, location_desc, latitude, longitude, grid, entity_id, is_active)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                ON CONFLICT(reference) DO UPDATE SET
                    name          = excluded.name,
                    location_desc = excluded.location_desc,
                    latitude      = excluded.latitude,
                    longitude     = excluded.longitude,
                    grid          = excluded.grid,
                    entity_id     = excluded.entity_id,
                    is_active     = excluded.is_active
                "#,
            )?;
            for park in parks {
                stmt.execute(params![
                    park.reference,
                    park.name,
                    park.location_desc,
                    park.latitude,
                    park.longitude,
                    park.grid,
                    park.entity_id,
                    park.is_active as i64,
                ])?;
            }
        }
        Ok(())
    }

    /// Replace the entire park table with a fresh download in one
    /// transaction — the `ReferenceDataApi` path, where a full re-download is
    /// the source of truth and delisted references must vanish (the iOS
    /// write-through path keeps the non-destructive [`upsert_pota_parks`]).
    ///
    /// [`upsert_pota_parks`]: Store::upsert_pota_parks
    pub fn replace_pota_parks(&self, parks: &[PotaPark]) -> Result<()> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute("DELETE FROM pota_park", [])?;
        Self::upsert_pota_parks_tx(&tx, parks)?;
        tx.commit()?;
        Ok(())
    }

    /// Total count of cached parks.
    pub fn pota_park_count(&self) -> Result<i64> {
        Ok(self
            .conn
            .query_row("SELECT COUNT(*) FROM pota_park", [], |row| row.get(0))?)
    }

    /// Bounded, paginated fetch ordered by reference — the host-cache
    /// hydration path. `limit` must be ≤ [`crate::MAX_FETCH_LIMIT`].
    pub fn fetch_pota_parks_page(&self, limit: i64, offset: i64) -> Result<Vec<PotaPark>> {
        if limit > crate::MAX_FETCH_LIMIT {
            return Err(crate::StoreError::FetchLimitExceeded {
                requested: limit,
                max: crate::MAX_FETCH_LIMIT,
            });
        }
        let mut stmt = self.conn.prepare(
            "SELECT reference, name, location_desc, latitude, longitude, grid, entity_id, is_active \
             FROM pota_park ORDER BY reference LIMIT ?1 OFFSET ?2",
        )?;
        let rows = stmt.query_map(params![limit, offset], Self::row_to_pota_park)?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    /// Fetch a single park by reference. Returns `None` if not cached.
    pub fn fetch_pota_park(&self, reference: &str) -> Result<Option<PotaPark>> {
        Ok(self
            .conn
            .query_row(
                "SELECT reference, name, location_desc, latitude, longitude, grid, entity_id, is_active \
                 FROM pota_park WHERE reference = ?1",
                params![reference],
                Self::row_to_pota_park,
            )
            .optional()?)
    }

    /// Parks with coordinates inside a lat/lon bounding box, capped at `limit`.
    /// A cheap pre-filter for the nearby-park search: the caller applies the
    /// exact haversine radius + distance sort in the geo layer, so the box just
    /// bounds how many rows that scan touches. Rows without coordinates are
    /// excluded (they can't be ranked by distance anyway).
    ///
    /// Ordered by `reference` (stable, deterministic) — `pota_park` has no
    /// popularity/activation-count column of its own (that lives separately in
    /// QSO history via [`Store::park_activation_counts`]), so reference is the
    /// most sensible stable tiebreak for a capped subset. Callers that need
    /// activation-based ranking (e.g. `SessionWizardApi::suggest_park`) already
    /// re-rank the returned rows client-side and are order-independent.
    ///
    /// [`Store::park_activation_counts`]: Store::park_activation_counts
    pub fn fetch_pota_parks_in_box(
        &self,
        min_lat: f64,
        max_lat: f64,
        min_lon: f64,
        max_lon: f64,
        limit: i64,
    ) -> Result<Vec<PotaPark>> {
        let mut stmt = self.conn.prepare(
            "SELECT reference, name, location_desc, latitude, longitude, grid, entity_id, is_active \
             FROM pota_park \
             WHERE latitude IS NOT NULL AND longitude IS NOT NULL \
               AND latitude BETWEEN ?1 AND ?2 AND longitude BETWEEN ?3 AND ?4 \
             ORDER BY reference \
             LIMIT ?5",
        )?;
        let rows = stmt.query_map(
            params![min_lat, max_lat, min_lon, max_lon, limit],
            Self::row_to_pota_park,
        )?;
        Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?)
    }

    fn row_to_pota_park(row: &rusqlite::Row<'_>) -> rusqlite::Result<PotaPark> {
        Ok(PotaPark {
            reference: row.get(0)?,
            name: row.get(1)?,
            location_desc: row.get(2)?,
            latitude: row.get(3)?,
            longitude: row.get(4)?,
            grid: row.get(5)?,
            entity_id: row.get(6)?,
            is_active: row.get::<_, i64>(7)? != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Store;

    fn sample(reference: &str, location_desc: &str) -> PotaPark {
        PotaPark {
            reference: reference.to_string(),
            name: format!("{reference} Park"),
            location_desc: location_desc.to_string(),
            latitude: Some(44.5),
            longitude: Some(-110.5),
            grid: Some("DN44".to_string()),
            entity_id: 291,
            is_active: true,
        }
    }

    #[test]
    fn batch_upsert_and_fetch() {
        let store = Store::open_in_memory("k").unwrap();
        store
            .upsert_pota_parks(&[sample("US-0001", "US-WY"), sample("US-0002", "US-WY,US-MT")])
            .unwrap();
        assert_eq!(store.pota_park_count().unwrap(), 2);
        let park = store.fetch_pota_park("US-0002").unwrap().unwrap();
        assert_eq!(park.location_desc, "US-WY,US-MT");
        assert!(park.is_active);
        assert!(store.fetch_pota_park("US-9999").unwrap().is_none());
    }

    #[test]
    fn batch_upsert_replaces_existing() {
        let store = Store::open_in_memory("k").unwrap();
        store.upsert_pota_parks(&[sample("US-0001", "US-WY")]).unwrap();
        let mut updated = sample("US-0001", "US-CA");
        updated.is_active = false;
        store.upsert_pota_parks(&[updated]).unwrap();
        assert_eq!(store.pota_park_count().unwrap(), 1);
        let park = store.fetch_pota_park("US-0001").unwrap().unwrap();
        assert_eq!(park.location_desc, "US-CA");
        assert!(!park.is_active);
    }

    #[test]
    fn fetch_in_box_includes_only_parks_inside_with_coordinates() {
        let store = Store::open_in_memory("k").unwrap();
        let mut inside = sample("US-0001", "US-WY");
        inside.latitude = Some(44.6);
        inside.longitude = Some(-110.5);
        let mut outside = sample("US-0002", "US-WY");
        outside.latitude = Some(10.0);
        outside.longitude = Some(-110.5);
        let mut no_coords = sample("US-0003", "US-WY");
        no_coords.latitude = None;
        no_coords.longitude = None;
        store.upsert_pota_parks(&[inside, outside, no_coords]).unwrap();

        let rows = store.fetch_pota_parks_in_box(44.0, 45.0, -111.0, -110.0, 100).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].reference, "US-0001");
    }

    #[test]
    fn fetch_in_box_respects_limit() {
        let store = Store::open_in_memory("k").unwrap();
        let mut a = sample("US-0001", "US-WY");
        a.latitude = Some(44.6);
        a.longitude = Some(-110.5);
        let mut b = sample("US-0002", "US-WY");
        b.latitude = Some(44.65);
        b.longitude = Some(-110.55);
        store.upsert_pota_parks(&[a, b]).unwrap();

        let rows = store.fetch_pota_parks_in_box(44.0, 45.0, -111.0, -110.0, 1).unwrap();
        assert_eq!(rows.len(), 1);
    }

    /// The capped subset must be deterministic, not an arbitrary row order —
    /// `fetch_pota_parks_in_box` orders by `reference` (the table has no
    /// popularity column of its own).
    #[test]
    fn fetch_in_box_orders_by_reference() {
        let store = Store::open_in_memory("k").unwrap();
        let mut c = sample("US-0003", "US-WY");
        c.latitude = Some(44.6);
        c.longitude = Some(-110.5);
        let mut a = sample("US-0001", "US-WY");
        a.latitude = Some(44.61);
        a.longitude = Some(-110.51);
        let mut b = sample("US-0002", "US-WY");
        b.latitude = Some(44.62);
        b.longitude = Some(-110.52);
        // Insert out of order to prove the ordering comes from the query, not
        // insertion order.
        store.upsert_pota_parks(&[c, a, b]).unwrap();

        let rows = store.fetch_pota_parks_in_box(44.0, 45.0, -111.0, -110.0, 100).unwrap();
        let refs: Vec<&str> = rows.iter().map(|park| park.reference.as_str()).collect();
        assert_eq!(refs, vec!["US-0001", "US-0002", "US-0003"]);
    }
}
