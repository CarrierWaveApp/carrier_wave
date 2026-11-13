//! UniFFI surface for ADIF parsing, validation, and the band/mode catalog
//! (`cw_domain::adif`, `cw_domain::adif_validator`, `cw_domain::adif_catalog`).
//!
//! The Apple apps' `ADIFParser` / `ADIFFieldValidator` / `ADIFCatalog` are thin
//! facades over these functions so ADIF tokenizing, field validation, and the
//! band/mode/submode tables live in Rust, not duplicated per platform. ADIF date
//! and time fields stay as `Date` on the Swift side (DateFormatter is simpler
//! there); the US-state / Canadian-province catalog is not yet ported, so it
//! remains in Swift too.

use std::collections::HashMap;

use cw_domain::adif;
use cw_domain::adif_catalog;
use cw_domain::adif_validator::{self, AdifField, Violation};

// ---------- Records ----------

/// One parsed ADIF QSO record. Mirrors Swift `ADIFRecord` (sans the `timestamp`
/// computed property, which Swift derives from `qsoDate`/`timeOn`).
#[derive(uniffi::Record)]
pub struct FfiAdifRecord {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency: Option<f64>,
    pub qso_date: Option<String>,
    pub time_on: Option<String>,
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    pub my_callsign: Option<String>,
    pub my_gridsquare: Option<String>,
    pub gridsquare: Option<String>,
    pub sig_info: Option<String>,
    pub my_sig_info: Option<String>,
    pub my_wwff_ref: Option<String>,
    pub wwff_ref: Option<String>,
    pub comment: Option<String>,
    pub dxcc: Option<i32>,
    pub country: Option<String>,
    pub state: Option<String>,
    pub name: Option<String>,
    pub qth: Option<String>,
    pub raw_adif: String,
    pub operator_call: Option<String>,
    pub station_callsign: Option<String>,
    pub sat_name: Option<String>,
    pub prop_mode: Option<String>,
}

impl From<adif::AdifRecord> for FfiAdifRecord {
    fn from(record: adif::AdifRecord) -> Self {
        FfiAdifRecord {
            callsign: record.callsign,
            band: record.band,
            mode: record.mode,
            frequency: record.frequency,
            qso_date: record.qso_date,
            time_on: record.time_on,
            rst_sent: record.rst_sent,
            rst_received: record.rst_received,
            my_callsign: record.my_callsign,
            my_gridsquare: record.my_gridsquare,
            gridsquare: record.gridsquare,
            sig_info: record.sig_info,
            my_sig_info: record.my_sig_info,
            my_wwff_ref: record.my_wwff_ref,
            wwff_ref: record.wwff_ref,
            comment: record.comment,
            dxcc: record.dxcc,
            country: record.country,
            state: record.state,
            name: record.name,
            qth: record.qth,
            raw_adif: record.raw_adif,
            operator_call: record.operator_call,
            station_callsign: record.station_callsign,
            sat_name: record.sat_name,
            prop_mode: record.prop_mode,
        }
    }
}

/// The field a [`FfiViolation`] is attached to. Mirrors Swift
/// `ADIFFieldValidator.Field` (raw values `call`/`band`/…).
#[derive(uniffi::Enum)]
pub enum FfiAdifField {
    Call,
    Band,
    Mode,
    Submode,
    Freq,
    Date,
    Time,
    Grid,
}

impl From<AdifField> for FfiAdifField {
    fn from(field: AdifField) -> Self {
        match field {
            AdifField::Call => FfiAdifField::Call,
            AdifField::Band => FfiAdifField::Band,
            AdifField::Mode => FfiAdifField::Mode,
            AdifField::Submode => FfiAdifField::Submode,
            AdifField::Freq => FfiAdifField::Freq,
            AdifField::Date => FfiAdifField::Date,
            AdifField::Time => FfiAdifField::Time,
            AdifField::Grid => FfiAdifField::Grid,
        }
    }
}

