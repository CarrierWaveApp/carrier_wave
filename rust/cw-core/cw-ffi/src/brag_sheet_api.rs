//! Brag Sheet FFI facade — the shared catalog/config/compute surface behind
//! the iOS `AsyncBragSheetStats` and its Android equivalent.
//!
//! Mirrors the `SessionWizardApi` structure: a thin `Arc<FieldStore>` facade,
//! `Ffi*` record/enum conversions over the pure `cw_domain::brag_sheet` types,
//! and cw-store `synced_config` persistence for the one configuration blob (a
//! synced entity, so the config rides the E2E dirty/push/pull journal and
//! converges across devices, LWW on `modified_at`).
//!
//! **Club overlay:** `compute_brag` maps every stat through
//! `cw_store::compute_configured_brag`, which always returns `NoData` for
//! `ClubMembersWorked` / `ClubsRepresented` (per Task 6 — those two need a
//! club roster that isn't visible to that layer). This facade closes that
//! gap: it reads the roster straight from the store's own `club` /
//! `club_member` tables (loading every member across every club, bounded to
//! `MAX_FETCH_LIMIT` per page), builds the callsign→club-name map exactly like
//! the iOS `clubsByCallsign` dictionary, calls `worked_member_callsigns` for
//! the resolved window, and overlays the two stats — full parity with Swift,
//! no residual gap (Swift reads its roster from the same club-membership
//! data, just app-side via SwiftData instead of cw-store).

use std::collections::HashMap;
use std::sync::Arc;

use chrono::{TimeZone, Utc};
use cw_domain::brag_sheet::{
    BandTableEntry as DomainBandTableEntry, BragCategory, BragConfiguration, BragPeriod,
    BragPeriodConfig, BragPreset, BragStatType, BragStatValue,
    ModeStreakEntry as DomainModeStreakEntry,
};
use cw_store::{ClubMemberFilter, MAX_FETCH_LIMIT};

use crate::{CwError, FieldStore};

/// `synced_config.config_type` for the persisted `BragConfiguration` blob. This
/// is a synced entity (rides the E2E dirty/push/pull journal, LWW on
/// `modified_at`), so the brag config converges across devices.
const CONFIG_TYPE_BRAG: &str = "bragSheet";

// ---------- Ffi enums ----------

#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiBragStatType {
    TotalQsos,
    TotalCwQsos,
    TotalPhoneQsos,
    TotalDigitalQsos,
    TotalDistance,
    OperatingDays,
    OperatingHours,
    ActiveBands,
    ActiveModes,
    UniqueCallsigns,
    QrpQsoCount,
    MilliwattQsoCount,
    Fastest10Qsos,
    Peak15MinRate,
    BestSessionRate,
    FastestActivation,
    FurthestContact,
    FurthestContactPerBand,
    FurthestQrpContact,
    AverageContactDistance,
    LowestPowerContact,
    BestWattsPerMile,
    DxccEntities,
    NewDxccEntities,
    StatesAndProvinces,
    GridSquares,
    Continents,
    MostContinentsInADay,
    WorkedAllStatesProgress,
    MostQsosInADay,
    MostQsosInASession,
    MostCountriesInADay,
    MostBandsInADay,
    CurrentOnAirStreak,
    BestOnAirStreak,
    CurrentActivationStreak,
    ModeStreaks,
    ParksActivated,
    ParksHunted,
    ParkToParkContacts,
    LargestNfer,
    BestActivation,
    NewParks,
    FastestCwSpeed,
    CwDistanceRecord,
    CwQrpRecord,
    PerfectReports,
    AverageRstReceived,
    BestRstAtDistance,
    EarliestQsoOfTheDay,
    LatestQsoOfTheDay,
    LongestSession,
    MostActiveDayOfWeek,
    BusiestBand,
    BusiestMode,
    RepeatCustomers,
    ClubMembersWorked,
    ClubsRepresented,
}

impl From<BragStatType> for FfiBragStatType {
    fn from(value: BragStatType) -> Self {
        use BragStatType::*;
        match value {
            TotalQsos => FfiBragStatType::TotalQsos,
            TotalCwQsos => FfiBragStatType::TotalCwQsos,
            TotalPhoneQsos => FfiBragStatType::TotalPhoneQsos,
            TotalDigitalQsos => FfiBragStatType::TotalDigitalQsos,
            TotalDistance => FfiBragStatType::TotalDistance,
            OperatingDays => FfiBragStatType::OperatingDays,
            OperatingHours => FfiBragStatType::OperatingHours,
            ActiveBands => FfiBragStatType::ActiveBands,
            ActiveModes => FfiBragStatType::ActiveModes,
            UniqueCallsigns => FfiBragStatType::UniqueCallsigns,
            QrpQsoCount => FfiBragStatType::QrpQsoCount,
            MilliwattQsoCount => FfiBragStatType::MilliwattQsoCount,
            Fastest10Qsos => FfiBragStatType::Fastest10Qsos,
            Peak15MinRate => FfiBragStatType::Peak15MinRate,
            BestSessionRate => FfiBragStatType::BestSessionRate,
            FastestActivation => FfiBragStatType::FastestActivation,
            FurthestContact => FfiBragStatType::FurthestContact,
            FurthestContactPerBand => FfiBragStatType::FurthestContactPerBand,
            FurthestQrpContact => FfiBragStatType::FurthestQrpContact,
            AverageContactDistance => FfiBragStatType::AverageContactDistance,
            LowestPowerContact => FfiBragStatType::LowestPowerContact,
            BestWattsPerMile => FfiBragStatType::BestWattsPerMile,
            DxccEntities => FfiBragStatType::DxccEntities,
            NewDxccEntities => FfiBragStatType::NewDxccEntities,
            StatesAndProvinces => FfiBragStatType::StatesAndProvinces,
            GridSquares => FfiBragStatType::GridSquares,
            Continents => FfiBragStatType::Continents,
            MostContinentsInADay => FfiBragStatType::MostContinentsInADay,
            WorkedAllStatesProgress => FfiBragStatType::WorkedAllStatesProgress,
            MostQsosInADay => FfiBragStatType::MostQsosInADay,
            MostQsosInASession => FfiBragStatType::MostQsosInASession,
            MostCountriesInADay => FfiBragStatType::MostCountriesInADay,
            MostBandsInADay => FfiBragStatType::MostBandsInADay,
            CurrentOnAirStreak => FfiBragStatType::CurrentOnAirStreak,
            BestOnAirStreak => FfiBragStatType::BestOnAirStreak,
            CurrentActivationStreak => FfiBragStatType::CurrentActivationStreak,
            ModeStreaks => FfiBragStatType::ModeStreaks,
            ParksActivated => FfiBragStatType::ParksActivated,
            ParksHunted => FfiBragStatType::ParksHunted,
            ParkToParkContacts => FfiBragStatType::ParkToParkContacts,
            LargestNfer => FfiBragStatType::LargestNfer,
            BestActivation => FfiBragStatType::BestActivation,
            NewParks => FfiBragStatType::NewParks,
            FastestCwSpeed => FfiBragStatType::FastestCwSpeed,
            CwDistanceRecord => FfiBragStatType::CwDistanceRecord,
            CwQrpRecord => FfiBragStatType::CwQrpRecord,
            PerfectReports => FfiBragStatType::PerfectReports,
            AverageRstReceived => FfiBragStatType::AverageRstReceived,
            BestRstAtDistance => FfiBragStatType::BestRstAtDistance,
            EarliestQsoOfTheDay => FfiBragStatType::EarliestQsoOfTheDay,
            LatestQsoOfTheDay => FfiBragStatType::LatestQsoOfTheDay,
            LongestSession => FfiBragStatType::LongestSession,
            MostActiveDayOfWeek => FfiBragStatType::MostActiveDayOfWeek,
            BusiestBand => FfiBragStatType::BusiestBand,
            BusiestMode => FfiBragStatType::BusiestMode,
            RepeatCustomers => FfiBragStatType::RepeatCustomers,
            ClubMembersWorked => FfiBragStatType::ClubMembersWorked,
            ClubsRepresented => FfiBragStatType::ClubsRepresented,
        }
    }
}

