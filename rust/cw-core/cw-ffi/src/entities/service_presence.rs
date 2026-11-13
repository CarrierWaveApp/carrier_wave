//! FFI surface for `ServicePresence` (mirrors `cw-store`'s `ServicePresence`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{ServicePresence, ServicePresenceFilter};

// ---------- DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiServicePresence {
    pub id: String,
    pub service_type_raw_value: String,
    pub is_present: bool,
    pub needs_upload: bool,
    pub upload_rejected: bool,
    pub rejected_at_build: Option<String>,
    pub is_submitted: bool,
    pub last_confirmed_at: Option<i64>,
    pub park_reference: Option<String>,
    pub cloud_dirty_flag: bool,
    pub qso_id: Option<String>,
}

// ---------- Conversions ----------

impl From<ServicePresence> for FfiServicePresence {
    fn from(x: ServicePresence) -> Self {
        FfiServicePresence {
            id: x.id,
            service_type_raw_value: x.service_type_raw_value,
            is_present: x.is_present,
            needs_upload: x.needs_upload,
            upload_rejected: x.upload_rejected,
            rejected_at_build: x.rejected_at_build,
            is_submitted: x.is_submitted,
            last_confirmed_at: x.last_confirmed_at,
            park_reference: x.park_reference,
            cloud_dirty_flag: x.cloud_dirty_flag,
            qso_id: x.qso_id,
        }
    }
}

impl From<FfiServicePresence> for ServicePresence {
    fn from(x: FfiServicePresence) -> Self {
        ServicePresence {
            id: x.id,
            service_type_raw_value: x.service_type_raw_value,
            is_present: x.is_present,
            needs_upload: x.needs_upload,
            upload_rejected: x.upload_rejected,
            rejected_at_build: x.rejected_at_build,
            is_submitted: x.is_submitted,
            last_confirmed_at: x.last_confirmed_at,
            park_reference: x.park_reference,
            cloud_dirty_flag: x.cloud_dirty_flag,
            qso_id: x.qso_id,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiServicePresenceFilter {
    pub qso_id: Option<String>,
    pub service_type_raw_value: Option<String>,
    pub needs_upload: Option<bool>,
    pub dirty_only: bool,
}

impl From<FfiServicePresenceFilter> for ServicePresenceFilter {
    fn from(f: FfiServicePresenceFilter) -> Self {
        ServicePresenceFilter {
            qso_id: f.qso_id,
            service_type_raw_value: f.service_type_raw_value,
            needs_upload: f.needs_upload,
            dirty_only: f.dirty_only,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_service_presence(&self, item: FfiServicePresence) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_service_presence(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ServicePresence, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of service-presence rows in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_service_presences(&self, items: Vec<FfiServicePresence>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_service_presence(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ServicePresence, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn service_presence_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.service_presence_count()?)
    }

    pub fn fetch_service_presences(
        &self,
        filter: FfiServicePresenceFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiServicePresence>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_service_presences(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiServicePresence::from).collect())
    }

    pub fn fetch_service_presence(&self, id: String) -> Result<Option<FfiServicePresence>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_service_presence(&id)?.map(FfiServicePresence::from))
    }

    pub fn delete_service_presence(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_service_presence(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ServicePresence, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
