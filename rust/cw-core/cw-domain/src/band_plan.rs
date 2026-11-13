//! US amateur radio band plan + common-frequency tables. Port of
//! `BandPlan.swift` and `BandPlan+Frequencies.swift`.
//!
//! Per the migration plan, this is now the canonical source — the Swift
//! side is regenerated from here. `BandPlan+Activities.swift` (CWT time
//! windows, ARRL usage zones, `FrequencyActivity` table) is intentionally
//! deferred: it's view-layer hint data that the iOS shim can keep until the
//! consumer migration in Phase 4 needs it crossed over.

use std::collections::HashSet;

use crate::iaru_region::IaruRegion;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum LicenseClass {
    Technician,
    General,
    Extra,
}

impl LicenseClass {
    /// Swift raw value.
    pub fn display_name(self) -> &'static str {
        match self {
            Self::Technician => "Technician",
            Self::General => "General",
            Self::Extra => "Extra",
        }
    }

    pub fn abbreviation(self) -> &'static str {
        match self {
            Self::Technician => "T",
            Self::General => "G",
            Self::Extra => "E",
        }
    }
}

/// A band segment with privileges. `modes` carries the mode codes ("CW",
/// "DATA", "SSB", "PHONE", "USB", "FM", "AM", "ALL").
#[derive(Debug, Clone, PartialEq)]
pub struct BandSegment {
    pub band: &'static str,
    pub start_mhz: f64,
    pub end_mhz: f64,
    pub modes: &'static [&'static str],
    pub minimum_license: LicenseClass,
    pub notes: Option<&'static str>,
}

impl BandSegment {
    pub fn contains(&self, frequency_mhz: f64) -> bool {
        frequency_mhz >= self.start_mhz && frequency_mhz <= self.end_mhz
    }

    pub fn allows_mode(&self, mode: &str) -> bool {
        let upper = mode.to_uppercase();
        self.modes.contains(&upper.as_str()) || self.modes.contains(&"ALL")
    }
}

