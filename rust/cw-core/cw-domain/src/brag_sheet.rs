//! Brag Sheet catalog, categories, periods, presets, configuration, and
//! stat-value display formatting. Pure (no I/O) port of the Swift:
//! - `Models/BragSheet/BragSheetStatType.swift`
//! - `Models/BragSheet/BragSheetCategory.swift`
//! - `Models/BragSheet/BragSheetPeriod.swift`
//! - `Models/BragSheet/BragSheetPreset.swift`
//! - `Models/BragSheet/BragSheetStatValue.swift`
//! - `Models/BragSheet/BragSheetConfiguration.swift`
//! - `Views/BragSheet/BragSheetStatRendering.swift`
//!
//! `BragStatType`'s serde string MUST equal the Swift `rawValue` (the case
//! name) exactly, including load-bearing acronym casing (`totalQSOs`,
//! `furthestQRPContact`, `newDXCCEntities`, `workedAllStatesProgress`,
//! `bestRSTAtDistance`, ...). `serde(rename_all = "camelCase")` cannot
//! reproduce these, so `Serialize`/`Deserialize` are implemented by hand via
//! `as_str`/`from_str` string tables below.
//!
//! NOTE: the implementation plan for this port describes "65 stats"; the
//! actual `BragSheetStatType.swift` `case` list (the authoritative source)
//! has exactly **58** cases. This module ports the 58 cases that exist in
//! Swift today — see the Phase 1 report for the discrepancy writeup.

use chrono::{DateTime, Datelike, Timelike, Utc};
use serde::de::{self, Deserializer, Visitor};
use serde::{Deserialize, Serialize, Serializer};
use std::fmt;

// ---- BragStatType ----------------------------------------------------------

/// All available statistics for brag sheet cards. Port of
/// `BragSheetStatType.swift` (65 cases).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BragStatType {
    // Totals
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
    // Speed & Rate
    Fastest10Qsos,
    Peak15MinRate,
    BestSessionRate,
    FastestActivation,
    // Distance
    FurthestContact,
    FurthestContactPerBand,
    FurthestQrpContact,
    AverageContactDistance,
    // Power & Efficiency
    LowestPowerContact,
    BestWattsPerMile,
    // Geographic Reach
    DxccEntities,
    NewDxccEntities,
    StatesAndProvinces,
    GridSquares,
    Continents,
    MostContinentsInADay,
    WorkedAllStatesProgress,
    // Volume Records
    MostQsosInADay,
    MostQsosInASession,
    MostCountriesInADay,
    MostBandsInADay,
    // Streaks
    CurrentOnAirStreak,
    BestOnAirStreak,
    CurrentActivationStreak,
    ModeStreaks,
    // POTA
    ParksActivated,
    ParksHunted,
    ParkToParkContacts,
    LargestNfer,
    BestActivation,
    NewParks,
    // CW
    FastestCwSpeed,
    CwDistanceRecord,
    CwQrpRecord,
    // Signal Quality
    PerfectReports,
    AverageRstReceived,
    BestRstAtDistance,
    // Fun & Unique
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

impl BragStatType {
    /// All 58 stat types, in declaration order (mirrors Swift `allCases`).
    pub fn all() -> Vec<Self> {
        use BragStatType::*;
        vec![
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
        ]
    }

