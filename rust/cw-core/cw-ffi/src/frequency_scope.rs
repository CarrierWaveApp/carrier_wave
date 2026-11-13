//! Frequency-scope FFI surface — wraps `cw_domain::frequency_scope`.
//!
//! Feeds the session wizard's interactive frequency selector on both platforms
//! (Swift `FrequencyScopeLogic`, Android `FrequencyScopeField`). DTOs carry the
//! `Ffi` prefix; advisory strings keep the wizard's markdown bold.

use cw_domain::band_plan::LicenseClass as DomainLicenseClass;
use cw_domain::frequency_scope as scope;

use crate::band_mode::FfiLicenseClass;

fn to_domain_license(cls: &FfiLicenseClass) -> DomainLicenseClass {
    match cls {
        FfiLicenseClass::Technician => DomainLicenseClass::Technician,
        FfiLicenseClass::General => DomainLicenseClass::General,
        FfiLicenseClass::Extra => DomainLicenseClass::Extra,
    }
}

/// One on-air station rendered on the ruler.
#[derive(uniffi::Record)]
pub struct FfiScopeSpot {
    pub frequency_hz: i64,
    pub callsign: String,
    /// Opaque render tier (host spot-tier ordinal; 0 when unknown).
    pub tier: i32,
    pub wpm: Option<i32>,
    pub age_seconds: i64,
}

/// Precomputed render data for one ruler row (frequency in Hz).
#[derive(uniffi::Record)]
pub struct FfiScopeRow {
    pub hz: i64,
    pub freq_text: String,
    pub spot: Option<FfiScopeSpot>,
    pub hatched: bool,
    pub seg_label: Option<String>,
    pub block_label: Option<String>,
    pub hole: Option<String>,
    pub pileup_count: i32,
    pub is_good: bool,
    /// Advisory for the row, with markdown bold (`**x**`).
    pub advisory: String,
}

/// Advisory for a frequency — green when clear/appropriate, else orange.
#[derive(uniffi::Record)]
pub struct FfiScopeVerdict {
    pub is_good: bool,
    pub message: String,
}

/// A Hz span `[low, high]`.
#[derive(uniffi::Record)]
pub struct FfiHzRange {
    pub low_hz: i64,
    pub high_hz: i64,
}

impl From<scope::ScopeSpot> for FfiScopeSpot {
    fn from(spot: scope::ScopeSpot) -> Self {
        FfiScopeSpot {
            frequency_hz: spot.frequency_hz,
            callsign: spot.callsign,
            tier: spot.tier,
            wpm: spot.wpm,
            age_seconds: spot.age_seconds,
        }
    }
}

impl From<&FfiScopeSpot> for scope::ScopeSpot {
    fn from(spot: &FfiScopeSpot) -> Self {
        scope::ScopeSpot {
            frequency_hz: spot.frequency_hz,
            callsign: spot.callsign.clone(),
            tier: spot.tier,
            wpm: spot.wpm,
            age_seconds: spot.age_seconds,
        }
    }
}

impl From<scope::ScopeRow> for FfiScopeRow {
    fn from(row: scope::ScopeRow) -> Self {
        FfiScopeRow {
            hz: row.hz,
            freq_text: row.freq_text,
            spot: row.spot.map(FfiScopeSpot::from),
            hatched: row.hatched,
            seg_label: row.seg_label,
            block_label: row.block_label,
            hole: row.hole,
            pileup_count: row.pileup_count,
            is_good: row.is_good,
            advisory: row.advisory,
        }
    }
}

impl From<scope::Verdict> for FfiScopeVerdict {
    fn from(verdict: scope::Verdict) -> Self {
        FfiScopeVerdict { is_good: verdict.is_good, message: verdict.message }
    }
}

/// Bands with a band plan, in scope order.
#[uniffi::export]
pub fn frequency_scope_available_bands() -> Vec<String> {
    scope::available_bands()
}

/// Full displayable Hz span of a band.
#[uniffi::export]
pub fn frequency_scope_band_range(band: String) -> Option<FfiHzRange> {
    scope::band_range_hz(&band).map(|(low, high)| FfiHzRange { low_hz: low, high_hz: high })
}

/// Where the scope starts for a band+mode (General-class op / FT8-FT4 hole).
#[uniffi::export]
pub fn frequency_scope_default_hz(band: String, mode: String) -> Option<i64> {
    scope::default_hz(&band, &mode)
}

/// The watering-hole mode at this frequency ("FT8"/"FT4"), if any.
#[uniffi::export]
pub fn frequency_scope_hole_mode(band: String, hz: i64) -> Option<String> {
    scope::hole_mode(&band, hz)
}

/// Build every ruler row for a band at the current step (Hz).
#[uniffi::export]
pub fn frequency_scope_rows(
    band: String,
    mode: String,
    license: FfiLicenseClass,
    step: i64,
    spots: Vec<FfiScopeSpot>,
) -> Vec<FfiScopeRow> {
    let domain_spots: Vec<scope::ScopeSpot> = spots.iter().map(scope::ScopeSpot::from).collect();
    scope::build_rows(&band, &mode, to_domain_license(&license), step, &domain_spots)
        .into_iter()
        .map(FfiScopeRow::from)
        .collect()
}

/// The verdict + advisory for one frequency (Hz).
#[uniffi::export]
pub fn frequency_scope_evaluate(
    hz: i64,
    band: String,
    mode: String,
    license: FfiLicenseClass,
    spots: Vec<FfiScopeSpot>,
) -> FfiScopeVerdict {
    let domain_spots: Vec<scope::ScopeSpot> = spots.iter().map(scope::ScopeSpot::from).collect();
    scope::evaluate(hz, &band, &mode, to_domain_license(&license), &domain_spots).into()
}