/// A single ADIF field-validation violation. Mirrors Swift
/// `ADIFFieldValidator.Violation`.
#[derive(uniffi::Record)]
pub struct FfiViolation {
    pub field: FfiAdifField,
    pub value: String,
    pub reason: String,
}

impl From<Violation> for FfiViolation {
    fn from(violation: Violation) -> Self {
        FfiViolation {
            field: violation.field.into(),
            value: violation.value,
            reason: violation.reason,
        }
    }
}

/// Mode-category bucket for the picker UI. Mirrors Swift
/// `ADIFCatalog.ModeCategory`.
#[derive(uniffi::Enum)]
pub enum FfiModeCategory {
    Phone,
    Cw,
    Digital,
    Image,
}

impl From<adif_catalog::ModeCategory> for FfiModeCategory {
    fn from(category: adif_catalog::ModeCategory) -> Self {
        match category {
            adif_catalog::ModeCategory::Phone => FfiModeCategory::Phone,
            adif_catalog::ModeCategory::Cw => FfiModeCategory::Cw,
            adif_catalog::ModeCategory::Digital => FfiModeCategory::Digital,
            adif_catalog::ModeCategory::Image => FfiModeCategory::Image,
        }
    }
}

/// A catalog mode entry. Mirrors Swift `ADIFCatalog.Mode`.
#[derive(uniffi::Record)]
pub struct FfiAdifMode {
    pub code: String,
    pub category: FfiModeCategory,
    pub description: String,
}

impl From<&adif_catalog::AdifMode> for FfiAdifMode {
    fn from(mode: &adif_catalog::AdifMode) -> Self {
        FfiAdifMode {
            code: mode.code.to_string(),
            category: mode.category.into(),
            description: mode.description.to_string(),
        }
    }
}

/// A catalog band entry. Mirrors Swift `ADIFCatalog.Band`.
#[derive(uniffi::Record)]
pub struct FfiAdifBand {
    pub code: String,
    pub description: String,
    pub min_mhz: f64,
    pub max_mhz: f64,
}

impl From<&adif_catalog::AdifBand> for FfiAdifBand {
    fn from(band: &adif_catalog::AdifBand) -> Self {
        FfiAdifBand {
            code: band.code.to_string(),
            description: band.description.to_string(),
            min_mhz: band.min_mhz,
            max_mhz: band.max_mhz,
        }
    }
}

/// One `submode → required parent mode` pairing. Mirrors a Swift
/// `ADIFCatalog.submodeParents` entry.
#[derive(uniffi::Record)]
pub struct FfiSubmodeParent {
    pub submode: String,
    pub parent_mode: String,
}

// ---------- Parser ----------

/// Parse a full ADIF document into records (header stripped at `<eoh>`, split on
/// `<eor>`; records missing `call`/`band`/`mode` are skipped). Never fails —
/// Swift's `parse(_:)` is declared `throws` for source compatibility but the
/// underlying parser only ever returns the (possibly empty) record list.
#[uniffi::export]
pub fn adif_parse(content: String) -> Vec<FfiAdifRecord> {
    adif::parse(&content).into_iter().map(FfiAdifRecord::from).collect()
}

/// Extract a single field's value from a raw ADIF string (case-insensitive field
/// name, trimmed value), or `None` if absent.
#[uniffi::export]
pub fn adif_extract_field(field_name: String, adif_str: String) -> Option<String> {
    adif::extract_field(&field_name, &adif_str)
}

/// Extract the DXCC entity number, or `None` if missing/unparseable.
#[uniffi::export]
pub fn adif_extract_dxcc(adif_str: String) -> Option<i32> {
    adif::extract_dxcc(&adif_str)
}

/// Parse every field of one record into a `field_name → value` map (names
/// lowercased, values untrimmed).
#[uniffi::export]
pub fn adif_extract_fields(record: String) -> HashMap<String, String> {
    adif::extract_fields(&record)
}