    /// The Swift `rawValue` string, verbatim. Load-bearing for
    /// serde/UserDefaults-blob compatibility.
    pub fn as_str(self) -> &'static str {
        use BragStatType::*;
        match self {
            TotalQsos => "totalQSOs",
            TotalCwQsos => "totalCWQSOs",
            TotalPhoneQsos => "totalPhoneQSOs",
            TotalDigitalQsos => "totalDigitalQSOs",
            TotalDistance => "totalDistance",
            OperatingDays => "operatingDays",
            OperatingHours => "operatingHours",
            ActiveBands => "activeBands",
            ActiveModes => "activeModes",
            UniqueCallsigns => "uniqueCallsigns",
            QrpQsoCount => "qrpQSOCount",
            MilliwattQsoCount => "milliwattQSOCount",
            Fastest10Qsos => "fastest10QSOs",
            Peak15MinRate => "peak15MinRate",
            BestSessionRate => "bestSessionRate",
            FastestActivation => "fastestActivation",
            FurthestContact => "furthestContact",
            FurthestContactPerBand => "furthestContactPerBand",
            FurthestQrpContact => "furthestQRPContact",
            AverageContactDistance => "averageContactDistance",
            LowestPowerContact => "lowestPowerContact",
            BestWattsPerMile => "bestWattsPerMile",
            DxccEntities => "dxccEntities",
            NewDxccEntities => "newDXCCEntities",
            StatesAndProvinces => "statesAndProvinces",
            GridSquares => "gridSquares",
            Continents => "continents",
            MostContinentsInADay => "mostContinentsInADay",
            WorkedAllStatesProgress => "workedAllStatesProgress",
            MostQsosInADay => "mostQSOsInADay",
            MostQsosInASession => "mostQSOsInASession",
            MostCountriesInADay => "mostCountriesInADay",
            MostBandsInADay => "mostBandsInADay",
            CurrentOnAirStreak => "currentOnAirStreak",
            BestOnAirStreak => "bestOnAirStreak",
            CurrentActivationStreak => "currentActivationStreak",
            ModeStreaks => "modeStreaks",
            ParksActivated => "parksActivated",
            ParksHunted => "parksHunted",
            ParkToParkContacts => "parkToParkContacts",
            LargestNfer => "largestNfer",
            BestActivation => "bestActivation",
            NewParks => "newParks",
            FastestCwSpeed => "fastestCWSpeed",
            CwDistanceRecord => "cwDistanceRecord",
            CwQrpRecord => "cwQRPRecord",
            PerfectReports => "perfectReports",
            AverageRstReceived => "averageRSTReceived",
            BestRstAtDistance => "bestRSTAtDistance",
            EarliestQsoOfTheDay => "earliestQSOOfTheDay",
            LatestQsoOfTheDay => "latestQSOOfTheDay",
            LongestSession => "longestSession",
            MostActiveDayOfWeek => "mostActiveDayOfWeek",
            BusiestBand => "busiestBand",
            BusiestMode => "busiestMode",
            RepeatCustomers => "repeatCustomers",
            ClubMembersWorked => "clubMembersWorked",
            ClubsRepresented => "clubsRepresented",
        }
    }

    /// Parse the Swift `rawValue` string back into a `BragStatType`.
    pub fn from_str_value(value: &str) -> Option<Self> {
        Self::all().into_iter().find(|s| s.as_str() == value)
    }

    /// Long display name. Port of `BragSheetStatType.displayName`.
    pub fn display_name(self) -> &'static str {
        use BragStatType::*;
        match self {
            TotalQsos => "Total QSOs",
            TotalCwQsos => "Total CW QSOs",
            TotalPhoneQsos => "Total Phone QSOs",
            TotalDigitalQsos => "Total Digital QSOs",
            TotalDistance => "Total Distance",
            OperatingDays => "Operating Days",
            OperatingHours => "Operating Hours",
            ActiveBands => "Active Bands",
            ActiveModes => "Active Modes",
            UniqueCallsigns => "Unique Callsigns",
            QrpQsoCount => "QRP QSO Count",
            MilliwattQsoCount => "Milliwatt QSO Count",
            Fastest10Qsos => "Fastest 10 QSOs",
            Peak15MinRate => "Peak 15-Min Rate",
            BestSessionRate => "Best Session Rate",
            FastestActivation => "Fastest Activation",
            FurthestContact => "Furthest Contact",
            FurthestContactPerBand => "Furthest per Band",
            FurthestQrpContact => "Furthest QRP Contact",
            AverageContactDistance => "Avg Contact Distance",
            LowestPowerContact => "Lowest Power Contact",
            BestWattsPerMile => "Best Watts-per-Mile",
            DxccEntities => "DXCC Entities",
            NewDxccEntities => "New DXCC Entities",
            StatesAndProvinces => "States & Provinces",
            GridSquares => "Grid Squares",
            Continents => "Continents",
            MostContinentsInADay => "Most Continents/Day",
            WorkedAllStatesProgress => "WAS Progress",
            MostQsosInADay => "Most QSOs in a Day",
            MostQsosInASession => "Most QSOs/Session",
            MostCountriesInADay => "Most Countries/Day",
            MostBandsInADay => "Most Bands in a Day",
            CurrentOnAirStreak => "On-Air Streak",
            BestOnAirStreak => "Best On-Air Streak",
            CurrentActivationStreak => "Activation Streak",
            ModeStreaks => "Mode Streaks",
            ParksActivated => "Parks Activated",
            ParksHunted => "Parks Hunted",
            ParkToParkContacts => "P2P Contacts",
            LargestNfer => "Largest N-fer",
            BestActivation => "Best Activation",
            NewParks => "New Parks",
            FastestCwSpeed => "Fastest CW Speed",
            CwDistanceRecord => "CW Distance Record",
            CwQrpRecord => "CW QRP Record",
            PerfectReports => "Perfect Reports",
            AverageRstReceived => "Avg RST Received",
            BestRstAtDistance => "Best RST at Distance",
            EarliestQsoOfTheDay => "Earliest QSO",
            LatestQsoOfTheDay => "Latest QSO",
            LongestSession => "Longest Session",
            MostActiveDayOfWeek => "Most Active Day",
            BusiestBand => "Busiest Band",
            BusiestMode => "Busiest Mode",
            RepeatCustomers => "Repeat Customers",
            ClubMembersWorked => "Club Members Worked",
            ClubsRepresented => "Clubs Represented",
        }
    }

    /// Short display name (compact badges/labels). Port of
    /// `BragSheetStatType.shortDisplayName`.
    pub fn short_display_name(self) -> &'static str {
        use BragStatType::*;
        match self {
            TotalQsos => "QSOs",
            TotalCwQsos => "CW QSOs",
            TotalPhoneQsos => "Phone",
            TotalDigitalQsos => "Digital",
            TotalDistance => "Distance",
            OperatingDays => "Days",
            OperatingHours => "Hours",
            ActiveBands => "Bands",
            ActiveModes => "Modes",
            UniqueCallsigns => "Callsigns",
            QrpQsoCount => "QRP QSOs",
            MilliwattQsoCount => "mW QSOs",
            Fastest10Qsos => "Fast 10",
            Peak15MinRate => "Peak Rate",
            BestSessionRate => "Best Rate",
            FastestActivation => "Fast Act.",
            FurthestContact => "Furthest",
            FurthestContactPerBand => "Far/Band",
            FurthestQrpContact => "Far QRP",
            AverageContactDistance => "Avg Dist",
            LowestPowerContact => "Low Power",
            BestWattsPerMile => "W/mi",
            DxccEntities => "DXCC",
            NewDxccEntities => "New DXCC",
            StatesAndProvinces => "States",
            GridSquares => "Grids",
            Continents => "Continents",
            MostContinentsInADay => "Cont/Day",
            WorkedAllStatesProgress => "WAS",
            MostQsosInADay => "QSOs/Day",
            MostQsosInASession => "QSOs/Sess",
            MostCountriesInADay => "DXCC/Day",
            MostBandsInADay => "Bands/Day",
            CurrentOnAirStreak => "Streak",
            BestOnAirStreak => "Best Streak",
            CurrentActivationStreak => "Act Streak",
            ModeStreaks => "Mode Streak",
            ParksActivated => "Activated",
            ParksHunted => "Hunted",
            ParkToParkContacts => "P2P",
            LargestNfer => "N-fer",
            BestActivation => "Best Act.",
            NewParks => "New Parks",
            FastestCwSpeed => "CW Speed",
            CwDistanceRecord => "CW Dist",
            CwQrpRecord => "CW QRP",
            PerfectReports => "Perfect",
            AverageRstReceived => "Avg RST",
            BestRstAtDistance => "RST@Dist",
            EarliestQsoOfTheDay => "Earliest",
            LatestQsoOfTheDay => "Latest",
            LongestSession => "Long Sess",
            MostActiveDayOfWeek => "Best Day",
            BusiestBand => "Top Band",
            BusiestMode => "Top Mode",
            RepeatCustomers => "Repeats",
            ClubMembersWorked => "Club Mbrs",
            ClubsRepresented => "Clubs",
        }
    }

    /// The category this stat belongs to. Port of
    /// `BragSheetStatType.category`.
    pub fn category(self) -> BragCategory {
        use BragStatType::*;
        match self {
            TotalQsos | TotalCwQsos | TotalPhoneQsos | TotalDigitalQsos | TotalDistance
            | OperatingDays | OperatingHours | ActiveBands | ActiveModes | UniqueCallsigns
            | QrpQsoCount | MilliwattQsoCount => BragCategory::Totals,
            Fastest10Qsos | Peak15MinRate | BestSessionRate | FastestActivation => {
                BragCategory::SpeedAndRate
            }
            FurthestContact | FurthestContactPerBand | FurthestQrpContact
            | AverageContactDistance => BragCategory::Distance,
            LowestPowerContact | BestWattsPerMile => BragCategory::PowerAndEfficiency,
            DxccEntities | NewDxccEntities | StatesAndProvinces | GridSquares | Continents
            | MostContinentsInADay | WorkedAllStatesProgress => BragCategory::GeographicReach,
            MostQsosInADay | MostQsosInASession | MostCountriesInADay | MostBandsInADay => {
                BragCategory::VolumeRecords
            }
            CurrentOnAirStreak | BestOnAirStreak | CurrentActivationStreak | ModeStreaks => {
                BragCategory::Streaks
            }
            ParksActivated | ParksHunted | ParkToParkContacts | LargestNfer | BestActivation
            | NewParks => BragCategory::Pota,
            FastestCwSpeed | CwDistanceRecord | CwQrpRecord => BragCategory::Cw,
            PerfectReports | AverageRstReceived | BestRstAtDistance => {
                BragCategory::SignalQuality
            }
            EarliestQsoOfTheDay | LatestQsoOfTheDay | LongestSession | MostActiveDayOfWeek
            | BusiestBand | BusiestMode | RepeatCustomers | ClubMembersWorked
            | ClubsRepresented => BragCategory::FunAndUnique,
        }
    }

    /// Semantic icon key derived from category (platform UIs map this to an
    /// SF Symbol / Material icon). Port of `BragSheetStatType.systemImage`
    /// (which switches on `category`).
    pub fn icon_key(self) -> &'static str {
        self.category().icon_key()
    }
}

