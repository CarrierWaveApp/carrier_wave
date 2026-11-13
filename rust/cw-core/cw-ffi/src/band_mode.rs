//! Band, mode, and band-plan FFI surface.
//!
//! Free functions wrapping `cw_domain::band::BandUtilities`,
//! `cw_domain::mode::ModeEquivalence`, and `cw_domain::band_plan`.
//! DTOs carry the `Ffi` prefix to avoid collisions with the domain types.
//! Consumed by `BandUtilities.swift`, `ModeEquivalence.swift`, and
//! `BandPlan.swift` via the generated `CarrierWaveCwFfi` bindings.

use cw_domain::band::BandUtilities;
use cw_domain::band_plan::{self, LicenseClass as DomainLicenseClass};
use cw_domain::mode::{ModeEquivalence, ModeFamily as DomainModeFamily};

// ---------- Band DTOs ----------

/// Frequency range for an amateur band (MHz).
#[derive(uniffi::Record)]
pub struct FfiBandRange {
    pub low_mhz: f64,
    pub high_mhz: f64,
}

// ---------- Mode DTOs ----------

/// Mode family — mirrors `ModeFamily` in `ModeEquivalence.swift`.
#[derive(uniffi::Enum)]
pub enum FfiModeFamily {
    Phone,
    Cw,
    Digital,
    Other,
}

impl From<DomainModeFamily> for FfiModeFamily {
    fn from(fam: DomainModeFamily) -> Self {
        match fam {
            DomainModeFamily::Phone   => FfiModeFamily::Phone,
            DomainModeFamily::Cw     => FfiModeFamily::Cw,
            DomainModeFamily::Digital => FfiModeFamily::Digital,
            DomainModeFamily::Other  => FfiModeFamily::Other,
        }
    }
}

/// ADIF parent mode + optional submode pair.
#[derive(uniffi::Record)]
pub struct FfiAdifModeSubmode {
    pub mode: String,
    pub submode: Option<String>,
}

// ---------- Band-plan DTOs ----------

/// US FCC license class — mirrors `LicenseClass` in `BandPlan.swift`.
#[derive(uniffi::Enum)]
pub enum FfiLicenseClass {
    Technician,
    General,
    Extra,
}

impl From<DomainLicenseClass> for FfiLicenseClass {
    fn from(cls: DomainLicenseClass) -> Self {
        match cls {
            DomainLicenseClass::Technician => FfiLicenseClass::Technician,
            DomainLicenseClass::General    => FfiLicenseClass::General,
            DomainLicenseClass::Extra      => FfiLicenseClass::Extra,
        }
    }
}

/// A US FCC band segment with privilege data.
#[derive(uniffi::Record)]
pub struct FfiBandSegment {
    pub band: String,
    pub start_mhz: f64,
    pub end_mhz: f64,
    /// Allowed mode codes ("CW", "DATA", "SSB", "PHONE", "USB", "FM", "AM", "ALL").
    pub modes: Vec<String>,
    pub minimum_license: FfiLicenseClass,
    pub notes: Option<String>,
}

// ---------- Band free functions ----------

/// Derive the amateur band name from a frequency in kHz.
/// Returns `None` for frequencies outside known amateur allocations.
#[uniffi::export]
pub fn band_derive(frequency_khz: f64) -> Option<String> {
    BandUtilities::derive_band(Some(frequency_khz)).map(str::to_string)
}

/// Frequency range `(low_mhz, high_mhz)` for a band, or `None` if unknown.
#[uniffi::export]
pub fn band_range(band: String) -> Option<FfiBandRange> {
    BandUtilities::range(&band)
        .map(|(low, high)| FfiBandRange { low_mhz: low, high_mhz: high })
}

/// Approximate top of CW/digital portion of an HF band, in kHz.
#[uniffi::export]
pub fn band_digital_boundary_khz(band: String) -> Option<f64> {
    BandUtilities::digital_boundary_khz(&band)
}

/// Approximate start of SSB/phone portion of an HF band, in kHz.
#[uniffi::export]
pub fn band_ssb_boundary_khz(band: String) -> Option<f64> {
    BandUtilities::ssb_boundary_khz(&band)
}

/// Band names in frequency order (low to high), including "Other".
/// Feeds `BandUtilities.bandOrder` on the Swift side.
#[uniffi::export]
pub fn band_order_list() -> Vec<String> {
    BandUtilities::BAND_ORDER.iter().map(|s| s.to_string()).collect()
}

/// Standard operating bands in display order (excludes "Other").
/// Feeds `BandUtilities.standardBands` on the Swift side.
#[uniffi::export]
pub fn standard_bands_list() -> Vec<String> {
    BandUtilities::STANDARD_BANDS.iter().map(|s| s.to_string()).collect()
}

