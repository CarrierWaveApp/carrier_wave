//! FFI surface for `Loadout` (mirrors `cw-store`'s `Loadout`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::Loadout;

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiLoadout {
    pub id: String,
    pub name: String,
    pub radio: Option<String>,
    pub antenna: Option<String>,
    pub key: Option<String>,
    pub mic: Option<String>,
    pub radio_item_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

// ---------- Conversions ----------

impl From<Loadout> for FfiLoadout {
    fn from(x: Loadout) -> Self {
        FfiLoadout {
            id: x.id,
            name: x.name,
            radio: x.radio,
            antenna: x.antenna,
            key: x.key,
            mic: x.mic,
            radio_item_id: x.radio_item_id,
            created_at: x.created_at,
            updated_at: x.updated_at,
        }
    }
}

impl From<FfiLoadout> for Loadout {
    fn from(x: FfiLoadout) -> Self {
        Loadout {
            id: x.id,
            name: x.name,
            radio: x.radio,
            antenna: x.antenna,
            key: x.key,
            mic: x.mic,
            radio_item_id: x.radio_item_id,
            created_at: x.created_at,
            updated_at: x.updated_at,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_loadout(&self, item: FfiLoadout) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_loadout(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Loadout, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn loadout_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.loadout_count()?)
    }

    pub fn fetch_loadouts(&self, limit: i64, offset: i64) -> Result<Vec<FfiLoadout>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_loadouts(limit, offset)?;
        Ok(rows.into_iter().map(FfiLoadout::from).collect())
    }

    pub fn fetch_loadout(&self, id: String) -> Result<Option<FfiLoadout>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_loadout(&id)?.map(FfiLoadout::from))
    }

    pub fn delete_loadout(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_loadout(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Loadout, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
