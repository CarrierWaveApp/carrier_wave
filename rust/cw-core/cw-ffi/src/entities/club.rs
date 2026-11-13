//! FFI surface for `Club` (mirrors `cw-store`'s `Club`).

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{Club, ClubFilter};

// ---------- DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiClub {
    pub id: String,
    pub name: String,
    pub callsign: Option<String>,
    pub description: Option<String>,
    pub notes_url: Option<String>,
    pub notes_title: Option<String>,
    pub has_logo: bool,
    pub cached_member_count: i64,
    pub last_synced_at: i64,
}

// ---------- Conversions ----------

impl From<Club> for FfiClub {
    fn from(x: Club) -> Self {
        FfiClub {
            id: x.id,
            name: x.name,
            callsign: x.callsign,
            description: x.description,
            notes_url: x.notes_url,
            notes_title: x.notes_title,
            has_logo: x.has_logo,
            cached_member_count: x.cached_member_count,
            last_synced_at: x.last_synced_at,
        }
    }
}

impl From<FfiClub> for Club {
    fn from(x: FfiClub) -> Self {
        Club {
            id: x.id,
            name: x.name,
            callsign: x.callsign,
            description: x.description,
            notes_url: x.notes_url,
            notes_title: x.notes_title,
            has_logo: x.has_logo,
            cached_member_count: x.cached_member_count,
            last_synced_at: x.last_synced_at,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiClubFilter {
    /// When set, only clubs the given callsign is a member of (case-insensitive).
    pub callsign_member: Option<String>,
}

impl From<FfiClubFilter> for ClubFilter {
    fn from(f: FfiClubFilter) -> Self {
        ClubFilter { callsign_member: f.callsign_member }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    pub fn upsert_club(&self, item: FfiClub) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_club(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Club, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn club_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.club_count()?)
    }

    pub fn fetch_clubs(
        &self,
        filter: FfiClubFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiClub>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_clubs(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiClub::from).collect())
    }

    pub fn fetch_club(&self, id: String) -> Result<Option<FfiClub>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_club(&id)?.map(FfiClub::from))
    }

    pub fn delete_club(&self, id: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_club(&id)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::Club, kind: FfiChangeKind::Delete });
        Ok(())
    }
}
