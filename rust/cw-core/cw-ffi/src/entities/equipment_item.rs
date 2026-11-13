//! FFI surface for `EquipmentItem` (mirrors `cw-store`'s `EquipmentItem`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{EquipmentItem, EquipmentItemFilter, EquipmentSort};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiEquipmentItem {
    pub id: String,
    pub catalog_id: String,
    pub catalog_name: String,
    pub category_raw_value: String,
    pub nickname: Option<String>,
    pub notes: Option<String>,
    pub acquired_date: Option<i64>,
    pub is_retired: bool,
    pub bands_json: Vec<u8>,
    pub modes_json: Vec<u8>,
    pub max_power_watts: Option<i64>,
    pub portability_raw_value: String,
    pub manufacturer: String,
    pub created_at: i64,
    pub weight_ounces: Option<i64>,
    pub connection_profile_json: Option<Vec<u8>>,
}

// ---------- Conversions ----------

impl From<EquipmentItem> for FfiEquipmentItem {
    fn from(x: EquipmentItem) -> Self {
        FfiEquipmentItem {
            id: x.id,
            catalog_id: x.catalog_id,
            catalog_name: x.catalog_name,
            category_raw_value: x.category_raw_value,
            nickname: x.nickname,
            notes: x.notes,
            acquired_date: x.acquired_date,
            is_retired: x.is_retired,
            bands_json: x.bands_json,
            modes_json: x.modes_json,
            max_power_watts: x.max_power_watts,
            portability_raw_value: x.portability_raw_value,
            manufacturer: x.manufacturer,
            created_at: x.created_at,
            weight_ounces: x.weight_ounces,
            connection_profile_json: x.connection_profile_json,
        }
    }
}

impl From<FfiEquipmentItem> for EquipmentItem {
    fn from(x: FfiEquipmentItem) -> Self {
        EquipmentItem {
            id: x.id,
            catalog_id: x.catalog_id,
            catalog_name: x.catalog_name,
            category_raw_value: x.category_raw_value,
            nickname: x.nickname,
            notes: x.notes,
            acquired_date: x.acquired_date,
            is_retired: x.is_retired,
            bands_json: x.bands_json,
            modes_json: x.modes_json,
            max_power_watts: x.max_power_watts,
            portability_raw_value: x.portability_raw_value,
            manufacturer: x.manufacturer,
            created_at: x.created_at,
            weight_ounces: x.weight_ounces,
            connection_profile_json: x.connection_profile_json,
        }
    }
}

// ---------- Filter DTO ----------

/// Result ordering for [`FieldStore::fetch_equipment_items`].
#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Default)]
pub enum FfiEquipmentSort {
    /// Newest first (default).
    #[default]
    CreatedAtDesc,
    /// Case-insensitive alphabetical by display name.
    NameAsc,
}

impl From<FfiEquipmentSort> for EquipmentSort {
    fn from(sort: FfiEquipmentSort) -> Self {
        match sort {
            FfiEquipmentSort::CreatedAtDesc => EquipmentSort::CreatedAtDesc,
            FfiEquipmentSort::NameAsc => EquipmentSort::NameAsc,
        }
    }
}

#[derive(uniffi::Record, Default)]
pub struct FfiEquipmentItemFilter {
    pub category_raw_value: Option<String>,
    pub is_retired: Option<bool>,
    pub sort: FfiEquipmentSort,
}

impl From<FfiEquipmentItemFilter> for EquipmentItemFilter {
    fn from(f: FfiEquipmentItemFilter) -> Self {
        EquipmentItemFilter {
            category_raw_value: f.category_raw_value,
            is_retired: f.is_retired,
            sort: f.sort.into(),
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_equipment_item(&self, item: FfiEquipmentItem) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_equipment_item(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::EquipmentItem, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of equipment items in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_equipment_items(&self, items: Vec<FfiEquipmentItem>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_equipment_item(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::EquipmentItem, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn equipment_item_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.equipment_item_count()?)
    }

    pub fn fetch_equipment_items(
        &self,
        filter: FfiEquipmentItemFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiEquipmentItem>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_equipment_items(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiEquipmentItem::from).collect())
    }

    pub fn fetch_equipment_item(&self, id: String) -> Result<Option<FfiEquipmentItem>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_equipment_item(&id)?.map(FfiEquipmentItem::from))
    }

    pub fn delete_equipment_item(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_equipment_item(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::EquipmentItem, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
