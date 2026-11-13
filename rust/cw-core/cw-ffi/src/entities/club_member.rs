//! FFI surface for `ClubMember` (mirrors `cw-store`'s `ClubMember`).
//!
//! Also exposes the two membership lookups every callsign-display site needs —
//! [`FieldStore::clubs_for_callsign`] and [`FieldStore::callsigns_in_club`] —
//! the portable replacements for `ClubsSyncService.clubs(for:)` /
//! `callsigns(inClub:)`.

use crate::observation::{FfiChangeKind, FfiStoreChange, FfiStoreTable};
use crate::{CwError, FieldStore};
use cw_store::{ClubMember, ClubMemberFilter};

// ---------- DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiClubMember {
    pub club_id: String,
    pub callsign: String,
    pub role: String,
    pub last_seen_at: Option<i64>,
    pub last_grid: Option<String>,
    pub is_carrier_wave_user: bool,
    /// Operator-entered member number. Local-only — preserved across server sync.
    pub number: Option<String>,
}

// ---------- Conversions ----------

impl From<ClubMember> for FfiClubMember {
    fn from(x: ClubMember) -> Self {
        FfiClubMember {
            club_id: x.club_id,
            callsign: x.callsign,
            role: x.role,
            last_seen_at: x.last_seen_at,
            last_grid: x.last_grid,
            is_carrier_wave_user: x.is_carrier_wave_user,
            number: x.number,
        }
    }
}

impl From<FfiClubMember> for ClubMember {
    fn from(x: FfiClubMember) -> Self {
        ClubMember {
            club_id: x.club_id,
            callsign: x.callsign,
            role: x.role,
            last_seen_at: x.last_seen_at,
            last_grid: x.last_grid,
            is_carrier_wave_user: x.is_carrier_wave_user,
            number: x.number,
        }
    }
}

// ---------- Filter DTO ----------

#[derive(uniffi::Record, Default)]
pub struct FfiClubMemberFilter {
    pub club_id: Option<String>,
    pub callsign: Option<String>,
}

impl From<FfiClubMemberFilter> for ClubMemberFilter {
    fn from(f: FfiClubMemberFilter) -> Self {
        ClubMemberFilter { club_id: f.club_id, callsign: f.callsign }
    }
}

// ---------- FieldStore methods ----------

#[uniffi::export]
impl FieldStore {
    /// Upsert a membership row from a server sync — preserves the local-only
    /// member `number` on conflict.
    pub fn upsert_club_member_from_server(&self, item: FfiClubMember) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.upsert_club_member_from_server(&item.into())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ClubMember, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    /// Set or clear the operator-entered member number for a `(club_id, callsign)`.
    pub fn set_club_member_number(
        &self,
        club_id: String,
        callsign: String,
        number: Option<String>,
    ) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.set_club_member_number(&club_id, &callsign, number.as_deref())?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ClubMember, kind: FfiChangeKind::Upsert });
        Ok(())
    }

    pub fn club_member_count(&self) -> Result<i64, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.club_member_count()?)
    }

    pub fn fetch_club_members(
        &self,
        filter: FfiClubMemberFilter,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<FfiClubMember>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_club_members(&filter.into(), limit, offset)?;
        Ok(rows.into_iter().map(FfiClubMember::from).collect())
    }

    pub fn delete_club_member(&self, club_id: String, callsign: String) -> Result<(), CwError> {
        {
            let store = self.inner.lock().expect("store mutex poisoned");
            store.delete_club_member(&club_id, &callsign)?;
        }
        self.notify(FfiStoreChange { table: FfiStoreTable::ClubMember, kind: FfiChangeKind::Delete });
        Ok(())
    }

    /// Club names the callsign belongs to (case-insensitive, name-sorted).
    pub fn clubs_for_callsign(&self, callsign: String) -> Result<Vec<String>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.clubs_for_callsign(&callsign)?)
    }

    /// Member callsigns in the named club (case-insensitive, callsign-sorted).
    pub fn callsigns_in_club(&self, club_name: String) -> Result<Vec<String>, CwError> {
        let store = self.inner.lock().expect("store mutex poisoned");
        Ok(store.callsigns_in_club(&club_name)?)
    }
}
