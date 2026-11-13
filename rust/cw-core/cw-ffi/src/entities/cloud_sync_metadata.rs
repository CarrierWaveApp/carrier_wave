//! FFI surface for `CloudSyncMetadata` (mirrors `cw-store`'s `CloudSyncMetadata`).
//!
//! The primary key is the composite `(entity_type, local_id)` — there is no single
//! UUID field. Two single-row fetch methods are exposed:
//!   - `fetch_cloud_sync_metadata(entity_type, local_id)` — by composite PK
//!   - `fetch_cloud_sync_metadata_by_record_name(record_name)` — by CK record name

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{CloudSyncMetadata, CloudSyncMetadataFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiCloudSyncMetadata {
    pub entity_type: String,
    pub local_id: String,
    pub record_name: String,
    pub encoded_system_fields: Option<Vec<u8>>,
    pub last_synced_at: Option<i64>,
}

// ---------- Conversions ----------

impl From<CloudSyncMetadata> for FfiCloudSyncMetadata {
    fn from(x: CloudSyncMetadata) -> Self {
        FfiCloudSyncMetadata {
            entity_type: x.entity_type,
            local_id: x.local_id,
            record_name: x.record_name,
            encoded_system_fields: x.encoded_system_fields,
            last_synced_at: x.last_synced_at,
        }
    }
}

impl From<FfiCloudSyncMetadata> for CloudSyncMetadata {
    fn from(x: FfiCloudSyncMetadata) -> Self {
        CloudSyncMetadata {
            entity_type: x.entity_type,
            local_id: x.local_id,
            record_name: x.record_name,
            encoded_system_fields: x.encoded_system_fields,
            last_synced_at: x.last_synced_at,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiCloudSyncMetadataFilter {
    pub entity_type: Option<String>,
}

impl From<FfiCloudSyncMetadataFilter> for CloudSyncMetadataFilter {
    fn from(f: FfiCloudSyncMetadataFilter) -> Self {
        CloudSyncMetadataFilter {
            entity_type: f.entity_type,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_cloud_sync_metadata(&self, item: FfiCloudSyncMetadata) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_cloud_sync_metadata(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::CloudSyncMetadata, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of cloud-sync-metadata rows in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_cloud_sync_metadata_batch(&self, items: Vec<FfiCloudSyncMetadata>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_cloud_sync_metadata(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::CloudSyncMetadata, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn cloud_sync_metadata_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.cloud_sync_metadata_count()?)
    }

    pub fn fetch_cloud_sync_metadatas(
        &self,
        filter: FfiCloudSyncMetadataFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiCloudSyncMetadata>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_cloud_sync_metadatas(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiCloudSyncMetadata::from).collect())
    }

    pub fn fetch_cloud_sync_metadata(
        &self,
        entity_type: String,
        local_id: String,
    ) -> Result<Option<FfiCloudSyncMetadata>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .fetch_cloud_sync_metadata(&entity_type, &local_id)?
            .map(FfiCloudSyncMetadata::from))
    }

    pub fn fetch_cloud_sync_metadata_by_record_name(
        &self,
        record_name: String,
    ) -> Result<Option<FfiCloudSyncMetadata>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store
            .fetch_cloud_sync_metadata_by_record_name(&record_name)?
            .map(FfiCloudSyncMetadata::from))
    }

    pub fn delete_cloud_sync_metadata(
        &self,
        entity_type: String,
        local_id: String,
    ) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_cloud_sync_metadata(&entity_type, &local_id)?;
        }
        self.notify(FfiStoreChange {
            table: FfiStoreTable::CloudSyncMetadata,
            kind: FfiChangeKind::Delete,
        });
        Ok(())
    }

    /// Delete every mapping row for one `entity_type` (the `resetForLocalWipe`
    /// teardown). Returns the number of rows removed.
    pub fn delete_cloud_sync_metadatas(&self, entity_type: String) -> Result<i64, CwError> {
        let removed = {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_cloud_sync_metadatas(&entity_type)?
        };
        self.notify(FfiStoreChange {
            table: FfiStoreTable::CloudSyncMetadata,
            kind: FfiChangeKind::Delete,
        });
        Ok(removed)
    }
}