impl Serialize for BragStatType {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(self.as_str())
    }
}

impl<'de> Deserialize<'de> for BragStatType {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct BragStatTypeVisitor;

        impl Visitor<'_> for BragStatTypeVisitor {
            type Value = BragStatType;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a BragStatType rawValue string")
            }

            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
            where
                E: de::Error,
            {
                BragStatType::from_str_value(value)
                    .ok_or_else(|| de::Error::unknown_variant(value, &["<BragStatType rawValue>"]))
            }
        }

        deserializer.deserialize_str(BragStatTypeVisitor)
    }
}

// ---- BragCategory -----------------------------------------------------------

/// Categories that organize brag sheet stats. Port of
/// `BragSheetCategory.swift` (11 cases).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BragCategory {
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

impl BragCategory {
    /// All 11 categories, in declaration order.
    pub fn all() -> Vec<Self> {
        use BragCategory::*;
        vec![
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
        ]
    }

    /// Display name. Port of `BragSheetCategory.displayName`.
    pub fn display_name(self) -> &'static str {
        use BragCategory::*;
        match self {
            Totals => "Totals",
            SpeedAndRate => "Speed & Rate",
            Distance => "Distance",
            PowerAndEfficiency => "Power & Efficiency",
            GeographicReach => "Geographic Reach",
            VolumeRecords => "Volume Records",
            Streaks => "Streaks",
            Pota => "POTA",
            Cw => "CW",
            SignalQuality => "Signal Quality",
            FunAndUnique => "Fun & Unique",
        }
    }

    /// Semantic icon key (platform UIs map to SF Symbol / Material icon).
    pub fn icon_key(self) -> &'static str {
        use BragCategory::*;
        match self {
            Totals => "number",
            SpeedAndRate => "gauge",
            Distance => "bearing",
            PowerAndEfficiency => "bolt",
            GeographicReach => "globe",
            VolumeRecords => "trophy",
            Streaks => "flame",
            Pota => "tree",
            Cw => "waveform",
            SignalQuality => "antenna",
            FunAndUnique => "sparkles",
        }
    }

    /// Stats belonging to this category, in `BragStatType::all()` order.
    /// Port of `BragSheetCategory.stats`.
    pub fn stats(self) -> Vec<BragStatType> {
        BragStatType::all()
            .into_iter()
            .filter(|s| s.category() == self)
            .collect()
    }
}

// ---- BragPeriod --------------------------------------------------------------

/// Time windows for brag sheet cards. Port of `BragSheetPeriod.swift`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BragPeriod {
    Weekly,
    Monthly,
    AllTime,
}

impl BragPeriod {
    /// All 3 periods, in declaration order.
    pub fn all() -> Vec<Self> {
        vec![BragPeriod::Weekly, BragPeriod::Monthly, BragPeriod::AllTime]
    }

    /// Display name. Port of `BragSheetPeriod.displayName`.
    pub fn display_name(self) -> &'static str {
        match self {
            BragPeriod::Weekly => "Weekly",
            BragPeriod::Monthly => "Monthly",
            BragPeriod::AllTime => "All Time",
        }
    }

    /// Short name. Port of `BragSheetPeriod.shortName`.
    pub fn short_name(self) -> &'static str {
        match self {
            BragPeriod::Weekly => "Week",
            BragPeriod::Monthly => "Month",
            BragPeriod::AllTime => "All",
        }
    }

    /// Default preset for this period. Port of `BragSheetPeriod.defaultPreset`.
    pub fn default_preset(self) -> BragPreset {
        match self {
            BragPeriod::Weekly => BragPreset::Contester,
            BragPeriod::Monthly => BragPreset::General,
            BragPeriod::AllTime => BragPreset::Dxer,
        }
    }

    /// Inclusive `(start_unix, end_unix)` UTC window for this period, given
    /// `now`. `AllTime` has no start (`None`). Port of
    /// `BragSheetPeriod.dateRange(now:)` — UTC calendar, week starts Monday.
    pub fn window(self, now: DateTime<Utc>) -> (Option<i64>, Option<i64>) {
        match self {
            BragPeriod::Weekly => {
                // weekday(): Mon=1 ... Sun=7 in chrono; Swift's Calendar
                // weekday is 1=Sun..7=Sat with firstWeekday=Monday. Compute
                // days-since-Monday directly from chrono's Mon=1 numbering.
                let days_from_monday = now.weekday().num_days_from_monday() as i64;
                let start_of_today = now
                    .date_naive()
                    .and_hms_opt(0, 0, 0)
                    .expect("valid midnight");
                let monday = start_of_today - chrono::Duration::days(days_from_monday);
                let start = DateTime::<Utc>::from_naive_utc_and_offset(monday, Utc);
                (Some(start.timestamp()), Some(now.timestamp()))
            }
            BragPeriod::Monthly => {
                let month_start_naive = now
                    .date_naive()
                    .with_day(1)
                    .expect("valid day 1")
                    .and_hms_opt(0, 0, 0)
                    .expect("valid midnight");
                let start = DateTime::<Utc>::from_naive_utc_and_offset(month_start_naive, Utc);
                (Some(start.timestamp()), Some(now.timestamp()))
            }
            BragPeriod::AllTime => (None, Some(now.timestamp())),
        }
    }
}

// ---- BragPreset ---------------------------------------------------------------

/// Curated starting-point configurations for brag sheet cards. Port of
/// `BragSheetPreset.swift` (7 cases).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum BragPreset {
    General,
    Dxer,
    Qrp,
    Activator,
    Contester,
    CwEnthusiast,
    ShowEverything,
}

