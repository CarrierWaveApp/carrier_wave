//! FFI surface for `ActivityLog` (mirrors `cw-store`'s `ActivityLog`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{ActivityLog, ActivityLogFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiActivityLog {
    pub id: String,
    pub name: String,
    pub my_callsign: String,
    pub created_at: i64,
    pub station_profile_id: Option<String>,
    pub current_grid: Option<String>,
    pub location_label: Option<String>,
    pub is_active: bool,
    pub cloud_dirty_flag: bool,
}

// ---------- Conversions ----------

impl From<ActivityLog> for FfiActivityLog {
    fn from(x: ActivityLog) -> Self {
        FfiActivityLog {
            id: x.id,
            name: x.name,
            my_callsign: x.my_callsign,
            created_at: x.created_at,
            station_profile_id: x.station_profile_id,
            current_grid: x.current_grid,
            location_label: x.location_label,
            is_active: x.is_active,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

impl From<FfiActivityLog> for ActivityLog {
    fn from(x: FfiActivityLog) -> Self {
        ActivityLog {
            id: x.id,
            name: x.name,
            my_callsign: x.my_callsign,
            created_at: x.created_at,
            station_profile_id: x.station_profile_id,
            current_grid: x.current_grid,
            location_label: x.location_label,
            is_active: x.is_active,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiActivityLogFilter {
    pub my_callsign: Option<String>,
    pub is_active: Option<bool>,
    pub dirty_only: bool,
}

impl From<FfiActivityLogFilter> for ActivityLogFilter {
    fn from(f: FfiActivityLogFilter) -> Self {
        ActivityLogFilter {
            my_callsign: f.my_callsign,
            is_active: f.is_active,
            dirty_only: f.dirty_only,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_activity_log(&self, item: FfiActivityLog) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_activity_log(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ActivityLog, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of activity logs in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_activity_logs(&self, items: Vec<FfiActivityLog>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_activity_log(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ActivityLog, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn activity_log_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.activity_log_count()?)
    }

    pub fn fetch_activity_logs(
        &self,
        filter: FfiActivityLogFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiActivityLog>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_activity_logs(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiActivityLog::from).collect())
    }

    pub fn fetch_activity_log(&self, id: String) -> Result<Option<FfiActivityLog>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_activity_log(&id)?.map(FfiActivityLog::from))
    }

    pub fn delete_activity_log(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_activity_log(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ActivityLog, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
