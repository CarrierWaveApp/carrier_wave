//! FFI surface for `WebSDRFavorite` (mirrors `cw-store`'s `WebSDRFavorite`).
//!
//! No filter type exists in cw-store for this entity — the list fetch takes only
//! `limit` and `offset`. The primary key is `host_port` (not a UUID `id`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::WebSDRFavorite;

// ---------- DTO ----------

#[derive(uniffi::Record)]
pub struct FfiWebSDRFavorite {
    pub host_port: String,
    pub display_name: String,
    pub location: String,
    pub antenna: Option<String>,
    pub added_date: i64,
}

// ---------- Conversions ----------

impl From<WebSDRFavorite> for FfiWebSDRFavorite {
    fn from(x: WebSDRFavorite) -> Self {
        FfiWebSDRFavorite {
            host_port: x.host_port,
            display_name: x.display_name,
            location: x.location,
            antenna: x.antenna,
            added_date: x.added_date,
        }
    }
}

impl From<FfiWebSDRFavorite> for WebSDRFavorite {
    fn from(x: FfiWebSDRFavorite) -> Self {
        WebSDRFavorite {
            host_port: x.host_port,
            display_name: x.display_name,
            location: x.location,
            antenna: x.antenna,
            added_date: x.added_date,
        }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_websdr_favorite(&self, item: FfiWebSDRFavorite) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_websdr_favorite(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::WebSdrFavorite, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Upsert a batch of WebSDR favorites in a single transaction — one commit for the
    /// whole batch (see `FieldStore::upsert_qsos`). Used by the SwiftData seed
    /// importer. Atomic per batch; notifies observers once.
    pub fn upsert_websdr_favorites(&self, items: Vec<FfiWebSDRFavorite>) -> Result<(), CwError> {
        if items.is_empty() {
            return Ok(());
        }
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.in_transaction(|| {
                for item in items {
                    store.upsert_websdr_favorite(&item.into())?;
                }
                Ok(())
            })?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::WebSdrFavorite, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn websdr_favorite_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.websdr_favorite_count()?)
    }

    pub fn fetch_websdr_favorites(
        &self,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiWebSDRFavorite>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_websdr_favorites(limit, offset)?;
        Ok(rows.into_iter().map(FfiWebSDRFavorite::from).collect())
    }

    pub fn fetch_websdr_favorite(
        &self,
        host_port: String,
    ) -> Result<Option<FfiWebSDRFavorite>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_websdr_favorite(&host_port)?.map(FfiWebSDRFavorite::from))
    }

    pub fn delete_websdr_favorite(&self, host_port: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_websdr_favorite(&host_port)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::WebSdrFavorite, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