impl BragPreset {
    /// All 7 presets, in declaration order.
    pub fn all() -> Vec<Self> {
        use BragPreset::*;
        vec![
            General,
            Dxer,
            Qrp,
            Activator,
            Contester,
            CwEnthusiast,
            ShowEverything,
        ]
    }

    /// Display name. Port of `BragSheetPreset.displayName`.
    pub fn display_name(self) -> &'static str {
        use BragPreset::*;
        match self {
            General => "General",
            Dxer => "DXer",
            Qrp => "QRP",
            Activator => "Activator",
            Contester => "Contester",
            CwEnthusiast => "CW Enthusiast",
            ShowEverything => "Show Everything",
        }
    }

    /// Description. Port of `BragSheetPreset.description`.
    pub fn description(self) -> &'static str {
        use BragPreset::*;
        match self {
            General => "Balanced overview",
            Dxer => "Distance & entities",
            Qrp => "Low power",
            Activator => "POTA activations",
            Contester => "Speed & volume",
            CwEnthusiast => "Morse code",
            ShowEverything => "All stats",
        }
    }

    /// Stats included in this preset, in display order. Port of
    /// `BragSheetPreset.stats`.
    pub fn stats(self) -> Vec<BragStatType> {
        use BragStatType::*;
        match self {
            BragPreset::General => vec![
                TotalQsos,
                FurthestContact,
                DxccEntities,
                StatesAndProvinces,
                ActiveBands,
                ActiveModes,
                OperatingDays,
                BestSessionRate,
                ClubMembersWorked,
            ],
            BragPreset::Dxer => vec![
                FurthestContact,
                FurthestContactPerBand,
                DxccEntities,
                NewDxccEntities,
                Continents,
                MostCountriesInADay,
                GridSquares,
                TotalDistance,
            ],
            BragPreset::Qrp => vec![
                LowestPowerContact,
                BestWattsPerMile,
                FurthestQrpContact,
                QrpQsoCount,
                MilliwattQsoCount,
                FurthestContact,
                TotalDistance,
            ],
            BragPreset::Activator => vec![
                ParksActivated,
                BestActivation,
                FastestActivation,
                ParkToParkContacts,
                LargestNfer,
                NewParks,
                TotalQsos,
                BestSessionRate,
            ],
            BragPreset::Contester => vec![
                Fastest10Qsos,
                Peak15MinRate,
                BestSessionRate,
                MostQsosInADay,
                TotalQsos,
                ActiveBands,
                UniqueCallsigns,
            ],
            BragPreset::CwEnthusiast => vec![
                TotalCwQsos,
                FastestCwSpeed,
                CwDistanceRecord,
                CwQrpRecord,
                Peak15MinRate,
                PerfectReports,
                CurrentOnAirStreak,
            ],
            BragPreset::ShowEverything => BragStatType::all(),
        }
    }

    /// Default hero stats (first 4) for this preset. Port of
    /// `BragSheetPreset.defaultHeroStats`.
    pub fn default_hero_stats(self) -> Vec<BragStatType> {
        self.stats().into_iter().take(4).collect()
    }
}

// ---- BragPeriodConfig / BragConfiguration --------------------------------------

/// Per-period configuration for a brag sheet card. Port of
/// `BragSheetPeriodConfig` (`BragSheetConfiguration.swift`). Field names
/// mirror the Swift `Codable` synthesized keys exactly so an existing iOS
/// UserDefaults blob decodes without a migration shim.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragPeriodConfig {
    #[serde(rename = "enabledStats")]
    pub enabled_stats: Vec<BragStatType>,
    #[serde(rename = "heroStats")]
    pub hero_stats: Vec<BragStatType>,
    #[serde(rename = "basePreset")]
    pub base_preset: Option<BragPreset>,
}

impl BragPeriodConfig {
    /// Create from a preset. Port of `BragSheetPeriodConfig.from(preset:)`.
    pub fn from_preset(preset: BragPreset) -> Self {
        let hero_stats: Vec<BragStatType> =
            preset.default_hero_stats().into_iter().take(4).collect();
        BragPeriodConfig {
            enabled_stats: preset.stats(),
            hero_stats,
            base_preset: Some(preset),
        }
    }

    /// Toggle a stat on or off. Port of `BragSheetPeriodConfig.toggle(_:)`.
    pub fn toggle(&mut self, stat: BragStatType) {
        if let Some(index) = self.enabled_stats.iter().position(|s| *s == stat) {
            self.enabled_stats.remove(index);
            self.hero_stats.retain(|s| *s != stat);
        } else {
            self.enabled_stats.push(stat);
        }
    }

    /// Toggle hero status for a stat. Returns `false` if the stat is not
    /// enabled, or if adding would exceed the 4-stat hero cap. Port of
    /// `BragSheetPeriodConfig.toggleHero(_:)`.
    pub fn toggle_hero(&mut self, stat: BragStatType) -> bool {
        if !self.enabled_stats.contains(&stat) {
            return false;
        }
        if let Some(index) = self.hero_stats.iter().position(|s| *s == stat) {
            self.hero_stats.remove(index);
            return true;
        }
        if self.hero_stats.len() >= 4 {
            return false;
        }
        self.hero_stats.push(stat);
        true
    }

    /// Move a stat within the enabled list from index `from` to `to`. Port of
    /// `BragSheetPeriodConfig.move(from:to:)` (single-index variant of
    /// Swift's `IndexSet` move).
    pub fn move_stat(&mut self, from: usize, to: usize) {
        if from >= self.enabled_stats.len() || from == to {
            return;
        }
        let insert_at = if to <= from { to } else { to - 1 };
        let stat = self.enabled_stats.remove(from);
        self.enabled_stats.insert(insert_at, stat);
    }
}

/// Top-level brag sheet configuration managing all periods. Port of
/// `BragSheetConfiguration.swift`. Field names mirror the Swift `Codable`
/// synthesized keys exactly.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragConfiguration {
    pub weekly: BragPeriodConfig,
    pub monthly: BragPeriodConfig,
    #[serde(rename = "allTime")]
    pub all_time: BragPeriodConfig,
    #[serde(rename = "includeMap")]
    pub include_map: bool,
    #[serde(rename = "includeEquipmentSummary")]
    pub include_equipment_summary: bool,
    #[serde(rename = "goldRecordBadges")]
    pub gold_record_badges: bool,
}

impl Default for BragConfiguration {
    /// Port of `BragSheetConfiguration.init()` default parameters.
    fn default() -> Self {
        BragConfiguration {
            weekly: BragPeriodConfig::from_preset(BragPreset::Contester),
            monthly: BragPeriodConfig::from_preset(BragPreset::General),
            all_time: BragPeriodConfig::from_preset(BragPreset::Dxer),
            include_map: true,
            include_equipment_summary: false,
            gold_record_badges: true,
        }
    }
}

