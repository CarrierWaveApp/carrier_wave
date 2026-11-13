//! FFI records/enums for the spot engine — flattened mirrors of
//! `cw_domain::spots` types plus the query-surface result shapes.

use std::collections::HashSet;

use cw_domain::spots::filters::{FilterContext, SpotFilter, SpotModeFilter, SpotStatusFilter};
use cw_domain::spots::model::{
    EnrichedSpot, MatchedNeed, NeedCategory, NeededStatus, NeedPriority, SpotSource,
};
use cw_domain::spots::needs::{
    BandSlotKey, CustomNeedPattern, CustomPatternType, NeedsPreferences, NeedsSnapshot,
};

use super::scope_db::{
    QueryResultSet, ScopeClubMemberRow, ScopeDxccRow, ScopePoloNoteRow, ScopeQsoRow,
};

// ---- Spots ----

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiSpotSource {
    Rbn,
    Pota,
    Sota,
    Wwff,
    DxSummit,
    DxHeat,
    DxWatch,
    Cluster,
    Pskr,
}

impl From<SpotSource> for FfiSpotSource {
    fn from(source: SpotSource) -> Self {
        match source {
            SpotSource::Rbn => FfiSpotSource::Rbn,
            SpotSource::Pota => FfiSpotSource::Pota,
            SpotSource::Sota => FfiSpotSource::Sota,
            SpotSource::Wwff => FfiSpotSource::Wwff,
            SpotSource::DxSummit => FfiSpotSource::DxSummit,
            SpotSource::DxHeat => FfiSpotSource::DxHeat,
            SpotSource::DxWatch => FfiSpotSource::DxWatch,
            SpotSource::Cluster => FfiSpotSource::Cluster,
            SpotSource::Pskr => FfiSpotSource::Pskr,
        }
    }
}

