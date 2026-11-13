//! FFI surface for `RadioMacro` (mirrors `cw-store`'s `RadioMacro`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{RadioMacro, RadioMacroFilter};

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiRadioMacro {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub macro_description: Option<String>,
    pub tags_csv: String,
    pub applies_to_csv: String,
    pub author: Option<String>,
    pub args_json: Vec<u8>,
    pub steps_json: Vec<u8>,
    pub capabilities_json: Vec<u8>,
    pub registry_json: Vec<u8>,
    pub format: i64,
    pub sort_order: i64,
    pub created_at: i64,
    pub updated_at: i64,
    pub tombstoned: bool,
    pub tombstone_reason: Option<String>,
    pub cloud_dirty_flag: bool,
}

// ---------- Conversions ----------

impl From<RadioMacro> for FfiRadioMacro {
    fn from(x: RadioMacro) -> Self {
        FfiRadioMacro {
            id: x.id,
            name: x.name,
            icon: x.icon,
            macro_description: x.macro_description,
            tags_csv: x.tags_csv,
            applies_to_csv: x.applies_to_csv,
            author: x.author,
            args_json: x.args_json,
            steps_json: x.steps_json,
            capabilities_json: x.capabilities_json,
            registry_json: x.registry_json,
            format: x.format,
            sort_order: x.sort_order,
            created_at: x.created_at,
            updated_at: x.updated_at,
            tombstoned: x.tombstoned,
            tombstone_reason: x.tombstone_reason,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

impl From<FfiRadioMacro> for RadioMacro {
    fn from(x: FfiRadioMacro) -> Self {
        RadioMacro {
            id: x.id,
            name: x.name,
            icon: x.icon,
            macro_description: x.macro_description,
            tags_csv: x.tags_csv,
            applies_to_csv: x.applies_to_csv,
            author: x.author,
            args_json: x.args_json,
            steps_json: x.steps_json,
            capabilities_json: x.capabilities_json,
            registry_json: x.registry_json,
            format: x.format,
            sort_order: x.sort_order,
            created_at: x.created_at,
            updated_at: x.updated_at,
            tombstoned: x.tombstoned,
            tombstone_reason: x.tombstone_reason,
            cloud_dirty_flag: x.cloud_dirty_flag,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiRadioMacroFilter {
    pub tombstoned: Option<bool>,
    pub dirty_only: bool,
}

impl From<FfiRadioMacroFilter> for RadioMacroFilter {
    fn from(f: FfiRadioMacroFilter) -> Self {
        RadioMacroFilter {
            tombstoned: f.tombstoned,
            dirty_only: f.dirty_only,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_radio_macro(&self, item: FfiRadioMacro) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_radio_macro(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::RadioMacro, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of radio macros in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_radio_macros(&self, items: Vec<FfiRadioMacro>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_radio_macro(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::RadioMacro, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn radio_macro_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.radio_macro_count()?)
    }

    pub fn fetch_radio_macros(
        &self,
        filter: FfiRadioMacroFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiRadioMacro>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_radio_macros(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiRadioMacro::from).collect())
    }

    pub fn fetch_radio_macro(&self, id: String) -> Result<Option<FfiRadioMacro>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_radio_macro(&id)?.map(FfiRadioMacro::from))
    }

    pub fn delete_radio_macro(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_radio_macro(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::RadioMacro, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