/// US FCC band segments. Same data as `BandPlan.segments` in Swift.
pub const SEGMENTS: &[BandSegment] = &[
    // 160 meters
    BandSegment {
        band: "160m",
        start_mhz: 1.800,
        end_mhz: 2.000,
        modes: &["CW", "DATA", "SSB", "PHONE"],
        minimum_license: LicenseClass::General,
        notes: None,
    },
    // 80 meters
    BandSegment { band: "80m", start_mhz: 3.500, end_mhz: 3.600, modes: &["CW", "DATA"], minimum_license: LicenseClass::Extra, notes: Some("Extra CW/Data") },
    BandSegment { band: "80m", start_mhz: 3.525, end_mhz: 3.600, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("General CW/Data") },
    BandSegment { band: "80m", start_mhz: 3.525, end_mhz: 3.600, modes: &["CW"], minimum_license: LicenseClass::Technician, notes: Some("Tech CW only") },
    BandSegment { band: "80m", start_mhz: 3.600, end_mhz: 3.800, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::Extra, notes: Some("Extra Phone") },
    BandSegment { band: "80m", start_mhz: 3.800, end_mhz: 4.000, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("General Phone") },
    // 60 meters (channelized)
    BandSegment { band: "60m", start_mhz: 5.332, end_mhz: 5.332, modes: &["USB", "CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("Channel 1") },
    BandSegment { band: "60m", start_mhz: 5.348, end_mhz: 5.348, modes: &["USB", "CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("Channel 2") },
    BandSegment { band: "60m", start_mhz: 5.358, end_mhz: 5.358, modes: &["USB", "CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("Channel 3") },
    BandSegment { band: "60m", start_mhz: 5.373, end_mhz: 5.373, modes: &["USB", "CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("Channel 4") },
    BandSegment { band: "60m", start_mhz: 5.405, end_mhz: 5.405, modes: &["USB", "CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("Channel 5") },
    // 40 meters
    BandSegment { band: "40m", start_mhz: 7.000, end_mhz: 7.025, modes: &["CW", "DATA"], minimum_license: LicenseClass::Extra, notes: Some("Extra CW/Data") },
    BandSegment { band: "40m", start_mhz: 7.025, end_mhz: 7.125, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("General CW/Data") },
    BandSegment { band: "40m", start_mhz: 7.025, end_mhz: 7.125, modes: &["CW"], minimum_license: LicenseClass::Technician, notes: Some("Tech CW only") },
    BandSegment { band: "40m", start_mhz: 7.125, end_mhz: 7.175, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::Extra, notes: Some("Extra Phone") },
    BandSegment { band: "40m", start_mhz: 7.175, end_mhz: 7.300, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("General Phone") },
    // 30 meters
    BandSegment { band: "30m", start_mhz: 10.100, end_mhz: 10.150, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("CW/Data only") },
    // 20 meters
    BandSegment { band: "20m", start_mhz: 14.000, end_mhz: 14.025, modes: &["CW", "DATA"], minimum_license: LicenseClass::Extra, notes: Some("Extra CW/Data") },
    BandSegment { band: "20m", start_mhz: 14.025, end_mhz: 14.150, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("General CW/Data") },
    BandSegment { band: "20m", start_mhz: 14.150, end_mhz: 14.225, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::Extra, notes: Some("Extra Phone") },
    BandSegment { band: "20m", start_mhz: 14.225, end_mhz: 14.350, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("General Phone") },
    // 17 meters
    BandSegment { band: "17m", start_mhz: 18.068, end_mhz: 18.110, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("CW/Data") },
    BandSegment { band: "17m", start_mhz: 18.110, end_mhz: 18.168, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("Phone") },
    // 15 meters
    BandSegment { band: "15m", start_mhz: 21.000, end_mhz: 21.025, modes: &["CW", "DATA"], minimum_license: LicenseClass::Extra, notes: Some("Extra CW/Data") },
    BandSegment { band: "15m", start_mhz: 21.025, end_mhz: 21.200, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("General CW/Data") },
    BandSegment { band: "15m", start_mhz: 21.025, end_mhz: 21.200, modes: &["CW"], minimum_license: LicenseClass::Technician, notes: Some("Tech CW only") },
    BandSegment { band: "15m", start_mhz: 21.200, end_mhz: 21.275, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::Extra, notes: Some("Extra Phone") },
    BandSegment { band: "15m", start_mhz: 21.275, end_mhz: 21.450, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("General Phone") },
    // 12 meters
    BandSegment { band: "12m", start_mhz: 24.890, end_mhz: 24.930, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("CW/Data") },
    BandSegment { band: "12m", start_mhz: 24.930, end_mhz: 24.990, modes: &["SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("Phone") },
    // 10 meters
    BandSegment { band: "10m", start_mhz: 28.000, end_mhz: 28.300, modes: &["CW", "DATA"], minimum_license: LicenseClass::General, notes: Some("CW/Data") },
    BandSegment { band: "10m", start_mhz: 28.000, end_mhz: 28.300, modes: &["CW", "DATA"], minimum_license: LicenseClass::Technician, notes: Some("Tech CW/Data") },
    BandSegment { band: "10m", start_mhz: 28.300, end_mhz: 28.500, modes: &["CW", "SSB", "PHONE"], minimum_license: LicenseClass::General, notes: Some("CW/Phone") },
    BandSegment { band: "10m", start_mhz: 28.300, end_mhz: 28.500, modes: &["CW", "SSB", "PHONE"], minimum_license: LicenseClass::Technician, notes: Some("Tech CW/Phone") },
    BandSegment { band: "10m", start_mhz: 28.500, end_mhz: 29.700, modes: &["SSB", "PHONE", "AM", "FM"], minimum_license: LicenseClass::General, notes: Some("Phone/AM/FM") },
    // VHF/UHF
    BandSegment { band: "6m", start_mhz: 50.000, end_mhz: 50.100, modes: &["CW"], minimum_license: LicenseClass::Technician, notes: Some("CW only") },
    BandSegment { band: "6m", start_mhz: 50.100, end_mhz: 54.000, modes: &["ALL"], minimum_license: LicenseClass::Technician, notes: None },
    BandSegment { band: "2m", start_mhz: 144.000, end_mhz: 144.100, modes: &["CW"], minimum_license: LicenseClass::Technician, notes: Some("CW only") },
    BandSegment { band: "2m", start_mhz: 144.100, end_mhz: 148.000, modes: &["ALL"], minimum_license: LicenseClass::Technician, notes: None },
    BandSegment { band: "70cm", start_mhz: 420.000, end_mhz: 450.000, modes: &["ALL"], minimum_license: LicenseClass::Technician, notes: None },
];

/// Find the first segment containing `frequency_mhz`, if any.
pub fn segment_for(frequency_mhz: f64) -> Option<&'static BandSegment> {
    SEGMENTS.iter().find(|s| s.contains(frequency_mhz))
}

/// All segments whose mode set allows `mode` (or is "ALL").
pub fn segments_allowing(mode: &str) -> impl Iterator<Item = &'static BandSegment> {
    let mode = mode.to_string();
    SEGMENTS.iter().filter(move |s| s.allows_mode(&mode))
}

/// All band names that appear in `SEGMENTS`, in first-seen order.
pub fn unique_bands() -> Vec<&'static str> {
    let mut seen: HashSet<&'static str> = HashSet::new();
    let mut bands = Vec::new();
    for s in SEGMENTS {
        if seen.insert(s.band) {
            bands.push(s.band);
        }
    }
    bands
}

// ---- Common frequency tables ----------------------------------------------

/// Region-2 (Americas) default CW calling frequencies (MHz).
pub const CW_CALLING_FREQUENCIES_REGION2: &[(&str, f64)] = &[
    ("160m", 1.810),
    ("80m", 3.560),
    ("40m", 7.030),
    ("30m", 10.116),
    ("20m", 14.060),
    ("17m", 18.080),
    ("15m", 21.060),
    ("12m", 24.910),
    ("10m", 28.060),
];

pub const CW_CALLING_FREQUENCIES_REGION1: &[(&str, f64)] = &[
    ("160m", 1.836),
    ("80m", 3.555),
    ("40m", 7.030),
    ("20m", 14.055),
    ("15m", 21.055),
    ("10m", 28.055),
];

pub const CW_CALLING_FREQUENCIES_REGION3: &[(&str, f64)] = &[
    ("160m", 1.836),
    ("80m", 3.525),
    ("40m", 7.030),
    ("20m", 14.060),
    ("15m", 21.060),
    ("10m", 28.060),
];

pub const SSB_CALLING_FREQUENCIES_REGION2: &[(&str, f64)] = &[
    ("160m", 1.900),
    ("80m", 3.885),
    ("40m", 7.200),
    ("20m", 14.250),
    ("17m", 18.140),
    ("15m", 21.300),
    ("12m", 24.950),
    ("10m", 28.400),
];

pub const SSB_CALLING_FREQUENCIES_REGION1: &[(&str, f64)] = &[
    ("160m", 1.843),
    ("80m", 3.690),
    ("40m", 7.090),
    ("20m", 14.285),
    ("15m", 21.205),
    ("10m", 28.500),
];

pub const SSB_CALLING_FREQUENCIES_REGION3: &[(&str, f64)] = &[
    ("160m", 1.850),
    ("80m", 3.825),
    ("40m", 7.090),
    ("20m", 14.250),
    ("15m", 21.350),
    ("10m", 28.500),
];

pub const FT8_FREQUENCIES: &[(&str, f64)] = &[
    ("160m", 1.840),
    ("80m", 3.573),
    ("40m", 7.074),
    ("30m", 10.136),
    ("20m", 14.074),
    ("17m", 18.100),
    ("15m", 21.074),
    ("12m", 24.915),
    ("10m", 28.074),
    ("6m", 50.313),
];

pub const FT4_FREQUENCIES: &[(&str, f64)] = &[
    ("80m", 3.575),
    ("40m", 7.0475),
    ("30m", 10.140),
    ("20m", 14.080),
    ("17m", 18.104),
    ("15m", 21.140),
    ("12m", 24.919),
    ("10m", 28.180),
    ("6m", 50.318),
];

pub const RTTY_FREQUENCIES: &[(&str, f64)] = &[
    ("80m", 3.580),
    ("40m", 7.080),
    ("20m", 14.080),
    ("15m", 21.080),
    ("10m", 28.080),
];

pub const AM_FREQUENCIES: &[(&str, f64)] = &[
    ("80m", 3.885),
    ("40m", 7.290),
    ("20m", 14.286),
];

pub const FM_FREQUENCIES: &[(&str, f64)] = &[
    ("10m", 29.600),
    ("6m", 52.525),
    ("2m", 146.520),
    ("70cm", 446.000),
];

fn lookup(table: &[(&str, f64)], band: &str) -> Option<f64> {
    table.iter().find(|(b, _)| *b == band).map(|(_, f)| *f)
}

/// CW calling frequency for `band` in the given region. Falls back to the
/// Region-2 table when no regional override is known (matches Swift).
pub fn cw_calling_frequency(band: &str, region: IaruRegion) -> Option<f64> {
    match region {
        IaruRegion::Region1 => {
            lookup(CW_CALLING_FREQUENCIES_REGION1, band)
                .or_else(|| lookup(CW_CALLING_FREQUENCIES_REGION2, band))
        }
        IaruRegion::Region2 => lookup(CW_CALLING_FREQUENCIES_REGION2, band),
        IaruRegion::Region3 => {
            lookup(CW_CALLING_FREQUENCIES_REGION3, band)
                .or_else(|| lookup(CW_CALLING_FREQUENCIES_REGION2, band))
        }
    }
}

/// SSB calling frequency (per-region with Region-2 fallback).
pub fn ssb_calling_frequency(band: &str, region: IaruRegion) -> Option<f64> {
    match region {
        IaruRegion::Region1 => {
            lookup(SSB_CALLING_FREQUENCIES_REGION1, band)
                .or_else(|| lookup(SSB_CALLING_FREQUENCIES_REGION2, band))
        }
        IaruRegion::Region2 => lookup(SSB_CALLING_FREQUENCIES_REGION2, band),
        IaruRegion::Region3 => {
            lookup(SSB_CALLING_FREQUENCIES_REGION3, band)
                .or_else(|| lookup(SSB_CALLING_FREQUENCIES_REGION2, band))
        }
    }
}

// ---- License privileges + validation (port of `BandPlanService`) -----------

/// Privilege rank: Technician < General < Extra (the `privilegeOrder` index).
pub fn license_rank(license: LicenseClass) -> usize {
    match license {
        LicenseClass::Technician => 0,
        LicenseClass::General => 1,
        LicenseClass::Extra => 2,
    }
}

/// Segments where `license` has privileges (`privilegedSegments(for:)`).
pub fn privileged_segments(license: LicenseClass) -> Vec<&'static BandSegment> {
    let user = license_rank(license);
    SEGMENTS.iter().filter(|seg| user >= license_rank(seg.minimum_license)).collect()
}

/// Map a mode to the segment vocabulary (`normalizeMode`): phone variants →
/// `PHONE`, data variants → `DATA`, else the uppercased mode.
pub fn normalize_mode(mode: &str) -> String {
    match mode.to_uppercase().as_str() {
        "LSB" | "USB" | "AM" | "FM" => "PHONE".to_string(),
        "RTTY" | "PSK" | "FT8" | "FT4" | "JTTY" | "JS8" | "WSPR" | "JT65" | "JT9" => "DATA".to_string(),
        other => other.to_string(),
    }
}

/// A band-plan rule violation classification (`BandPlanViolation.ViolationType`).
/// The planner only needs the category, so the message/suggestion strings the
/// Swift service builds are dropped here.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViolationType {
    NoPrivileges,
    WrongMode,
    OutOfBand,
    /// Soft warning — CW outside a CW segment is unusual but permitted.
    UnusualFrequency,
}

/// Classify a frequency/mode/license combination (`BandPlanService.validate`),
/// returning `None` when the operation is allowed. Faithful to the Swift branch
/// order: out-of-band → wrong-mode/unusual → license privileges.
pub fn validate(frequency_mhz: f64, mode: &str, license: LicenseClass) -> Option<ViolationType> {
    let normalized = normalize_mode(mode);
    let matching: Vec<&BandSegment> = SEGMENTS.iter().filter(|seg| seg.contains(frequency_mhz)).collect();
    if matching.is_empty() {
        return Some(ViolationType::OutOfBand);
    }
    let mode_segments: Vec<&&BandSegment> =
        matching.iter().filter(|seg| seg.allows_mode(&normalized)).collect();
    if mode_segments.is_empty() {
        // `buildModeViolation`: CW anywhere is only "unusual"; anything else is
        // the wrong mode for this frequency.
        return if normalized == "CW" {
            Some(ViolationType::UnusualFrequency)
        } else {
            Some(ViolationType::WrongMode)
        };
    }
    // `checkLicensePrivileges`: allowed if any mode segment is within privileges.
    let user = license_rank(license);
    let allowed = mode_segments.iter().any(|seg| user >= license_rank(seg.minimum_license));
    if allowed {
        None
    } else {
        Some(ViolationType::NoPrivileges)
    }
}

// ---- ARRL usage zones (port of `BandPlan+Activities` usage zones) -----------

/// Conventional (voluntary) usage of a frequency range per the ARRL band plan.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Usage {
    Cw,
    Digital,
    /// Mixed CW/data zones.
    CwAndDigital,
    Phone,
    Am,
    Fm,
}

/// A frequency range with its conventional usage. Unlike [`BandSegment`], the
/// range is **end-exclusive** (`UsageZone.contains` uses `<`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UsageZone {
    pub band: &'static str,
    pub start_mhz: f64,
    pub end_mhz: f64,
    pub usage: Usage,
}

impl UsageZone {
    pub fn contains(&self, frequency_mhz: f64) -> bool {
        frequency_mhz >= self.start_mhz && frequency_mhz < self.end_mhz
    }

    /// Whether `mode` conventionally belongs in this zone (`matchesMode`).
    pub fn matches_mode(&self, mode: &str) -> bool {
        match mode.to_uppercase().as_str() {
            "CW" => self.usage == Usage::Cw || self.usage == Usage::CwAndDigital,
            "SSB" | "USB" | "LSB" => self.usage == Usage::Phone,
            "FT8" | "FT4" | "RTTY" | "JTTY" | "PSK31" | "PSK" => {
                self.usage == Usage::Digital || self.usage == Usage::CwAndDigital
            }
            "AM" => self.usage == Usage::Am || self.usage == Usage::Phone,
            "FM" => self.usage == Usage::Fm,
            _ => self.usage == Usage::Cw || self.usage == Usage::CwAndDigital,
        }
    }

    /// Whether this is the *primary* (preferred) zone for `mode` — stricter than
    /// [`matches_mode`] (a mixed zone is not primary for CW) (`isPrimaryZone`).
    pub fn is_primary_zone(&self, mode: &str) -> bool {
        match mode.to_uppercase().as_str() {
            "CW" => self.usage == Usage::Cw,
            "SSB" | "USB" | "LSB" => self.usage == Usage::Phone,
            "FT8" | "FT4" | "RTTY" | "JTTY" | "PSK31" | "PSK" => self.usage == Usage::Digital,
            "AM" => self.usage == Usage::Am,
            "FM" => self.usage == Usage::Fm,
            _ => self.usage == Usage::Cw,
        }
    }
}

/// Conventional ARRL usage zones. Same data as `BandPlan.usageZones` in Swift.
pub const USAGE_ZONES: &[UsageZone] = &[
    UsageZone { band: "160m", start_mhz: 1.800, end_mhz: 1.810, usage: Usage::Cw },
    UsageZone { band: "160m", start_mhz: 1.810, end_mhz: 1.843, usage: Usage::CwAndDigital },
    UsageZone { band: "160m", start_mhz: 1.843, end_mhz: 2.000, usage: Usage::Phone },
    UsageZone { band: "80m", start_mhz: 3.500, end_mhz: 3.570, usage: Usage::Cw },
    UsageZone { band: "80m", start_mhz: 3.570, end_mhz: 3.600, usage: Usage::Digital },
    UsageZone { band: "80m", start_mhz: 3.600, end_mhz: 3.700, usage: Usage::CwAndDigital },
    UsageZone { band: "80m", start_mhz: 3.700, end_mhz: 4.000, usage: Usage::Phone },
    UsageZone { band: "60m", start_mhz: 5.332, end_mhz: 5.332, usage: Usage::CwAndDigital },
    UsageZone { band: "60m", start_mhz: 5.348, end_mhz: 5.348, usage: Usage::CwAndDigital },
    UsageZone { band: "60m", start_mhz: 5.358, end_mhz: 5.358, usage: Usage::CwAndDigital },
    UsageZone { band: "60m", start_mhz: 5.373, end_mhz: 5.373, usage: Usage::CwAndDigital },
    UsageZone { band: "60m", start_mhz: 5.405, end_mhz: 5.405, usage: Usage::CwAndDigital },
    UsageZone { band: "40m", start_mhz: 7.000, end_mhz: 7.040, usage: Usage::Cw },
    UsageZone { band: "40m", start_mhz: 7.040, end_mhz: 7.125, usage: Usage::CwAndDigital },
    UsageZone { band: "40m", start_mhz: 7.125, end_mhz: 7.300, usage: Usage::Phone },
    UsageZone { band: "30m", start_mhz: 10.100, end_mhz: 10.130, usage: Usage::Cw },
    UsageZone { band: "30m", start_mhz: 10.130, end_mhz: 10.150, usage: Usage::Digital },
    UsageZone { band: "20m", start_mhz: 14.000, end_mhz: 14.070, usage: Usage::Cw },
    UsageZone { band: "20m", start_mhz: 14.070, end_mhz: 14.100, usage: Usage::Digital },
    UsageZone { band: "20m", start_mhz: 14.100, end_mhz: 14.150, usage: Usage::CwAndDigital },
    UsageZone { band: "20m", start_mhz: 14.150, end_mhz: 14.350, usage: Usage::Phone },
    UsageZone { band: "17m", start_mhz: 18.068, end_mhz: 18.100, usage: Usage::Cw },
    UsageZone { band: "17m", start_mhz: 18.100, end_mhz: 18.110, usage: Usage::Digital },
    UsageZone { band: "17m", start_mhz: 18.110, end_mhz: 18.168, usage: Usage::Phone },
    UsageZone { band: "15m", start_mhz: 21.000, end_mhz: 21.070, usage: Usage::Cw },
    UsageZone { band: "15m", start_mhz: 21.070, end_mhz: 21.110, usage: Usage::Digital },
    UsageZone { band: "15m", start_mhz: 21.110, end_mhz: 21.200, usage: Usage::CwAndDigital },
    UsageZone { band: "15m", start_mhz: 21.200, end_mhz: 21.450, usage: Usage::Phone },
    UsageZone { band: "12m", start_mhz: 24.890, end_mhz: 24.920, usage: Usage::Cw },
    UsageZone { band: "12m", start_mhz: 24.920, end_mhz: 24.930, usage: Usage::Digital },
    UsageZone { band: "12m", start_mhz: 24.930, end_mhz: 24.990, usage: Usage::Phone },
    UsageZone { band: "10m", start_mhz: 28.000, end_mhz: 28.070, usage: Usage::Cw },
    UsageZone { band: "10m", start_mhz: 28.070, end_mhz: 28.150, usage: Usage::Digital },
    UsageZone { band: "10m", start_mhz: 28.150, end_mhz: 28.300, usage: Usage::CwAndDigital },
    UsageZone { band: "10m", start_mhz: 28.300, end_mhz: 29.000, usage: Usage::Phone },
    UsageZone { band: "10m", start_mhz: 29.000, end_mhz: 29.200, usage: Usage::Am },
    UsageZone { band: "10m", start_mhz: 29.500, end_mhz: 29.700, usage: Usage::Fm },
    UsageZone { band: "6m", start_mhz: 50.000, end_mhz: 50.100, usage: Usage::Cw },
    UsageZone { band: "6m", start_mhz: 50.100, end_mhz: 50.300, usage: Usage::Phone },
    UsageZone { band: "6m", start_mhz: 50.300, end_mhz: 50.600, usage: Usage::Digital },
    UsageZone { band: "6m", start_mhz: 52.000, end_mhz: 54.000, usage: Usage::Fm },
    UsageZone { band: "2m", start_mhz: 144.000, end_mhz: 144.100, usage: Usage::Cw },
    UsageZone { band: "2m", start_mhz: 144.100, end_mhz: 144.275, usage: Usage::Phone },
    UsageZone { band: "2m", start_mhz: 144.275, end_mhz: 144.500, usage: Usage::Digital },
    UsageZone { band: "2m", start_mhz: 146.000, end_mhz: 148.000, usage: Usage::Fm },
    UsageZone { band: "70cm", start_mhz: 420.000, end_mhz: 432.000, usage: Usage::Fm },
    UsageZone { band: "70cm", start_mhz: 432.000, end_mhz: 433.000, usage: Usage::Cw },
    UsageZone { band: "70cm", start_mhz: 440.000, end_mhz: 450.000, usage: Usage::Fm },
];

/// Usage zones for `band` that conventionally carry `mode` (`usageZones(forBand:mode:)`).
pub fn usage_zones_for(band: &str, mode: &str) -> Vec<&'static UsageZone> {
    USAGE_ZONES.iter().filter(|zone| zone.band == band && zone.matches_mode(mode)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segment_for_picks_first_matching_range() {
        let seg = segment_for(14.080).unwrap();
        assert_eq!(seg.band, "20m");
        // 80m extra-only range; first match should be the Extra 3.500–3.600 entry.
        let seg = segment_for(3.510).unwrap();
        assert_eq!(seg.minimum_license, LicenseClass::Extra);
    }

    #[test]
    fn segment_allows_mode_handles_all_alias() {
        let seg = segment_for(146.0).unwrap();
        assert!(seg.allows_mode("FM"));
        assert!(seg.allows_mode("FT8"));
    }

    #[test]
    fn frequency_lookup_with_region_fallback() {
        // 30m has no region-1 override → falls back to region-2 value.
        assert_eq!(
            cw_calling_frequency("30m", IaruRegion::Region1),
            Some(10.116)
        );
        // 80m region-1 specifically returns 3.555
        assert_eq!(
            cw_calling_frequency("80m", IaruRegion::Region1),
            Some(3.555)
        );
        // 20m region-2 default
        assert_eq!(
            ssb_calling_frequency("20m", IaruRegion::Region2),
            Some(14.250)
        );
    }

    #[test]
    fn unique_bands_in_first_seen_order() {
        let bands = unique_bands();
        assert_eq!(bands[0], "160m");
        assert!(bands.contains(&"6m"));
        assert!(bands.contains(&"70cm"));
    }

    #[test]
    fn segments_allowing_mode_returns_expected_count() {
        let cw_count = segments_allowing("CW").count();
        assert!(cw_count > 10);
    }
}