impl From<FfiBragStatType> for BragStatType {
    fn from(value: FfiBragStatType) -> Self {
        use FfiBragStatType::*;
        match value {
            TotalQsos => BragStatType::TotalQsos,
            TotalCwQsos => BragStatType::TotalCwQsos,
            TotalPhoneQsos => BragStatType::TotalPhoneQsos,
            TotalDigitalQsos => BragStatType::TotalDigitalQsos,
            TotalDistance => BragStatType::TotalDistance,
            OperatingDays => BragStatType::OperatingDays,
            OperatingHours => BragStatType::OperatingHours,
            ActiveBands => BragStatType::ActiveBands,
            ActiveModes => BragStatType::ActiveModes,
            UniqueCallsigns => BragStatType::UniqueCallsigns,
            QrpQsoCount => BragStatType::QrpQsoCount,
            MilliwattQsoCount => BragStatType::MilliwattQsoCount,
            Fastest10Qsos => BragStatType::Fastest10Qsos,
            Peak15MinRate => BragStatType::Peak15MinRate,
            BestSessionRate => BragStatType::BestSessionRate,
            FastestActivation => BragStatType::FastestActivation,
            FurthestContact => BragStatType::FurthestContact,
            FurthestContactPerBand => BragStatType::FurthestContactPerBand,
            FurthestQrpContact => BragStatType::FurthestQrpContact,
            AverageContactDistance => BragStatType::AverageContactDistance,
            LowestPowerContact => BragStatType::LowestPowerContact,
            BestWattsPerMile => BragStatType::BestWattsPerMile,
            DxccEntities => BragStatType::DxccEntities,
            NewDxccEntities => BragStatType::NewDxccEntities,
            StatesAndProvinces => BragStatType::StatesAndProvinces,
            GridSquares => BragStatType::GridSquares,
            Continents => BragStatType::Continents,
            MostContinentsInADay => BragStatType::MostContinentsInADay,
            WorkedAllStatesProgress => BragStatType::WorkedAllStatesProgress,
            MostQsosInADay => BragStatType::MostQsosInADay,
            MostQsosInASession => BragStatType::MostQsosInASession,
            MostCountriesInADay => BragStatType::MostCountriesInADay,
            MostBandsInADay => BragStatType::MostBandsInADay,
            CurrentOnAirStreak => BragStatType::CurrentOnAirStreak,
            BestOnAirStreak => BragStatType::BestOnAirStreak,
            CurrentActivationStreak => BragStatType::CurrentActivationStreak,
            ModeStreaks => BragStatType::ModeStreaks,
            ParksActivated => BragStatType::ParksActivated,
            ParksHunted => BragStatType::ParksHunted,
            ParkToParkContacts => BragStatType::ParkToParkContacts,
            LargestNfer => BragStatType::LargestNfer,
            BestActivation => BragStatType::BestActivation,
            NewParks => BragStatType::NewParks,
            FastestCwSpeed => BragStatType::FastestCwSpeed,
            CwDistanceRecord => BragStatType::CwDistanceRecord,
            CwQrpRecord => BragStatType::CwQrpRecord,
            PerfectReports => BragStatType::PerfectReports,
            AverageRstReceived => BragStatType::AverageRstReceived,
            BestRstAtDistance => BragStatType::BestRstAtDistance,
            EarliestQsoOfTheDay => BragStatType::EarliestQsoOfTheDay,
            LatestQsoOfTheDay => BragStatType::LatestQsoOfTheDay,
            LongestSession => BragStatType::LongestSession,
            MostActiveDayOfWeek => BragStatType::MostActiveDayOfWeek,
            BusiestBand => BragStatType::BusiestBand,
            BusiestMode => BragStatType::BusiestMode,
            RepeatCustomers => BragStatType::RepeatCustomers,
            ClubMembersWorked => BragStatType::ClubMembersWorked,
            ClubsRepresented => BragStatType::ClubsRepresented,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiBragCategory {
    Totals,
    SpeedAndRate,
    Distance,
    PowerAndEfficiency,
    GeographicReach,
    VolumeRecords,
    Streaks,
    Pota,
    Cw,
    SignalQuality,
    FunAndUnique,
}

impl From<BragCategory> for FfiBragCategory {
    fn from(value: BragCategory) -> Self {
        use BragCategory::*;
        match value {
            Totals => FfiBragCategory::Totals,
            SpeedAndRate => FfiBragCategory::SpeedAndRate,
            Distance => FfiBragCategory::Distance,
            PowerAndEfficiency => FfiBragCategory::PowerAndEfficiency,
            GeographicReach => FfiBragCategory::GeographicReach,
            VolumeRecords => FfiBragCategory::VolumeRecords,
            Streaks => FfiBragCategory::Streaks,
            Pota => FfiBragCategory::Pota,
            Cw => FfiBragCategory::Cw,
            SignalQuality => FfiBragCategory::SignalQuality,
            FunAndUnique => FfiBragCategory::FunAndUnique,
        }
    }
}

impl From<FfiBragCategory> for BragCategory {
    fn from(value: FfiBragCategory) -> Self {
        use FfiBragCategory::*;
        match value {
            Totals => BragCategory::Totals,
            SpeedAndRate => BragCategory::SpeedAndRate,
            Distance => BragCategory::Distance,
            PowerAndEfficiency => BragCategory::PowerAndEfficiency,
            GeographicReach => BragCategory::GeographicReach,
            VolumeRecords => BragCategory::VolumeRecords,
            Streaks => BragCategory::Streaks,
            Pota => BragCategory::Pota,
            Cw => BragCategory::Cw,
            SignalQuality => BragCategory::SignalQuality,
            FunAndUnique => BragCategory::FunAndUnique,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiBragPeriod {
    Weekly,
    Monthly,
    AllTime,
}

impl From<BragPeriod> for FfiBragPeriod {
    fn from(value: BragPeriod) -> Self {
        match value {
            BragPeriod::Weekly => FfiBragPeriod::Weekly,
            BragPeriod::Monthly => FfiBragPeriod::Monthly,
            BragPeriod::AllTime => FfiBragPeriod::AllTime,
        }
    }
}

impl From<FfiBragPeriod> for BragPeriod {
    fn from(value: FfiBragPeriod) -> Self {
        match value {
            FfiBragPeriod::Weekly => BragPeriod::Weekly,
            FfiBragPeriod::Monthly => BragPeriod::Monthly,
            FfiBragPeriod::AllTime => BragPeriod::AllTime,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, PartialEq, Eq, Debug)]
pub enum FfiBragPreset {
    General,
    Dxer,
    Qrp,
    Activator,
    Contester,
    CwEnthusiast,
    ShowEverything,
}

impl From<BragPreset> for FfiBragPreset {
    fn from(value: BragPreset) -> Self {
        use BragPreset::*;
        match value {
            General => FfiBragPreset::General,
            Dxer => FfiBragPreset::Dxer,
            Qrp => FfiBragPreset::Qrp,
            Activator => FfiBragPreset::Activator,
            Contester => FfiBragPreset::Contester,
            CwEnthusiast => FfiBragPreset::CwEnthusiast,
            ShowEverything => FfiBragPreset::ShowEverything,
        }
    }
}

impl From<FfiBragPreset> for BragPreset {
    fn from(value: FfiBragPreset) -> Self {
        use FfiBragPreset::*;
        match value {
            General => BragPreset::General,
            Dxer => BragPreset::Dxer,
            Qrp => BragPreset::Qrp,
            Activator => BragPreset::Activator,
            Contester => BragPreset::Contester,
            CwEnthusiast => BragPreset::CwEnthusiast,
            ShowEverything => BragPreset::ShowEverything,
        }
    }
}

/// Per-band table row. Mirrors `cw_domain::brag_sheet::BandTableEntry`.
#[derive(uniffi::Record, Clone, PartialEq, Debug)]
pub struct FfiBandTableEntry {
    pub band: String,
    pub callsign: String,
    pub distance_km: Option<f64>,
}

impl From<DomainBandTableEntry> for FfiBandTableEntry {
    fn from(value: DomainBandTableEntry) -> Self {
        FfiBandTableEntry { band: value.band, callsign: value.callsign, distance_km: value.distance_km }
    }
}

impl From<FfiBandTableEntry> for DomainBandTableEntry {
    fn from(value: FfiBandTableEntry) -> Self {
        DomainBandTableEntry { band: value.band, callsign: value.callsign, distance_km: value.distance_km }
    }
}

/// One mode's on-air streak. Mirrors `cw_domain::brag_sheet::ModeStreakEntry`.
#[derive(uniffi::Record, Clone, PartialEq, Debug)]
pub struct FfiModeStreakEntry {
    pub mode: String,
    pub current: i64,
    pub longest: i64,
}

impl From<DomainModeStreakEntry> for FfiModeStreakEntry {
    fn from(value: DomainModeStreakEntry) -> Self {
        FfiModeStreakEntry { mode: value.mode, current: value.current, longest: value.longest }
    }
}

impl From<FfiModeStreakEntry> for DomainModeStreakEntry {
    fn from(value: FfiModeStreakEntry) -> Self {
        DomainModeStreakEntry { mode: value.mode, current: value.current, longest: value.longest }
    }
}

/// A computed stat value. Mirrors `cw_domain::brag_sheet::BragStatValue`, one
/// variant per case (UniFFI enums can't carry per-variant docs from the
/// domain type, so the shape is duplicated verbatim).
#[derive(uniffi::Enum, Clone, PartialEq, Debug)]
pub enum FfiBragStatValue {
    Count { value: i64 },
    Distance { km: f64 },
    Duration { seconds: f64 },
    Rate { value: f64, label: String },
    Contact { callsign: String, distance_km: Option<f64>, band: Option<String> },
    Power { watts: f64, callsign: String, distance_km: Option<f64>, band: Option<String> },
    Efficiency { watts_per_mile: f64, detail: String },
    Progress { current: i64, total: i64 },
    Streak { current: i64, longest: i64 },
    BandTable { entries: Vec<FfiBandTableEntry> },
    DayOfWeek { day: String, count: i64 },
    CallsignCount { callsign: String, count: i64 },
    TimeOfDay { unix_seconds: i64 },
    ParkDetail { park: String, date: Option<String>, count: i64 },
    ModeStreakList { entries: Vec<FfiModeStreakEntry> },
    Wpm { words: i64 },
    Rst { value: String, detail: Option<String> },
    NoData,
}

impl From<BragStatValue> for FfiBragStatValue {
    fn from(value: BragStatValue) -> Self {
        match value {
            BragStatValue::Count(value) => FfiBragStatValue::Count { value },
            BragStatValue::Distance { km } => FfiBragStatValue::Distance { km },
            BragStatValue::Duration { seconds } => FfiBragStatValue::Duration { seconds },
            BragStatValue::Rate { value, label } => FfiBragStatValue::Rate { value, label },
            BragStatValue::Contact { callsign, distance_km, band } => {
                FfiBragStatValue::Contact { callsign, distance_km, band }
            }
            BragStatValue::Power { watts, callsign, distance_km, band } => {
                FfiBragStatValue::Power { watts, callsign, distance_km, band }
            }
            BragStatValue::Efficiency { watts_per_mile, detail } => {
                FfiBragStatValue::Efficiency { watts_per_mile, detail }
            }
            BragStatValue::Progress { current, total } => FfiBragStatValue::Progress { current, total },
            BragStatValue::Streak { current, longest } => FfiBragStatValue::Streak { current, longest },
            BragStatValue::BandTable(entries) => {
                FfiBragStatValue::BandTable { entries: entries.into_iter().map(FfiBandTableEntry::from).collect() }
            }
            BragStatValue::DayOfWeek { day, count } => FfiBragStatValue::DayOfWeek { day, count },
            BragStatValue::CallsignCount { callsign, count } => {
                FfiBragStatValue::CallsignCount { callsign, count }
            }
            BragStatValue::TimeOfDay { unix_seconds } => FfiBragStatValue::TimeOfDay { unix_seconds },
            BragStatValue::ParkDetail { park, date, count } => {
                FfiBragStatValue::ParkDetail { park, date, count }
            }
            BragStatValue::ModeStreakList(entries) => FfiBragStatValue::ModeStreakList {
                entries: entries.into_iter().map(FfiModeStreakEntry::from).collect(),
            },
            BragStatValue::Wpm(words) => FfiBragStatValue::Wpm { words },
            BragStatValue::Rst { value, detail } => FfiBragStatValue::Rst { value, detail },
            BragStatValue::NoData => FfiBragStatValue::NoData,
        }
    }
}

impl From<FfiBragStatValue> for BragStatValue {
    fn from(value: FfiBragStatValue) -> Self {
        match value {
            FfiBragStatValue::Count { value } => BragStatValue::Count(value),
            FfiBragStatValue::Distance { km } => BragStatValue::Distance { km },
            FfiBragStatValue::Duration { seconds } => BragStatValue::Duration { seconds },
            FfiBragStatValue::Rate { value, label } => BragStatValue::Rate { value, label },
            FfiBragStatValue::Contact { callsign, distance_km, band } => {
                BragStatValue::Contact { callsign, distance_km, band }
            }
            FfiBragStatValue::Power { watts, callsign, distance_km, band } => {
                BragStatValue::Power { watts, callsign, distance_km, band }
            }
            FfiBragStatValue::Efficiency { watts_per_mile, detail } => {
                BragStatValue::Efficiency { watts_per_mile, detail }
            }
            FfiBragStatValue::Progress { current, total } => BragStatValue::Progress { current, total },
            FfiBragStatValue::Streak { current, longest } => BragStatValue::Streak { current, longest },
            FfiBragStatValue::BandTable { entries } => {
                BragStatValue::BandTable(entries.into_iter().map(DomainBandTableEntry::from).collect())
            }
            FfiBragStatValue::DayOfWeek { day, count } => BragStatValue::DayOfWeek { day, count },
            FfiBragStatValue::CallsignCount { callsign, count } => {
                BragStatValue::CallsignCount { callsign, count }
            }
            FfiBragStatValue::TimeOfDay { unix_seconds } => BragStatValue::TimeOfDay { unix_seconds },
            FfiBragStatValue::ParkDetail { park, date, count } => {
                BragStatValue::ParkDetail { park, date, count }
            }
            FfiBragStatValue::ModeStreakList { entries } => {
                BragStatValue::ModeStreakList(entries.into_iter().map(DomainModeStreakEntry::from).collect())
            }
            FfiBragStatValue::Wpm { words } => BragStatValue::Wpm(words),
            FfiBragStatValue::Rst { value, detail } => BragStatValue::Rst { value, detail },
            FfiBragStatValue::NoData => BragStatValue::NoData,
        }
    }
}

// ---------- Ffi records ----------

/// Catalog metadata for one stat. Port of `BragSheetStatType`'s display
/// surface (`catalog()`).
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiBragStatMeta {
    pub stat_type: FfiBragStatType,
    pub display_name: String,
    pub short_display_name: String,
    pub category: FfiBragCategory,
    pub icon_key: String,
}

/// Category metadata. Port of `BragSheetCategory`'s display surface
/// (`categories()`).
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiBragCategoryMeta {
    pub category: FfiBragCategory,
    pub display_name: String,
}

/// Preset metadata (name + description + the ordered stat list, so clients
/// can render a preview before applying, plus the default hero-stat subset
/// `apply_preset` would select).
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiBragPresetInfo {
    pub preset: FfiBragPreset,
    pub display_name: String,
    pub description: String,
    pub stats: Vec<FfiBragStatType>,
    pub default_hero_stats: Vec<FfiBragStatType>,
}

/// Per-period configuration. Mirrors `cw_domain::brag_sheet::BragPeriodConfig`.
#[derive(uniffi::Record, Clone, PartialEq, Debug)]
pub struct FfiBragPeriodConfig {
    pub enabled_stats: Vec<FfiBragStatType>,
    pub hero_stats: Vec<FfiBragStatType>,
    pub base_preset: Option<FfiBragPreset>,
}

impl From<BragPeriodConfig> for FfiBragPeriodConfig {
    fn from(value: BragPeriodConfig) -> Self {
        FfiBragPeriodConfig {
            enabled_stats: value.enabled_stats.into_iter().map(FfiBragStatType::from).collect(),
            hero_stats: value.hero_stats.into_iter().map(FfiBragStatType::from).collect(),
            base_preset: value.base_preset.map(FfiBragPreset::from),
        }
    }
}

impl From<FfiBragPeriodConfig> for BragPeriodConfig {
    fn from(value: FfiBragPeriodConfig) -> Self {
        BragPeriodConfig {
            enabled_stats: value.enabled_stats.into_iter().map(BragStatType::from).collect(),
            hero_stats: value.hero_stats.into_iter().map(BragStatType::from).collect(),
            base_preset: value.base_preset.map(BragPreset::from),
        }
    }
}

/// Top-level configuration. Mirrors `cw_domain::brag_sheet::BragConfiguration`.
#[derive(uniffi::Record, Clone, PartialEq, Debug)]
pub struct FfiBragConfiguration {
    pub weekly: FfiBragPeriodConfig,
    pub monthly: FfiBragPeriodConfig,
    pub all_time: FfiBragPeriodConfig,
    pub include_map: bool,
    pub include_equipment_summary: bool,
    pub gold_record_badges: bool,
}

impl From<BragConfiguration> for FfiBragConfiguration {
    fn from(value: BragConfiguration) -> Self {
        FfiBragConfiguration {
            weekly: value.weekly.into(),
            monthly: value.monthly.into(),
            all_time: value.all_time.into(),
            include_map: value.include_map,
            include_equipment_summary: value.include_equipment_summary,
            gold_record_badges: value.gold_record_badges,
        }
    }
}

impl From<FfiBragConfiguration> for BragConfiguration {
    fn from(value: FfiBragConfiguration) -> Self {
        BragConfiguration {
            weekly: value.weekly.into(),
            monthly: value.monthly.into(),
            all_time: value.all_time.into(),
            include_map: value.include_map,
            include_equipment_summary: value.include_equipment_summary,
            gold_record_badges: value.gold_record_badges,
        }
    }
}

/// One computed stat result, ready for display.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiBragStatResult {
    pub stat_type: FfiBragStatType,
    pub value: FfiBragStatValue,
    pub formatted: String,
    pub icon_key: String,
}

// ---------- API object ----------

/// Brag Sheet API bound to a [`FieldStore`]. Stateless beyond the store
/// handle — catalog/category/preset metadata is pure; config is persisted to
/// the store's synced `synced_config` table; `compute_brag` reads QSOs (+ the club roster for the two
/// club overlay stats) from the store.
#[derive(uniffi::Object)]
pub struct BragSheetApi {
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl BragSheetApi {
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>) -> Self {
        BragSheetApi { store }
    }

    /// All 58 stat types with display metadata, in catalog order.
    pub fn catalog(&self) -> Vec<FfiBragStatMeta> {
        BragStatType::all()
            .into_iter()
            .map(|stat| FfiBragStatMeta {
                stat_type: stat.into(),
                display_name: stat.display_name().to_string(),
                short_display_name: stat.short_display_name().to_string(),
                category: stat.category().into(),
                icon_key: stat.icon_key().to_string(),
            })
            .collect()
    }

    /// All 11 categories with display metadata, in declaration order.
    pub fn categories(&self) -> Vec<FfiBragCategoryMeta> {
        BragCategory::all()
            .into_iter()
            .map(|category| FfiBragCategoryMeta {
                category: category.into(),
                display_name: category.display_name().to_string(),
            })
            .collect()
    }

    /// All 7 curated presets with display metadata, in declaration order.
    pub fn presets(&self) -> Vec<FfiBragPresetInfo> {
        BragPreset::all()
            .into_iter()
            .map(|preset| FfiBragPresetInfo {
                preset: preset.into(),
                display_name: preset.display_name().to_string(),
                description: preset.description().to_string(),
                stats: preset.stats().into_iter().map(FfiBragStatType::from).collect(),
                default_hero_stats: preset.default_hero_stats().into_iter().map(FfiBragStatType::from).collect(),
            })
            .collect()
    }

    /// Load the persisted brag sheet configuration from the synced-config store.
    /// Missing row ⇒ `BragConfiguration::default()` (mirrors the Swift
    /// `UserDefaults`-missing-blob fallback).
    pub fn load_config(&self) -> Result<FfiBragConfiguration, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let config = match store.fetch_synced_config(CONFIG_TYPE_BRAG)? {
            Some(raw) => serde_json::from_str::<BragConfiguration>(&raw)
                .map_err(|err| CwError::Store { reason: format!("invalid brag configuration blob: {err}") })?,
            None => BragConfiguration::default(),
        };
        Ok(config.into())
    }

    /// Persist the brag sheet configuration to the synced-config store, marking
    /// the row dirty with a fresh `modified_at` so the change is pushed on the
    /// next sync pass (LWW convergence across devices).
    pub fn save_config(&self, cfg: FfiBragConfiguration) -> Result<(), CwError> {
        let config: BragConfiguration = cfg.into();
        let raw = serde_json::to_string(&config)
            .map_err(|err| CwError::Store { reason: format!("failed to encode brag configuration: {err}") })?;
        let store = self.store.inner.lock().expect("store mutex poisoned");
        store.upsert_synced_config(CONFIG_TYPE_BRAG, &raw, Some(Utc::now().timestamp()), true)?;
        Ok(())
    }

    /// Idempotently import a legacy brag-sheet config JSON blob (the iOS
    /// `UserDefaults["bragSheetConfiguration"]` value) into the synced-config
    /// store, marking it dirty (a fresh `modified_at`) so it pushes. No-ops if a
    /// row already exists. Returns true if it wrote (migrated), false if it
    /// skipped (already present) — errors only on malformed JSON.
    pub fn import_legacy_config(&self, legacy_json: String) -> Result<bool, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        if store.fetch_synced_config(CONFIG_TYPE_BRAG)?.is_some() {
            return Ok(false);
        }
        let config = serde_json::from_str::<BragConfiguration>(&legacy_json)
            .map_err(|err| CwError::Store { reason: format!("invalid legacy brag configuration blob: {err}") })?;
        let raw = serde_json::to_string(&config)
            .map_err(|err| CwError::Store { reason: format!("failed to encode brag configuration: {err}") })?;
        store.upsert_synced_config(CONFIG_TYPE_BRAG, &raw, Some(Utc::now().timestamp()), true)?;
        Ok(true)
    }

    /// Apply `preset` to `period` on `config`, returning the mutated
    /// configuration. Stateless transform — the caller persists the result
    /// via `save_config`. Port of `BragSheetConfiguration.applyPreset(_:to:)`.
    pub fn apply_preset(
        &self,
        config: FfiBragConfiguration,
        preset: FfiBragPreset,
        period: FfiBragPeriod,
    ) -> FfiBragConfiguration {
        let mut config: BragConfiguration = config.into();
        config.apply_preset(preset.into(), period.into());
        config.into()
    }

    /// Copy the `from` period's config onto `to`, returning the mutated
    /// configuration. Port of `BragSheetConfiguration.copyConfig(from:to:)`.
    pub fn copy_period_config(
        &self,
        config: FfiBragConfiguration,
        from: FfiBragPeriod,
        to: FfiBragPeriod,
    ) -> FfiBragConfiguration {
        let mut config: BragConfiguration = config.into();
        config.copy_config(from.into(), to.into());
        config.into()
    }

    /// Toggle `stat` on or off for `period`, returning the mutated
    /// configuration. Port of `BragSheetPeriodConfig.toggle(_:)`.
    pub fn toggle_stat(
        &self,
        config: FfiBragConfiguration,
        stat: FfiBragStatType,
        period: FfiBragPeriod,
    ) -> FfiBragConfiguration {
        let mut config: BragConfiguration = config.into();
        let period: BragPeriod = period.into();
        let mut period_config = config.config_for(period).clone();
        period_config.toggle(stat.into());
        config.set_config(period_config, period);
        config.into()
    }

    /// Toggle hero status for `stat` on `period`, returning the mutated
    /// configuration. The domain `toggle_hero` enforces the 4-stat hero cap
    /// and rejects stats that aren't enabled — a rejected toggle simply
    /// leaves the config unchanged. Port of
    /// `BragSheetPeriodConfig.toggleHero(_:)`.
    pub fn toggle_hero_stat(
        &self,
        config: FfiBragConfiguration,
        stat: FfiBragStatType,
        period: FfiBragPeriod,
    ) -> FfiBragConfiguration {
        let mut config: BragConfiguration = config.into();
        let period: BragPeriod = period.into();
        let mut period_config = config.config_for(period).clone();
        period_config.toggle_hero(stat.into());
        config.set_config(period_config, period);
        config.into()
    }

    /// Move a stat within `period`'s enabled list from index `from` to `to`,
    /// returning the mutated configuration. Port of
    /// `BragSheetPeriodConfig.move(from:to:)`.
    pub fn move_stat(
        &self,
        config: FfiBragConfiguration,
        period: FfiBragPeriod,
        from: u32,
        to: u32,
    ) -> FfiBragConfiguration {
        let mut config: BragConfiguration = config.into();
        let period: BragPeriod = period.into();
        let mut period_config = config.config_for(period).clone();
        period_config.move_stat(from as usize, to as usize);
        config.set_config(period_config, period);
        config.into()
    }

    /// Compute every enabled stat for `period` as of `now_unix` (unix
    /// seconds), in the configured enabled order. Resolves the period's UTC
    /// window, loads the persisted config, dispatches to
    /// `Store::compute_configured_brag` for the 56 store-computable stats,
    /// then overlays `ClubMembersWorked` / `ClubsRepresented` from the
    /// store's own club roster (see module docs) — full parity with the
    /// Swift `BragSheetComputationActor+RustOverlay` club stats.
    ///
    /// `use_metric` selects the unit system for `formatted` on
    /// distance-bearing stats (mirrors iOS `UnitFormatter.useMetric`), so
    /// both platforms render byte-identical distance strings.
    pub fn compute_brag(
        &self,
        period: FfiBragPeriod,
        now_unix: i64,
        use_metric: bool,
    ) -> Result<Vec<FfiBragStatResult>, CwError> {
        let period: BragPeriod = period.into();
        let now = Utc.timestamp_opt(now_unix, 0).single().unwrap_or_else(Utc::now);
        let (start, end) = period.window(now);
        let today = now.date_naive();

        let config = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            match store.fetch_synced_config(CONFIG_TYPE_BRAG)? {
                Some(raw) => serde_json::from_str::<BragConfiguration>(&raw).map_err(|err| CwError::Store {
                    reason: format!("invalid brag configuration blob: {err}"),
                })?,
                None => BragConfiguration::default(),
            }
        };
        let enabled = config.config_for(period).enabled_stats.clone();

        let parsed = cw_domain::query::parse("").map_err(CwError::from)?.with_date_window(start, end);

        let needs_club_overlay =
            enabled.contains(&BragStatType::ClubMembersWorked) || enabled.contains(&BragStatType::ClubsRepresented);

        let (mut computed, worked_members, clubs_by_callsign) = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            let computed = store.compute_configured_brag(&parsed, &enabled, today)?;
            if needs_club_overlay {
                let (roster, clubs_by_callsign) = club_roster(&store)?;
                let members: Vec<String> = roster.into_iter().collect();
                let worked = store.worked_member_callsigns(&parsed, &members)?;
                (computed, worked, clubs_by_callsign)
            } else {
                (computed, Vec::new(), HashMap::new())
            }
        };

        if needs_club_overlay {
            for (stat, value) in computed.iter_mut() {
                match stat {
                    BragStatType::ClubMembersWorked => {
                        *value = if worked_members.is_empty() {
                            BragStatValue::NoData
                        } else {
                            BragStatValue::Count(worked_members.len() as i64)
                        };
                    }
                    BragStatType::ClubsRepresented => {
                        *value = clubs_represented_value(&worked_members, &clubs_by_callsign);
                    }
                    _ => {}
                }
            }
        }

        Ok(computed
            .into_iter()
            .map(|(stat, value)| FfiBragStatResult {
                stat_type: stat.into(),
                formatted: value.formatted(use_metric),
                icon_key: stat.icon_key().to_string(),
                value: value.into(),
            })
            .collect())
    }
}

/// Every distinct member callsign across every club, plus the
/// callsign→club-names map (see [`club_roster`]).
type ClubRoster = (std::collections::HashSet<String>, HashMap<String, Vec<String>>);

/// Build the full club roster (every distinct member callsign across every
/// club) and the callsign→club-names map, paginating `fetch_club_members` at
/// `MAX_FETCH_LIMIT` per page. Mirrors the iOS `clubMemberCallsigns` /
/// `clubsByCallsign` app-side dictionaries, which are built from the same
/// club-membership data (there, via SwiftData; here, via cw-store directly).
fn club_roster(store: &cw_store::Store) -> Result<ClubRoster, CwError> {
    // club_id -> name, so member rows can be grouped by club display name
    // (matches Swift's `clubsByCallsign: [String: [String]]` of club *names*).
    let clubs = store.fetch_clubs(&cw_store::ClubFilter::default(), MAX_FETCH_LIMIT, 0)?;
    let mut club_names: HashMap<String, String> = HashMap::new();
    for club in clubs {
        club_names.insert(club.id, club.name);
    }

    let mut roster = std::collections::HashSet::new();
    let mut clubs_by_callsign: HashMap<String, Vec<String>> = HashMap::new();
    let mut offset = 0i64;
    loop {
        let page = store.fetch_club_members(&ClubMemberFilter::default(), MAX_FETCH_LIMIT, offset)?;
        let page_len = page.len() as i64;
        for member in page {
            let callsign = member.callsign.to_uppercase();
            roster.insert(callsign.clone());
            if let Some(name) = club_names.get(&member.club_id) {
                clubs_by_callsign.entry(callsign).or_default().push(name.clone());
            }
        }
        if page_len < MAX_FETCH_LIMIT {
            break;
        }
        offset += MAX_FETCH_LIMIT;
    }
    Ok((roster, clubs_by_callsign))
}

/// Distinct club names represented among `worked_members`. Port of
/// `BragSheetComputationActor+RustOverlay.clubsRepresentedValue`.
fn clubs_represented_value(
    worked_members: &[String],
    clubs_by_callsign: &HashMap<String, Vec<String>>,
) -> BragStatValue {
    let mut clubs = std::collections::HashSet::new();
    for call in worked_members {
        if let Some(member_clubs) = clubs_by_callsign.get(&call.to_uppercase()) {
            clubs.extend(member_clubs.iter().cloned());
        }
    }
    if clubs.is_empty() {
        BragStatValue::NoData
    } else {
        BragStatValue::Count(clubs.len() as i64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cw_store::{Club, ClubMember, Qso};

    fn store() -> Arc<FieldStore> {
        Arc::new(FieldStore::open_in_memory("k".into()).unwrap())
    }

    /// A minimal, visible QSO fixture (mirrors the `base_qso` helper in
    /// `cw-store/src/analytics.rs`'s own tests).
    fn base_qso(id: &str, callsign: &str) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: callsign.to_string(),
            band: Some("20m".to_string()),
            mode: Some("CW".to_string()),
            freq_khz: Some(14_030.0),
            qso_date: 1_750_000_000,
            my_grid: Some("FN31".to_string()),
            their_grid: Some("EM12".to_string()),
            rst_sent: None,
            rst_rcvd: None,
            my_callsign: Some("W6JY".to_string()),
            park: None,
            their_park: None,
            notes: None,
            notes_user_authored: false,
            spot_comments_data: None,
            callsign_change_note: None,
            original_callsign: None,
            import_source_raw_value: "logger".to_string(),
            imported_at: 1_750_000_000,
            modified_at: None,
            raw_adif: None,
            name: None,
            qth: None,
            state: None,
            country: None,
            power: None,
            my_rig: None,
            station_profile_name: None,
            sota_ref: None,
            wwff_ref: None,
            aoa_code: None,
            qrz_log_id: None,
            qrz_confirmed: false,
            lotw_confirmed_date: None,
            lotw_confirmed: false,
            dxcc: Some(291),
            their_license_class: None,
            contest_name: None,
            contest_serial_sent: None,
            contest_serial_received: None,
            contest_exchange_sent: None,
            contest_exchange_received: None,
            is_hidden: false,
            is_activity_log_qso: false,
            station_callsign: None,
            logging_session_id: None,
            dirty: true,
            sat_name: None,
            prop_mode: None,
        }
    }

    #[test]
    fn catalog_categories_presets_counts() {
        let api = BragSheetApi::new(store());
        assert_eq!(api.catalog().len(), 58);
        assert_eq!(api.categories().len(), 11);
        assert_eq!(api.presets().len(), 7);
    }

    #[test]
    fn presets_carry_non_empty_stat_lists() {
        let api = BragSheetApi::new(store());
        let presets = api.presets();
        assert_eq!(presets.len(), 7);
        for preset in &presets {
            assert!(!preset.stats.is_empty(), "{:?} has empty stats", preset.preset);
            assert!(
                !preset.default_hero_stats.is_empty(),
                "{:?} has empty default_hero_stats",
                preset.preset
            );
            assert!(preset.default_hero_stats.len() <= 4);
        }
        let show_everything =
            presets.iter().find(|p| p.preset == FfiBragPreset::ShowEverything).unwrap();
        assert_eq!(show_everything.stats.len(), 58);
    }

    #[test]
    fn apply_preset_sets_period_stats() {
        let api = BragSheetApi::new(store());
        let config = api.load_config().unwrap();
        let updated = api.apply_preset(config, FfiBragPreset::Dxer, FfiBragPeriod::Weekly);

        let expected: Vec<FfiBragStatType> =
            BragPreset::Dxer.stats().into_iter().map(FfiBragStatType::from).collect();
        assert_eq!(updated.weekly.enabled_stats, expected);
        assert_eq!(updated.weekly.base_preset, Some(FfiBragPreset::Dxer));
    }

    #[test]
    fn copy_period_config_duplicates_between_periods() {
        let api = BragSheetApi::new(store());
        let config = api.load_config().unwrap();
        let updated = api.copy_period_config(config.clone(), FfiBragPeriod::Weekly, FfiBragPeriod::Monthly);
        assert_eq!(updated.monthly, updated.weekly);
        assert_ne!(config.monthly, config.weekly, "fixture should start with differing periods");
    }

    #[test]
    fn toggle_stat_adds_then_removes() {
        let api = BragSheetApi::new(store());
        let mut config = api.load_config().unwrap();
        config.weekly.enabled_stats = vec![FfiBragStatType::TotalQsos];

        let added = api.toggle_stat(config, FfiBragStatType::FurthestContact, FfiBragPeriod::Weekly);
        assert!(added.weekly.enabled_stats.contains(&FfiBragStatType::FurthestContact));

        let removed = api.toggle_stat(added, FfiBragStatType::FurthestContact, FfiBragPeriod::Weekly);
        assert!(!removed.weekly.enabled_stats.contains(&FfiBragStatType::FurthestContact));
        assert_eq!(removed.weekly.enabled_stats, vec![FfiBragStatType::TotalQsos]);
    }

    #[test]
    fn toggle_hero_stat_caps_at_four() {
        let api = BragSheetApi::new(store());
        let mut config = api.load_config().unwrap();
        config.weekly = FfiBragPeriodConfig {
            enabled_stats: BragPreset::ShowEverything.stats().into_iter().map(FfiBragStatType::from).collect(),
            hero_stats: Vec::new(),
            base_preset: Some(FfiBragPreset::ShowEverything),
        };

        let candidates: Vec<FfiBragStatType> = config.weekly.enabled_stats.iter().copied().take(5).collect();
        let mut current = config;
        for (i, stat) in candidates.iter().enumerate() {
            current = api.toggle_hero_stat(current, *stat, FfiBragPeriod::Weekly);
            if i < 4 {
                assert!(current.weekly.hero_stats.contains(stat));
            } else {
                // 5th hero add is rejected by the domain cap; config unchanged.
                assert!(!current.weekly.hero_stats.contains(stat));
            }
        }
        assert_eq!(current.weekly.hero_stats.len(), 4);
    }

    #[test]
    fn move_stat_reorders_enabled_list() {
        let api = BragSheetApi::new(store());
        let mut config = api.load_config().unwrap();
        config.weekly.enabled_stats = vec![
            FfiBragStatType::TotalQsos,
            FfiBragStatType::FurthestContact,
            FfiBragStatType::DxccEntities,
            FfiBragStatType::GridSquares,
        ];

        let updated = api.move_stat(config, FfiBragPeriod::Weekly, 0, 2);
        assert_eq!(
            updated.weekly.enabled_stats,
            vec![
                FfiBragStatType::FurthestContact,
                FfiBragStatType::TotalQsos,
                FfiBragStatType::DxccEntities,
                FfiBragStatType::GridSquares,
            ]
        );
    }

    #[test]
    fn load_config_defaults_on_empty_kv() {
        let api = BragSheetApi::new(store());
        let config = api.load_config().unwrap();
        assert_eq!(config.weekly.base_preset, Some(FfiBragPreset::Contester));
        assert_eq!(config.monthly.base_preset, Some(FfiBragPreset::General));
        assert_eq!(config.all_time.base_preset, Some(FfiBragPreset::Dxer));
        assert!(config.include_map);
        assert!(!config.include_equipment_summary);
        assert!(config.gold_record_badges);
    }

    #[test]
    fn save_then_load_roundtrips_mutated_config() {
        let api = BragSheetApi::new(store());
        let mut config = api.load_config().unwrap();
        config.include_map = false;
        config.gold_record_badges = false;
        config.weekly.base_preset = Some(FfiBragPreset::Qrp);
        config.weekly.enabled_stats = vec![FfiBragStatType::TotalQsos, FfiBragStatType::FurthestContact];
        config.weekly.hero_stats = vec![FfiBragStatType::TotalQsos];

        api.save_config(config.clone()).unwrap();
        let loaded = api.load_config().unwrap();
        assert_eq!(loaded, config);
    }

    #[test]
    fn import_into_empty_writes_and_load_reflects_it() {
        let api = BragSheetApi::new(store());
        let weekly = BragPeriodConfig {
            enabled_stats: Vec::new(),
            hero_stats: Vec::new(),
            base_preset: Some(BragPreset::Qrp),
        };
        let config = BragConfiguration {
            weekly,
            include_map: false,
            gold_record_badges: false,
            ..BragConfiguration::default()
        };
        let legacy_json = serde_json::to_string(&config).unwrap();

        let wrote = api.import_legacy_config(legacy_json).unwrap();
        assert!(wrote);

        let loaded = api.load_config().unwrap();
        assert_eq!(loaded, FfiBragConfiguration::from(config));
    }

    #[test]
    fn import_skips_when_already_present() {
        let api = BragSheetApi::new(store());
        let original = api.load_config().unwrap();
        api.save_config(original.clone()).unwrap();

        let default_config = BragConfiguration::default();
        let weekly = BragPeriodConfig { base_preset: Some(BragPreset::Qrp), ..default_config.weekly.clone() };
        let different =
            BragConfiguration { weekly, include_map: !default_config.include_map, ..default_config };
        let legacy_json = serde_json::to_string(&different).unwrap();

        let wrote = api.import_legacy_config(legacy_json).unwrap();
        assert!(!wrote);

        let loaded = api.load_config().unwrap();
        assert_eq!(loaded, original);
    }

    #[test]
    fn import_rejects_malformed_json() {
        let api = BragSheetApi::new(store());
        let result = api.import_legacy_config("{not valid".to_string());
        assert!(result.is_err());
    }

    #[test]
    fn save_config_marks_synced_config_row_dirty_for_push() {
        let store = store();
        let api = BragSheetApi::new(store.clone());
        let config = api.load_config().unwrap();
        api.save_config(config).unwrap();

        let inner = store.inner.lock().unwrap();
        let dirty = inner.fetch_dirty_synced_configs().unwrap();
        assert_eq!(dirty.len(), 1, "saved brag config is dirty so it pushes");
        assert_eq!(dirty[0].config_type, "bragSheet");
        assert!(dirty[0].modified_at.is_some(), "fresh modified_at set for LWW");
    }

    #[test]
    fn import_legacy_marks_synced_config_row_dirty() {
        let store = store();
        let api = BragSheetApi::new(store.clone());
        let legacy_json = serde_json::to_string(&BragConfiguration::default()).unwrap();
        assert!(api.import_legacy_config(legacy_json).unwrap());

        let inner = store.inner.lock().unwrap();
        let dirty = inner.fetch_dirty_synced_configs().unwrap();
        assert_eq!(dirty.len(), 1, "imported brag config is dirty so it pushes");
    }

    #[test]
    fn compute_brag_returns_one_result_per_enabled_stat() {
        let store = store();
        let api = BragSheetApi::new(store.clone());

        // Seed a couple of visible QSOs so the period isn't the empty-store
        // NoData short-circuit.
        {
            let inner = store.inner.lock().unwrap();
            inner.upsert_qso(&base_qso("q1", "W1AW")).unwrap();
        }

        let now = 1_750_000_500;
        let results = api.compute_brag(FfiBragPeriod::AllTime, now, true).unwrap();

        let config = api.load_config().unwrap();
        assert_eq!(results.len(), config.all_time.enabled_stats.len());
        for result in &results {
            assert!(!result.formatted.is_empty());
            assert!(!result.icon_key.is_empty());
        }
    }

    #[test]
    fn compute_brag_use_metric_false_formats_distance_in_miles() {
        let store = store();
        let api = BragSheetApi::new(store.clone());

        // base_qso's grids (FN31 <-> EM12) give TotalDistance a real km value
        // to convert, proving `use_metric` threads end-to-end through the
        // FFI facade into `BragStatValue::formatted`.
        {
            let inner = store.inner.lock().unwrap();
            inner.upsert_qso(&base_qso("q1", "W1AW")).unwrap();
        }

        let mut config = api.load_config().unwrap();
        config.all_time.enabled_stats = vec![FfiBragStatType::TotalDistance];
        api.save_config(config).unwrap();

        let metric = api.compute_brag(FfiBragPeriod::AllTime, 1_750_000_500, true).unwrap();
        let imperial = api.compute_brag(FfiBragPeriod::AllTime, 1_750_000_500, false).unwrap();

        let metric_distance = metric.iter().find(|r| r.stat_type == FfiBragStatType::TotalDistance).unwrap();
        let imperial_distance = imperial.iter().find(|r| r.stat_type == FfiBragStatType::TotalDistance).unwrap();

        assert!(metric_distance.formatted.ends_with("km"), "{}", metric_distance.formatted);
        assert!(imperial_distance.formatted.ends_with("mi"), "{}", imperial_distance.formatted);
        assert_ne!(metric_distance.formatted, imperial_distance.formatted);
    }

    #[test]
    fn compute_brag_club_overlay_matches_roster() {
        let store = store();
        let api = BragSheetApi::new(store.clone());

        {
            let inner = store.inner.lock().unwrap();
            inner.upsert_qso(&base_qso("q1", "W1AW")).unwrap();
            inner
                .upsert_club(&Club {
                    id: "club-1".to_string(),
                    name: "Test Radio Club".to_string(),
                    callsign: None,
                    description: None,
                    notes_url: None,
                    notes_title: None,
                    has_logo: false,
                    cached_member_count: 1,
                    last_synced_at: 0,
                })
                .unwrap();
            inner.upsert_club_member_from_server(&ClubMember::server_member("club-1", "W1AW", "member")).unwrap();
        }

        // Enable the two club stats for AllTime via a ShowEverything preset.
        let mut config = api.load_config().unwrap();
        config.all_time.enabled_stats =
            vec![FfiBragStatType::ClubMembersWorked, FfiBragStatType::ClubsRepresented];
        api.save_config(config).unwrap();

        let results = api.compute_brag(FfiBragPeriod::AllTime, 1_750_000_500, true).unwrap();
        assert_eq!(results.len(), 2);

        let members = results.iter().find(|r| r.stat_type == FfiBragStatType::ClubMembersWorked).unwrap();
        assert_eq!(members.value, FfiBragStatValue::Count { value: 1 });
        assert_eq!(members.formatted, "1");

        let clubs = results.iter().find(|r| r.stat_type == FfiBragStatType::ClubsRepresented).unwrap();
        assert_eq!(clubs.value, FfiBragStatValue::Count { value: 1 });
    }
}