impl BragConfiguration {
    /// Get config for a specific period. Port of
    /// `BragSheetConfiguration.config(for:)`.
    pub fn config_for(&self, period: BragPeriod) -> &BragPeriodConfig {
        match period {
            BragPeriod::Weekly => &self.weekly,
            BragPeriod::Monthly => &self.monthly,
            BragPeriod::AllTime => &self.all_time,
        }
    }

    /// Set config for a specific period. Port of
    /// `BragSheetConfiguration.setConfig(_:for:)`.
    pub fn set_config(&mut self, config: BragPeriodConfig, period: BragPeriod) {
        match period {
            BragPeriod::Weekly => self.weekly = config,
            BragPeriod::Monthly => self.monthly = config,
            BragPeriod::AllTime => self.all_time = config,
        }
    }

    /// Apply a preset to a specific period. Port of
    /// `BragSheetConfiguration.applyPreset(_:to:)`.
    pub fn apply_preset(&mut self, preset: BragPreset, period: BragPeriod) {
        self.set_config(BragPeriodConfig::from_preset(preset), period);
    }

    /// Copy config from one period to another. Port of
    /// `BragSheetConfiguration.copyConfig(from:to:)`.
    pub fn copy_config(&mut self, source: BragPeriod, destination: BragPeriod) {
        let config = self.config_for(source).clone();
        self.set_config(config, destination);
    }
}

// ---- BragStatValue ------------------------------------------------------------

/// Per-band table entry (band -> callsign -> distance). Port of
/// `BandTableEntry` (`BragSheetStatValue.swift`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BandTableEntry {
    pub band: String,
    pub callsign: String,
    #[serde(rename = "distanceKm")]
    pub distance_km: Option<f64>,
}

/// A single mode's on-air streak. Port of `ModeStreakEntry`
/// (`BragSheetStatValue.swift`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModeStreakEntry {
    pub mode: String,
    pub current: i64,
    pub longest: i64,
}

/// A computed stat value for display on a brag sheet card. Port of
/// `BragSheetStatValue.swift`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value")]
pub enum BragStatValue {
    Count(i64),
    Distance {
        km: f64,
    },
    Duration {
        seconds: f64,
    },
    Rate {
        value: f64,
        label: String,
    },
    Contact {
        callsign: String,
        distance_km: Option<f64>,
        band: Option<String>,
    },
    Power {
        watts: f64,
        callsign: String,
        distance_km: Option<f64>,
        band: Option<String>,
    },
    Efficiency {
        watts_per_mile: f64,
        detail: String,
    },
    Progress {
        current: i64,
        total: i64,
    },
    Streak {
        current: i64,
        longest: i64,
    },
    BandTable(Vec<BandTableEntry>),
    DayOfWeek {
        day: String,
        count: i64,
    },
    CallsignCount {
        callsign: String,
        count: i64,
    },
    TimeOfDay {
        unix_seconds: i64,
    },
    ParkDetail {
        park: String,
        date: Option<String>,
        count: i64,
    },
    ModeStreakList(Vec<ModeStreakEntry>),
    Wpm(i64),
    Rst {
        value: String,
        detail: Option<String>,
    },
    NoData,
}

impl BragStatValue {
    /// Whether this stat has meaningful data to display. Port of
    /// `BragSheetStatValue.hasData`.
    pub fn has_data(&self) -> bool {
        !matches!(self, BragStatValue::NoData)
    }

    /// Primary display string for the hero row (large number). Port of
    /// `BragSheetStatValue.heroValue`, which formats distance via
    /// `UnitFormatter.distanceCompact` (no unit suffix) honoring the caller's
    /// mi/km preference. `use_metric` mirrors iOS's `UnitFormatter.useMetric`.
    pub fn hero_value(&self, use_metric: bool) -> String {
        match self {
            BragStatValue::Count(num) => format!("{num}"),
            BragStatValue::Distance { km } => format_distance_compact(*km, use_metric),
            BragStatValue::Duration { seconds } => format_duration_compact(*seconds),
            BragStatValue::Rate { value, .. } => format!("{:.0}", value),
            BragStatValue::Contact { callsign, .. } => callsign.clone(),
            BragStatValue::Power { watts, .. } => format!("{:.0}W", watts),
            BragStatValue::Efficiency { watts_per_mile, .. } => format!("{:.3}", watts_per_mile),
            BragStatValue::Progress { current, total } => format!("{current}/{total}"),
            BragStatValue::Streak { current, .. } => format!("{current}d"),
            BragStatValue::DayOfWeek { day, .. } => day.clone(),
            BragStatValue::CallsignCount { callsign, .. } => callsign.clone(),
            BragStatValue::TimeOfDay { unix_seconds } => format_utc_time(*unix_seconds),
            BragStatValue::ParkDetail { park, .. } => park.clone(),
            BragStatValue::Wpm(words) => format!("{words}"),
            BragStatValue::Rst { value, .. } => value.clone(),
            BragStatValue::BandTable(_) | BragStatValue::ModeStreakList(_) => "--".to_string(),
            BragStatValue::NoData => "--".to_string(),
        }
    }

    /// Full formatted display string. Distance-bearing variants use the
    /// unit-suffixed `UnitFormatter.distance` tiered formatting (meters under
    /// 1km, one decimal under 10km, "k km"/"k mi" over 1000); everything else
    /// matches `hero_value`. `use_metric` mirrors iOS's
    /// `UnitFormatter.useMetric`. Port of `BragSheetStatRendering.swift`'s
    /// subtitle/detail formatting.
    pub fn formatted(&self, use_metric: bool) -> String {
        match self {
            BragStatValue::Distance { km } => format_distance_labeled(*km, use_metric),
            _ => self.hero_value(use_metric),
        }
    }
}

/// km<->mi conversion factor. Port of `UnitFormatter.kmToMiles`.
const KM_TO_MILES: f64 = 0.621371;

/// Compact distance (no unit label): "5k"/"340" in the caller's unit system.
/// Port of `UnitFormatter.distanceCompact`.
fn format_distance_compact(km: f64, use_metric: bool) -> String {
    let value = if use_metric { km } else { km * KM_TO_MILES };
    if value >= 1_000.0 {
        format!("{:.0}k", value / 1_000.0)
    } else {
        format!("{:.0}", value)
    }
}

/// Distance with a unit-label suffix ("m"/"km" or "ft"/"mi"), tiered exactly
/// like `UnitFormatter.distance` -> `metricDistance`/`imperialDistance`.
fn format_distance_labeled(km: f64, use_metric: bool) -> String {
    if use_metric {
        if km < 1.0 {
            return format!("{:.0} m", km * 1_000.0);
        }
        if km < 10.0 {
            return format!("{:.1} km", km);
        }
        if km >= 1_000.0 {
            return format!("{:.0}k km", km / 1_000.0);
        }
        return format!("{:.0} km", km);
    }
    let mi = km * KM_TO_MILES;
    if mi < 0.1 {
        let feet = mi * 5_280.0;
        return format!("{:.0} ft", feet);
    }
    if mi < 10.0 {
        return format!("{:.1} mi", mi);
    }
    if mi >= 1_000.0 {
        return format!("{:.0}k mi", mi / 1_000.0);
    }
    format!("{:.0} mi", mi)
}

