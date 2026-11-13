//! FFI surface for `pota_park` reference data (mirrors `cw-store`'s `PotaPark`).
//!
//! Unlike the other modules here this is **not** a synced `@Model` — it is
//! reference data downloaded from pota.app and written through to cw-store so the
//! Rust POTA-awards aggregate can resolve `qso.park` → states without the Swift
//! `POTAParksCache`. No observation `notify` fires: nothing in the app `@Query`s
//! this table, and the write-through happens off the sync path.

use crate::{CwError, FieldStore};
use cw_store::PotaPark;

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiPotaPark {
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

// ---------- Conversions ----------

impl From<PotaPark> for FfiPotaPark {
    fn from(x: PotaPark) -> Self {
        FfiPotaPark {
            reference: x.reference,
            name: x.name,
            location_desc: x.location_desc,
            latitude: x.latitude,
            longitude: x.longitude,
            grid: x.grid,
            entity_id: x.entity_id,
            is_active: x.is_active,
        }
    }
}

impl From<FfiPotaPark> for PotaPark {
    fn from(x: FfiPotaPark) -> Self {
        PotaPark {
            reference: x.reference,
            name: x.name,
            location_desc: x.location_desc,
            latitude: x.latitude,
            longitude: x.longitude,
            grid: x.grid,
            entity_id: x.entity_id,
            is_active: x.is_active,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    /// Insert-or-replace a batch of parks in a single transaction. The
    /// `POTAParksCache` download writes tens of thousands of rows, so the batch
    /// commits atomically. No `notify` — reference data, off the sync path.
    pub fn upsert_pota_parks(&self, parks: Vec<FfiPotaPark>) -> Result<(), CwError> {
        let rows: Vec<PotaPark> = parks.into_iter().map(PotaPark::from).collect();
        let store = self.inner.lock().expect("store mutex poisoned");
        store.upsert_pota_parks(&rows)?;
        Ok(())
    }

    /// Total count of cached parks — lets the write-through skip a redundant
    /// download when the table is already populated.
    pub fn pota_park_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.pota_park_count()?)
    }

    /// Fetch a single park by reference. Returns `None` if not cached.
    pub fn fetch_pota_park(&self, reference: String) -> Result<Option<FfiPotaPark>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_pota_park(&reference)?.map(FfiPotaPark::from))
    }
}