impl From<FfiSpotSource> for SpotSource {
    fn from(source: FfiSpotSource) -> Self {
        match source {
            FfiSpotSource::Rbn => SpotSource::Rbn,
            FfiSpotSource::Pota => SpotSource::Pota,
            FfiSpotSource::Sota => SpotSource::Sota,
            FfiSpotSource::Wwff => SpotSource::Wwff,
            FfiSpotSource::DxSummit => SpotSource::DxSummit,
            FfiSpotSource::DxHeat => SpotSource::DxHeat,
            FfiSpotSource::DxWatch => SpotSource::DxWatch,
            FfiSpotSource::Cluster => SpotSource::Cluster,
            FfiSpotSource::Pskr => SpotSource::Pskr,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiNeededStatus {
    NewEntity,
    NewBandSlot,
    WorkedNotConfirmed,
    Confirmed,
    Unknown,
}

impl From<NeededStatus> for FfiNeededStatus {
    fn from(status: NeededStatus) -> Self {
        match status {
            NeededStatus::NewEntity => FfiNeededStatus::NewEntity,
            NeededStatus::NewBandSlot => FfiNeededStatus::NewBandSlot,
            NeededStatus::WorkedNotConfirmed => FfiNeededStatus::WorkedNotConfirmed,
            NeededStatus::Confirmed => FfiNeededStatus::Confirmed,
            NeededStatus::Unknown => FfiNeededStatus::Unknown,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiNeedPriority {
    Low,
    Medium,
    High,
}

impl From<NeedPriority> for FfiNeedPriority {
    fn from(priority: NeedPriority) -> Self {
        match priority {
            NeedPriority::Low => FfiNeedPriority::Low,
            NeedPriority::Medium => FfiNeedPriority::Medium,
            NeedPriority::High => FfiNeedPriority::High,
        }
    }
}

/// Flattened need category kind; `value`/`band` on [`FfiMatchedNeed`] carry
/// the associated data.
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiNeedKind {
    DxccEntity,
    DxccBandSlot,
    WasState,
    WasStateMode,
    PotaNewPark,
    PotaActivatorState,
    PotaActivatorEntity,
    WwffNewReference,
    Custom,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiMatchedNeed {
    pub kind: FfiNeedKind,
    pub label: String,
    pub priority: FfiNeedPriority,
    /// Entity prefix / state / pattern, depending on `kind`.
    pub value: Option<String>,
    /// Band for `DxccBandSlot`, mode for `WasStateMode`.
    pub band: Option<String>,
}

impl From<&MatchedNeed> for FfiMatchedNeed {
    fn from(need: &MatchedNeed) -> Self {
        let (kind, value, band) = match &need.category {
            NeedCategory::DxccEntity { entity } => {
                (FfiNeedKind::DxccEntity, Some(entity.clone()), None)
            }
            NeedCategory::DxccBandSlot { entity, band } => {
                (FfiNeedKind::DxccBandSlot, Some(entity.clone()), Some(band.clone()))
            }
            NeedCategory::WasState { state } => {
                (FfiNeedKind::WasState, Some(state.clone()), None)
            }
            NeedCategory::WasStateMode { state, mode } => {
                (FfiNeedKind::WasStateMode, Some(state.clone()), Some(mode.clone()))
            }
            NeedCategory::PotaNewPark => (FfiNeedKind::PotaNewPark, None, None),
            NeedCategory::PotaActivatorState { state } => {
                (FfiNeedKind::PotaActivatorState, Some(state.clone()), None)
            }
            NeedCategory::PotaActivatorEntity { entity } => {
                (FfiNeedKind::PotaActivatorEntity, Some(entity.clone()), None)
            }
            NeedCategory::WwffNewReference => (FfiNeedKind::WwffNewReference, None, None),
            NeedCategory::Custom { pattern, .. } => {
                (FfiNeedKind::Custom, Some(pattern.clone()), None)
            }
        };
        FfiMatchedNeed {
            kind,
            label: need.label.clone(),
            priority: need.priority.into(),
            value,
            band,
        }
    }
}

/// A fully enriched spot, flattened for the FFI (UnifiedSpot fields inline).
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiEnrichedSpot {
    pub id: String,
    pub callsign: String,
    pub frequency_khz: f64,
    pub mode: String,
    /// Unix epoch seconds.
    pub timestamp: i64,
    pub source: FfiSpotSource,
    /// Derived band string, e.g. "20m" (empty when out of band).
    pub band: String,
    pub snr: Option<i32>,
    pub wpm: Option<i32>,
    pub spotter: Option<String>,
    pub spotter_grid: Option<String>,
    pub park_ref: Option<String>,
    pub park_name: Option<String>,
    pub comments: Option<String>,
    /// POTA's raw `source` field ("RBN" ⇒ skimmer-relayed, else human).
    pub pota_source: Option<String>,
    pub summit_code: Option<String>,
    pub summit_name: Option<String>,
    pub summit_points: Option<i32>,
    pub wwff_ref: Option<String>,
    pub wwff_name: Option<String>,
    pub dx_grid: Option<String>,
    pub continent_code: Option<String>,
    pub split_info: Option<String>,
    pub lotw_user: Option<bool>,
    pub dxcc_prefix: Option<String>,
    pub cq_zone: Option<i32>,
    pub iota_ref: Option<String>,
    pub location_desc: Option<String>,
    pub state_abbr: Option<String>,
    // Enrichment
    pub distance_meters: Option<f64>,
    pub bearing_degrees: Option<f64>,
    /// `SpotRegion.raw_value()`, e.g. "NE US" (persisted format).
    pub region: String,
    /// `SpotContinent.raw_value()`, e.g. "NA".
    pub region_continent: String,
    pub state: Option<String>,
    pub country: Option<String>,
    pub dxcc_entity: Option<String>,
    pub needed_status: FfiNeededStatus,
    pub operator_name: Option<String>,
    pub matched_needs: Vec<FfiMatchedNeed>,
}

impl From<&EnrichedSpot> for FfiEnrichedSpot {
    fn from(enriched: &EnrichedSpot) -> Self {
        let spot = &enriched.spot;
        FfiEnrichedSpot {
            id: spot.id.clone(),
            callsign: spot.callsign.clone(),
            frequency_khz: spot.frequency_khz,
            mode: spot.mode.clone(),
            timestamp: spot.timestamp,
            source: spot.source.into(),
            band: spot.band().to_string(),
            snr: spot.snr,
            wpm: spot.wpm,
            spotter: spot.spotter.clone(),
            spotter_grid: spot.spotter_grid.clone(),
            park_ref: spot.park_ref.clone(),
            park_name: spot.park_name.clone(),
            comments: spot.comments.clone(),
            pota_source: spot.pota_source.clone(),
            summit_code: spot.summit_code.clone(),
            summit_name: spot.summit_name.clone(),
            summit_points: spot.summit_points,
            wwff_ref: spot.wwff_ref.clone(),
            wwff_name: spot.wwff_name.clone(),
            dx_grid: spot.dx_grid.clone(),
            continent_code: spot.continent.clone(),
            split_info: spot.split_info.clone(),
            lotw_user: spot.lotw_user,
            dxcc_prefix: spot.dxcc_prefix.clone(),
            cq_zone: spot.cq_zone,
            iota_ref: spot.iota_ref.clone(),
            location_desc: spot.location_desc.clone(),
            state_abbr: spot.state_abbr.clone(),
            distance_meters: enriched.distance_meters,
            bearing_degrees: enriched.bearing_degrees,
            region: enriched.region.raw_value().to_string(),
            region_continent: enriched.region.continent().raw_value().to_string(),
            state: enriched.state.clone(),
            country: enriched.country.clone(),
            dxcc_entity: enriched.dxcc_entity.clone(),
            needed_status: enriched.needed_status.into(),
            operator_name: enriched.operator_name.clone(),
            matched_needs: enriched.matched_needs.iter().map(FfiMatchedNeed::from).collect(),
        }
    }
}

// ---- Filters ----

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiSpotModeFilter {
    All,
    Cw,
    Phone,
    Digital,
}

impl From<FfiSpotModeFilter> for SpotModeFilter {
    fn from(filter: FfiSpotModeFilter) -> Self {
        match filter {
            FfiSpotModeFilter::All => SpotModeFilter::All,
            FfiSpotModeFilter::Cw => SpotModeFilter::Cw,
            FfiSpotModeFilter::Phone => SpotModeFilter::Phone,
            FfiSpotModeFilter::Digital => SpotModeFilter::Digital,
        }
    }
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiSpotStatusFilter {
    All,
    NewOnly,
    NeededOnly,
    NewAndNeeded,
}

impl From<FfiSpotStatusFilter> for SpotStatusFilter {
    fn from(filter: FfiSpotStatusFilter) -> Self {
        match filter {
            FfiSpotStatusFilter::All => SpotStatusFilter::All,
            FfiSpotStatusFilter::NewOnly => SpotStatusFilter::NewOnly,
            FfiSpotStatusFilter::NeededOnly => SpotStatusFilter::NeededOnly,
            FfiSpotStatusFilter::NewAndNeeded => SpotStatusFilter::NewAndNeeded,
        }
    }
}

/// Composed spot filter — the union of both platforms' widget stacks.
/// Empty vecs mean "no filter" (matching both platforms).
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct FfiSpotFilter {
    pub sources: Vec<FfiSpotSource>,
    pub bands: Vec<String>,
    pub mode_families: Vec<FfiSpotModeFilter>,
    /// Exact uppercased mode strings (iOS).
    pub modes: Vec<String>,
    /// `SpotContinent.raw_value()` strings, e.g. "NA".
    pub continents: Vec<String>,
    /// `SpotRegionGroup.raw_value()` strings, e.g. "US".
    pub region_groups: Vec<String>,
    pub status: Option<FfiSpotStatusFilter>,
    pub max_age_minutes: Option<i64>,
    pub text: Option<String>,
    pub hide_worked: bool,
    pub needs_only: bool,
}

impl FfiSpotFilter {
    pub(crate) fn to_domain(&self) -> SpotFilter {
        use cw_domain::spots::region::{SpotContinent, SpotRegionGroup};
        let non_empty_set = |values: &[String]| -> Option<HashSet<String>> {
            if values.is_empty() { None } else { Some(values.iter().cloned().collect()) }
        };
        SpotFilter {
            sources: if self.sources.is_empty() {
                None
            } else {
                Some(self.sources.iter().map(|s| SpotSource::from(*s)).collect())
            },
            bands: non_empty_set(&self.bands),
            mode_families: if self.mode_families.is_empty() {
                None
            } else {
                Some(self.mode_families.iter().map(|f| SpotModeFilter::from(*f)).collect())
            },
            modes: non_empty_set(&self.modes),
            continents: if self.continents.is_empty() {
                None
            } else {
                Some(
                    self.continents
                        .iter()
                        .filter_map(|raw| SpotContinent::from_raw(raw))
                        .collect(),
                )
            },
            region_groups: if self.region_groups.is_empty() {
                None
            } else {
                Some(
                    self.region_groups
                        .iter()
                        .filter_map(|raw| region_group_from_raw(raw))
                        .collect::<HashSet<SpotRegionGroup>>(),
                )
            },
            status: self.status.map(SpotStatusFilter::from).unwrap_or_default(),
            max_age_minutes: self.max_age_minutes,
            text: self.text.clone(),
            hide_worked: self.hide_worked,
            needs_only: self.needs_only,
        }
    }
}

fn region_group_from_raw(raw: &str) -> Option<cw_domain::spots::region::SpotRegionGroup> {
    use cw_domain::spots::region::SpotRegionGroup;
    Some(match raw {
        "US" => SpotRegionGroup::Us,
        "Canada" => SpotRegionGroup::Canada,
        "Mexico" => SpotRegionGroup::Mexico,
        "Caribbean" => SpotRegionGroup::Caribbean,
        "Europe" => SpotRegionGroup::Europe,
        "Asia" => SpotRegionGroup::Asia,
        "Oceania" => SpotRegionGroup::Oceania,
        "Africa" => SpotRegionGroup::Africa,
        "S. America" => SpotRegionGroup::SouthAmerica,
        "Other" => SpotRegionGroup::Other,
        _ => return None,
    })
}

/// Per-evaluation worked-callsign context for filters.
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct FfiWorkedContext {
    /// Uppercased callsigns already worked (drives `hide_worked`).
    pub worked: Vec<String>,
    /// Uppercased callsigns worked today (drives the status filter).
    pub worked_today: Vec<String>,
}

impl FfiWorkedContext {
    pub(crate) fn to_domain(&self, now: i64) -> FilterContext {
        FilterContext {
            now,
            worked: self.worked.iter().cloned().collect(),
            worked_today: self.worked_today.iter().cloned().collect(),
        }
    }
}

// ---- Needs snapshot ----

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiBandSlot {
    pub entity: String,
    pub band: String,
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiCustomPatternType {
    Callsign,
    Entity,
    State,
    ParkRef,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiCustomPattern {
    pub pattern: String,
    pub pattern_type: FfiCustomPatternType,
    pub label: String,
}

/// Host-computed needs snapshot (iOS `NeedsEngine` output projected flat).
#[derive(uniffi::Record, Clone, Debug, Default)]
pub struct FfiNeedsSnapshot {
    pub dxcc_all_time_worked: Vec<String>,
    pub dxcc_band_slots_worked: Vec<FfiBandSlot>,
    pub was_states_worked: Vec<String>,
    pub was_states_missing: Vec<String>,
    pub pota_parks_worked: Vec<String>,
    pub pota_activator_states_missing: Vec<String>,
    pub wwff_references_worked: Vec<String>,
    pub custom_patterns: Vec<FfiCustomPattern>,
    /// "phone" / "cw" / "digital" / "other".
    pub mode_families_worked: Vec<String>,
    pub track_dxcc: bool,
    pub track_was: bool,
    pub track_pota_hunter: bool,
    pub track_wwff_hunter: bool,
}

impl FfiNeedsSnapshot {
    pub(crate) fn to_domain(&self) -> (NeedsSnapshot, NeedsPreferences) {
        let snapshot = NeedsSnapshot {
            dxcc: cw_domain::spots::needs::DxccNeeds {
                all_time_worked: self.dxcc_all_time_worked.iter().cloned().collect(),
                band_slots_worked: self
                    .dxcc_band_slots_worked
                    .iter()
                    .map(|slot| BandSlotKey {
                        entity: slot.entity.clone(),
                        band: slot.band.clone(),
                    })
                    .collect(),
                total_known_entities: 0,
                grid_square: None,
            },
            was: cw_domain::spots::needs::WasNeeds {
                country: "USA".to_string(),
                subdivision_term: "states".to_string(),
                states_worked: self.was_states_worked.iter().cloned().collect(),
                states_missing: self.was_states_missing.iter().cloned().collect(),
                per_mode_worked: Default::default(),
            },
            pota_hunter: cw_domain::spots::needs::PotaHunterNeeds {
                parks_worked: self.pota_parks_worked.iter().cloned().collect(),
                next_tier_threshold: 0,
                next_tier_name: None,
            },
            pota_activator: cw_domain::spots::needs::PotaActivatorNeeds {
                states_missing: self.pota_activator_states_missing.iter().cloned().collect(),
                entities_worked: 0,
                next_entity_tier_threshold: 0,
            },
            wwff_hunter: cw_domain::spots::needs::WwffHunterNeeds {
                references_worked: self.wwff_references_worked.iter().cloned().collect(),
                next_tier_threshold: 0,
                next_tier_name: None,
            },
            custom_patterns: self
                .custom_patterns
                .iter()
                .map(|pattern| CustomNeedPattern {
                    pattern: pattern.pattern.clone(),
                    pattern_type: match pattern.pattern_type {
                        FfiCustomPatternType::Callsign => CustomPatternType::Callsign,
                        FfiCustomPatternType::Entity => CustomPatternType::Entity,
                        FfiCustomPatternType::State => CustomPatternType::State,
                        FfiCustomPatternType::ParkRef => CustomPatternType::ParkRef,
                    },
                    label: pattern.label.clone(),
                })
                .collect(),
            mode_families_worked: self.mode_families_worked.iter().cloned().collect(),
        };
        let prefs = NeedsPreferences {
            track_dxcc: self.track_dxcc,
            track_was: self.track_was,
            track_pota_hunter: self.track_pota_hunter,
            track_wwff_hunter: self.track_wwff_hunter,
        };
        (snapshot, prefs)
    }
}

// ---- Engine config / status / snapshot ----

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiSpotEngineConfig {
    /// Activities-server base URL (RBN proxy), e.g.
    /// `https://activities.carrierwave.app`.
    pub activities_base_url: String,
    pub enabled_sources: Vec<FfiSpotSource>,
    pub poll_interval_secs: u32,
    pub max_spot_age_secs: u32,
    /// RBN fetch cap (iOS `SpotFetchLimits`, Sweep uses 100).
    pub rbn_limit: u32,
    /// SOTA fetch cap.
    pub sota_count: u32,
    /// DX-web trio fetch caps (Sweep uses 50).
    pub dx_web_limit: u32,
}

impl Default for FfiSpotEngineConfig {
    fn default() -> Self {
        FfiSpotEngineConfig {
            activities_base_url: "https://activities.carrierwave.app".to_string(),
            enabled_sources: vec![
                FfiSpotSource::Rbn,
                FfiSpotSource::Pota,
                FfiSpotSource::Sota,
                FfiSpotSource::Wwff,
            ],
            poll_interval_secs: 30,
            max_spot_age_secs: 1_800,
            rbn_limit: 100,
            sota_count: 50,
            dx_web_limit: 50,
        }
    }
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiSourceCount {
    pub source: FfiSpotSource,
    pub count: u32,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiSourceError {
    pub source: FfiSpotSource,
    pub message: String,
}

/// A published view of the engine's spot pool.
#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiSpotSnapshot {
    /// Monotonic publish counter; equal generations = identical data.
    pub generation: u64,
    pub spots: Vec<FfiEnrichedSpot>,
    pub counts: Vec<FfiSourceCount>,
    pub errors: Vec<FfiSourceError>,
    /// Unix epoch seconds of the last completed poll (0 = never).
    pub last_refresh: i64,
    /// Result of the active band-scope query, when one is set.
    pub allowed_spot_ids: Option<Vec<String>>,
}

// ---- Query surface ----

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiQueryResultSet {
    pub columns: Vec<String>,
    pub rows: Vec<FfiQueryRow>,
    pub truncated: bool,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiQueryRow {
    pub values: Vec<Option<String>>,
}

impl From<QueryResultSet> for FfiQueryResultSet {
    fn from(result: QueryResultSet) -> Self {
        FfiQueryResultSet {
            columns: result.columns,
            rows: result.rows.into_iter().map(|values| FfiQueryRow { values }).collect(),
            truncated: result.truncated,
        }
    }
}

/// Query error carrying editor position info (1-based; None when SQLite
/// didn't report an offset).
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SpotQueryError {
    #[error("{reason}")]
    Query { reason: String, line: Option<u32>, column: Option<u32> },
}

impl From<super::scope_db::ScopeQueryError> for SpotQueryError {
    fn from(err: super::scope_db::ScopeQueryError) -> Self {
        SpotQueryError::Query { reason: err.message, line: err.line, column: err.column }
    }
}

// ---- Mirror rows ----

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiScopeQso {
    pub id: String,
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub frequency: Option<f64>,
    pub timestamp: f64,
    pub my_callsign: String,
    pub their_grid: Option<String>,
    pub my_grid: Option<String>,
    pub park_ref: Option<String>,
    pub their_park_ref: Option<String>,
    pub dxcc: Option<i64>,
    pub modified_at: Option<f64>,
    pub is_hidden: bool,
    pub is_activity_log: bool,
}

impl From<&FfiScopeQso> for ScopeQsoRow {
    fn from(qso: &FfiScopeQso) -> Self {
        ScopeQsoRow {
            id: qso.id.clone(),
            callsign: qso.callsign.clone(),
            band: qso.band.clone(),
            mode: qso.mode.clone(),
            frequency: qso.frequency,
            timestamp: qso.timestamp,
            my_callsign: qso.my_callsign.clone(),
            their_grid: qso.their_grid.clone(),
            my_grid: qso.my_grid.clone(),
            park_ref: qso.park_ref.clone(),
            their_park_ref: qso.their_park_ref.clone(),
            dxcc: qso.dxcc,
            modified_at: qso.modified_at,
            is_hidden: qso.is_hidden,
            is_activity_log: qso.is_activity_log,
        }
    }
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiScopeDxcc {
    pub entity: String,
    pub prefix: Option<String>,
    pub continent: Option<String>,
    pub cq_zone: Option<i64>,
    pub itu_zone: Option<i64>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
}

impl From<&FfiScopeDxcc> for ScopeDxccRow {
    fn from(row: &FfiScopeDxcc) -> Self {
        ScopeDxccRow {
            entity: row.entity.clone(),
            prefix: row.prefix.clone(),
            continent: row.continent.clone(),
            cq_zone: row.cq_zone,
            itu_zone: row.itu_zone,
            lat: row.lat,
            lon: row.lon,
        }
    }
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiScopePoloNote {
    pub callsign: String,
    pub tag: Option<String>,
    pub body: Option<String>,
}

impl From<&FfiScopePoloNote> for ScopePoloNoteRow {
    fn from(row: &FfiScopePoloNote) -> Self {
        ScopePoloNoteRow {
            callsign: row.callsign.clone(),
            tag: row.tag.clone(),
            body: row.body.clone(),
        }
    }
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiScopeClubMember {
    pub callsign: String,
    pub club: String,
}

// ---- Goal profiles (Band Scope v2) ----

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum FfiBasePredicate {
    All,
    Parks,
    DxccNeeded,
    ClubMembers,
    NeededOnly,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiGoalProfile {
    pub id: String,
    pub name: String,
    pub base_predicate: FfiBasePredicate,
    pub clubs: Vec<String>,
    /// `NeedCategory` keys that count as "needed" under this profile;
    /// empty = all categories.
    pub need_categories: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiQuickToggles {
    pub wpm_ceiling: Option<u32>,
    pub suppress_worked_today: bool,
    pub rbn_enabled: bool,
    /// Radio-mode filter: mode strings a spot must match (hide in Heard,
    /// dim in Scope). Empty = no mode filtering.
    pub enabled_modes: Vec<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct FfiCompiledProfileQueries {
    pub scope_pass: String,
    pub heard_pass: String,
    pub wpm_dim: Option<String>,
}

impl From<FfiGoalProfile> for cw_domain::spots::goal_profile::GoalProfile {
    fn from(profile: FfiGoalProfile) -> Self {
        use cw_domain::spots::goal_profile::BasePredicate;
        cw_domain::spots::goal_profile::GoalProfile {
            id: profile.id,
            name: profile.name,
            base_predicate: match profile.base_predicate {
                FfiBasePredicate::All => BasePredicate::All,
                FfiBasePredicate::Parks => BasePredicate::Parks,
                FfiBasePredicate::DxccNeeded => BasePredicate::DxccNeeded,
                FfiBasePredicate::ClubMembers => BasePredicate::ClubMembers,
                FfiBasePredicate::NeededOnly => BasePredicate::NeededOnly,
            },
            clubs: profile.clubs,
            need_categories: profile.need_categories,
        }
    }
}

impl From<FfiQuickToggles> for cw_domain::spots::goal_profile::QuickToggles {
    fn from(toggles: FfiQuickToggles) -> Self {
        cw_domain::spots::goal_profile::QuickToggles {
            wpm_ceiling: toggles.wpm_ceiling,
            suppress_worked_today: toggles.suppress_worked_today,
            rbn_enabled: toggles.rbn_enabled,
            enabled_modes: toggles.enabled_modes,
        }
    }
}

impl From<&FfiScopeClubMember> for ScopeClubMemberRow {
    fn from(row: &FfiScopeClubMember) -> Self {
        ScopeClubMemberRow {
            callsign: row.callsign.to_uppercase(),
            club: row.club.clone(),
        }
    }
}