// ---------- Validators ----------

#[uniffi::export]
pub fn adif_validate_callsign(call: String) -> Option<FfiViolation> {
    adif_validator::validate_callsign(&call).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_band(band: String) -> Option<FfiViolation> {
    adif_validator::validate_band(&band).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_mode(mode: String) -> Option<FfiViolation> {
    adif_validator::validate_mode(&mode).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_submode(submode: String, parent_mode: String) -> Option<FfiViolation> {
    adif_validator::validate_submode(&submode, &parent_mode).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_band_freq_consistency(band: String, freq_mhz: f64) -> Option<FfiViolation> {
    adif_validator::validate_band_freq_consistency(&band, freq_mhz).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_date(date_str: String) -> Option<FfiViolation> {
    adif_validator::validate_date(&date_str).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_time(time_str: String) -> Option<FfiViolation> {
    adif_validator::validate_time(&time_str).map(FfiViolation::from)
}

#[uniffi::export]
pub fn adif_validate_grid_square(grid: String) -> Option<FfiViolation> {
    adif_validator::validate_grid_square(&grid).map(FfiViolation::from)
}

/// Composite upload validator. Each `Some` optional is only checked when
/// non-empty (mirrors Swift's `validateForUpload`).
#[allow(clippy::too_many_arguments)]
#[uniffi::export]
pub fn adif_validate_for_upload(
    callsign: String,
    band: String,
    mode: String,
    submode: Option<String>,
    freq_mhz: Option<f64>,
    date_str: Option<String>,
    time_str: Option<String>,
    grid: Option<String>,
) -> Vec<FfiViolation> {
    adif_validator::validate_for_upload(
        &callsign,
        &band,
        &mode,
        submode.as_deref(),
        freq_mhz,
        date_str.as_deref(),
        time_str.as_deref(),
        grid.as_deref(),
    )
    .into_iter()
    .map(FfiViolation::from)
    .collect()
}

// ---------- Catalog ----------

/// All ADIF 3.1.7 modes, in catalog order.
#[uniffi::export]
pub fn adif_modes() -> Vec<FfiAdifMode> {
    adif_catalog::MODES.iter().map(FfiAdifMode::from).collect()
}

/// All ADIF 3.1.7 bands, low → high frequency.
#[uniffi::export]
pub fn adif_bands() -> Vec<FfiAdifBand> {
    adif_catalog::BANDS.iter().map(FfiAdifBand::from).collect()
}

/// The full submode → required-parent-mode table.
#[uniffi::export]
pub fn adif_submode_parents() -> Vec<FfiSubmodeParent> {
    adif_catalog::SUBMODE_PARENTS
        .iter()
        .map(|(submode, parent)| FfiSubmodeParent {
            submode: submode.to_string(),
            parent_mode: parent.to_string(),
        })
        .collect()
}

/// Look up a mode by code (case-insensitive, trimmed), or `None`.
#[uniffi::export]
pub fn adif_mode_for_code(code: String) -> Option<FfiAdifMode> {
    adif_catalog::mode_for_code(&code).map(FfiAdifMode::from)
}

/// Look up a band by code (case-insensitive, trimmed), or `None`.
#[uniffi::export]
pub fn adif_band_for_code(code: String) -> Option<FfiAdifBand> {
    adif_catalog::band_for_code(&code).map(FfiAdifBand::from)
}

/// The required parent mode for a submode (case-insensitive, trimmed), or `None`.
#[uniffi::export]
pub fn adif_parent_mode_for_submode(submode: String) -> Option<String> {
    adif_catalog::parent_mode_for_submode(&submode).map(str::to_string)
}

/// Whether `code` is a recognized ADIF submode of any parent mode.
#[uniffi::export]
pub fn adif_is_submode(code: String) -> bool {
    adif_catalog::is_submode(&code)
}
