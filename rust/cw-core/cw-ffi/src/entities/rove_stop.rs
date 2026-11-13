//! FFI surface for `RoveStop` (mirrors `cw-store`'s `rove_stop` table).
//!
//! Structured, portable replacement for the iOS Swift-`JSONEncoder` `[RoveStop]`
//! blob on `logging_session.rove_stops_data`. The host reads a session's stops
//! with `fetch_rove_stops` and writes them wholesale with `replace_rove_stops`
//! (the analogue of the iOS `roveStops` array setter). Timestamps cross as Unix
//! seconds — no 2001-reference-epoch doubles.

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::RoveStop;

// ---------- DTO ----------

#[derive(uniffi::Record, Clone)]
pub struct FfiRoveStop {
    pub id: String,
    pub logging_session_id: String,
    pub park_reference: String,
    /// Unix seconds, UTC.
    pub started_at: i64,
    /// Unix seconds, UTC. Nil while the stop is still open.
    pub ended_at: Option<i64>,
    pub my_grid: Option<String>,
    pub qso_count: i64,
    pub notes: Option<String>,
    pub cloud_dirty_flag: bool,
}

// ---------- Conversions ----------

impl From<RoveStop> for FfiRoveStop {
    fn from(x: RoveStop) -> Self {
        FfiRoveStop {
            id: x.id,
            logging_session_id: x.logging_session_id,
            park_reference: x.park_reference,
            started_at: x.started_at,
            ended_at: x.ended_at,
            my_grid: x.my_grid,
            qso_count: x.qso_count,
            notes: x.notes,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

impl From<FfiRoveStop> for RoveStop {
    fn from(x: FfiRoveStop) -> Self {
        RoveStop {
            id: x.id,
            logging_session_id: x.logging_session_id,
            park_reference: x.park_reference,
            started_at: x.started_at,
            ended_at: x.ended_at,
            my_grid: x.my_grid,
            qso_count: x.qso_count,
            notes: x.notes,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    /// The rove stops for a session, chronological.
    pub fn fetch_rove_stops(&self, logging_session_id: String) -> Result<Vec<FfiRoveStop>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .fetch_rove_stops(&logging_session_id)?
            .into_iter()
            .map(FfiRoveStop::from)
            .collect())
    }

    /// Insert or replace a single rove stop.
    pub fn upsert_rove_stop(&self, item: FfiRoveStop) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_rove_stop(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::RoveStop, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Replace a session's rove stops wholesale (the iOS `roveStops` setter): the
    /// session's existing stops are deleted, then `stops` inserted (each rebound
    /// to `logging_session_id`).
    pub fn replace_rove_stops(
        &self,
        logging_session_id: String,
        stops: Vec<FfiRoveStop>,
    ) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            let rows: Vec<RoveStop> = stops.into_iter().map(RoveStop::from).collect();
            store.replace_rove_stops(&logging_session_id, &rows)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::RoveStop, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Delete every rove stop for a session.
    pub fn delete_rove_stops_for_session(&self, logging_session_id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_rove_stops_for_session(&logging_session_id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::RoveStop, kind: FfiChangeKind::Delete });
        Ok(())
    }

    pub fn rove_stop_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.rove_stop_count()?)
    }
}
