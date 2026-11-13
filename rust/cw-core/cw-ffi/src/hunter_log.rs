//! FFI surface for the hunter-log pure helpers (`cw_domain::hunter_log` +
//! `cw_domain::quick_entry::extract_primary`). These back the Android (and
//! Swift) hunter quick-log lookup, dedup badges, and FT8 QSO enrichment.

use cw_domain::hunter_log::{self, DxccDerivation};
use cw_domain::quick_entry;

/// DXCC entity derived from a callsign / fallback grid (`derive_dxcc`).
#[derive(uniffi::Record)]
pub struct FfiDxccDerivation {
    /// DXCC entity number (maps onto `QSO.dxcc`).
    pub dxcc_id: i64,
    /// Entity name (maps onto `QSO.country`).
    pub name: String,
    /// The matched representative prefix.
    pub prefix: String,
}

impl From<DxccDerivation> for FfiDxccDerivation {
    fn from(d: DxccDerivation) -> Self {
        FfiDxccDerivation { dxcc_id: i64::from(d.dxcc_id), name: d.name, prefix: d.prefix }
    }
}

/// Extract the primary callsign from a portable/prefix callsign
/// (`"I/W6JSV/P" -> "W6JSV"`). Case-preserving; no-slash input is unchanged.
#[uniffi::export]
pub fn hunter_extract_primary(callsign: String) -> String {
    quick_entry::extract_primary(&callsign)
}

/// Composite worked-before dedup key `"<band>|<MODE-FAMILY>|<PARK>"`. A contact
/// is a dupe when the callsign's worked-today key set (see
/// `ActivityLogApi.worked_today`) contains this key.
#[uniffi::export]
pub fn hunter_band_mode_park_key(band: String, mode: String, park: Option<String>) -> String {
    hunter_log::band_mode_park_key(&band, &mode, park.as_deref())
}

/// Derive the DXCC entity for a contact from its callsign prefix, falling back
/// to the nearest entity for `grid`. `None` when neither resolves.
#[uniffi::export]
pub fn hunter_derive_dxcc(callsign: String, grid: Option<String>) -> Option<FfiDxccDerivation> {
    hunter_log::derive_dxcc(&callsign, grid.as_deref()).map(FfiDxccDerivation::from)
}