// ---------- Mode free functions ----------

/// Generic mode names that should yield to specific ones when merging.
/// Feeds `ModeEquivalence.genericModes` on the Swift side.
#[uniffi::export]
pub fn mode_generic_modes() -> Vec<String> {
    ModeEquivalence::GENERIC_MODES.iter().map(|s| s.to_string()).collect()
}

/// Phone-family mode names — all equivalent for deduplication.
/// Feeds `ModeEquivalence.phoneModes` on the Swift side.
#[uniffi::export]
pub fn mode_phone_modes() -> Vec<String> {
    ModeEquivalence::PHONE_MODES.iter().map(|s| s.to_string()).collect()
}

/// Digital-family mode names — all equivalent for deduplication.
/// Feeds `ModeEquivalence.digitalModes` on the Swift side.
#[uniffi::export]
pub fn mode_digital_modes() -> Vec<String> {
    ModeEquivalence::DIGITAL_MODES.iter().map(|s| s.to_string()).collect()
}

/// CW-family mode names.
/// Feeds `ModeEquivalence.cwModes` on the Swift side.
#[uniffi::export]
pub fn mode_cw_modes() -> Vec<String> {
    ModeEquivalence::CW_MODES.iter().map(|s| s.to_string()).collect()
}

/// Mode family classification for a given mode string.
#[uniffi::export]
pub fn mode_family(mode: String) -> FfiModeFamily {
    ModeEquivalence::family(&mode).into()
}

/// `true` iff `mode1` and `mode2` belong to the same mode family.
#[uniffi::export]
pub fn modes_are_equivalent(mode1: String, mode2: String) -> bool {
    ModeEquivalence::are_equivalent(&mode1, &mode2)
}

/// Returns the more specific of two equivalent modes (prefers non-generic).
#[uniffi::export]
pub fn mode_more_specific(mode1: String, mode2: String) -> String {
    ModeEquivalence::more_specific(&mode1, &mode2)
}

/// `true` iff `mode` is a generic mode name (PHONE or DATA).
#[uniffi::export]
pub fn mode_is_generic(mode: String) -> bool {
    ModeEquivalence::is_generic(&mode)
}

/// Canonical display name for a mode (PHONE → SSB; others unchanged).
#[uniffi::export]
pub fn mode_canonical_name(mode: String) -> String {
    ModeEquivalence::canonical_name(&mode)
}

/// Canonical name for dedup key construction (all phone-family → SSB;
/// others uppercased).
#[uniffi::export]
pub fn mode_canonical_name_for_dedup(mode: String) -> String {
    ModeEquivalence::canonical_name_for_dedup(&mode)
}

/// ADIF parent mode and optional submode for a mode string.
/// USB/LSB → (SSB, USB/LSB), FT4 → (MFSK, FT4), PSK31 → (PSK, PSK31).
#[uniffi::export]
pub fn mode_adif_mode_submode(mode: String) -> FfiAdifModeSubmode {
    let (m, sub) = ModeEquivalence::adif_mode_submode(&mode);
    FfiAdifModeSubmode { mode: m, submode: sub }
}

/// Normalize a mode for strict ADIF-compliant services
/// (PHONE → SSB, DATA → RTTY), then apply the standard mode/submode split.
#[uniffi::export]
pub fn mode_normalize_for_strict_adif(mode: String) -> FfiAdifModeSubmode {
    let (m, sub) = ModeEquivalence::normalize_for_strict_adif(&mode);
    FfiAdifModeSubmode { mode: m, submode: sub }
}

/// Deduplicate a list of mode strings by family, preferring specific over
/// generic. Output: family representatives sorted alphabetically, then
/// other-family modes sorted alphabetically.
#[uniffi::export]
pub fn modes_deduplicated(modes: Vec<String>) -> Vec<String> {
    ModeEquivalence::deduplicated_modes(&modes)
}

// ---------- Band plan free functions ----------

/// All US FCC band segments with privilege data, in definition order.
/// Feeds `BandPlan.segments` on the Swift side.
#[uniffi::export]
pub fn band_plan_segments() -> Vec<FfiBandSegment> {
    band_plan::SEGMENTS
        .iter()
        .map(|seg| FfiBandSegment {
            band: seg.band.to_string(),
            start_mhz: seg.start_mhz,
            end_mhz: seg.end_mhz,
            modes: seg.modes.iter().map(|m| m.to_string()).collect(),
            minimum_license: seg.minimum_license.into(),
            notes: seg.notes.map(str::to_string),
        })
        .collect()
}