/// Compact duration: "8m" under an hour, else "2h15m". Port of
/// `BragSheetStatValue.formatDurationCompact`.
fn format_duration_compact(seconds: f64) -> String {
    let total_minutes = (seconds / 60.0) as i64;
    if total_minutes < 60 {
        return format!("{total_minutes}m");
    }
    let hours = total_minutes / 60;
    let minutes = total_minutes % 60;
    format!("{hours}h{minutes}m")
}

/// UTC "HHmmZ" time-of-day string, e.g. "0312Z". Port of
/// `BragSheetStatValue.formatUTCTime`.
fn format_utc_time(unix_seconds: i64) -> String {
    let dt = DateTime::<Utc>::from_timestamp(unix_seconds, 0).unwrap_or_else(Utc::now);
    format!("{:02}{:02}Z", dt.hour(), dt.minute())
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    // ---- Task 1: BragStatType + BragCategory ----

    #[test]
    fn all_58_stats_present() {
        // The implementation plan states 65 stats; the authoritative Swift
        // source (`BragSheetStatType.swift`) has exactly 58 `case`s. This
        // ports the 58 that actually exist. See Phase 1 report.
        assert_eq!(BragStatType::all().len(), 58);
    }

    #[test]
    fn serde_rawvalue_roundtrip() {
        assert_eq!(
            serde_json::to_string(&BragStatType::TotalQsos).unwrap(),
            "\"totalQSOs\""
        );
        assert_eq!(BragStatType::FurthestQrpContact.as_str(), "furthestQRPContact");
        assert_eq!(BragStatType::NewDxccEntities.as_str(), "newDXCCEntities");
        assert_eq!(
            BragStatType::WorkedAllStatesProgress.as_str(),
            "workedAllStatesProgress"
        );
        assert_eq!(BragStatType::BestRstAtDistance.as_str(), "bestRSTAtDistance");
        assert_eq!(BragStatType::ParkToParkContacts.as_str(), "parkToParkContacts");

        // Roundtrip through serde_json for every variant.
        for stat in BragStatType::all() {
            let json = serde_json::to_string(&stat).unwrap();
            let back: BragStatType = serde_json::from_str(&json).unwrap();
            assert_eq!(stat, back);
        }
    }

    #[test]
    fn every_stat_has_metadata_and_category() {
        for s in BragStatType::all() {
            assert!(!s.display_name().is_empty());
            assert!(!s.short_display_name().is_empty());
            let _ = s.category();
            assert!(!s.icon_key().is_empty());
        }
    }

    #[test]
    fn categories_cover_all_stats_partition() {
        let mut seen = 0;
        for c in BragCategory::all() {
            seen += c.stats().len();
        }
        assert_eq!(seen, 58); // each of the 58 stats in exactly one category
    }

    #[test]
    fn category_icon_keys_match_semantic_mapping() {
        assert_eq!(BragCategory::Totals.icon_key(), "number");
        assert_eq!(BragCategory::SpeedAndRate.icon_key(), "gauge");
        assert_eq!(BragCategory::Distance.icon_key(), "bearing");
        assert_eq!(BragCategory::PowerAndEfficiency.icon_key(), "bolt");
        assert_eq!(BragCategory::GeographicReach.icon_key(), "globe");
        assert_eq!(BragCategory::VolumeRecords.icon_key(), "trophy");
        assert_eq!(BragCategory::Streaks.icon_key(), "flame");
        assert_eq!(BragCategory::Pota.icon_key(), "tree");
        assert_eq!(BragCategory::Cw.icon_key(), "waveform");
        assert_eq!(BragCategory::SignalQuality.icon_key(), "antenna");
        assert_eq!(BragCategory::FunAndUnique.icon_key(), "sparkles");
    }

    // ---- Task 2: BragPeriod ----

    #[test]
    fn weekly_starts_monday_0000z() {
        // 2026-07-11 is a Saturday; Monday 00:00Z is 2026-07-06.
        let now = Utc.with_ymd_and_hms(2026, 7, 11, 15, 0, 0).unwrap();
        let (start, _) = BragPeriod::Weekly.window(now);
        assert_eq!(
            start,
            Some(Utc.with_ymd_and_hms(2026, 7, 6, 0, 0, 0).unwrap().timestamp())
        );
    }

    #[test]
    fn monthly_starts_first_0000z() {
        let now = Utc.with_ymd_and_hms(2026, 7, 11, 15, 0, 0).unwrap();
        let (start, _) = BragPeriod::Monthly.window(now);
        assert_eq!(
            start,
            Some(Utc.with_ymd_and_hms(2026, 7, 1, 0, 0, 0).unwrap().timestamp())
        );
    }

    #[test]
    fn all_time_has_no_start() {
        let now = Utc.with_ymd_and_hms(2026, 7, 11, 0, 0, 0).unwrap();
        assert_eq!(BragPeriod::AllTime.window(now).0, None);
        assert_eq!(BragPeriod::AllTime.window(now).1, Some(now.timestamp()));
    }

    #[test]
    fn weekly_window_when_now_is_monday() {
        // Monday itself: start should be the same day at 0000Z.
        let now = Utc.with_ymd_and_hms(2026, 7, 6, 3, 0, 0).unwrap();
        let (start, _) = BragPeriod::Weekly.window(now);
        assert_eq!(
            start,
            Some(Utc.with_ymd_and_hms(2026, 7, 6, 0, 0, 0).unwrap().timestamp())
        );
    }

    #[test]
    fn default_preset_mapping() {
        assert_eq!(BragPeriod::Weekly.default_preset(), BragPreset::Contester);
        assert_eq!(BragPeriod::Monthly.default_preset(), BragPreset::General);
        assert_eq!(BragPeriod::AllTime.default_preset(), BragPreset::Dxer);
    }

    // ---- Task 3: BragPreset ----

    #[test]
    fn show_everything_has_all_58() {
        assert_eq!(BragPreset::ShowEverything.stats().len(), 58);
        assert_eq!(BragPreset::ShowEverything.stats(), BragStatType::all());
    }

    #[test]
    fn default_hero_is_first_four() {
        for preset in BragPreset::all() {
            let expected: Vec<_> = preset.stats().into_iter().take(4).collect();
            assert_eq!(preset.default_hero_stats(), expected);
        }
    }

    #[test]
    fn general_preset_matches_swift() {
        use BragStatType::*;
        assert_eq!(
            BragPreset::General.stats(),
            vec![
                TotalQsos,
                FurthestContact,
                DxccEntities,
                StatesAndProvinces,
                ActiveBands,
                ActiveModes,
                OperatingDays,
                BestSessionRate,
                ClubMembersWorked,
            ]
        );
    }

    #[test]
    fn dxer_preset_matches_swift() {
        use BragStatType::*;
        assert_eq!(
            BragPreset::Dxer.stats(),
            vec![
                FurthestContact,
                FurthestContactPerBand,
                DxccEntities,
                NewDxccEntities,
                Continents,
                MostCountriesInADay,
                GridSquares,
                TotalDistance,
            ]
        );
    }

    #[test]
    fn qrp_preset_matches_swift() {
        use BragStatType::*;
        assert_eq!(
            BragPreset::Qrp.stats(),
            vec![
                LowestPowerContact,
                BestWattsPerMile,
                FurthestQrpContact,
                QrpQsoCount,
                MilliwattQsoCount,
                FurthestContact,
                TotalDistance,
            ]
        );
    }

    #[test]
    fn activator_preset_matches_swift() {
        use BragStatType::*;
        assert_eq!(
            BragPreset::Activator.stats(),
            vec![
                ParksActivated,
                BestActivation,
                FastestActivation,
                ParkToParkContacts,
                LargestNfer,
                NewParks,
                TotalQsos,
                BestSessionRate,
            ]
        );
    }

    #[test]
    fn contester_preset_matches_swift() {
        use BragStatType::*;
        assert_eq!(
            BragPreset::Contester.stats(),
            vec![
                Fastest10Qsos,
                Peak15MinRate,
                BestSessionRate,
                MostQsosInADay,
                TotalQsos,
                ActiveBands,
                UniqueCallsigns,
            ]
        );
    }

    #[test]
    fn cw_enthusiast_preset_matches_swift() {
        use BragStatType::*;
        assert_eq!(
            BragPreset::CwEnthusiast.stats(),
            vec![
                TotalCwQsos,
                FastestCwSpeed,
                CwDistanceRecord,
                CwQrpRecord,
                Peak15MinRate,
                PerfectReports,
                CurrentOnAirStreak,
            ]
        );
    }

    // ---- Task 4: BragPeriodConfig + BragConfiguration ----

    #[test]
    fn toggle_hero_caps_at_four() {
        let mut c = BragPeriodConfig::from_preset(BragPreset::ShowEverything);
        c.hero_stats.clear();
        let stats: Vec<_> = c.enabled_stats.iter().copied().take(5).collect();
        for (i, s) in stats.iter().enumerate() {
            let ok = c.toggle_hero(*s);
            assert_eq!(ok, i < 4);
        }
        assert_eq!(c.hero_stats.len(), 4);
    }

    #[test]
    fn toggle_hero_rejects_non_enabled_stat() {
        let mut c = BragPeriodConfig::from_preset(BragPreset::General);
        // Pick a stat definitely not in General's preset.
        let outside = BragStatType::all()
            .into_iter()
            .find(|s| !c.enabled_stats.contains(s))
            .expect("some stat outside the preset");
        assert!(!c.toggle_hero(outside));
        assert!(!c.hero_stats.contains(&outside));
    }

    #[test]
    fn toggle_removes_from_enabled_and_hero() {
        let mut c = BragPeriodConfig::from_preset(BragPreset::General);
        let stat = c.enabled_stats[0];
        c.toggle_hero(stat); // ensure present in hero if capacity allows, or already there
        c.toggle(stat);
        assert!(!c.enabled_stats.contains(&stat));
        assert!(!c.hero_stats.contains(&stat));
    }

    #[test]
    fn toggle_adds_when_absent() {
        let mut c = BragPeriodConfig::from_preset(BragPreset::General);
        let outside = BragStatType::all()
            .into_iter()
            .find(|s| !c.enabled_stats.contains(s))
            .unwrap();
        c.toggle(outside);
        assert!(c.enabled_stats.contains(&outside));
    }

    /// Ground-truth cases from Swift's `enabledStats.move(fromOffsets:
    /// [from], toOffset: to)` (single-index `IndexSet` move), starting from
    /// `[A, B, C, D]`:
    /// - move(0, 2) -> [B, A, C, D]
    /// - move(1, 3) -> [A, C, B, D]
    /// - move(2, 0) -> [C, A, B, D]
    /// - move(3, 1) -> [A, D, B, C]
    #[test]
    fn move_stat_matches_swift_move_semantics() {
        let c = BragPeriodConfig::from_preset(BragPreset::General);
        let original = c.enabled_stats.clone();
        assert!(original.len() >= 4, "need at least 4 enabled stats to test");
        let (a, b, c_, d) = (original[0], original[1], original[2], original[3]);

        let mut cfg = c.clone();
        cfg.move_stat(0, 2);
        assert_eq!(&cfg.enabled_stats[0..4], &[b, a, c_, d]);

        let mut cfg = c.clone();
        cfg.move_stat(1, 3);
        assert_eq!(&cfg.enabled_stats[0..4], &[a, c_, b, d]);

        let mut cfg = c.clone();
        cfg.move_stat(2, 0);
        assert_eq!(&cfg.enabled_stats[0..4], &[c_, a, b, d]);

        let mut cfg = c;
        cfg.move_stat(3, 1);
        assert_eq!(&cfg.enabled_stats[0..4], &[a, d, b, c_]);
    }

    #[test]
    fn default_config_matches_swift_defaults() {
        let config = BragConfiguration::default();
        assert_eq!(config.weekly.base_preset, Some(BragPreset::Contester));
        assert_eq!(config.monthly.base_preset, Some(BragPreset::General));
        assert_eq!(config.all_time.base_preset, Some(BragPreset::Dxer));
        assert!(config.include_map);
        assert!(!config.include_equipment_summary);
        assert!(config.gold_record_badges);
    }

    #[test]
    fn config_for_and_set_config_roundtrip() {
        let mut config = BragConfiguration::default();
        let custom = BragPeriodConfig::from_preset(BragPreset::Qrp);
        config.set_config(custom.clone(), BragPeriod::Weekly);
        assert_eq!(config.config_for(BragPeriod::Weekly), &custom);
    }

    #[test]
    fn apply_preset_sets_period_config() {
        let mut config = BragConfiguration::default();
        config.apply_preset(BragPreset::CwEnthusiast, BragPeriod::AllTime);
        assert_eq!(
            config.config_for(BragPeriod::AllTime).base_preset,
            Some(BragPreset::CwEnthusiast)
        );
        assert_eq!(
            config.config_for(BragPeriod::AllTime).enabled_stats,
            BragPreset::CwEnthusiast.stats()
        );
    }

    #[test]
    fn copy_config_duplicates_between_periods() {
        let mut config = BragConfiguration::default();
        config.copy_config(BragPeriod::Weekly, BragPeriod::Monthly);
        assert_eq!(config.config_for(BragPeriod::Weekly), config.config_for(BragPeriod::Monthly));
    }

    #[test]
    fn config_json_roundtrip_matches_swift_blob() {
        // Fixture representing the Swift Codable JSON shape: enabledStats /
        // heroStats / basePreset per period, plus the three top-level flags.
        let json = r#"{
            "weekly": {
                "enabledStats": ["totalQSOs", "furthestContact"],
                "heroStats": ["totalQSOs"],
                "basePreset": "contester"
            },
            "monthly": {
                "enabledStats": ["dxccEntities"],
                "heroStats": [],
                "basePreset": "general"
            },
            "allTime": {
                "enabledStats": ["furthestQRPContact", "newDXCCEntities"],
                "heroStats": ["furthestQRPContact"],
                "basePreset": null
            },
            "includeMap": true,
            "includeEquipmentSummary": false,
            "goldRecordBadges": true
        }"#;

        let decoded: BragConfiguration = serde_json::from_str(json).unwrap();
        assert_eq!(decoded.weekly.enabled_stats, vec![BragStatType::TotalQsos, BragStatType::FurthestContact]);
        assert_eq!(decoded.weekly.base_preset, Some(BragPreset::Contester));
        assert_eq!(decoded.all_time.enabled_stats, vec![BragStatType::FurthestQrpContact, BragStatType::NewDxccEntities]);
        assert_eq!(decoded.all_time.base_preset, None);
        assert!(decoded.include_map);
        assert!(!decoded.include_equipment_summary);

        let re_encoded = serde_json::to_string(&decoded).unwrap();
        let round_tripped: BragConfiguration = serde_json::from_str(&re_encoded).unwrap();
        assert_eq!(decoded, round_tripped);
    }

    // ---- Task 5: BragStatValue ----

    #[test]
    fn progress_formats_fraction() {
        assert_eq!(
            BragStatValue::Progress { current: 38, total: 50 }.formatted(true),
            "38/50"
        );
    }

    #[test]
    fn time_of_day_formats_zulu() {
        let dt = Utc.with_ymd_and_hms(2026, 7, 11, 3, 12, 0).unwrap();
        let value = BragStatValue::TimeOfDay { unix_seconds: dt.timestamp() };
        assert_eq!(value.formatted(true), "0312Z");
    }

    #[test]
    fn no_data_has_no_data() {
        assert!(!BragStatValue::NoData.has_data());
    }

    #[test]
    fn count_has_data() {
        assert!(BragStatValue::Count(0).has_data());
        assert_eq!(BragStatValue::Count(142).formatted(true), "142");
    }

    #[test]
    fn streak_formats_days_suffix() {
        assert_eq!(
            BragStatValue::Streak { current: 12, longest: 30 }.formatted(true),
            "12d"
        );
    }

    #[test]
    fn power_formats_watts_suffix() {
        assert_eq!(
            BragStatValue::Power {
                watts: 5.0,
                callsign: "W6JY".to_string(),
                distance_km: Some(100.0),
                band: Some("20m".to_string()),
            }
            .formatted(true),
            "5W"
        );
    }

    #[test]
    fn distance_compact_formats_km_and_thousands() {
        assert_eq!(BragStatValue::Distance { km: 340.0 }.formatted(true), "340 km");
        assert_eq!(BragStatValue::Distance { km: 5_400.0 }.formatted(true), "5k km");
    }

    #[test]
    fn distance_formatted_imperial_matches_unit_formatter() {
        // UnitFormatter.distance(340km * 0.621371 = 211.26 mi) -> "211 mi"
        // (imperialDistance: mi >= 10 && < 1000 -> "%.0f mi").
        assert_eq!(BragStatValue::Distance { km: 340.0 }.formatted(false), "211 mi");
    }

    #[test]
    fn duration_compact_under_and_over_hour() {
        assert_eq!(BragStatValue::Duration { seconds: 502.0 }.formatted(true), "8m");
        assert_eq!(BragStatValue::Duration { seconds: 8_100.0 }.formatted(true), "2h15m");
    }

    #[test]
    fn band_table_and_mode_streak_list_hero_value_is_dashes() {
        assert_eq!(BragStatValue::BandTable(vec![]).formatted(true), "--");
        assert_eq!(BragStatValue::ModeStreakList(vec![]).formatted(true), "--");
    }

    #[test]
    fn hero_value_distance_is_compact_no_suffix_both_units() {
        assert_eq!(BragStatValue::Distance { km: 340.0 }.hero_value(true), "340");
        assert_eq!(BragStatValue::Distance { km: 340.0 }.hero_value(false), "211");
        assert_eq!(BragStatValue::Distance { km: 5_400.0 }.hero_value(true), "5k");
    }

    #[test]
    fn distance_labeled_metric_tiers_match_unit_formatter() {
        // metricDistance tiers: <1km -> meters; <10km -> 1 decimal; >=1000km -> "k km".
        assert_eq!(BragStatValue::Distance { km: 0.5 }.formatted(true), "500 m");
        assert_eq!(BragStatValue::Distance { km: 5.0 }.formatted(true), "5.0 km");
        assert_eq!(BragStatValue::Distance { km: 12_000.0 }.formatted(true), "12k km");
    }

    #[test]
    fn distance_labeled_imperial_tiers_match_unit_formatter() {
        // imperialDistance tiers: <0.1mi -> feet; <10mi -> 1 decimal; >=1000mi -> "k mi".
        // 0.05 km -> 0.0311 mi -> feet path: 0.0311 * 5280 ~= 164 ft.
        assert_eq!(BragStatValue::Distance { km: 0.05 }.formatted(false), "164 ft");
        assert_eq!(BragStatValue::Distance { km: 8.0 }.formatted(false), "5.0 mi");
        assert_eq!(BragStatValue::Distance { km: 20_000.0 }.formatted(false), "12k mi");
    }

    #[test]
    fn stat_value_json_roundtrip() {
        let values = vec![
            BragStatValue::Count(5),
            BragStatValue::Progress { current: 1, total: 2 },
            BragStatValue::NoData,
            BragStatValue::BandTable(vec![BandTableEntry {
                band: "20m".to_string(),
                callsign: "W6JY".to_string(),
                distance_km: Some(123.4),
            }]),
            BragStatValue::ModeStreakList(vec![ModeStreakEntry {
                mode: "CW".to_string(),
                current: 3,
                longest: 10,
            }]),
        ];
        for value in values {
            let json = serde_json::to_string(&value).unwrap();
            let back: BragStatValue = serde_json::from_str(&json).unwrap();
            assert_eq!(value, back);
        }
    }
}
