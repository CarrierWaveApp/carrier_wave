//! FFI surface for `SessionSpot` (mirrors `cw-store`'s `SessionSpot`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{SessionSpot, SessionSpotFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiSessionSpot {
    pub id: String,
    pub logging_session_id: String,
    pub callsign: String,
    pub frequency_k_hz: f64,
    pub mode: String,
    pub timestamp: i64,
    pub source: String,
    pub snr: Option<i64>,
    pub wpm: Option<i64>,
    pub spotter: Option<String>,
    pub spotter_grid: Option<String>,
    pub park_ref: Option<String>,
    pub park_name: Option<String>,
    pub comments: Option<String>,
    pub region: String,
    pub distance_meters: Option<f64>,
    pub bearing_degrees: Option<f64>,
    pub cloud_dirty_flag: bool,
}

// ---------- Conversions ----------

impl From<SessionSpot> for FfiSessionSpot {
    fn from(x: SessionSpot) -> Self {
        FfiSessionSpot {
            id: x.id,
            logging_session_id: x.logging_session_id,
            callsign: x.callsign,
            frequency_k_hz: x.frequency_k_hz,
            mode: x.mode,
            timestamp: x.timestamp,
            source: x.source,
            snr: x.snr,
            wpm: x.wpm,
            spotter: x.spotter,
            spotter_grid: x.spotter_grid,
            park_ref: x.park_ref,
            park_name: x.park_name,
            comments: x.comments,
            region: x.region,
            distance_meters: x.distance_meters,
            bearing_degrees: x.bearing_degrees,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

impl From<FfiSessionSpot> for SessionSpot {
    fn from(x: FfiSessionSpot) -> Self {
        SessionSpot {
            id: x.id,
            logging_session_id: x.logging_session_id,
            callsign: x.callsign,
            frequency_k_hz: x.frequency_k_hz,
            mode: x.mode,
            timestamp: x.timestamp,
            source: x.source,
            snr: x.snr,
            wpm: x.wpm,
            spotter: x.spotter,
            spotter_grid: x.spotter_grid,
            park_ref: x.park_ref,
            park_name: x.park_name,
            comments: x.comments,
            region: x.region,
            distance_meters: x.distance_meters,
            bearing_degrees: x.bearing_degrees,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiSessionSpotFilter {
    pub logging_session_id: Option<String>,
    pub since: Option<i64>,
    pub dirty_only: bool,
}

impl From<FfiSessionSpotFilter> for SessionSpotFilter {
    fn from(f: FfiSessionSpotFilter) -> Self {
        SessionSpotFilter {
            logging_session_id: f.logging_session_id,
            since: f.since,
            dirty_only: f.dirty_only,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_session_spot(&self, item: FfiSessionSpot) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_session_spot(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::SessionSpot, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of session spots in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_session_spots(&self, items: Vec<FfiSessionSpot>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_session_spot(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::SessionSpot, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn session_spot_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.session_spot_count()?)
    }

    pub fn fetch_session_spots(
        &self,
        filter: FfiSessionSpotFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiSessionSpot>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_session_spots(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiSessionSpot::from).collect())
    }

    pub fn fetch_session_spot(&self, id: String) -> Result<Option<FfiSessionSpot>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_session_spot(&id)?.map(FfiSessionSpot::from))
    }

    pub fn delete_session_spot(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_session_spot(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::SessionSpot, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
