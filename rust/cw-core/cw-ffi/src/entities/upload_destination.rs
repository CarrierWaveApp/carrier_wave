//! FFI surface for `UploadDestination` (mirrors `cw-store`'s `UploadDestination`).
//!
//! No filter type exists in cw-store for this entity — the list fetch takes only
//! `limit` and `offset` (the table is tiny; no filtering is needed).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::UploadDestination;

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiUploadDestination {
    pub id: String,
    pub type_raw_value: String,
    pub is_enabled: bool,
    pub last_sync_at: Option<i64>,
}

// ---------- Conversions ----------

impl From<UploadDestination> for FfiUploadDestination {
    fn from(x: UploadDestination) -> Self {
        FfiUploadDestination {
            id: x.id,
            type_raw_value: x.type_raw_value,
            is_enabled: x.is_enabled,
            last_sync_at: x.last_sync_at,
        }
    }
}

impl From<FfiUploadDestination> for UploadDestination {
    fn from(x: FfiUploadDestination) -> Self {
        UploadDestination {
            id: x.id,
            type_raw_value: x.type_raw_value,
            is_enabled: x.is_enabled,
            last_sync_at: x.last_sync_at,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_upload_destination(&self, item: FfiUploadDestination) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_upload_destination(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::UploadDestination, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of upload destinations in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_upload_destinations(&self, items: Vec<FfiUploadDestination>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_upload_destination(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::UploadDestination, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn upload_destination_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.upload_destination_count()?)
    }

    pub fn fetch_upload_destinations(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiUploadDestination>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_upload_destinations(limit, offset)?;
        Ok(rows.into_iter().map(FfiUploadDestination::from).collect())
    }

    pub fn fetch_upload_destination(
        &self,
        id: String,
    ) -> Result<Option<FfiUploadDestination>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_upload_destination(&id)?.map(FfiUploadDestination::from))
    }

    pub fn delete_upload_destination(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_upload_destination(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::UploadDestination, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
