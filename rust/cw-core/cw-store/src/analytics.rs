//! Aggregation queries — the analytics surface (Phase 4 item #6).
//!
//! Mirrors the iOS dashboard / award / map aggregations (`StatsComputationActor`,
//! `POTAAwardsActor`, `MapDataLoadingActor`, …). Every aggregate runs as a SQL
//! `GROUP BY` / `COUNT(DISTINCT)` so the caller never loads rows — cost is O(result
//! rows), not O(QSOs). Each restricts to "visible" QSOs (not hidden, not a metadata
//! pseudo-mode) and accepts an optional `.cwquery` DSL filter, reusing
//! `compile_where`.
//!
//! See docs/plans/2026-06-20-rust-analytics-surface-design.md.

use crate::qso::MAX_FETCH_LIMIT;
use crate::query::compile_where;
use crate::Result;
use crate::Store;
use cw_domain::location_prefix::COUNTRIES;
use cw_domain::query::ParsedQuery;
use rusqlite::OptionalExtension;
use serde::{Deserialize, Serialize};

/// SQL fragment restricting to QSOs that count toward stats: not hidden and not a
/// metadata pseudo-mode (WEATHER/SOLAR/NOTE). Matches Swift `!isHidden` +
/// `!QSOMode.isMetadata`. A NULL/empty mode is a real QSO and is kept.
/// Shared with `map_data` — the map surface uses the same visibility predicate.
pub(crate) const VISIBLE_QSO: &str =
    "is_hidden = 0 AND (mode IS NULL OR cw_lower(mode) NOT IN ('weather','solar','note'))";

/// SQL predicate matching a metadata pseudo-mode (the negation of the mode half of
/// `VISIBLE_QSO`). A NULL mode is a real QSO, so it is NOT metadata.
const METADATA_MODE: &str = "(mode IS NOT NULL AND cw_lower(mode) IN ('weather','solar','note'))";

/// `FROM`/`WHERE` shared by the `session_item_detail` queries: QSOs (alias `q`) joined to
/// their logging session (alias `ls`) where the session has QSOs and uses the bound name
/// as any equipment slot, excluding metadata pseudo-modes. The name binds four positional
/// `?` (rig/antenna/key/mic). Exact, case-sensitive match mirrors
/// `EquipmentItemDetailActor.fetchMatchingSessions`; no hidden filter — the Swift consumer
/// only excludes metadata when tallying QSO snapshots (it does not re-check `is_hidden`).
const SESSION_ITEM_FROM_MATCH: &str = "FROM qso q JOIN logging_session ls \
     ON q.logging_session_id = ls.id \
     WHERE ls.qso_count > 0 \
     AND (ls.my_rig = ? OR ls.my_antenna = ? OR ls.my_key = ? OR ls.my_mic = ?) \
     AND (q.mode IS NULL OR cw_lower(q.mode) NOT IN ('weather','solar','note'))";

/// America 250 WAS window, UTC unix seconds. `[2026-01-01, 2027-01-01)`. Mirrors the
/// hard-coded calendar range in `POTAAwardsActor.fetchWAS250QSOs`.
const WAS250_START: i64 = 1_767_225_600;
const WAS250_END: i64 = 1_798_761_600;

/// The 50 US states that count toward WAS. Mirrors `POTAAwardsActor.validStates`
/// (Swift). DC and territories are intentionally excluded — WAS is the 50 states.
const VALID_US_STATES: &[&str] = &[
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS",
    "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
    "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV",
    "WI", "WY",
];

/// SQL expression normalizing the stored `state` column to a WAS abbreviation: take
/// the text before " // " (the LoFi comment suffix), uppercase, trim spaces. Mirrors
/// Swift `USStates.normalizeAbbreviation`.
const NORMALIZED_STATE: &str = "TRIM(UPPER(CASE WHEN INSTR(state, ' // ') > 0 \
     THEN SUBSTR(state, 1, INSTR(state, ' // ') - 1) ELSE state END))";

/// Rust-side equivalent of the `NORMALIZED_STATE` SQL fragment, for callers that
/// already hold the `state` value in memory (e.g. the map aggregation, which reads
/// rows via `qso_map_rows` rather than issuing its own SQL). Same rule: strip a
/// trailing " // ..." LoFi comment, uppercase, trim, then validate against
/// [`VALID_US_STATES`]. Returns `None` if `state` is absent or not one of the 50
/// valid abbreviations.
pub fn normalized_valid_state(state: &str) -> Option<&'static str> {
    let base = state.split(" // ").next().unwrap_or(state).trim().to_uppercase();
    VALID_US_STATES.iter().find(|&&valid| valid == base).copied()
}

/// Headline distinct counts for the stats dashboard (`StatsComputationActor`
/// totals). Distinctness is case-sensitive on the raw stored value to mirror the
/// Swift `Set<String>` accumulators.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DistinctCounts {
    pub qsos: i64,
    pub bands: i64,
    pub grids: i64,
    pub entities: i64,
    pub parks: i64,
    /// QSOs confirmed on QRZ OR LoTW (the headline "confirmed QSLs" count).
    pub confirmed: i64,
    /// QSOs confirmed on QRZ (`StatsComputationActor.qrzConfirmedCount`).
    pub qrz_confirmed: i64,
    /// QSOs confirmed on LoTW (`lotwConfirmedCount`).
    pub lotw_confirmed: i64,
    /// QSOs carrying a non-empty their_grid (`qsosWithGrid`).
    pub with_grid: i64,
    /// QSOs carrying a non-empty park (`qsosWithParkRef`).
    pub with_park: i64,
    /// QSOs carrying a valid dxcc > 0 (`qsosWithDXCC`).
    pub with_dxcc: i64,
    /// Distinct raw callsigns worked (`uniqueCallsignCount`).
    pub unique_callsigns: i64,
}

/// A grouped count row: the dimension key (machine value), a human label, the QSO
/// count, and the number of distinct callsigns in the group.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DimensionCount {
    pub key: String,
    pub label: String,
    pub count: i64,
    pub distinct_calls: i64,
}

/// Dimensions `qso_count_by` can group on.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AggregateDimension {
    Band,
    ModeFamily,
    Dxcc,
    Month,
}

/// One POTA activation: a (park, operator, UTC-date) group with its unique/total QSO
/// counts. Mirrors `POTAAwardsActor`'s `ActivationGroup` — the group key uppercases
/// park + operator callsign and buckets by UTC day; `unique_qsos` dedupes by
/// `UPPER(callsign)|band|mode`; `successful` is `unique_qsos >= min_qsos`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ActivationRollup {
    pub park: String,
    pub operator_callsign: String,
    pub utc_date: String,
    pub unique_qsos: i64,
    pub total_qsos: i64,
    pub successful: bool,
}

/// One worked grid tile (Maidenhead prefix) with its QSO/confirmed counts and the
/// most recent QSO timestamp — backs the map grid overlay.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct GridTile {
    /// Uppercased grid prefix of the requested precision (e.g. 4 → "EM12").
    pub tile: String,
    pub count: i64,
    pub confirmed: i64,
    /// Most recent QSO in the tile (unix seconds, UTC).
    pub last_qso: i64,
    /// Distinct raw callsigns worked in the tile, sorted ascending. Mirrors
    /// `GridSquareData.callsigns` (`GridOverlayDataActor` / `GridTrackerDetailView`).
    pub callsigns: Vec<String>,
    /// Distinct raw bands worked in the tile, sorted ascending.
    pub bands: Vec<String>,
    /// Distinct raw modes worked in the tile, sorted ascending.
    pub modes: Vec<String>,
}

/// Split a `GROUP_CONCAT(DISTINCT x)` result into a sorted, de-duplicated `Vec`.
/// `None` (no rows / all-NULL) → empty. Values never contain commas (callsigns,
/// bands, modes), so a plain comma split is safe.
fn split_distinct_concat(concat: Option<String>) -> Vec<String> {
    let Some(concat) = concat else {
        return Vec::new();
    };
    let mut out: Vec<String> = concat.split(',').map(str::to_string).collect();
    out.sort();
    out.dedup();
    out
}

/// WAS (Worked All States) rollup: the valid US states worked overall and per mode
/// family. Mirrors `POTAAwardsActor+WAS250` / `StatsComputationActor` WAS — a state
/// counts only when the normalized `state` field is one of the 50 states.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WasSummary {
    /// All valid states worked (sorted uppercased abbreviations).
    pub all_states: Vec<String>,
    /// Per mode-family state sets (family ∈ Phone/CW/Digital/Other), family-sorted;
    /// states within a family sorted ascending.
    pub per_mode: Vec<WasModeStates>,
}

/// The states worked on one mode family (a row of `WasSummary::per_mode`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WasModeStates {
    pub mode_family: String,
    pub states: Vec<String>,
}

/// America 250 WAS progress (all 50 states in 2026). Port of `WAS250Progress`.
/// The 2026 UTC window is intrinsic to the award (the Swift fetch hard-codes it),
/// so it is not driven by the `query` filter. State sets are sorted for
/// determinism; the pipeline counts mirror the Swift diagnostic fields.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Was250 {
    /// Valid states worked on any mode in 2026.
    pub states_worked: Vec<String>,
    pub cw_states: Vec<String>,
    pub phone_states: Vec<String>,
    pub digital_states: Vec<String>,
    /// Non-hidden 2026 QSOs that carry a `state` value (incl. metadata).
    pub total_qsos: i64,
    /// …of which are metadata pseudo-modes (excluded from the state sets).
    pub metadata_excluded: i64,
    /// Non-metadata 2026 QSOs with a `state` value.
    pub with_state_field: i64,
    /// …of which normalize to one of the 50 states.
    pub with_valid_state: i64,
}

/// One WAS drilldown row: for a (source × mode × state) the QSO count and the distinct
/// callsigns that contributed. Mirrors `StatsComputationActor`'s `wasData`
/// (`[WASFilterKey: WASStateData]`). `source` is `"all"` or `"qth"` (QSOs not at a park);
/// `mode` is `None` for the all-modes rollup or an uppercased raw mode. `callsigns` are
/// uppercased, distinct, and sorted — the consumer takes `Set(...).sorted()` anyway.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WasDrilldownRow {
    pub source: String,
    pub mode: Option<String>,
    pub state: String,
    pub count: i64,
    pub callsigns: Vec<String>,
}

/// One worked DXCC entity with its location and QSO count — backs DXCC needs and the
/// map entity rollup. Extends `qso_count_by(Dxcc)` with lat/lon from `cw-domain`'s
/// country table; unknown ids get a `"DXCC <id>"` name and `(0, 0)`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DxccWorked {
    pub dxcc_id: i64,
    pub name: String,
    pub latitude: f64,
    pub longitude: f64,
    pub count: i64,
    /// Distinct raw bands worked for this entity, sorted ascending (map/needs detail).
    pub bands: Vec<String>,
}

/// Per-service upload/confirmation counts (mirrors `AsyncServicePresenceCounts` /
/// `PresenceComputationActor.computeCounts`). Both counts are **unique QSOs** (dedup by
/// `qso_id`) over presence rows whose QSO is not hidden. `uploaded` counts QSOs with a
/// present row for the service; `pending` counts `needs_upload` QSOs restricted to the
/// configured services and (when set) the primary callsign. Unlike the other aggregates
/// this applies only the hidden filter — metadata pseudo-modes are NOT excluded, matching
/// the Swift actor.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ServicePresenceCount {
    /// `ServiceType` raw value (e.g. "qrz", "lotw", "pota").
    pub service: String,
    pub uploaded: i64,
    pub pending: i64,
}

/// One park's activity rollup (mirrors `MyParksView.computeMyParkEntries`). Keyed by a
/// single park reference (comma-separated `park`/`their_park` values are split first).
/// `activation_days` = distinct UTC days the park was activated; `hunt_qsos` = raw count
/// of QSOs hunting that park; `last_worked` = max QSO timestamp across both.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ParkRollup {
    pub park: String,
    pub activation_days: i64,
    pub hunt_qsos: i64,
    /// Most recent QSO touching this park (unix seconds, UTC).
    pub last_worked: i64,
}

/// One worked US state with its QSO count (mirrors the map's state rollup). `state` is a
/// normalized, valid (50-state) abbreviation; `count` is raw QSOs (not unique callsigns).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StateCount {
    pub state: String,
    pub count: i64,
}

/// One equipment item's session rollup (mirrors `EquipmentStatsActor`). Aggregates the
/// `logging_session` table (sessions with `qso_count > 0`); `kind` is the equipment
/// category ("radio"/"antenna"/"key"/"mic"), `name` the equipment string.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionEquipmentRollup {
    pub kind: String,
    pub name: String,
    pub session_count: i64,
    pub total_qsos: i64,
    /// Earliest / latest session start using this item (unix seconds, UTC).
    pub first_used: i64,
    pub last_used: i64,
}

/// One rig+antenna combo's session rollup (mirrors `EquipmentStatsActor` combos).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionComboRollup {
    pub rig: String,
    pub antenna: String,
    pub session_count: i64,
    pub total_qsos: i64,
}

/// One (name, count) tally row in a `SessionItemDetail` breakdown. `name` is the raw
/// band or mode string (empty for NULL/empty); rows are sorted count-desc then name-asc.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ItemTally {
    pub name: String,
    pub count: i64,
}

/// Per-equipment-item QSO breakdown (mirrors `EquipmentItemDetailActor.computeQSOStats`).
/// Covers the QSO-derived half of the item-detail screen: total QSOs, distinct DXCC
/// entities, distance extremes, and per-band / per-mode tallies over every QSO whose
/// logging session uses the named item (as rig / antenna / key / mic). The session list
/// and paired-equipment counts stay session-side. Distances use the `cw_grid_distance_km`
/// UDF and count only QSOs with two parseable grids and a positive distance, matching the
/// Swift `distanceKm > 0` guard.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionItemDetail {
    /// Non-metadata QSOs across the item's sessions.
    pub total_qsos: i64,
    /// Distinct `dxcc > 0` entities worked.
    pub unique_entities: i64,
    /// Greatest / least / mean great-circle distance (km) over QSOs with a positive,
    /// computable distance. `None` when no QSO qualifies.
    pub farthest_km: Option<f64>,
    pub shortest_km: Option<f64>,
    pub average_km: Option<f64>,
    /// Per-band QSO counts, count-desc then band-asc.
    pub band_breakdown: Vec<ItemTally>,
    /// Per-mode QSO counts, count-desc then mode-asc.
    pub mode_breakdown: Vec<ItemTally>,
}

/// The SQL-trivial subset of brag-sheet period metrics (mirrors
/// `BragSheetComputationActor`). Computed over visible QSOs matching `query` (the caller
/// encodes the period as a DSL date window). Distance / streak / per-session-window /
/// new-this-period / activation-grouping metrics are intentionally NOT included here —
/// they need per-row math and stay SwiftData-side (see the design doc's out-of-scope).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragPeriodMetrics {
    pub total_qsos: i64,
    pub cw_qsos: i64,
    pub phone_qsos: i64,
    pub digital_qsos: i64,
    /// Distinct UTC days with a QSO.
    pub operating_days: i64,
    /// Distinct lowercased bands.
    pub active_bands: i64,
    /// Distinct uppercased callsigns.
    pub unique_callsigns: i64,
    /// Distinct non-null DXCC entities.
    pub dxcc_entities: i64,
    pub qrp_qsos: i64,
    pub milliwatt_qsos: i64,
    /// Distinct non-null `their_park` references (raw, not split).
    pub parks_hunted: i64,
    /// QSOs with both `park` and `their_park` set (park-to-park).
    pub park_to_park: i64,
    /// QSOs with an RST received of "599" or "59".
    pub perfect_reports: i64,
}

/// A single furthest-contact record (mirrors the `.contact` brag stat). `band` is the raw
/// stored band (empty for NULL); `distance_km` is the great-circle distance to that station.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragContact {
    pub callsign: String,
    pub band: String,
    pub distance_km: f64,
}

/// Per-band furthest contact (a row of `BragDistanceStats::furthest_per_band`). `band` is the
/// lowercased band key (mirrors `computeFurthestPerBand`'s `band.lowercased()` grouping).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragBandRecord {
    pub band: String,
    pub callsign: String,
    pub distance_km: f64,
}

/// The lowest-power contact (mirrors the `.power` brag stat). `distance_km` is `None` when
/// that QSO's grids don't yield a distance.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragPowerContact {
    pub watts: i64,
    pub callsign: String,
    pub band: String,
    pub distance_km: Option<f64>,
}

/// The best watts-per-mile contact (mirrors the `.efficiency` brag stat). Selected by
/// minimizing `power / miles`; `distance_km` is always present (the candidate set requires a
/// positive distance). The Swift side formats the ratio + detail string.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragEfficiency {
    pub watts: i64,
    pub callsign: String,
    pub band: String,
    pub distance_km: f64,
}

/// The distance-shaped brag-sheet stats (mirrors `BragSheetComputationActor+Distance` /
/// `+Records`'s distance records). Computed over visible QSOs matching `query` (the caller
/// encodes the period as a DSL date window) using the `cw_grid_distance_km` UDF. Each
/// "furthest" is the max-distance contact within a filtered subset; `None` / empty when no
/// QSO qualifies. Distances are great-circle (haversine), matching the UDF.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragDistanceStats {
    /// Furthest contact overall (`computeFurthestContact`).
    pub furthest: Option<BragContact>,
    /// Furthest QRP (power ≤ 5) contact (`computeFurthestQRP`).
    pub furthest_qrp: Option<BragContact>,
    /// Furthest CW contact (`computeCWDistanceRecord`).
    pub furthest_cw: Option<BragContact>,
    /// Furthest CW + QRP contact (`computeCWQRPRecord`).
    pub furthest_cw_qrp: Option<BragContact>,
    /// Furthest contact with a perfect report (599/59) (`computeBestRSTAtDistance`).
    pub furthest_perfect_rst: Option<BragContact>,
    /// Per-band furthest contacts, distance-desc then band-asc (`computeFurthestPerBand`).
    pub furthest_per_band: Vec<BragBandRecord>,
    /// Mean distance over all computable-distance QSOs (`computeAverageDistance`).
    pub average_km: Option<f64>,
    /// Lowest-power (> 0 W) contact (`computeLowestPower`).
    pub lowest_power: Option<BragPowerContact>,
    /// Best watts-per-mile contact (`computeBestWattsPerMile`).
    pub best_watts_per_mile: Option<BragEfficiency>,
}

/// A current/longest streak pair in calendar days (mirrors the `.streak` brag stat).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StreakValue {
    pub current: i64,
    pub longest: i64,
}

/// A per-mode-family streak (a row of `BragStreaks::modes`). `mode` ∈ "CW"/"Phone"/"Digital".
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ModeStreak {
    pub mode: String,
    pub current: i64,
    pub longest: i64,
}

/// The streak-shaped brag-sheet stats (mirrors `BragSheetComputationActor+Records`'s streak
/// math). All day-bucketing is **UTC** — `computeCurrentStreak`/`computeBestStreak` used the
/// device-local calendar in Swift; this normalizes them to UTC for consistency with every
/// other brag day-stat (and so the aggregate is deterministic + DST-correct). `current`
/// counts only when the last active day is `today` or yesterday, hence the `today` parameter.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragStreaks {
    /// Consecutive UTC days with any visible QSO (`computeCurrentStreak`/`computeBestStreak`
    /// return the same pair).
    pub on_air: StreakValue,
    /// Consecutive UTC days with a successful (≥ 10 unique-QSO) park activation
    /// (`computeActivationStreak`). `None` when no day qualifies (the `.noData` case).
    pub activation: Option<StreakValue>,
    /// Per mode-family (CW/Phone/Digital, in that order) day streaks, families with ≥ 1 QSO
    /// only (`computeModeStreaks`).
    pub modes: Vec<ModeStreak>,
}

/// The geographic-reach brag-sheet stats (mirrors `BragSheetComputationActor`'s
/// `computeGeoStat` set). All counts are over visible QSOs matching `query` (the period),
/// except `new_dxcc_entities` which also consults the all-time log. `continents` /
/// `most_continents_day` of 0 map to the `.noData` case view-side; `continents` is shown as
/// `current/6` and `was_states` as `current/50`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragGeographic {
    /// Distinct non-null DXCC entities (`computeDXCCEntities`).
    pub dxcc_entities: i64,
    /// Period entities whose all-time-earliest QSO is within the period (`computeNewDXCC`).
    pub new_dxcc_entities: i64,
    /// Distinct valid 50-state abbreviations (`computeStatesProvinces`).
    pub states_provinces: i64,
    /// Distinct 4-char their-grid prefixes (`computeGridSquares`).
    pub grid_squares: i64,
    /// Distinct continents worked (`computeContinents`; shown `/6`).
    pub continents: i64,
    /// Max distinct continents in a single UTC day (`computeMostContinentsDay`).
    pub most_continents_day: i64,
    /// Distinct valid states worked on USA (dxcc 291) (`computeWASProgress`; shown `/50`).
    pub was_states: i64,
}

/// One park activation extreme: the (park, UTC-day) group with the most raw QSOs. Mirrors
/// `BragSheetComputationActor.computeBestActivation`'s `.parkDetail` result. `day` is a
/// `YYYY-MM-DD` UTC calendar day; the routing layer maps it back to a `Date`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragBestActivation {
    pub park: String,
    pub day: String,
    pub count: i64,
}

/// The POTA-category brag-sheet stats (mirrors `BragSheetComputationActor+POTA`). All counts are
/// over visible QSOs matching `query` (the period), except `new_parks` which also consults the
/// all-time log. `best_activation` is `None` when there are no parked QSOs.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragPota {
    /// Distinct parks activated: (park, UTC-day) groups with >= 10 unique QSOs → count of distinct
    /// parks among them (`computeParksActivated`). Unique key = `UPPER(call)|band|mode|UPPER(park)`.
    pub parks_activated: i64,
    /// Distinct non-empty raw `their_park` references hunted (`computeParksHunted`).
    pub parks_hunted: i64,
    /// QSOs with both a non-empty `park` and `their_park` (`computeP2P`).
    pub park_to_park: i64,
    /// The (park, UTC-day) activation group with the most raw QSOs (`computeBestActivation`).
    pub best_activation: Option<BragBestActivation>,
    /// Parks (activated ∪ hunted) in the period whose all-time-earliest contact (on either column)
    /// is at/after the period's earliest QSO (`computeNewParks`).
    pub new_parks: i64,
}

/// The SQL-expressible volume / records / "fun" brag-sheet stats (the day-grouped, busiest,
/// and time-of-day stats from `computeVolumeStat` / `computeFunStat` / misc totals). The
/// `*_day` / `most_qsos_session` / `active_modes` counts are 0 when there are no QSOs (→
/// `.noData` view-side for the records); the `Option` "best" fields are `None` then. Excludes
/// the session-sequence stats (operating hours / rates / longest session) and the club stats.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragRecords {
    /// Most QSOs in a single UTC day (`computeMostQSOsDay`).
    pub most_qsos_day: i64,
    /// Most QSOs in a single session (`computeMostQSOsSession`; session = logging session or
    /// the QSO id when unsessioned).
    pub most_qsos_session: i64,
    /// Most distinct DXCC entities in a UTC day (`computeMostCountriesDay`).
    pub most_countries_day: i64,
    /// Most distinct bands in a UTC day (`computeMostBandsDay`).
    pub most_bands_day: i64,
    /// Weekday (Sun…Sat) with the most QSOs + that count (`computeMostActiveDay`).
    pub most_active_weekday: Option<ItemTally>,
    /// Most-worked band (lowercased) + count (`computeBusiestBand`).
    pub busiest_band: Option<ItemTally>,
    /// Most-worked canonical mode + count (`computeBusiestMode`).
    pub busiest_mode: Option<ItemTally>,
    /// Most-worked callsign (count > 1) + count (`computeRepeatCustomers`).
    pub repeat_customer: Option<ItemTally>,
    /// Timestamp of the QSO closest to UTC midnight (`computeEarliestQSO`).
    pub earliest_qso: Option<i64>,
    /// Timestamp of the QSO furthest into the UTC day (`computeLatestQSO`).
    pub latest_qso: Option<i64>,
    /// Summed great-circle distance over computable-distance QSOs (`computeTotalDistance`;
    /// `None` when ≤ 0).
    pub total_distance_km: Option<f64>,
    /// Distinct canonical modes (`computeActiveModes`).
    pub active_modes: i64,
}

/// The session-/sequence-based brag-sheet stats (`BragSheetComputationActor`'s speed-and-rate,
/// operating-hours, longest-session, and largest-Nfer stats). Unlike the other aggregates these
/// require per-QSO timestamps grouped by session / sorted in time, so the store fetches the
/// minimal columns (session key, timestamp, park, UTC day) for the period once and folds them
/// in Rust — O(period rows), mirroring the actor's snapshot scan. Durations are in seconds.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BragSessionStats {
    /// Total active operating time (`computeOperatingHours`): per session, summed inter-QSO
    /// gaps ≤ 15 min, floored at 60 s; `None` over no QSOs.
    pub operating_seconds: Option<f64>,
    /// Shortest time to log 10 consecutive QSOs in a session (`computeFastest10`).
    pub fastest_ten_seconds: Option<f64>,
    /// Best QSOs/hour over a session with ≥ 10 QSOs (`computeBestSessionRate`).
    pub best_session_rate: Option<f64>,
    /// Shortest time from the 1st to 10th QSO of an activation (`computeFastestActivation`).
    pub fastest_activation_seconds: Option<f64>,
    /// Longest single session span, first→last QSO (`computeLongestSession`).
    pub longest_session_seconds: Option<f64>,
    /// Most QSOs within any 15-minute window (`computePeak15MinRate`).
    pub peak_15_min_count: i64,
    /// Most distinct parks activated in a single session (`computeLargestNfer`); 0 / 1 → the
    /// `.noData` case view-side.
    pub largest_nfer: i64,
}

impl Store {
    /// Headline distinct counts over visible QSOs matching `query`.
    pub fn qso_distinct_counts(&self, query: &ParsedQuery) -> Result<DistinctCounts> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT COUNT(*), \
             COUNT(DISTINCT CASE WHEN band IS NOT NULL AND band <> '' THEN band END), \
             COUNT(DISTINCT CASE WHEN their_grid IS NOT NULL AND their_grid <> '' THEN their_grid END), \
             COUNT(DISTINCT CASE WHEN dxcc IS NOT NULL AND dxcc > 0 THEN dxcc END), \
             COUNT(DISTINCT CASE WHEN park IS NOT NULL AND park <> '' THEN park END), \
             COALESCE(SUM(CASE WHEN qrz_confirmed = 1 OR lotw_confirmed = 1 THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN qrz_confirmed = 1 THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN lotw_confirmed = 1 THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN their_grid IS NOT NULL AND their_grid <> '' THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN park IS NOT NULL AND park <> '' THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN dxcc IS NOT NULL AND dxcc > 0 THEN 1 ELSE 0 END), 0), \
             COUNT(DISTINCT callsign) \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql})"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let counts = self.conn.query_row(&sql, refs.as_slice(), |row| {
            Ok(DistinctCounts {
                qsos: row.get(0)?,
                bands: row.get(1)?,
                grids: row.get(2)?,
                entities: row.get(3)?,
                parks: row.get(4)?,
                confirmed: row.get(5)?,
                qrz_confirmed: row.get(6)?,
                lotw_confirmed: row.get(7)?,
                with_grid: row.get(8)?,
                with_park: row.get(9)?,
                with_dxcc: row.get(10)?,
                unique_callsigns: row.get(11)?,
            })
        })?;
        Ok(counts)
    }

    /// QSO counts grouped by a dimension, over visible QSOs matching `query`.
    /// Ordered most-frequent first (months chronological). Bounded by the group
    /// cardinality (bands/families/entities/months are small), never by QSO count.
    pub fn qso_count_by(
        &self,
        query: &ParsedQuery,
        dimension: AggregateDimension,
    ) -> Result<Vec<DimensionCount>> {
        match dimension {
            AggregateDimension::Band => {
                let rows = self.grouped_counts(
                    "band",
                    " AND band IS NOT NULL AND band <> ''",
                    "ORDER BY COUNT(*) DESC, k ASC",
                    query,
                )?;
                Ok(rows
                    .into_iter()
                    .map(|(key, count, calls)| DimensionCount {
                        label: key.clone(),
                        key,
                        count,
                        distinct_calls: calls,
                    })
                    .collect())
            }
            AggregateDimension::ModeFamily => {
                let rows = self.grouped_counts(
                    "cw_mode_family(mode)",
                    "",
                    "ORDER BY COUNT(*) DESC, k ASC",
                    query,
                )?;
                Ok(rows
                    .into_iter()
                    .map(|(key, count, calls)| DimensionCount {
                        label: key.clone(),
                        key,
                        count,
                        distinct_calls: calls,
                    })
                    .collect())
            }
            AggregateDimension::Month => {
                let rows = self.grouped_counts(
                    "strftime('%Y-%m', qso_date, 'unixepoch')",
                    "",
                    "ORDER BY k ASC",
                    query,
                )?;
                Ok(rows
                    .into_iter()
                    .map(|(key, count, calls)| DimensionCount {
                        label: key.clone(),
                        key,
                        count,
                        distinct_calls: calls,
                    })
                    .collect())
            }
            AggregateDimension::Dxcc => {
                let rows = self.grouped_counts(
                    "CAST(dxcc AS TEXT)",
                    " AND dxcc IS NOT NULL AND dxcc > 0",
                    "ORDER BY COUNT(*) DESC, k ASC",
                    query,
                )?;
                Ok(rows
                    .into_iter()
                    .map(|(key, count, calls)| {
                        let label = key
                            .parse::<u32>()
                            .ok()
                            .and_then(dxcc_name)
                            .map(str::to_string)
                            .unwrap_or_else(|| format!("DXCC {key}"));
                        DimensionCount {
                            key,
                            label,
                            count,
                            distinct_calls: calls,
                        }
                    })
                    .collect())
            }
        }
    }

    /// POTA activation rollup over visible, parked QSOs matching `query`. Groups by
    /// `(UPPER(park), UPPER(my_callsign), UTC-day)` and, per group, counts total QSOs
    /// and unique QSOs (deduped by `UPPER(callsign)|band|mode`). `successful` marks
    /// groups with at least `min_qsos` unique QSOs.
    ///
    /// The grouped result is capped at [`MAX_FETCH_LIMIT`] rows. `ORDER BY day DESC`
    /// puts the newest activations first, so the cap keeps the most recent ones — the
    /// browser only ever renders a bounded page and the group scan (backed by
    /// `idx_qso_park`) stays cheap even on very large logbooks.
    pub fn qso_activation_rollup(
        &self,
        query: &ParsedQuery,
        min_qsos: i64,
    ) -> Result<Vec<ActivationRollup>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT UPPER(park) AS park_key, \
                    UPPER(COALESCE(my_callsign, '')) AS op_key, \
                    strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day, \
                    COUNT(DISTINCT UPPER(callsign) || '|' || COALESCE(band, '') || '|' || COALESCE(mode, '')), \
                    COUNT(*) \
             FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
             GROUP BY park_key, op_key, day \
             ORDER BY day DESC, park_key ASC, op_key ASC \
             LIMIT {MAX_FETCH_LIMIT}"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            let unique_qsos: i64 = row.get(3)?;
            Ok(ActivationRollup {
                park: row.get(0)?,
                operator_callsign: row.get(1)?,
                utc_date: row.get(2)?,
                unique_qsos,
                total_qsos: row.get(4)?,
                successful: unique_qsos >= min_qsos,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Worked grid tiles at `precision` (e.g. 4) over visible QSOs matching `query`:
    /// per tile, QSO count, confirmed count, and the most recent QSO timestamp.
    /// Bounded by tile cardinality. Grids shorter than `precision` are skipped.
    pub fn qso_grid_tiles(&self, query: &ParsedQuery, precision: i64) -> Result<Vec<GridTile>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT UPPER(SUBSTR(their_grid, 1, ?)) AS tile, COUNT(*), \
             COALESCE(SUM(CASE WHEN qrz_confirmed = 1 OR lotw_confirmed = 1 THEN 1 ELSE 0 END), 0), \
             MAX(qso_date), \
             GROUP_CONCAT(DISTINCT callsign), GROUP_CONCAT(DISTINCT band), GROUP_CONCAT(DISTINCT mode) \
             FROM qso WHERE {VISIBLE_QSO} \
             AND their_grid IS NOT NULL AND LENGTH(their_grid) >= ? AND ({where_sql}) \
             GROUP BY tile ORDER BY COUNT(*) DESC, tile ASC"
        );
        // Bind order matches the SQL placeholders: SUBSTR length, the LENGTH guard,
        // then the compiled WHERE values.
        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
            vec![Box::new(precision), Box::new(precision)];
        bound.extend(values.iter().map(|v| v.to_sql_param()));
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(GridTile {
                tile: row.get(0)?,
                count: row.get(1)?,
                confirmed: row.get(2)?,
                last_qso: row.get(3)?,
                // GROUP_CONCAT(DISTINCT …) yields a comma-joined string in arbitrary
                // order; split + sort for a deterministic Vec matching the Swift Set.
                callsigns: split_distinct_concat(row.get::<_, Option<String>>(4)?),
                bands: split_distinct_concat(row.get::<_, Option<String>>(5)?),
                modes: split_distinct_concat(row.get::<_, Option<String>>(6)?),
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// WAS rollup over visible QSOs matching `query`: the valid US states worked
    /// overall and per mode family. A state qualifies only when the normalized
    /// `state` field (`NORMALIZED_STATE`) is one of the 50 states. Bounded by
    /// (family × state) cardinality, never by QSO count.
    pub fn was_summary(&self, query: &ParsedQuery) -> Result<WasSummary> {
        let (where_sql, values) = compile_where(query);
        let valid_list = VALID_US_STATES
            .iter()
            .map(|state| format!("'{state}'"))
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "SELECT cw_mode_family(mode) AS fam, {NORMALIZED_STATE} AS st \
             FROM qso WHERE {VISIBLE_QSO} AND state IS NOT NULL \
             AND {NORMALIZED_STATE} IN ({valid_list}) AND ({where_sql}) \
             GROUP BY fam, st ORDER BY fam ASC, st ASC"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            let fam: String = row.get(0)?;
            let st: String = row.get(1)?;
            Ok((fam, st))
        })?;
        // Rows arrive grouped by family then state ascending, so each family's Vec
        // is already sorted; `all` dedupes across families via the BTreeSet.
        let mut per_mode_map: std::collections::BTreeMap<String, Vec<String>> =
            std::collections::BTreeMap::new();
        let mut all: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
        for row in rows {
            let (fam, st) = row?;
            all.insert(st.clone());
            per_mode_map.entry(fam).or_default().push(st);
        }
        let per_mode = per_mode_map
            .into_iter()
            .map(|(mode_family, states)| WasModeStates { mode_family, states })
            .collect();
        Ok(WasSummary { all_states: all.into_iter().collect(), per_mode })
    }

    /// America 250 WAS progress over non-hidden 2026 QSOs that carry a `state`,
    /// matching `query` (the app passes an empty filter). Faithful port of
    /// `POTAAwardsActor.computeWAS250` + `WAS250Computation`: metadata pseudo-modes
    /// are counted in the raw totals but excluded from the state sets; states are
    /// normalized then validated against the 50 states, and bucketed by mode family.
    pub fn was250(&self, query: &ParsedQuery) -> Result<Was250> {
        let (where_sql, values) = compile_where(query);
        let valid_list = VALID_US_STATES
            .iter()
            .map(|state| format!("'{state}'"))
            .collect::<Vec<_>>()
            .join(", ");

        // Pipeline counts over the full 2026 / state-present / non-hidden set.
        let counts_sql = format!(
            "SELECT COUNT(*), \
             COALESCE(SUM(CASE WHEN {METADATA_MODE} THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN NOT {METADATA_MODE} THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN NOT {METADATA_MODE} AND {NORMALIZED_STATE} IN ({valid_list}) \
               THEN 1 ELSE 0 END), 0) \
             FROM qso \
             WHERE is_hidden = 0 AND state IS NOT NULL \
             AND qso_date >= ? AND qso_date < ? AND ({where_sql})"
        );
        let (total, metadata, with_state, with_valid) = {
            let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
                vec![Box::new(WAS250_START), Box::new(WAS250_END)];
            bound.extend(values.iter().map(|v| v.to_sql_param()));
            let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
            self.conn.query_row(&counts_sql, refs.as_slice(), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            })?
        };

        // Per-family valid states over non-metadata 2026 QSOs.
        let states_sql = format!(
            "SELECT cw_mode_family(mode) AS fam, {NORMALIZED_STATE} AS st \
             FROM qso \
             WHERE is_hidden = 0 AND state IS NOT NULL AND NOT {METADATA_MODE} \
             AND qso_date >= ? AND qso_date < ? \
             AND {NORMALIZED_STATE} IN ({valid_list}) AND ({where_sql}) \
             GROUP BY fam, st ORDER BY fam ASC, st ASC"
        );
        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
            vec![Box::new(WAS250_START), Box::new(WAS250_END)];
        bound.extend(values.iter().map(|v| v.to_sql_param()));
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&states_sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        let mut all: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
        let mut cw: Vec<String> = Vec::new();
        let mut phone: Vec<String> = Vec::new();
        let mut digital: Vec<String> = Vec::new();
        for row in rows {
            let (fam, st) = row?;
            all.insert(st.clone());
            // Rows arrive family-then-state ascending, so each bucket stays sorted.
            match fam.as_str() {
                "CW" => cw.push(st),
                "Phone" => phone.push(st),
                "Digital" => digital.push(st),
                _ => {} // Other → counts toward all_states only (matches Swift switch)
            }
        }
        Ok(Was250 {
            states_worked: all.into_iter().collect(),
            cw_states: cw,
            phone_states: phone,
            digital_states: digital,
            total_qsos: total,
            metadata_excluded: metadata,
            with_state_field: with_state,
            with_valid_state: with_valid,
        })
    }

    /// WAS drilldown over visible QSOs matching `query`: per (source × mode × state),
    /// the QSO count and distinct callsigns. Faithful port of
    /// `StatsComputationActor`'s `wasData` accumulation — `source` is `all` (every QSO)
    /// or `qth` (QSOs not at a park); `mode` is `None` for the all-modes rollup or an
    /// uppercased raw mode. Only valid 50-state QSOs count. Bounded by
    /// (source × mode × state) cardinality, never by QSO count.
    pub fn was_drilldown(&self, query: &ParsedQuery) -> Result<Vec<WasDrilldownRow>> {
        use std::collections::{BTreeMap, BTreeSet};

        let (where_sql, values) = compile_where(query);
        let valid_list = VALID_US_STATES
            .iter()
            .map(|state| format!("'{state}'"))
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "SELECT CASE WHEN park IS NULL OR park = '' THEN 1 ELSE 0 END AS is_qth, \
                    UPPER(COALESCE(mode, '')) AS mode_key, \
                    {NORMALIZED_STATE} AS st, \
                    COUNT(*), \
                    GROUP_CONCAT(DISTINCT UPPER(callsign)) \
             FROM qso WHERE {VISIBLE_QSO} AND state IS NOT NULL \
             AND {NORMALIZED_STATE} IN ({valid_list}) AND ({where_sql}) \
             GROUP BY is_qth, mode_key, st"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
                split_distinct_concat(row.get::<_, Option<String>>(4)?),
            ))
        })?;

        // Key: (source, mode, state) → (count, distinct callsigns). BTreeMap/Set give a
        // deterministic, sorted result; the rollups (all modes / all sources) accumulate
        // by inserting each base group into multiple keys.
        type Acc = BTreeMap<(String, Option<String>, String), (i64, BTreeSet<String>)>;
        fn bump(acc: &mut Acc, source: &str, mode: Option<&str>, state: &str, cnt: i64, calls: &[String]) {
            let entry = acc
                .entry((source.to_string(), mode.map(str::to_string), state.to_string()))
                .or_insert((0, BTreeSet::new()));
            entry.0 += cnt;
            entry.1.extend(calls.iter().cloned());
        }

        let mut acc: Acc = BTreeMap::new();
        for row in rows {
            let (is_qth, mode_key, state, cnt, calls) = row?;
            bump(&mut acc, "all", None, &state, cnt, &calls);
            bump(&mut acc, "all", Some(&mode_key), &state, cnt, &calls);
            if is_qth == 1 {
                bump(&mut acc, "qth", None, &state, cnt, &calls);
                bump(&mut acc, "qth", Some(&mode_key), &state, cnt, &calls);
            }
        }

        Ok(acc
            .into_iter()
            .map(|((source, mode, state), (count, calls))| WasDrilldownRow {
                source,
                mode,
                state,
                count,
                callsigns: calls.into_iter().collect(),
            })
            .collect())
    }

    /// Worked DXCC entities over visible QSOs matching `query`: per entity, the QSO
    /// count plus name/lat/lon from `cw-domain`. Ordered most-frequent first. Bounded
    /// by entity cardinality.
    pub fn dxcc_worked(&self, query: &ParsedQuery) -> Result<Vec<DxccWorked>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT dxcc, COUNT(*), GROUP_CONCAT(DISTINCT band) FROM qso \
             WHERE {VISIBLE_QSO} AND dxcc IS NOT NULL AND dxcc > 0 AND ({where_sql}) \
             GROUP BY dxcc ORDER BY COUNT(*) DESC, dxcc ASC"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            let dxcc_id: i64 = row.get(0)?;
            let count: i64 = row.get(1)?;
            let bands = split_distinct_concat(row.get::<_, Option<String>>(2)?);
            Ok((dxcc_id, count, bands))
        })?;
        let mut out = Vec::new();
        for row in rows {
            let (dxcc_id, count, bands) = row?;
            let country = u32::try_from(dxcc_id).ok().and_then(dxcc_country);
            let (name, latitude, longitude) = match country {
                Some(entity) => (entity.name.to_string(), entity.latitude, entity.longitude),
                None => (format!("DXCC {dxcc_id}"), 0.0, 0.0),
            };
            out.push(DxccWorked { dxcc_id, name, latitude, longitude, count, bands });
        }
        Ok(out)
    }

    /// Per-service uploaded/pending unique-QSO counts over presence rows whose QSO is
    /// not hidden and matches `query`. `uploaded` = distinct QSOs with a present row;
    /// `pending` = distinct QSOs with a `needs_upload` row for a configured service,
    /// restricted (when `primary_callsign` is `Some`) to QSOs whose `my_callsign` is
    /// empty or equals it (case-insensitive). Bounded by service cardinality.
    pub fn service_presence_counts(
        &self,
        query: &ParsedQuery,
        primary_callsign: Option<&str>,
        configured_services: &[String],
    ) -> Result<Vec<ServicePresenceCount>> {
        let (where_sql, values) = compile_where(query);
        // `IN ()` is invalid; with no configured services nothing is pending.
        let configured_clause = if configured_services.is_empty() {
            "0".to_string()
        } else {
            let placeholders = vec!["?"; configured_services.len()].join(", ");
            format!("sp.service_type_raw_value IN ({placeholders})")
        };
        let callsign_clause = if primary_callsign.is_some() {
            "(q.my_callsign IS NULL OR q.my_callsign = '' OR UPPER(q.my_callsign) = UPPER(?))"
        } else {
            "1"
        };
        let sql = format!(
            "SELECT sp.service_type_raw_value AS service, \
             COUNT(DISTINCT CASE WHEN sp.is_present = 1 THEN sp.qso_id END) AS uploaded, \
             COUNT(DISTINCT CASE WHEN sp.needs_upload = 1 AND {configured_clause} AND {callsign_clause} \
               THEN sp.qso_id END) AS pending \
             FROM service_presence sp JOIN qso q ON q.id = sp.qso_id \
             WHERE q.is_hidden = 0 AND ({where_sql}) \
             GROUP BY sp.service_type_raw_value ORDER BY service ASC"
        );
        // Bind order = textual placeholder order: the configured `IN (...)` list, the
        // primary callsign, then the compiled WHERE values.
        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> = Vec::new();
        for service in configured_services {
            bound.push(Box::new(service.clone()));
        }
        if let Some(primary) = primary_callsign {
            bound.push(Box::new(primary.to_string()));
        }
        bound.extend(values.iter().map(|v| v.to_sql_param()));
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(ServicePresenceCount {
                service: row.get(0)?,
                uploaded: row.get(1)?,
                pending: row.get(2)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Per-park activity rollup over visible QSOs matching `query`. Activations group by
    /// `(raw park, UTC day)`; hunts group by `(raw their_park)`. Comma-separated park
    /// lists are split per side and merged: a park's `activation_days` is the union of
    /// distinct UTC days, `hunt_qsos` the summed raw counts, `last_worked` the max across
    /// both. Mirrors `MyParksView.computeMyParkEntries` and retires its unbounded scan.
    pub fn qso_park_rollup(&self, query: &ParsedQuery) -> Result<Vec<ParkRollup>> {
        let (where_sql, values) = compile_where(query);

        // Accumulate per final (split) park reference.
        struct Acc {
            days: std::collections::BTreeSet<String>,
            hunts: i64,
            last: i64,
        }
        fn touch<'a>(
            parks: &'a mut std::collections::BTreeMap<String, Acc>,
            key: &str,
        ) -> &'a mut Acc {
            parks
                .entry(key.to_string())
                .or_insert_with(|| Acc { days: std::collections::BTreeSet::new(), hunts: 0, last: i64::MIN })
        }
        let mut parks: std::collections::BTreeMap<String, Acc> = std::collections::BTreeMap::new();

        // Activations: (raw park, day) groups with the group's max timestamp.
        let act_sql = format!(
            "SELECT park, strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day, MAX(qso_date) \
             FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
             GROUP BY park, day"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        {
            let mut stmt = self.conn.prepare(&act_sql)?;
            let rows = stmt.query_map(refs.as_slice(), |row| {
                let raw: String = row.get(0)?;
                let day: String = row.get(1)?;
                let last: i64 = row.get(2)?;
                Ok((raw, day, last))
            })?;
            for row in rows {
                let (raw, day, last) = row?;
                for park in split_refs(&raw) {
                    let acc = touch(&mut parks, &park);
                    acc.days.insert(day.clone());
                    acc.last = acc.last.max(last);
                }
            }
        }

        // Hunts: (raw their_park) groups with raw count + max timestamp.
        let hunt_sql = format!(
            "SELECT their_park, COUNT(*), MAX(qso_date) \
             FROM qso WHERE {VISIBLE_QSO} AND their_park IS NOT NULL AND their_park <> '' AND ({where_sql}) \
             GROUP BY their_park"
        );
        {
            let mut stmt = self.conn.prepare(&hunt_sql)?;
            let rows = stmt.query_map(refs.as_slice(), |row| {
                let raw: String = row.get(0)?;
                let count: i64 = row.get(1)?;
                let last: i64 = row.get(2)?;
                Ok((raw, count, last))
            })?;
            for row in rows {
                let (raw, count, last) = row?;
                for park in split_refs(&raw) {
                    let acc = touch(&mut parks, &park);
                    acc.hunts += count;
                    acc.last = acc.last.max(last);
                }
            }
        }

        Ok(parks
            .into_iter()
            .map(|(park, acc)| ParkRollup {
                park,
                activation_days: acc.days.len() as i64,
                hunt_qsos: acc.hunts,
                last_worked: acc.last,
            })
            .collect())
    }

    /// Per-state QSO counts over visible QSOs matching `query`. A state qualifies only
    /// when the normalized `state` field is one of the 50 states; `count` is raw QSOs.
    /// Ordered most-frequent first. Mirrors the map's state rollup (unique-states count =
    /// row count). Bounded by state cardinality.
    pub fn qso_state_counts(&self, query: &ParsedQuery) -> Result<Vec<StateCount>> {
        let (where_sql, values) = compile_where(query);
        let valid_list = VALID_US_STATES
            .iter()
            .map(|state| format!("'{state}'"))
            .collect::<Vec<_>>()
            .join(", ");
        let sql = format!(
            "SELECT {NORMALIZED_STATE} AS st, COUNT(*) \
             FROM qso WHERE {VISIBLE_QSO} AND state IS NOT NULL \
             AND {NORMALIZED_STATE} IN ({valid_list}) AND ({where_sql}) \
             GROUP BY st ORDER BY COUNT(*) DESC, st ASC"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(StateCount { state: row.get(0)?, count: row.get(1)? })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Equipment rollup over the `logging_session` table (sessions with `qso_count > 0`):
    /// per (kind, name), the session count, total QSOs, and first/last use. Mirrors
    /// `EquipmentStatsActor` (top rigs/antennas/keys/mics; magnet/dust/top-N are
    /// view-side selections over this). No DSL filter — sessions are not QSO-queryable.
    pub fn session_equipment_rollup(&self) -> Result<Vec<SessionEquipmentRollup>> {
        let sql = "SELECT kind, name, COUNT(*), SUM(qc), MIN(st), MAX(st) FROM ( \
             SELECT 'radio' AS kind, my_rig AS name, qso_count AS qc, started_at AS st \
               FROM logging_session WHERE qso_count > 0 AND my_rig IS NOT NULL AND my_rig <> '' \
             UNION ALL \
             SELECT 'antenna', my_antenna, qso_count, started_at \
               FROM logging_session WHERE qso_count > 0 AND my_antenna IS NOT NULL AND my_antenna <> '' \
             UNION ALL \
             SELECT 'key', my_key, qso_count, started_at \
               FROM logging_session WHERE qso_count > 0 AND my_key IS NOT NULL AND my_key <> '' \
             UNION ALL \
             SELECT 'mic', my_mic, qso_count, started_at \
               FROM logging_session WHERE qso_count > 0 AND my_mic IS NOT NULL AND my_mic <> '' \
             ) GROUP BY kind, name ORDER BY COUNT(*) DESC, kind ASC, name ASC";
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| {
            Ok(SessionEquipmentRollup {
                kind: row.get(0)?,
                name: row.get(1)?,
                session_count: row.get(2)?,
                total_qsos: row.get(3)?,
                first_used: row.get(4)?,
                last_used: row.get(5)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Rig+antenna combo rollup over `logging_session` (both non-empty, `qso_count > 0`):
    /// per combo, session count + total QSOs. Mirrors `EquipmentStatsActor` combos.
    pub fn session_combo_rollup(&self) -> Result<Vec<SessionComboRollup>> {
        let sql = "SELECT my_rig, my_antenna, COUNT(*), SUM(qso_count) FROM logging_session \
             WHERE qso_count > 0 AND my_rig IS NOT NULL AND my_rig <> '' \
             AND my_antenna IS NOT NULL AND my_antenna <> '' \
             GROUP BY my_rig, my_antenna ORDER BY COUNT(*) DESC, my_rig ASC, my_antenna ASC";
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map([], |row| {
            Ok(SessionComboRollup {
                rig: row.get(0)?,
                antenna: row.get(1)?,
                session_count: row.get(2)?,
                total_qsos: row.get(3)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Per-equipment-item QSO breakdown for the item named `name` (faithful port of
    /// `EquipmentItemDetailActor.computeQSOStats`). Aggregates over every non-metadata QSO
    /// whose logging session (with `qso_count > 0`) uses `name` as rig / antenna / key /
    /// mic. Bounded by band/mode cardinality, never by QSO count. Distances come from the
    /// `cw_grid_distance_km` UDF and count only positive, computable distances (the Swift
    /// `distanceKm > 0` guard); `farthest`/`shortest`/`average` are `None` when none qualify.
    pub fn session_item_detail(&self, name: &str) -> Result<SessionItemDetail> {
        // Totals + distinct entities + distance extremes in one single-row query. The
        // inner select projects each matching QSO's dxcc and great-circle distance; the
        // outer aggregates ignore NULL distances (invalid grids) and the `> 0` filter
        // drops same-grid (0 km) contacts, matching the Swift guard.
        let totals_sql = format!(
            "SELECT COUNT(*), \
             COUNT(DISTINCT CASE WHEN dxcc IS NOT NULL AND dxcc > 0 THEN dxcc END), \
             MIN(CASE WHEN dist > 0 THEN dist END), \
             MAX(CASE WHEN dist > 0 THEN dist END), \
             AVG(CASE WHEN dist > 0 THEN dist END) \
             FROM (SELECT q.dxcc AS dxcc, cw_grid_distance_km(q.my_grid, q.their_grid) AS dist \
                   {SESSION_ITEM_FROM_MATCH})"
        );
        let (total_qsos, unique_entities, shortest_km, farthest_km, average_km) = {
            let bound = bind_name_four(name);
            let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
            self.conn.query_row(&totals_sql, refs.as_slice(), |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, Option<f64>>(2)?,
                    row.get::<_, Option<f64>>(3)?,
                    row.get::<_, Option<f64>>(4)?,
                ))
            })?
        };

        let band_breakdown = self.session_item_tally("q.band", name)?;
        let mode_breakdown = self.session_item_tally("q.mode", name)?;

        Ok(SessionItemDetail {
            total_qsos,
            unique_entities,
            farthest_km,
            shortest_km,
            average_km,
            band_breakdown,
            mode_breakdown,
        })
    }

    /// One `session_item_detail` breakdown over `col` (`q.band` or `q.mode`): raw value →
    /// QSO count, count-desc then value-asc. NULL/empty values fold into the `""` bucket
    /// (the Swift `qso.band` / `qso.mode` are non-optional strings, possibly empty).
    fn session_item_tally(&self, col: &str, name: &str) -> Result<Vec<ItemTally>> {
        let sql = format!(
            "SELECT COALESCE({col}, '') AS k, COUNT(*) {SESSION_ITEM_FROM_MATCH} \
             GROUP BY k ORDER BY COUNT(*) DESC, k ASC"
        );
        let bound = bind_name_four(name);
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(ItemTally { name: row.get(0)?, count: row.get(1)? })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// SQL-trivial brag-sheet period metrics over visible QSOs matching `query` (the
    /// caller encodes the period as a DSL date window). One row of conditional
    /// aggregates; see `BragPeriodMetrics` for the included subset and what is deferred.
    pub fn brag_period_metrics(&self, query: &ParsedQuery) -> Result<BragPeriodMetrics> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT COUNT(*), \
             COALESCE(SUM(CASE WHEN cw_mode_family(mode) = 'CW' THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN cw_mode_family(mode) = 'Phone' THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN cw_mode_family(mode) = 'Digital' THEN 1 ELSE 0 END), 0), \
             COUNT(DISTINCT strftime('%Y-%m-%d', qso_date, 'unixepoch')), \
             COUNT(DISTINCT cw_lower(COALESCE(band, ''))), \
             COUNT(DISTINCT UPPER(callsign)), \
             COUNT(DISTINCT CASE WHEN dxcc IS NOT NULL THEN dxcc END), \
             COALESCE(SUM(CASE WHEN power IS NOT NULL AND power <= 5 THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN power IS NOT NULL AND power < 1 THEN 1 ELSE 0 END), 0), \
             COUNT(DISTINCT CASE WHEN their_park IS NOT NULL THEN their_park END), \
             COALESCE(SUM(CASE WHEN park IS NOT NULL AND park <> '' \
               AND their_park IS NOT NULL AND their_park <> '' THEN 1 ELSE 0 END), 0), \
             COALESCE(SUM(CASE WHEN rst_rcvd IN ('599', '59') THEN 1 ELSE 0 END), 0) \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql})"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let metrics = self.conn.query_row(&sql, refs.as_slice(), |row| {
            Ok(BragPeriodMetrics {
                total_qsos: row.get(0)?,
                cw_qsos: row.get(1)?,
                phone_qsos: row.get(2)?,
                digital_qsos: row.get(3)?,
                operating_days: row.get(4)?,
                active_bands: row.get(5)?,
                unique_callsigns: row.get(6)?,
                dxcc_entities: row.get(7)?,
                qrp_qsos: row.get(8)?,
                milliwatt_qsos: row.get(9)?,
                parks_hunted: row.get(10)?,
                park_to_park: row.get(11)?,
                perfect_reports: row.get(12)?,
            })
        })?;
        Ok(metrics)
    }

    /// The distance-shaped brag-sheet stats over visible QSOs matching `query`. Faithful
    /// port of `BragSheetComputationActor`'s distance/records math: each "furthest" is the
    /// max-distance contact within a filtered subset, plus per-band, average, lowest-power,
    /// and best-watts-per-mile. Every query is bounded (LIMIT 1 / band cardinality / a single
    /// AVG row), never by QSO count, via the `cw_grid_distance_km` UDF.
    pub fn brag_distance_stats(&self, query: &ParsedQuery) -> Result<BragDistanceStats> {
        Ok(BragDistanceStats {
            furthest: self.brag_furthest(query, "")?,
            furthest_qrp: self.brag_furthest(query, " AND power IS NOT NULL AND power <= 5")?,
            furthest_cw: self.brag_furthest(query, " AND cw_mode_family(mode) = 'CW'")?,
            furthest_cw_qrp: self
                .brag_furthest(query, " AND cw_mode_family(mode) = 'CW' AND power IS NOT NULL AND power <= 5")?,
            furthest_perfect_rst: self.brag_furthest(query, " AND rst_rcvd IN ('599', '59')")?,
            furthest_per_band: self.brag_furthest_per_band(query)?,
            average_km: self.brag_average_km(query)?,
            lowest_power: self.brag_lowest_power(query)?,
            best_watts_per_mile: self.brag_best_watts_per_mile(query)?,
        })
    }

    /// The max-distance contact among visible QSOs matching `query` plus `extra_filter`
    /// (a leading-`AND` SQL fragment, e.g. the QRP / CW / perfect-RST predicate). `None`
    /// when no matching QSO has a computable distance. Tie-break: distance desc, callsign asc.
    fn brag_furthest(&self, query: &ParsedQuery, extra_filter: &str) -> Result<Option<BragContact>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT callsign, COALESCE(band, '') AS band, d FROM ( \
               SELECT callsign, band, cw_grid_distance_km(my_grid, their_grid) AS d \
               FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}){extra_filter} \
             ) WHERE d IS NOT NULL ORDER BY d DESC, callsign ASC LIMIT 1"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn
            .query_row(&sql, refs.as_slice(), |row| {
                Ok(BragContact { callsign: row.get(0)?, band: row.get(1)?, distance_km: row.get(2)? })
            })
            .optional()
            .map_err(Into::into)
    }

    /// Per-band furthest contact (band key lowercased), distance-desc then band-asc. Within a
    /// band the winner is distance desc, callsign asc.
    fn brag_furthest_per_band(&self, query: &ParsedQuery) -> Result<Vec<BragBandRecord>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT band, callsign, d FROM ( \
               SELECT LOWER(COALESCE(band, '')) AS band, callsign, d, \
                      ROW_NUMBER() OVER ( \
                        PARTITION BY LOWER(COALESCE(band, '')) ORDER BY d DESC, callsign ASC \
                      ) AS rn \
               FROM ( \
                 SELECT band, callsign, cw_grid_distance_km(my_grid, their_grid) AS d \
                 FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
               ) WHERE d IS NOT NULL \
             ) WHERE rn = 1 ORDER BY d DESC, band ASC"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok(BragBandRecord { band: row.get(0)?, callsign: row.get(1)?, distance_km: row.get(2)? })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Mean distance over visible QSOs matching `query` with a computable distance (NULL
    /// distances excluded; 0-km same-grid contacts included, matching `computeAverageDistance`).
    fn brag_average_km(&self, query: &ParsedQuery) -> Result<Option<f64>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT AVG(d) FROM ( \
               SELECT cw_grid_distance_km(my_grid, their_grid) AS d \
               FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             ) WHERE d IS NOT NULL"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        // AVG over no rows yields NULL → None.
        self.conn
            .query_row(&sql, refs.as_slice(), |row| row.get::<_, Option<f64>>(0))
            .map_err(Into::into)
    }

    /// The lowest-power (> 0 W) contact, tie-broken by callsign asc. Carries that QSO's
    /// distance when computable.
    fn brag_lowest_power(&self, query: &ParsedQuery) -> Result<Option<BragPowerContact>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT power, callsign, COALESCE(band, '') AS band, d FROM ( \
               SELECT power, callsign, band, cw_grid_distance_km(my_grid, their_grid) AS d \
               FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             ) WHERE power IS NOT NULL AND power > 0 ORDER BY power ASC, callsign ASC LIMIT 1"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn
            .query_row(&sql, refs.as_slice(), |row| {
                Ok(BragPowerContact {
                    watts: row.get(0)?,
                    callsign: row.get(1)?,
                    band: row.get(2)?,
                    distance_km: row.get(3)?,
                })
            })
            .optional()
            .map_err(Into::into)
    }

    /// The best watts-per-mile contact (min `power / miles`) among visible QSOs matching
    /// `query` with power > 0 and a positive distance. Tie-break: callsign asc. The ratio is
    /// monotonic in `power / distance`, so the mile conversion does not affect selection.
    fn brag_best_watts_per_mile(&self, query: &ParsedQuery) -> Result<Option<BragEfficiency>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT power, callsign, COALESCE(band, '') AS band, d FROM ( \
               SELECT power, callsign, band, cw_grid_distance_km(my_grid, their_grid) AS d \
               FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             ) WHERE power IS NOT NULL AND power > 0 AND d IS NOT NULL AND d > 0 \
             ORDER BY (CAST(power AS REAL) / (d * 0.621371)) ASC, callsign ASC LIMIT 1"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn
            .query_row(&sql, refs.as_slice(), |row| {
                Ok(BragEfficiency {
                    watts: row.get(0)?,
                    callsign: row.get(1)?,
                    band: row.get(2)?,
                    distance_km: row.get(3)?,
                })
            })
            .optional()
            .map_err(Into::into)
    }

    /// The streak-shaped brag-sheet stats over visible QSOs matching `query`, relative to
    /// `today` (UTC calendar day). Faithful port of `BragSheetComputationActor`'s streak math,
    /// normalized to UTC day-bucketing. Each streak is a fold over a small set of distinct
    /// active days (bounded by day cardinality, never QSO count) via `cw_domain::streak`.
    pub fn brag_streaks(&self, query: &ParsedQuery, today: chrono::NaiveDate) -> Result<BragStreaks> {
        let on_air_days = self.brag_active_days(query, "")?;
        let on_air = streak_value(&on_air_days, today);

        let activation_days = self.brag_activation_days(query)?;
        let activation = if activation_days.is_empty() {
            None
        } else {
            Some(streak_value(&activation_days, today))
        };

        let modes = self.brag_mode_streaks(query, today)?;

        Ok(BragStreaks { on_air, activation, modes })
    }

    /// Distinct active UTC days (`YYYY-MM-DD`) over visible QSOs matching `query` plus
    /// `extra_filter` (a leading-`AND` fragment). Parsed to `NaiveDate` by the caller.
    fn brag_active_days(&self, query: &ParsedQuery, extra_filter: &str) -> Result<Vec<String>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT DISTINCT strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}){extra_filter}"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| row.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Distinct UTC days carrying a successful park activation (a `(raw park, UTC day)` group
    /// with ≥ 10 unique QSOs, deduped by `UPPER(callsign)|band|mode|UPPER(park)` — mirrors
    /// `uniqueQSOCount`). Bounded by (park × day) cardinality.
    fn brag_activation_days(&self, query: &ParsedQuery) -> Result<Vec<String>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT DISTINCT day FROM ( \
               SELECT strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day, park, \
                      COUNT(DISTINCT UPPER(callsign) || '|' || COALESCE(band, '') || '|' \
                        || COALESCE(mode, '') || '|' || UPPER(park)) AS uniq \
               FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
               GROUP BY day, park \
             ) WHERE uniq >= 10"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| row.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Per mode-family (CW/Phone/Digital) day streaks. One pass collects each family's distinct
    /// UTC days; families with ≥ 1 QSO emit a streak, in CW/Phone/Digital order.
    fn brag_mode_streaks(&self, query: &ParsedQuery, today: chrono::NaiveDate) -> Result<Vec<ModeStreak>> {
        use std::collections::BTreeSet;
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT cw_mode_family(mode) AS fam, strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) GROUP BY fam, day"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        let mut by_family: std::collections::HashMap<String, BTreeSet<String>> =
            std::collections::HashMap::new();
        for row in rows {
            let (fam, day) = row?;
            by_family.entry(fam).or_default().insert(day);
        }
        // CW/Phone/Digital order mirrors the Swift loop; "Other" is excluded.
        let mut out = Vec::new();
        for fam in ["CW", "Phone", "Digital"] {
            if let Some(days) = by_family.get(fam) {
                let value = streak_value(&days.iter().cloned().collect::<Vec<_>>(), today);
                out.push(ModeStreak { mode: fam.to_string(), current: value.current, longest: value.longest });
            }
        }
        Ok(out)
    }

    /// The geographic-reach brag-sheet stats over visible QSOs matching `query`. Faithful
    /// port of `BragSheetComputationActor`'s `computeGeoStat` set; continents use the
    /// `cw_continent` UDF and `new_dxcc_entities` additionally consults the all-time log.
    pub fn brag_geographic(&self, query: &ParsedQuery) -> Result<BragGeographic> {
        let valid_list = VALID_US_STATES
            .iter()
            .map(|state| format!("'{state}'"))
            .collect::<Vec<_>>()
            .join(", ");

        let distinct_state = format!("COUNT(DISTINCT {NORMALIZED_STATE})");
        let dxcc_entities = self.geo_count("COUNT(DISTINCT dxcc)", " AND dxcc IS NOT NULL", query)?;
        let states_provinces = self.geo_count(
            &distinct_state,
            &format!(" AND state IS NOT NULL AND {NORMALIZED_STATE} IN ({valid_list})"),
            query,
        )?;
        let grid_squares = self.geo_count(
            "COUNT(DISTINCT SUBSTR(their_grid, 1, 4))",
            " AND their_grid IS NOT NULL AND their_grid <> ''",
            query,
        )?;
        let continents = self.geo_count("COUNT(DISTINCT cw_continent(dxcc))", "", query)?;
        let was_states = self.geo_count(
            &distinct_state,
            &format!(" AND dxcc = 291 AND state IS NOT NULL AND {NORMALIZED_STATE} IN ({valid_list})"),
            query,
        )?;
        let most_continents_day = self.brag_most_continents_day(query)?;
        let new_dxcc_entities = self.brag_new_dxcc(query)?;

        Ok(BragGeographic {
            dxcc_entities,
            new_dxcc_entities,
            states_provinces,
            grid_squares,
            continents,
            most_continents_day,
            was_states,
        })
    }

    /// Run a single-row `SELECT <select_sql> FROM qso WHERE <visible> AND (<query>)<extra>`
    /// returning the scalar `i64` (COUNT yields 0 over no rows).
    fn geo_count(&self, select_sql: &str, extra_filter: &str, query: &ParsedQuery) -> Result<i64> {
        let (where_sql, values) = compile_where(query);
        let sql = format!("SELECT {select_sql} FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}){extra_filter}");
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0)).map_err(Into::into)
    }

    /// Max distinct continents worked in a single UTC day over visible QSOs matching `query`
    /// (`computeMostContinentsDay`). 0 when there are no QSOs / no continent-mapped days.
    fn brag_most_continents_day(&self, query: &ParsedQuery) -> Result<i64> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT MAX(c) FROM ( \
               SELECT COUNT(DISTINCT cw_continent(dxcc)) AS c \
               FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
               GROUP BY strftime('%Y-%m-%d', qso_date, 'unixepoch') \
             )"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let max: Option<i64> = self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0))?;
        Ok(max.unwrap_or(0))
    }

    /// Count of period entities (visible + `query`) whose all-time-earliest QSO is at or after
    /// the period's earliest QSO — i.e. first ever worked within the period (`computeNewDXCC`).
    /// The all-time earliest ignores the `query` filter; the period start / membership apply it.
    fn brag_new_dxcc(&self, query: &ParsedQuery) -> Result<i64> {
        let (where_sql, values) = compile_where(query);
        // `where_sql` appears twice (entity membership + period-start subqueries), so bind the
        // compiled values twice in textual order.
        let sql = format!(
            "SELECT COUNT(*) FROM ( \
               SELECT dxcc, MIN(qso_date) AS first_ever \
               FROM qso WHERE {VISIBLE_QSO} AND dxcc IS NOT NULL GROUP BY dxcc \
             ) g \
             WHERE g.dxcc IN ( \
               SELECT DISTINCT dxcc FROM qso \
               WHERE {VISIBLE_QSO} AND dxcc IS NOT NULL AND ({where_sql}) \
             ) AND g.first_ever >= ( \
               SELECT MIN(qso_date) FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             )"
        );
        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        bound.extend(values.iter().map(|v| v.to_sql_param()));
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0)).map_err(Into::into)
    }

    /// The POTA-category brag stats over visible QSOs matching `query`. Faithful port of
    /// `BragSheetComputationActor+POTA`: parks activated (≥ 10 unique QSOs per park/day),
    /// parks hunted, park-to-park, best activation, and new-this-period parks. Each query is
    /// bounded (a single scalar, a `LIMIT 1` group, or grouped by park cardinality), never by
    /// QSO count.
    pub fn brag_pota(&self, query: &ParsedQuery) -> Result<BragPota> {
        Ok(BragPota {
            parks_activated: self.brag_parks_activated(query)?,
            parks_hunted: self
                .geo_count("COUNT(DISTINCT their_park)", " AND their_park IS NOT NULL AND their_park <> ''", query)?,
            park_to_park: self.geo_count(
                "COUNT(*)",
                " AND park IS NOT NULL AND park <> '' AND their_park IS NOT NULL AND their_park <> ''",
                query,
            )?,
            best_activation: self.brag_best_activation(query)?,
            new_parks: self.brag_new_parks(query)?,
        })
    }

    /// Count of distinct parks whose (park, UTC-day) activation group has ≥ 10 unique QSOs
    /// (`computeParksActivated`). Unique key dedupes by `UPPER(call)|band|mode|UPPER(park)`,
    /// mirroring `uniqueQSOCount`; grouping is by the raw park reference + UTC day.
    fn brag_parks_activated(&self, query: &ParsedQuery) -> Result<i64> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT COUNT(DISTINCT park) FROM ( \
               SELECT park, \
                      COUNT(DISTINCT UPPER(callsign) || '|' || COALESCE(band, '') || '|' \
                            || COALESCE(mode, '') || '|' || UPPER(park)) AS uniq \
               FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
               GROUP BY park, strftime('%Y-%m-%d', qso_date, 'unixepoch') \
               HAVING uniq >= 10 \
             )"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0)).map_err(Into::into)
    }

    /// The (park, UTC-day) activation group with the most raw QSOs (`computeBestActivation`).
    /// Tie-break is deterministic — count DESC, park ASC, day ASC — so the oracle can match the
    /// (otherwise nondeterministic) Swift `max(by:)`. `None` when there are no parked QSOs.
    fn brag_best_activation(&self, query: &ParsedQuery) -> Result<Option<BragBestActivation>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT park, strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day, COUNT(*) AS c \
             FROM qso WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
             GROUP BY park, day \
             ORDER BY c DESC, park ASC, day ASC LIMIT 1"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn
            .query_row(&sql, refs.as_slice(), |row| {
                Ok(BragBestActivation { park: row.get(0)?, day: row.get(1)?, count: row.get(2)? })
            })
            .optional()
            .map_err(Into::into)
    }

    /// Count of period parks (activated ∪ hunted) whose all-time-earliest contact — a QSO with
    /// `park = X` OR `their_park = X` — is at/after the period's earliest QSO (`computeNewParks`).
    /// The all-time scan ignores the `query` filter; the period start + membership apply it. The
    /// all-time per-park MIN folds both columns via `UNION ALL` (like `brag_new_dxcc`).
    fn brag_new_parks(&self, query: &ParsedQuery) -> Result<i64> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT COUNT(*) FROM ( \
               SELECT ref, MIN(qso_date) AS first_ever FROM ( \
                 SELECT park AS ref, qso_date FROM qso \
                 WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' \
                 UNION ALL \
                 SELECT their_park AS ref, qso_date FROM qso \
                 WHERE {VISIBLE_QSO} AND their_park IS NOT NULL AND their_park <> '' \
               ) GROUP BY ref \
             ) g \
             WHERE g.ref IN ( \
               SELECT park FROM qso \
               WHERE {VISIBLE_QSO} AND park IS NOT NULL AND park <> '' AND ({where_sql}) \
               UNION \
               SELECT their_park FROM qso \
               WHERE {VISIBLE_QSO} AND their_park IS NOT NULL AND their_park <> '' AND ({where_sql}) \
             ) AND g.first_ever >= ( \
               SELECT MIN(qso_date) FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             )"
        );
        // `where_sql` appears three times (park membership, their_park membership, period start),
        // so bind the compiled values three times in textual order.
        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        bound.extend(values.iter().map(|v| v.to_sql_param()));
        bound.extend(values.iter().map(|v| v.to_sql_param()));
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0)).map_err(Into::into)
    }

    /// The SQL-expressible volume / records / "fun" brag stats over visible QSOs matching
    /// `query`. Faithful port of `computeVolumeStat` / the GROUP-BY-shaped `computeFunStat`
    /// set + `computeTotalDistance` / `computeActiveModes`. Each query is bounded (a single MAX
    /// row, a `LIMIT 1` group, or a scalar), never by QSO count.
    pub fn brag_records(&self, query: &ParsedQuery) -> Result<BragRecords> {
        const DAY: &str = "strftime('%Y-%m-%d', qso_date, 'unixepoch')";

        let most_active_weekday = self
            .brag_best_tally("strftime('%w', qso_date, 'unixepoch')", "", query)?
            .map(|tally| ItemTally { name: weekday_name(&tally.name), count: tally.count });

        let total_distance_km = self.brag_total_distance(query)?.filter(|sum| *sum > 0.0);

        Ok(BragRecords {
            most_qsos_day: self.brag_group_max(DAY, "COUNT(*)", query)?,
            most_qsos_session: self.brag_group_max("COALESCE(logging_session_id, id)", "COUNT(*)", query)?,
            most_countries_day: self.brag_group_max(DAY, "COUNT(DISTINCT dxcc)", query)?,
            most_bands_day: self.brag_group_max(DAY, "COUNT(DISTINCT LOWER(COALESCE(band, '')))", query)?,
            most_active_weekday,
            busiest_band: self.brag_best_tally("LOWER(COALESCE(band, ''))", "", query)?,
            busiest_mode: self.brag_best_tally("cw_mode_canonical(COALESCE(mode, ''))", "", query)?,
            repeat_customer: self.brag_best_tally("UPPER(callsign)", "HAVING COUNT(*) > 1", query)?,
            earliest_qso: self.brag_extreme_time("(qso_date % 86400) ASC, qso_date ASC", query)?,
            latest_qso: self.brag_extreme_time("(qso_date % 86400) DESC, qso_date DESC", query)?,
            total_distance_km,
            active_modes: self.geo_count("COUNT(DISTINCT cw_mode_canonical(COALESCE(mode, '')))", "", query)?,
        })
    }

    /// The session-/sequence-based brag stats over visible QSOs matching `query`. Faithful port
    /// of `BragSheetComputationActor`'s speed/rate/operating-hours/longest-session/largest-Nfer
    /// math: fetches the minimal per-QSO columns (session key, timestamp, park, UTC day) once
    /// and folds them in Rust (O(period rows) — these stats are inherently per-row sequences).
    pub fn brag_session_stats(&self, query: &ParsedQuery) -> Result<BragSessionStats> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT COALESCE(logging_session_id, id) AS sk, qso_date, park, \
                    strftime('%Y-%m-%d', qso_date, 'unixepoch') AS day \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql})"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows_iter = stmt.query_map(refs.as_slice(), |row| {
            Ok(SessionRow {
                session: row.get(0)?,
                timestamp: row.get(1)?,
                park: row.get(2)?,
                day: row.get(3)?,
            })
        })?;
        let mut rows = Vec::new();
        for row in rows_iter {
            rows.push(row?);
        }
        Ok(session_stats_fold(&rows))
    }

    /// MAX over per-group `agg` values (`group_sql` is the `GROUP BY` expression). 0 over no
    /// rows. Used for the per-day / per-session "most …" records.
    fn brag_group_max(&self, group_sql: &str, agg: &str, query: &ParsedQuery) -> Result<i64> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT MAX(c) FROM ( \
               SELECT {agg} AS c FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) GROUP BY {group_sql} \
             )"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let max: Option<i64> = self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0))?;
        Ok(max.unwrap_or(0))
    }

    /// The top `(key, count)` group over visible QSOs matching `query`, ordered count-desc then
    /// key-asc. `having` is an optional `HAVING …` clause. `None` over no rows.
    fn brag_best_tally(&self, key_sql: &str, having: &str, query: &ParsedQuery) -> Result<Option<ItemTally>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT {key_sql} AS k, COUNT(*) AS c FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             GROUP BY k {having} ORDER BY c DESC, k ASC LIMIT 1"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn
            .query_row(&sql, refs.as_slice(), |row| Ok(ItemTally { name: row.get(0)?, count: row.get(1)? }))
            .optional()
            .map_err(Into::into)
    }

    /// The `qso_date` of the QSO at the `order_by` extreme of time-of-day (seconds since UTC
    /// midnight = `qso_date % 86400`). `None` over no rows.
    fn brag_extreme_time(&self, order_by: &str, query: &ParsedQuery) -> Result<Option<i64>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT qso_date FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) ORDER BY {order_by} LIMIT 1"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn.query_row(&sql, refs.as_slice(), |row| row.get(0)).optional().map_err(Into::into)
    }

    /// Summed great-circle distance (km) over computable-distance QSOs matching `query`.
    /// `None` over no computable distances.
    fn brag_total_distance(&self, query: &ParsedQuery) -> Result<Option<f64>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT SUM(d) FROM ( \
               SELECT cw_grid_distance_km(my_grid, their_grid) AS d \
               FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) \
             ) WHERE d IS NOT NULL"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn.query_row(&sql, refs.as_slice(), |row| row.get::<_, Option<f64>>(0)).map_err(Into::into)
    }

    /// Average RST strength digit over visible QSOs matching `query`. Faithful port of
    /// `BragSheetComputationActor.computeAverageRST`: for each QSO whose `rst_rcvd` yields an S
    /// digit (see `cw_rst_s`), average those digits. `None` when no QSO qualifies. The Swift
    /// caller renders this as `String(format: "S%.1f", avg)`.
    pub fn brag_average_rst(&self, query: &ParsedQuery) -> Result<Option<f64>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT AVG(cw_rst_s(rst_rcvd)) \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) AND cw_rst_s(rst_rcvd) IS NOT NULL"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        self.conn
            .query_row(&sql, refs.as_slice(), |row| row.get::<_, Option<f64>>(0))
            .map_err(Into::into)
    }

    /// The DISTINCT uppercased QSO callsigns (over visible QSOs matching `query`) that are in the
    /// (uppercased) `members` set, sorted ascending. Supplies the worked-member callsign set for
    /// `BragSheetComputationActor.computeClubMembersWorked` / `computeClubsRepresented`; the
    /// club→callsign mapping stays app-side. Empty `members` → empty vec.
    pub fn worked_member_callsigns(&self, query: &ParsedQuery, members: &[String]) -> Result<Vec<String>> {
        // `IN ()` is invalid; with no members nothing can match.
        if members.is_empty() {
            return Ok(Vec::new());
        }
        let (where_sql, values) = compile_where(query);
        let placeholders = vec!["?"; members.len()].join(", ");
        let sql = format!(
            "SELECT DISTINCT UPPER(callsign) AS member \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}) AND UPPER(callsign) IN ({placeholders}) \
             ORDER BY member ASC"
        );
        // Bind order = textual placeholder order: the compiled WHERE values, then the
        // uppercased members `IN (...)` list.
        let mut bound: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        for member in members {
            bound.push(Box::new(member.to_uppercase()));
        }
        let refs: Vec<&dyn rusqlite::types::ToSql> = bound.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| row.get::<_, String>(0))?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    /// Compute every `enabled` brag stat over visible QSOs matching `query` (already
    /// date-windowed by the caller via `ParsedQuery::with_date_window`), relative to `today`
    /// (UTC calendar day, for the streak "current" calc). Faithful port of the per-stat
    /// dispatch in `BragSheetComputationActor+RustOverlay.swift` (`value(for:bundle:)` and its
    /// per-category mappers): each aggregate bundle (`brag_period_metrics`,
    /// `brag_distance_stats`, `brag_streaks`, `brag_geographic`, `brag_records`,
    /// `brag_session_stats`, `brag_pota`, `brag_average_rst`) is computed at most once, then
    /// each stat is mapped from the relevant bundle. `brag_period_metrics` is always computed
    /// (it's a single trivial-SQL row) both to answer `Totals` stats and to mirror Swift's
    /// `guard bundle.period.totalQSOs > 0` short-circuit — when the period has zero QSOs every
    /// stat resolves to `NoData` without running the other (pricier) aggregates. The remaining
    /// bundles are computed lazily, only if `enabled` actually needs them. Returns one
    /// `(stat, value)` pair per entry of `enabled`, in the same order.
    ///
    /// `ClubMembersWorked` / `ClubsRepresented` need a club-member callsign set /
    /// callsign→club mapping that isn't available at this layer (Swift keeps the club roster
    /// app-side and calls `worked_member_callsigns` separately) — those two always resolve to
    /// `BragStatValue::NoData` here; the FFI/app layer may overlay them. `FastestCwSpeed` is a
    /// stub in the Swift source (no computation exists anywhere) and is also always `NoData`.
    pub fn compute_configured_brag(
        &self,
        query: &ParsedQuery,
        enabled: &[cw_domain::brag_sheet::BragStatType],
        today: chrono::NaiveDate,
    ) -> Result<Vec<(cw_domain::brag_sheet::BragStatType, cw_domain::brag_sheet::BragStatValue)>> {
        use cw_domain::brag_sheet::{BragCategory, BragStatType, BragStatValue};

        let period = self.brag_period_metrics(query)?;

        if period.total_qsos == 0 {
            return Ok(enabled.iter().map(|stat| (*stat, BragStatValue::NoData)).collect());
        }

        let needs = |predicate: fn(BragCategory) -> bool| enabled.iter().any(|s| predicate(s.category()));

        let distance = if needs(|c| matches!(c, BragCategory::Distance | BragCategory::PowerAndEfficiency | BragCategory::Cw))
            || enabled.contains(&BragStatType::BestRstAtDistance)
        {
            Some(self.brag_distance_stats(query)?)
        } else {
            None
        };
        let streaks = if needs(|c| matches!(c, BragCategory::Streaks)) {
            Some(self.brag_streaks(query, today)?)
        } else {
            None
        };
        let geographic = if needs(|c| matches!(c, BragCategory::GeographicReach)) {
            Some(self.brag_geographic(query)?)
        } else {
            None
        };
        let records = if needs(|c| matches!(c, BragCategory::VolumeRecords | BragCategory::FunAndUnique))
            || enabled.contains(&BragStatType::TotalDistance)
            || enabled.contains(&BragStatType::ActiveModes)
        {
            Some(self.brag_records(query)?)
        } else {
            None
        };
        let session = if needs(|c| matches!(c, BragCategory::SpeedAndRate))
            || enabled.contains(&BragStatType::OperatingHours)
            || enabled.contains(&BragStatType::LongestSession)
            || enabled.contains(&BragStatType::LargestNfer)
        {
            Some(self.brag_session_stats(query)?)
        } else {
            None
        };
        let pota = if needs(|c| matches!(c, BragCategory::Pota)) { Some(self.brag_pota(query)?) } else { None };
        let average_rst = if enabled.contains(&BragStatType::AverageRstReceived) {
            self.brag_average_rst(query)?
        } else {
            None
        };

        Ok(enabled
            .iter()
            .map(|stat| {
                let value = brag_stat_value(
                    *stat,
                    &period,
                    distance.as_ref(),
                    streaks.as_ref(),
                    geographic.as_ref(),
                    records.as_ref(),
                    session.as_ref(),
                    pota.as_ref(),
                    average_rst,
                );
                (*stat, value)
            })
            .collect())
    }

    /// Shared `GROUP BY` runner: returns `(key, count, distinct_callsigns)` per
    /// group. `key_sql` is the grouping expression (also selected); `extra_filter`
    /// is appended to the WHERE (e.g. non-null guards); `order_by` is the full
    /// `ORDER BY` clause.
    fn grouped_counts(
        &self,
        key_sql: &str,
        extra_filter: &str,
        order_by: &str,
        query: &ParsedQuery,
    ) -> Result<Vec<(String, i64, i64)>> {
        let (where_sql, values) = compile_where(query);
        let sql = format!(
            "SELECT {key_sql} AS k, COUNT(*), COUNT(DISTINCT callsign) \
             FROM qso WHERE {VISIBLE_QSO} AND ({where_sql}){extra_filter} \
             GROUP BY k {order_by}"
        );
        let boxed: Vec<Box<dyn rusqlite::types::ToSql>> =
            values.iter().map(|v| v.to_sql_param()).collect();
        let refs: Vec<&dyn rusqlite::types::ToSql> = boxed.iter().map(|b| b.as_ref()).collect();
        let mut stmt = self.conn.prepare(&sql)?;
        let rows = stmt.query_map(refs.as_slice(), |row| {
            let key: Option<String> = row.get(0)?;
            Ok((key.unwrap_or_default(), row.get(1)?, row.get(2)?))
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }
}

/// One fetched row for the session-stats fold: its session key (`logging_session_id` or the
/// QSO id), timestamp, optional park, and UTC day string.
struct SessionRow {
    session: String,
    timestamp: i64,
    park: Option<String>,
    day: String,
}

/// Inter-QSO 15-minute gap threshold (seconds) for "active" operating time.
const ACTIVE_GAP_SECONDS: i64 = 15 * 60;

/// Sum of inter-QSO gaps ≤ 15 min over a time-sorted session (`computeOperatingHours` /
/// `computeBestSessionRate`'s active-time inner loop).
fn session_active_time(sorted: &[i64]) -> i64 {
    sorted
        .windows(2)
        .map(|pair| pair[1] - pair[0])
        .filter(|gap| *gap <= ACTIVE_GAP_SECONDS)
        .sum()
}

/// Fold the fetched rows into the session-/sequence-based brag stats, mirroring
/// `BragSheetComputationActor`'s per-session and global-timestamp loops.
fn session_stats_fold(rows: &[SessionRow]) -> BragSessionStats {
    use std::collections::{BTreeMap, BTreeSet};
    if rows.is_empty() {
        return BragSessionStats {
            operating_seconds: None,
            fastest_ten_seconds: None,
            best_session_rate: None,
            fastest_activation_seconds: None,
            longest_session_seconds: None,
            peak_15_min_count: 0,
            largest_nfer: 0,
        };
    }

    let mut by_session: BTreeMap<&str, Vec<i64>> = BTreeMap::new();
    let mut parked_sessions: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    let mut by_activation: BTreeMap<(&str, &str), Vec<i64>> = BTreeMap::new();
    let mut all_ts: Vec<i64> = Vec::with_capacity(rows.len());
    for row in rows {
        all_ts.push(row.timestamp);
        by_session.entry(&row.session).or_default().push(row.timestamp);
        if let Some(park) = row.park.as_deref().filter(|park| !park.is_empty()) {
            parked_sessions.entry(&row.session).or_default().insert(park);
            by_activation.entry((park, row.day.as_str())).or_default().push(row.timestamp);
        }
    }

    let mut operating = 0f64;
    let mut longest = 0i64;
    let mut fastest_ten: Option<i64> = None;
    let mut best_rate = 0f64;
    for stamps in by_session.values_mut() {
        stamps.sort_unstable();
        // Operating hours: ≥ 2 QSOs → max(active, 60); a lone QSO → 60.
        operating += if stamps.len() >= 2 {
            session_active_time(stamps).max(60) as f64
        } else {
            60.0
        };
        // Longest session span (first → last).
        longest = longest.max(stamps[stamps.len() - 1] - stamps[0]);
        if stamps.len() >= 10 {
            // Fastest 10 consecutive: min window span.
            let win_min = stamps.windows(10).map(|win| win[9] - win[0]).min();
            fastest_ten = match (fastest_ten, win_min) {
                (Some(cur), Some(win)) => Some(cur.min(win)),
                (None, win) => win,
                (cur, None) => cur,
            };
            // Best session rate (QSOs/hour over active time).
            let active = session_active_time(stamps);
            if active > 0 {
                let rate = stamps.len() as f64 / (active as f64 / 3_600.0);
                best_rate = best_rate.max(rate);
            }
        }
    }

    // Fastest activation: shortest 1st→10th span over (park, day) groups with ≥ 10 QSOs.
    let mut fastest_activation: Option<i64> = None;
    for stamps in by_activation.values_mut() {
        if stamps.len() >= 10 {
            stamps.sort_unstable();
            let span = stamps[9] - stamps[0];
            fastest_activation = Some(fastest_activation.map_or(span, |cur: i64| cur.min(span)));
        }
    }

    let largest_nfer = parked_sessions.values().map(BTreeSet::len).max().unwrap_or(0) as i64;

    BragSessionStats {
        operating_seconds: Some(operating),
        fastest_ten_seconds: fastest_ten.map(|secs| secs as f64),
        best_session_rate: (best_rate > 0.0).then_some(best_rate),
        fastest_activation_seconds: fastest_activation.map(|secs| secs as f64),
        longest_session_seconds: (longest > 0).then_some(longest as f64),
        peak_15_min_count: peak_15_min_count(&mut all_ts),
        largest_nfer,
    }
}

/// Most timestamps within any 15-minute window (`computePeak15MinRate`). Sorts in place and
/// sweeps with a two-pointer; the window is `[t, t + 15min]` inclusive.
fn peak_15_min_count(all_ts: &mut [i64]) -> i64 {
    all_ts.sort_unstable();
    let mut best = 0i64;
    let mut end = 0usize;
    for start in 0..all_ts.len() {
        if end < start {
            end = start;
        }
        while end < all_ts.len() && all_ts[end] <= all_ts[start] + ACTIVE_GAP_SECONDS {
            end += 1;
        }
        best = best.max((end - start) as i64);
    }
    best
}

/// Map a SQLite `strftime('%w')` weekday index ("0"=Sun … "6"=Sat) to its short name,
/// mirroring `computeMostActiveDay`'s `dayNames` table. Unknown → "?".
fn weekday_name(index: &str) -> String {
    const NAMES: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    index
        .parse::<usize>()
        .ok()
        .and_then(|idx| NAMES.get(idx))
        .map_or_else(|| "?".to_string(), |name| (*name).to_string())
}

/// Fold a set of `YYYY-MM-DD` active days into a current/longest streak relative to `today`
/// via `cw_domain::streak`. Unparseable days are skipped (strftime always yields valid dates).
fn streak_value(days: &[String], today: chrono::NaiveDate) -> StreakValue {
    let dates = days
        .iter()
        .filter_map(|day| chrono::NaiveDate::parse_from_str(day, "%Y-%m-%d").ok());
    let result = cw_domain::streak::calculate_streak(dates, today);
    StreakValue { current: i64::from(result.current), longest: i64::from(result.longest) }
}

/// Bind a single equipment name to the four positional `?` placeholders in
/// `SESSION_ITEM_FROM_MATCH` (rig / antenna / key / mic).
fn bind_name_four(name: &str) -> Vec<Box<dyn rusqlite::types::ToSql>> {
    (0..4)
        .map(|_| Box::new(name.to_string()) as Box<dyn rusqlite::types::ToSql>)
        .collect()
}

/// Split a comma-separated park-reference field into individual trimmed, non-empty
/// references. Mirrors `MyParksView.splitParkRefs`.
fn split_refs(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(|part| part.trim().to_string())
        .filter(|part| !part.is_empty())
        .collect()
}

/// DXCC entity record for an entity id, via the `cw-domain` country table.
fn dxcc_country(id: u32) -> Option<&'static cw_domain::location_prefix::PrefixCountry> {
    COUNTRIES.iter().find(|c| c.id == id)
}

/// DXCC entity name for an entity id, via the `cw-domain` country table.
fn dxcc_name(id: u32) -> Option<&'static str> {
    dxcc_country(id).map(|c| c.name)
}

/// Map one `BragStatType` to its `BragStatValue` from the (lazily computed) aggregate
/// bundles. Faithful port of `BragSheetComputationActor+RustOverlay.swift`'s `value(for:
/// bundle:)` and its per-category mappers (`totalsValue` / `speedValue` / `distanceValue` /
/// `powerValue` / `geoValue` / `volumeValue` / `streakValue` / `potaValue` / `cwValue` /
/// `signalValue` / `funValue`). `period` is always present (the caller already checked
/// `total_qsos > 0`); the other bundles are `None` when not needed by `enabled` and any
/// stat that would read a missing bundle maps to `NoData` (defensive — `compute_configured_brag`
/// always supplies the bundle a requested stat needs).
#[allow(clippy::too_many_arguments)]
fn brag_stat_value(
    stat: cw_domain::brag_sheet::BragStatType,
    period: &BragPeriodMetrics,
    distance: Option<&BragDistanceStats>,
    streaks: Option<&BragStreaks>,
    geographic: Option<&BragGeographic>,
    records: Option<&BragRecords>,
    session: Option<&BragSessionStats>,
    pota: Option<&BragPota>,
    average_rst: Option<f64>,
) -> cw_domain::brag_sheet::BragStatValue {
    use cw_domain::brag_sheet::BragStatType::*;
    use cw_domain::brag_sheet::{BandTableEntry, BragStatValue as V, ModeStreakEntry};

    let contact = |row: &Option<BragContact>| -> V {
        row.as_ref()
            .map(|c| V::Contact {
                callsign: c.callsign.clone(),
                distance_km: Some(c.distance_km),
                band: Some(c.band.clone()),
            })
            .unwrap_or(V::NoData)
    };
    let tally = |row: &Option<ItemTally>| -> V {
        row.as_ref().map(|t| V::CallsignCount { callsign: t.name.clone(), count: t.count }).unwrap_or(V::NoData)
    };
    let time = |unix: Option<i64>| -> V { unix.map(|secs| V::TimeOfDay { unix_seconds: secs }).unwrap_or(V::NoData) };

    match stat {
        // ---- Totals ----
        TotalQsos => V::Count(period.total_qsos),
        TotalCwQsos => V::Count(period.cw_qsos),
        TotalPhoneQsos => V::Count(period.phone_qsos),
        TotalDigitalQsos => V::Count(period.digital_qsos),
        TotalDistance => {
            records.and_then(|r| r.total_distance_km).map(|km| V::Distance { km }).unwrap_or(V::NoData)
        }
        OperatingDays => V::Count(period.operating_days),
        OperatingHours => {
            session.and_then(|s| s.operating_seconds).map(|secs| V::Duration { seconds: secs }).unwrap_or(V::NoData)
        }
        ActiveBands => V::Count(period.active_bands),
        ActiveModes => records.map(|r| V::Count(r.active_modes)).unwrap_or(V::NoData),
        UniqueCallsigns => V::Count(period.unique_callsigns),
        QrpQsoCount => V::Count(period.qrp_qsos),
        MilliwattQsoCount => V::Count(period.milliwatt_qsos),

        // ---- Speed & Rate ----
        Fastest10Qsos => session
            .and_then(|s| s.fastest_ten_seconds)
            .map(|secs| V::Rate { value: 10.0, label: format_duration_label(secs) })
            .unwrap_or(V::NoData),
        Peak15MinRate => {
            let Some(session) = session else { return V::NoData };
            if period.total_qsos < 2 {
                return V::Count(period.total_qsos);
            }
            let count = session.peak_15_min_count;
            let projected = (count as f64) * (60.0 / 15.0);
            V::Rate { value: count as f64, label: format!("{count} in 15m ({}/hr)", projected as i64) }
        }
        BestSessionRate => session
            .and_then(|s| s.best_session_rate)
            .map(|rate| V::Rate { value: rate, label: format!("{rate:.0} QSOs/hr") })
            .unwrap_or(V::NoData),
        FastestActivation => session
            .and_then(|s| s.fastest_activation_seconds)
            .map(|secs| V::Duration { seconds: secs })
            .unwrap_or(V::NoData),

        // ---- Distance ----
        FurthestContact => distance.map(|d| contact(&d.furthest)).unwrap_or(V::NoData),
        FurthestQrpContact => distance.map(|d| contact(&d.furthest_qrp)).unwrap_or(V::NoData),
        AverageContactDistance => {
            distance.and_then(|d| d.average_km).map(|km| V::Distance { km }).unwrap_or(V::NoData)
        }
        FurthestContactPerBand => {
            let Some(distance) = distance else { return V::NoData };
            if distance.furthest_per_band.is_empty() {
                return V::NoData;
            }
            V::BandTable(
                distance
                    .furthest_per_band
                    .iter()
                    .map(|row| BandTableEntry {
                        band: row.band.clone(),
                        callsign: row.callsign.clone(),
                        distance_km: Some(row.distance_km),
                    })
                    .collect(),
            )
        }

        // ---- Power & Efficiency ----
        LowestPowerContact => {
            let Some(low) = distance.and_then(|d| d.lowest_power.as_ref()) else { return V::NoData };
            V::Power {
                watts: low.watts as f64,
                callsign: low.callsign.clone(),
                distance_km: low.distance_km,
                band: Some(low.band.clone()),
            }
        }
        BestWattsPerMile => {
            let Some(best) = distance.and_then(|d| d.best_watts_per_mile.as_ref()) else { return V::NoData };
            let miles = best.distance_km * 0.621_371;
            let wpm = (best.watts as f64) / miles;
            let detail = format!(
                "{}W to {} at {} on {}",
                best.watts,
                best.callsign,
                format_distance_miles_or_km(best.distance_km),
                best.band
            );
            V::Efficiency { watts_per_mile: wpm, detail }
        }

        // ---- Geographic Reach ----
        DxccEntities => geographic.map(|g| V::Count(g.dxcc_entities)).unwrap_or(V::NoData),
        NewDxccEntities => geographic.map(|g| V::Count(g.new_dxcc_entities)).unwrap_or(V::NoData),
        StatesAndProvinces => geographic.map(|g| V::Count(g.states_provinces)).unwrap_or(V::NoData),
        GridSquares => geographic.map(|g| V::Count(g.grid_squares)).unwrap_or(V::NoData),
        Continents => geographic
            .map(|g| if g.continents > 0 { V::Progress { current: g.continents, total: 6 } } else { V::NoData })
            .unwrap_or(V::NoData),
        MostContinentsInADay => geographic
            .map(|g| if g.most_continents_day > 0 { V::Count(g.most_continents_day) } else { V::NoData })
            .unwrap_or(V::NoData),
        WorkedAllStatesProgress => {
            geographic.map(|g| V::Progress { current: g.was_states, total: 50 }).unwrap_or(V::NoData)
        }

        // ---- Volume Records ----
        MostQsosInADay => {
            records.map(|r| if r.most_qsos_day > 0 { V::Count(r.most_qsos_day) } else { V::NoData }).unwrap_or(V::NoData)
        }
        MostQsosInASession => records
            .map(|r| if r.most_qsos_session > 0 { V::Count(r.most_qsos_session) } else { V::NoData })
            .unwrap_or(V::NoData),
        MostCountriesInADay => records
            .map(|r| if r.most_countries_day > 0 { V::Count(r.most_countries_day) } else { V::NoData })
            .unwrap_or(V::NoData),
        MostBandsInADay => {
            records.map(|r| if r.most_bands_day > 0 { V::Count(r.most_bands_day) } else { V::NoData }).unwrap_or(V::NoData)
        }

        // ---- Streaks ----
        CurrentOnAirStreak | BestOnAirStreak => streaks
            .map(|s| V::Streak { current: s.on_air.current, longest: s.on_air.longest })
            .unwrap_or(V::NoData),
        CurrentActivationStreak => streaks
            .and_then(|s| s.activation.as_ref())
            .map(|a| V::Streak { current: a.current, longest: a.longest })
            .unwrap_or(V::NoData),
        ModeStreaks => {
            let Some(streaks) = streaks else { return V::NoData };
            if streaks.modes.is_empty() {
                return V::NoData;
            }
            V::ModeStreakList(
                streaks
                    .modes
                    .iter()
                    .map(|m| ModeStreakEntry { mode: m.mode.clone(), current: m.current, longest: m.longest })
                    .collect(),
            )
        }

        // ---- POTA ----
        ParksActivated => pota.map(|p| V::Count(p.parks_activated)).unwrap_or(V::NoData),
        ParksHunted => pota.map(|p| V::Count(p.parks_hunted)).unwrap_or(V::NoData),
        ParkToParkContacts => pota.map(|p| V::Count(p.park_to_park)).unwrap_or(V::NoData),
        NewParks => pota.map(|p| V::Count(p.new_parks)).unwrap_or(V::NoData),
        LargestNfer => session
            .map(|s| if s.largest_nfer > 1 { V::Count(s.largest_nfer) } else { V::NoData })
            .unwrap_or(V::NoData),
        BestActivation => {
            let Some(best) = pota.and_then(|p| p.best_activation.as_ref()) else { return V::NoData };
            V::ParkDetail { park: best.park.clone(), date: Some(best.day.clone()), count: best.count }
        }

        // ---- CW ----
        CwDistanceRecord => distance.map(|d| contact(&d.furthest_cw)).unwrap_or(V::NoData),
        CwQrpRecord => distance.map(|d| contact(&d.furthest_cw_qrp)).unwrap_or(V::NoData),
        FastestCwSpeed => V::NoData, // stub in the Swift source; no computation exists anywhere

        // ---- Signal Quality ----
        PerfectReports => V::Count(period.perfect_reports),
        AverageRstReceived => average_rst.map(|value| V::Rst { value: format!("S{value:.1}"), detail: None }).unwrap_or(V::NoData),
        BestRstAtDistance => distance.map(|d| contact(&d.furthest_perfect_rst)).unwrap_or(V::NoData),

        // ---- Fun & Unique ----
        EarliestQsoOfTheDay => records.map(|r| time(r.earliest_qso)).unwrap_or(V::NoData),
        LatestQsoOfTheDay => records.map(|r| time(r.latest_qso)).unwrap_or(V::NoData),
        LongestSession => {
            session.and_then(|s| s.longest_session_seconds).map(|secs| V::Duration { seconds: secs }).unwrap_or(V::NoData)
        }
        MostActiveDayOfWeek => records
            .and_then(|r| r.most_active_weekday.as_ref())
            .map(|t| V::DayOfWeek { day: t.name.clone(), count: t.count })
            .unwrap_or(V::NoData),
        BusiestBand => records.map(|r| tally(&r.busiest_band)).unwrap_or(V::NoData),
        BusiestMode => records.map(|r| tally(&r.busiest_mode)).unwrap_or(V::NoData),
        RepeatCustomers => records.map(|r| tally(&r.repeat_customer)).unwrap_or(V::NoData),

        // ---- Club stats: no roster available at this layer (see fn doc). ----
        ClubMembersWorked | ClubsRepresented => V::NoData,
    }
}

/// `"Nm SSs"` or `"Nh Nm"` duration label for the `Fastest10Qsos` rate value. Port of
/// `BragSheetComputationActor`'s `formatDuration` helper as used by the RustOverlay.
fn format_duration_label(seconds: f64) -> String {
    let total_seconds = seconds as i64; // truncate toward zero, matching Swift's `Int(seconds)`
    let minutes = total_seconds / 60;
    let secs = total_seconds % 60;
    let hours = minutes / 60;
    let mins = minutes % 60;
    if minutes >= 60 {
        format!("{hours}h {mins}m")
    } else {
        format!("{minutes}m {secs}s")
    }
}

/// Distance formatted in miles (matches `UnitFormatter.distance`'s default imperial display
/// used in the best-watts-per-mile detail string): whole miles, or km fallback text is not
/// needed since the Rust domain layer only formats metric — this mirrors the Swift call site's
/// input (km) converted to the `"NN mi"` label.
fn format_distance_miles_or_km(distance_km: f64) -> String {
    format!("{:.0} mi", distance_km * 0.621_371)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::qso::Qso;
    use crate::LoggingSession;
    use crate::ServicePresence;
    use crate::Store;

    #[test]
    fn normalized_valid_state_strips_comment_and_validates() {
        // Plain valid abbreviation, case-insensitive.
        assert_eq!(normalized_valid_state("ca"), Some("CA"));
        // LoFi comment suffix stripped before validating.
        assert_eq!(normalized_valid_state("TX // some note"), Some("TX"));
        // Not one of the 50 states (DC/territories excluded, matches WAS rule).
        assert_eq!(normalized_valid_state("DC"), None);
        assert_eq!(normalized_valid_state("PR"), None);
        // Garbage input.
        assert_eq!(normalized_valid_state("not a state"), None);
    }

    fn base_qso(id: &str) -> Qso {
        Qso {
            id: id.to_string(),
            callsign: "W1AW".to_string(),
            band: Some("20m".to_string()),
            mode: Some("FT8".to_string()),
            freq_khz: Some(14_074.0),
            qso_date: 1_700_000_000,
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
            imported_at: 1_700_000_000,
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

    fn parse(query: &str) -> ParsedQuery {
        cw_domain::query::parse(query).unwrap()
    }

    fn seed() -> Store {
        let store = Store::open_in_memory("k").unwrap();
        // 20m FT8 W1AW US, confirmed
        let mut a = base_qso("a");
        a.qrz_confirmed = true;
        store.upsert_qso(&a).unwrap();
        // 40m CW K2XX US, park
        let mut b = base_qso("b");
        b.callsign = "K2XX".to_string();
        b.band = Some("40m".to_string());
        b.mode = Some("CW".to_string());
        b.their_grid = Some("DM79".to_string());
        b.park = Some("US-0001".to_string());
        b.qso_date = 1_700_100_000;
        store.upsert_qso(&b).unwrap();
        // 20m SSB W1AW (dup callsign, phone), Canada
        let mut c = base_qso("c");
        c.band = Some("20m".to_string());
        c.mode = Some("SSB".to_string());
        c.dxcc = Some(1);
        c.their_grid = Some("EM12".to_string());
        store.upsert_qso(&c).unwrap();
        // hidden — excluded everywhere
        let mut h = base_qso("h");
        h.callsign = "HIDDEN".to_string();
        h.is_hidden = true;
        store.upsert_qso(&h).unwrap();
        // metadata pseudo-mode — excluded everywhere
        let mut m = base_qso("m");
        m.callsign = "META".to_string();
        m.mode = Some("WEATHER".to_string());
        store.upsert_qso(&m).unwrap();
        store
    }

    #[test]
    fn distinct_counts_excludes_hidden_and_metadata() {
        let store = seed();
        let counts = store.qso_distinct_counts(&parse("")).unwrap();
        assert_eq!(counts.qsos, 3); // a, b, c (not h, not m)
        assert_eq!(counts.bands, 2); // 20m, 40m
        assert_eq!(counts.grids, 2); // EM12, DM79
        assert_eq!(counts.entities, 2); // 291, 1
        assert_eq!(counts.parks, 1); // US-0001
        assert_eq!(counts.confirmed, 1); // a (qrz)
        assert_eq!(counts.qrz_confirmed, 1); // a
        assert_eq!(counts.lotw_confirmed, 0);
        assert_eq!(counts.with_grid, 3); // a, b, c all have their_grid
        assert_eq!(counts.with_park, 1); // b (US-0001)
        assert_eq!(counts.with_dxcc, 3); // a, b → 291; c → 1
        assert_eq!(counts.unique_callsigns, 2); // W1AW (a, c), K2XX (b)
    }

    #[test]
    fn distinct_counts_respects_dsl_filter() {
        let store = seed();
        let counts = store.qso_distinct_counts(&parse("band:20m")).unwrap();
        assert_eq!(counts.qsos, 2); // a, c
        assert_eq!(counts.bands, 1);
    }

    #[test]
    fn count_by_band_orders_by_frequency() {
        let store = seed();
        let rows = store
            .qso_count_by(&parse(""), AggregateDimension::Band)
            .unwrap();
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].key, "20m"); // 2 QSOs
        assert_eq!(rows[0].count, 2);
        assert_eq!(rows[0].distinct_calls, 1); // both W1AW
        assert_eq!(rows[1].key, "40m");
        assert_eq!(rows[1].count, 1);
    }

    #[test]
    fn count_by_mode_family_groups_phone_and_digital() {
        let store = seed();
        let rows = store
            .qso_count_by(&parse(""), AggregateDimension::ModeFamily)
            .unwrap();
        // FT8→Digital, CW→CW, SSB→Phone
        let digital = rows.iter().find(|r| r.key == "Digital").unwrap();
        assert_eq!(digital.count, 1);
        let phone = rows.iter().find(|r| r.key == "Phone").unwrap();
        assert_eq!(phone.count, 1);
        let cw = rows.iter().find(|r| r.key == "CW").unwrap();
        assert_eq!(cw.count, 1);
    }

    #[test]
    fn count_by_dxcc_labels_via_country_table() {
        let store = seed();
        let rows = store
            .qso_count_by(&parse(""), AggregateDimension::Dxcc)
            .unwrap();
        let us = rows.iter().find(|r| r.key == "291").unwrap();
        assert_eq!(us.label, "United States");
        assert_eq!(us.count, 2);
        let canada = rows.iter().find(|r| r.key == "1").unwrap();
        assert_eq!(canada.label, "Canada");
    }

    #[test]
    fn activation_rollup_dedupes_and_marks_successful() {
        let store = Store::open_in_memory("k").unwrap();
        // Park US-0001, op W6JY, same UTC day: 3 QSOs but W1AW worked twice on the
        // SAME band+mode (a dup) → 2 unique.
        for (idx, (call, band, mode)) in [
            ("W1AW", "20m", "FT8"),
            ("W1AW", "20m", "FT8"), // dup of the first
            ("K2XX", "40m", "CW"),
        ]
        .iter()
        .enumerate()
        {
            let mut qso = base_qso(&format!("p{idx}"));
            qso.callsign = (*call).to_string();
            qso.band = Some((*band).to_string());
            qso.mode = Some((*mode).to_string());
            qso.park = Some("US-0001".to_string());
            qso.my_callsign = Some("w6jy".to_string()); // lowercased on purpose
            qso.qso_date = 1_700_000_000;
            store.upsert_qso(&qso).unwrap();
        }
        let rows = store.qso_activation_rollup(&parse(""), 2).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].park, "US-0001");
        assert_eq!(rows[0].operator_callsign, "W6JY"); // uppercased
        assert_eq!(rows[0].total_qsos, 3);
        assert_eq!(rows[0].unique_qsos, 2); // the FT8 dup collapses
        assert!(rows[0].successful); // 2 >= min 2

        // With a higher threshold the same activation is not successful.
        let strict = store.qso_activation_rollup(&parse(""), 10).unwrap();
        assert!(!strict[0].successful);
    }

    #[test]
    fn activation_rollup_caps_grouped_result_at_max_fetch_limit() {
        let store = Store::open_in_memory("k").unwrap();
        // One activation per distinct UTC day for MAX_FETCH_LIMIT + 5 days — each a
        // separate (park, op, day) group. The grouped result must be capped so a
        // huge logbook can't return an unbounded row set.
        let day = 86_400_i64;
        let extra = 5_i64;
        for idx in 0..(MAX_FETCH_LIMIT + extra) {
            let mut qso = base_qso(&format!("p{idx}"));
            qso.park = Some("US-0001".to_string());
            qso.qso_date = 1_700_000_000 + idx * day;
            store.upsert_qso(&qso).unwrap();
        }
        let rows = store.qso_activation_rollup(&parse(""), 1).unwrap();
        assert_eq!(rows.len() as i64, MAX_FETCH_LIMIT, "grouped result must be capped");
        // ORDER BY day DESC keeps the newest activations: the very latest day
        // (idx = MAX_FETCH_LIMIT + extra - 1) must be present.
        let newest = utc_day(1_700_000_000 + (MAX_FETCH_LIMIT + extra - 1) * day);
        assert!(rows.iter().any(|r| r.utc_date == newest), "newest activation must survive the cap");
    }

    /// `strftime('%Y-%m-%d', ts, 'unixepoch')` — the same UTC-day key the rollup groups on.
    fn utc_day(ts: i64) -> String {
        let store = Store::open_in_memory("k").unwrap();
        store
            .conn
            .query_row("SELECT strftime('%Y-%m-%d', ?, 'unixepoch')", rusqlite::params![ts], |row| {
                row.get(0)
            })
            .unwrap()
    }

    #[test]
    fn grid_tiles_group_by_prefix_with_confirmed_and_last() {
        let store = seed(); // a: EM12 (confirmed), b: DM79, c: EM12; hidden/meta excluded
        let tiles = store.qso_grid_tiles(&parse(""), 4).unwrap();
        assert_eq!(tiles.len(), 2);
        // EM12 has 2 (a, c), ordered first by count desc.
        assert_eq!(tiles[0].tile, "EM12");
        assert_eq!(tiles[0].count, 2);
        assert_eq!(tiles[0].confirmed, 1); // only a
        // EM12 = a (W1AW/20m/FT8) + c (W1AW/20m/SSB): distinct, sorted.
        assert_eq!(tiles[0].callsigns, vec!["W1AW"]);
        assert_eq!(tiles[0].bands, vec!["20m"]);
        assert_eq!(tiles[0].modes, vec!["FT8", "SSB"]);
        assert_eq!(tiles[1].tile, "DM79");
        assert_eq!(tiles[1].count, 1);
        assert_eq!(tiles[1].callsigns, vec!["K2XX"]);
        assert_eq!(tiles[1].bands, vec!["40m"]);
        assert_eq!(tiles[1].modes, vec!["CW"]);
        // 2-char precision collapses EM12+EM12 → "EM" (2) and DM79 → "DM" (1).
        let coarse = store.qso_grid_tiles(&parse(""), 2).unwrap();
        assert_eq!(coarse[0].tile, "EM");
        assert_eq!(coarse[0].count, 2);
        assert_eq!(coarse[1].tile, "DM");
    }

    #[test]
    fn was_summary_dedupes_states_and_groups_by_family() {
        let store = Store::open_in_memory("k").unwrap();
        // VA worked on FT8 (Digital) and CW; TX on SSB (Phone) via a LoFi-style
        // "tx // Texas" suffix; an invalid state and a null state are excluded.
        for (idx, (mode, state)) in [
            ("FT8", Some("VA")),
            ("CW", Some("va")), // lowercased on purpose → normalizes to VA
            ("SSB", Some("tx // Texas")),
            ("FT8", Some("ZZ")), // not a real state
            ("CW", None),
        ]
        .iter()
        .enumerate()
        {
            let mut qso = base_qso(&format!("s{idx}"));
            qso.mode = Some((*mode).to_string());
            qso.state = state.map(str::to_string);
            store.upsert_qso(&qso).unwrap();
        }
        // Hidden + metadata rows carry a valid state but must be excluded.
        let mut hidden = base_qso("hid");
        hidden.state = Some("CA".to_string());
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut meta = base_qso("met");
        meta.mode = Some("WEATHER".to_string());
        meta.state = Some("CA".to_string());
        store.upsert_qso(&meta).unwrap();

        let summary = store.was_summary(&parse("")).unwrap();
        assert_eq!(summary.all_states, vec!["TX", "VA"]);
        let cw = summary.per_mode.iter().find(|m| m.mode_family == "CW").unwrap();
        assert_eq!(cw.states, vec!["VA"]);
        let digital = summary.per_mode.iter().find(|m| m.mode_family == "Digital").unwrap();
        assert_eq!(digital.states, vec!["VA"]);
        let phone = summary.per_mode.iter().find(|m| m.mode_family == "Phone").unwrap();
        assert_eq!(phone.states, vec!["TX"]);
        // No CA leaked from the hidden/metadata rows.
        assert!(!summary.all_states.contains(&"CA".to_string()));
    }

    #[test]
    fn was_summary_respects_dsl_filter() {
        let store = Store::open_in_memory("k").unwrap();
        let mut va = base_qso("va");
        va.state = Some("VA".to_string());
        va.band = Some("20m".to_string());
        store.upsert_qso(&va).unwrap();
        let mut tx = base_qso("tx");
        tx.state = Some("TX".to_string());
        tx.band = Some("40m".to_string());
        store.upsert_qso(&tx).unwrap();

        let summary = store.was_summary(&parse("band:20m")).unwrap();
        assert_eq!(summary.all_states, vec!["VA"]);
    }

    /// A timestamp inside the 2026 WAS250 window (early Jan 2026 UTC).
    const TS_2026: i64 = 1_767_300_000;

    #[test]
    fn was250_buckets_by_family_and_counts_pipeline() {
        let store = Store::open_in_memory("k").unwrap();
        // In-window rows.
        for (idx, (mode, state)) in [
            ("FT8", Some("VA")),        // Digital, valid
            ("CW", Some("va")),         // CW, valid (lowercase normalizes)
            ("SSB", Some("tx // TX")),  // Phone, valid (LoFi suffix stripped)
            ("FT8", Some("ZZ")),        // invalid state
        ]
        .iter()
        .enumerate()
        {
            let mut qso = base_qso(&format!("w{idx}"));
            qso.mode = Some((*mode).to_string());
            qso.state = state.map(str::to_string);
            qso.qso_date = TS_2026 + idx as i64;
            store.upsert_qso(&qso).unwrap();
        }
        // Metadata in-window with a state → counted in totals, excluded from sets.
        let mut meta = base_qso("wmeta");
        meta.mode = Some("WEATHER".to_string());
        meta.state = Some("CA".to_string());
        meta.qso_date = TS_2026 + 10;
        store.upsert_qso(&meta).unwrap();
        // Hidden in-window → excluded entirely.
        let mut hidden = base_qso("whid");
        hidden.state = Some("NY".to_string());
        hidden.is_hidden = true;
        hidden.qso_date = TS_2026 + 11;
        store.upsert_qso(&hidden).unwrap();
        // Out-of-window (2023) with a valid state → excluded entirely.
        let mut old = base_qso("wold");
        old.state = Some("FL".to_string()); // qso_date stays at the 2023 default
        store.upsert_qso(&old).unwrap();
        // In-window but NULL state → not fetched (state IS NOT NULL).
        let mut nostate = base_qso("wns");
        nostate.qso_date = TS_2026 + 12;
        store.upsert_qso(&nostate).unwrap();

        let was = store.was250(&parse("")).unwrap();
        assert_eq!(was.states_worked, vec!["TX", "VA"]);
        assert_eq!(was.cw_states, vec!["VA"]);
        assert_eq!(was.digital_states, vec!["VA"]);
        assert_eq!(was.phone_states, vec!["TX"]);
        // Fetched (non-hidden, 2026, state present): w0..w3 + meta = 5.
        assert_eq!(was.total_qsos, 5);
        assert_eq!(was.metadata_excluded, 1); // meta
        assert_eq!(was.with_state_field, 4); // w0..w3
        assert_eq!(was.with_valid_state, 3); // VA, VA, TX (not ZZ)
    }

    #[test]
    fn was250_window_excludes_other_years() {
        let store = Store::open_in_memory("k").unwrap();
        let mut in_2026 = base_qso("in");
        in_2026.state = Some("VA".to_string());
        in_2026.qso_date = TS_2026;
        store.upsert_qso(&in_2026).unwrap();
        let mut in_2023 = base_qso("out");
        in_2023.state = Some("TX".to_string()); // 2023 default timestamp
        store.upsert_qso(&in_2023).unwrap();
        // Exactly at the upper bound (2027-01-01) is excluded (`< end`).
        let mut at_end = base_qso("end");
        at_end.state = Some("CA".to_string());
        at_end.qso_date = 1_798_761_600;
        store.upsert_qso(&at_end).unwrap();

        let was = store.was250(&parse("")).unwrap();
        assert_eq!(was.states_worked, vec!["VA"]);
        assert_eq!(was.total_qsos, 1);
    }

    fn drilldown_row<'a>(
        rows: &'a [WasDrilldownRow],
        source: &str,
        mode: Option<&str>,
        state: &str,
    ) -> Option<&'a WasDrilldownRow> {
        rows.iter().find(|row| {
            row.source == source && row.mode.as_deref() == mode && row.state == state
        })
    }

    #[test]
    fn was_drilldown_splits_by_source_mode_state() {
        let store = Store::open_in_memory("k").unwrap();
        // VA on FT8 from QTH (no park).
        let mut a = base_qso("a");
        a.callsign = "K1AA".to_string();
        a.state = Some("VA".to_string());
        store.upsert_qso(&a).unwrap();
        // VA on CW at a park (not QTH).
        let mut b = base_qso("b");
        b.callsign = "K2BB".to_string();
        b.mode = Some("CW".to_string());
        b.state = Some("va".to_string()); // normalizes to VA
        b.park = Some("US-0001".to_string());
        store.upsert_qso(&b).unwrap();
        // TX on FT8 from QTH.
        let mut c = base_qso("c");
        c.callsign = "K3CC".to_string();
        c.state = Some("tx // Texas".to_string());
        store.upsert_qso(&c).unwrap();
        // Excluded: hidden, metadata, invalid state.
        let mut hidden = base_qso("h");
        hidden.state = Some("CA".to_string());
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut meta = base_qso("m");
        meta.state = Some("CA".to_string());
        meta.mode = Some("WEATHER".to_string());
        store.upsert_qso(&meta).unwrap();
        let mut invalid = base_qso("z");
        invalid.state = Some("ZZ".to_string());
        store.upsert_qso(&invalid).unwrap();

        let rows = store.was_drilldown(&parse("")).unwrap();

        // all / any mode / VA: both FT8 + CW.
        let all_va = drilldown_row(&rows, "all", None, "VA").unwrap();
        assert_eq!(all_va.count, 2);
        assert_eq!(all_va.callsigns, vec!["K1AA", "K2BB"]);
        // all / FT8 / VA: just the QTH one.
        assert_eq!(drilldown_row(&rows, "all", Some("FT8"), "VA").unwrap().count, 1);
        assert_eq!(drilldown_row(&rows, "all", Some("CW"), "VA").unwrap().count, 1);
        // qth / any / VA: only the FT8 QTH QSO (CW VA was at a park).
        let qth_va = drilldown_row(&rows, "qth", None, "VA").unwrap();
        assert_eq!(qth_va.count, 1);
        assert_eq!(qth_va.callsigns, vec!["K1AA"]);
        assert!(drilldown_row(&rows, "qth", Some("CW"), "VA").is_none());
        // TX appears under all + qth (it's a QTH QSO).
        assert_eq!(drilldown_row(&rows, "all", None, "TX").unwrap().count, 1);
        assert_eq!(drilldown_row(&rows, "qth", None, "TX").unwrap().count, 1);
        // No CA / ZZ leaked from hidden / metadata / invalid rows.
        assert!(drilldown_row(&rows, "all", None, "CA").is_none());
        assert!(drilldown_row(&rows, "all", None, "ZZ").is_none());
    }

    #[test]
    fn was_drilldown_respects_dsl_filter() {
        let store = Store::open_in_memory("k").unwrap();
        let mut va = base_qso("va");
        va.state = Some("VA".to_string());
        va.band = Some("20m".to_string());
        store.upsert_qso(&va).unwrap();
        let mut tx = base_qso("tx");
        tx.state = Some("TX".to_string());
        tx.band = Some("40m".to_string());
        store.upsert_qso(&tx).unwrap();

        let rows = store.was_drilldown(&parse("band:20m")).unwrap();
        assert!(drilldown_row(&rows, "all", None, "VA").is_some());
        assert!(drilldown_row(&rows, "all", None, "TX").is_none());
    }

    #[test]
    fn dxcc_worked_counts_and_labels_with_location() {
        let store = seed(); // a:291, b:291, c:1 visible; hidden/meta(291) excluded
        let worked = store.dxcc_worked(&parse("")).unwrap();
        assert_eq!(worked.len(), 2);
        // 291 (US) has 2, ordered first by count desc.
        assert_eq!(worked[0].dxcc_id, 291);
        assert_eq!(worked[0].count, 2);
        assert_eq!(worked[0].name, "United States");
        assert!((worked[0].latitude - 38.0).abs() < f64::EPSILON);
        assert!((worked[0].longitude - -97.0).abs() < f64::EPSILON);
        assert_eq!(worked[1].dxcc_id, 1);
        assert_eq!(worked[1].count, 1);
        assert_eq!(worked[1].name, "Canada");
    }

    fn presence(id: &str, service: &str, qso_id: &str, present: bool, needs: bool) -> ServicePresence {
        ServicePresence {
            id: id.to_string(),
            service_type_raw_value: service.to_string(),
            is_present: present,
            needs_upload: needs,
            upload_rejected: false,
            rejected_at_build: None,
            is_submitted: false,
            last_confirmed_at: None,
            park_reference: None,
            cloud_dirty_flag: false,
            qso_id: Some(qso_id.to_string()),
        }
    }

    fn seed_presence() -> Store {
        let store = Store::open_in_memory("k").unwrap();
        // q1 (W6JY), q2 (K9ZZ), qh (W6JY, hidden).
        let mut q1 = base_qso("q1");
        q1.my_callsign = Some("W6JY".to_string());
        store.upsert_qso(&q1).unwrap();
        let mut q2 = base_qso("q2");
        q2.callsign = "K2XX".to_string();
        q2.my_callsign = Some("K9ZZ".to_string());
        store.upsert_qso(&q2).unwrap();
        let mut qh = base_qso("qh");
        qh.my_callsign = Some("W6JY".to_string());
        qh.is_hidden = true;
        store.upsert_qso(&qh).unwrap();

        // qrz: present q1 (x2 dup), needs_upload q1 + q2; lotw: present q1;
        // pota: needs_upload on the hidden qh (must be excluded entirely).
        store.upsert_service_presence(&presence("p1", "qrz", "q1", true, false)).unwrap();
        store.upsert_service_presence(&presence("p2", "qrz", "q1", true, false)).unwrap();
        store.upsert_service_presence(&presence("p3", "qrz", "q2", false, true)).unwrap();
        store.upsert_service_presence(&presence("p4", "qrz", "q1", false, true)).unwrap();
        store.upsert_service_presence(&presence("p5", "lotw", "q1", true, false)).unwrap();
        store.upsert_service_presence(&presence("p6", "pota", "qh", false, true)).unwrap();
        store
    }

    #[test]
    fn service_presence_counts_dedup_and_primary_callsign() {
        let store = seed_presence();
        let configured = vec!["qrz".to_string()];
        let rows = store
            .service_presence_counts(&parse(""), Some("W6JY"), &configured)
            .unwrap();
        // pota is only on the hidden QSO → excluded; lotw < qrz alphabetically.
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].service, "lotw");
        assert_eq!(rows[0].uploaded, 1); // q1 present
        assert_eq!(rows[0].pending, 0); // lotw not configured
        assert_eq!(rows[1].service, "qrz");
        assert_eq!(rows[1].uploaded, 1); // q1 (dup collapses)
        // pending: q2 (K9ZZ) filtered out by primary; only q1 remains.
        assert_eq!(rows[1].pending, 1);
    }

    #[test]
    fn service_presence_counts_no_primary_counts_all_callsigns() {
        let store = seed_presence();
        let configured = vec!["qrz".to_string()];
        let rows = store
            .service_presence_counts(&parse(""), None, &configured)
            .unwrap();
        let qrz = rows.iter().find(|r| r.service == "qrz").unwrap();
        // No primary filter → both q1 and q2 count toward pending.
        assert_eq!(qrz.pending, 2);
    }

    #[test]
    fn service_presence_counts_unconfigured_has_no_pending() {
        let store = seed_presence();
        let rows = store
            .service_presence_counts(&parse(""), None, &[])
            .unwrap();
        assert!(rows.iter().all(|r| r.pending == 0));
        // uploaded still reported regardless of configuration.
        let qrz = rows.iter().find(|r| r.service == "qrz").unwrap();
        assert_eq!(qrz.uploaded, 1);
    }

    #[test]
    fn park_rollup_merges_activations_and_hunts() {
        let store = Store::open_in_memory("k").unwrap();
        let day1 = 1_700_000_000; // 2023-11-14 UTC
        let day2 = 1_700_100_000; // 2023-11-16 UTC (different day)
        // Activations of K-1 on two days (one a same-day dup), plus a combined K-1,K-2.
        let acts = [
            ("pa1", "K-1", day1),
            ("pa2", "K-1", day1),
            ("pa3", "K-1", day2),
            ("pa4", "K-1, K-2", day1),
        ];
        for (id, park, date) in acts {
            let mut qso = base_qso(id);
            qso.park = Some(park.to_string());
            qso.qso_date = date;
            store.upsert_qso(&qso).unwrap();
        }
        // Hunts: K-9 twice, K-1 once (latest timestamp overall).
        for (id, park, date) in [("h1", "K-9", day1), ("h2", "K-9", day1), ("h3", "K-1", 1_700_200_000)] {
            let mut qso = base_qso(id);
            qso.their_park = Some(park.to_string());
            qso.qso_date = date;
            store.upsert_qso(&qso).unwrap();
        }
        // Hidden + metadata excluded.
        let mut hidden = base_qso("hid");
        hidden.park = Some("K-1".to_string());
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();

        let rollup = store.qso_park_rollup(&parse("")).unwrap();
        let k1 = rollup.iter().find(|p| p.park == "K-1").unwrap();
        assert_eq!(k1.activation_days, 2); // day1 (dup collapses) + day2
        assert_eq!(k1.hunt_qsos, 1); // h3
        assert_eq!(k1.last_worked, 1_700_200_000); // the hunt is latest
        let k2 = rollup.iter().find(|p| p.park == "K-2").unwrap();
        assert_eq!(k2.activation_days, 1); // only via the combined pa4
        assert_eq!(k2.hunt_qsos, 0);
        let k9 = rollup.iter().find(|p| p.park == "K-9").unwrap();
        assert_eq!(k9.activation_days, 0);
        assert_eq!(k9.hunt_qsos, 2);
    }

    #[test]
    fn state_counts_groups_valid_states_only() {
        let store = Store::open_in_memory("k").unwrap();
        for (id, state) in [("a", Some("VA")), ("b", Some("va")), ("c", Some("tx // Texas")), ("d", Some("ZZ")), ("e", None)] {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.state = state.map(str::to_string);
            store.upsert_qso(&qso).unwrap();
        }
        let counts = store.qso_state_counts(&parse("")).unwrap();
        // VA x2 (a, b), TX x1 (c); ZZ invalid + null excluded. Ordered count desc.
        assert_eq!(counts.len(), 2);
        assert_eq!(counts[0].state, "VA");
        assert_eq!(counts[0].count, 2);
        assert_eq!(counts[1].state, "TX");
        assert_eq!(counts[1].count, 1);
    }

    fn base_session(id: &str) -> LoggingSession {
        LoggingSession {
            id: id.to_string(),
            my_callsign: "W6JY".to_string(),
            started_at: 1_700_000_000,
            ended_at: None,
            frequency: None,
            mode: "CW".to_string(),
            activation_type_raw_value: "pota".to_string(),
            programs_raw_value: "[]".to_string(),
            status_raw_value: "active".to_string(),
            park_reference: None,
            sota_reference: None,
            mission_reference: None,
            wwff_reference: None,
            my_grid: None,
            power: None,
            my_rig: None,
            notes: None,
            qso_comment: None,
            custom_title: None,
            qso_count: 0,
            spot_comments_data: None,
            is_rove: false,
            rove_stops_data: None,
            my_antenna: None,
            my_key: None,
            my_mic: None,
            extra_equipment: None,
            attendees: None,
            photo_filenames: "[]".to_string(),
            radio_item_id: None,
            station_callsign: None,
            operator_callsigns_raw_value: "[]".to_string(),
            solar_k_index: None,
            solar_flux: None,
            solar_sunspots: None,
            solar_propagation_rating: None,
            solar_a_index: None,
            solar_band_conditions: None,
            solar_timestamp: None,
            solar_conditions: None,
            weather_temperature_f: None,
            weather_temperature_c: None,
            weather_humidity: None,
            weather_wind_speed: None,
            weather_wind_direction: None,
            weather_description: None,
            weather_timestamp: None,
            weather: None,
            cloud_dirty_flag: false,
            contest_id: None,
            contest_category: None,
            contest_overlay_category: None,
            contest_power: None,
            contest_bands: None,
            contest_operator: None,
            activation_latitude: None,
            activation_longitude: None,
            activation_distance_miles: None,
            activation_elevation_gain_feet: None,
            ruck_weight_pounds: None,
            qrp_activation: false,
            with_pets: false,
            with_kids: false,
            winlink_sent: false,
            aprs_sent: false,
            varac_sent: false,
            adaptive_sport: false,
            track_points_data: None,
            tota_category_raw_value: None,
            personal_effort_factor: None,
            first_activation_of_tile_ever: false,
            winter_activation_override: None,
            tiles_activated_data: None,
            tota_t3_candidates_data: None,
            tota_t3_snapshot_at: None,
            tota_official_points: None,
        }
    }

    fn seed_equipment(store: &Store) {
        // s1, s2: IC-7300 + EFHW; s3: KX2 + Begali key, no antenna; s4: qso_count 0 (excluded).
        let sessions = [
            ("s1", Some("IC-7300"), Some("EFHW"), None, 10, 100),
            ("s2", Some("IC-7300"), Some("EFHW"), None, 5, 200),
            ("s3", Some("KX2"), None, Some("Begali"), 3, 300),
            ("s4", Some("IC-7300"), Some("Dipole"), None, 0, 400),
        ];
        for (id, rig, antenna, key, qsos, started) in sessions {
            let mut session = base_session(id);
            session.my_rig = rig.map(str::to_string);
            session.my_antenna = antenna.map(str::to_string);
            session.my_key = key.map(str::to_string);
            session.qso_count = qsos;
            session.started_at = started;
            store.upsert_logging_session(&session).unwrap();
        }
    }

    #[test]
    fn equipment_rollup_unpivots_and_excludes_empty_sessions() {
        let store = Store::open_in_memory("k").unwrap();
        seed_equipment(&store);
        let rollup = store.session_equipment_rollup().unwrap();
        let rig = rollup.iter().find(|r| r.kind == "radio" && r.name == "IC-7300").unwrap();
        assert_eq!(rig.session_count, 2); // s1, s2 (s4 has qso_count 0)
        assert_eq!(rig.total_qsos, 15);
        assert_eq!(rig.first_used, 100);
        assert_eq!(rig.last_used, 200);
        let antenna = rollup.iter().find(|r| r.kind == "antenna" && r.name == "EFHW").unwrap();
        assert_eq!(antenna.session_count, 2);
        let key = rollup.iter().find(|r| r.kind == "key" && r.name == "Begali").unwrap();
        assert_eq!(key.session_count, 1);
        // No Dipole row — only used by the excluded zero-QSO session.
        assert!(!rollup.iter().any(|r| r.name == "Dipole"));
    }

    #[test]
    fn combo_rollup_requires_rig_and_antenna() {
        let store = Store::open_in_memory("k").unwrap();
        seed_equipment(&store);
        let combos = store.session_combo_rollup().unwrap();
        assert_eq!(combos.len(), 1); // only IC-7300+EFHW (KX2 has no antenna)
        assert_eq!(combos[0].rig, "IC-7300");
        assert_eq!(combos[0].antenna, "EFHW");
        assert_eq!(combos[0].session_count, 2);
        assert_eq!(combos[0].total_qsos, 15);
    }

    /// Seed two sessions (IC-7300 rig, Begali key) with QSOs covering distance, a
    /// same-grid (0 km) contact, a second entity, and a metadata pseudo-mode.
    fn seed_item_detail(store: &Store) {
        let mut rig = base_session("sr");
        rig.my_rig = Some("IC-7300".to_string());
        rig.qso_count = 4;
        store.upsert_logging_session(&rig).unwrap();
        let mut key = base_session("sk");
        key.my_key = Some("Begali".to_string());
        key.qso_count = 1;
        store.upsert_logging_session(&key).unwrap();

        // IC-7300 QSOs.
        let mut q1 = base_qso("q1"); // 20m FT8, FN31→DM12 (~4012 km), dxcc 291
        q1.logging_session_id = Some("sr".to_string());
        q1.their_grid = Some("DM12".to_string());
        store.upsert_qso(&q1).unwrap();
        let mut q2 = base_qso("q2"); // 20m CW, FN31→FN31 (0 km, excluded from distance)
        q2.logging_session_id = Some("sr".to_string());
        q2.mode = Some("CW".to_string());
        q2.their_grid = Some("FN31".to_string());
        store.upsert_qso(&q2).unwrap();
        let mut q3 = base_qso("q3"); // 40m CW, FN31→EM12, dxcc 6
        q3.logging_session_id = Some("sr".to_string());
        q3.band = Some("40m".to_string());
        q3.mode = Some("CW".to_string());
        q3.dxcc = Some(6);
        store.upsert_qso(&q3).unwrap();
        let mut q4 = base_qso("q4"); // metadata → excluded entirely
        q4.logging_session_id = Some("sr".to_string());
        q4.mode = Some("WEATHER".to_string());
        store.upsert_qso(&q4).unwrap();

        // Begali QSO (must not leak into IC-7300).
        let mut q5 = base_qso("q5");
        q5.logging_session_id = Some("sk".to_string());
        store.upsert_qso(&q5).unwrap();
    }

    #[test]
    fn session_item_detail_aggregates_rig_qsos() {
        let store = Store::open_in_memory("k").unwrap();
        seed_item_detail(&store);
        let detail = store.session_item_detail("IC-7300").unwrap();

        assert_eq!(detail.total_qsos, 3); // q1, q2, q3 (q4 metadata excluded, q5 is Begali)
        assert_eq!(detail.unique_entities, 2); // 291, 6
        // Band: 20m (q1, q2) before 40m (q3).
        assert_eq!(
            detail.band_breakdown,
            vec![
                ItemTally { name: "20m".to_string(), count: 2 },
                ItemTally { name: "40m".to_string(), count: 1 },
            ]
        );
        // Mode: CW (q2, q3) before FT8 (q1).
        assert_eq!(
            detail.mode_breakdown,
            vec![
                ItemTally { name: "CW".to_string(), count: 2 },
                ItemTally { name: "FT8".to_string(), count: 1 },
            ]
        );
        // Distances: q1 (~4012 km) and q3 (>0) qualify; q2 (0 km) is excluded.
        let farthest = detail.farthest_km.unwrap();
        let shortest = detail.shortest_km.unwrap();
        let average = detail.average_km.unwrap();
        assert!(farthest >= shortest && shortest > 0.0);
        assert!((average - (farthest + shortest) / 2.0).abs() < 1e-6); // only two distances
        assert!((farthest - 4012.0).abs() < 200.0);
    }

    #[test]
    fn session_item_detail_isolates_by_item_and_handles_empty() {
        let store = Store::open_in_memory("k").unwrap();
        seed_item_detail(&store);

        // Begali key sees only its one QSO.
        let begali = store.session_item_detail("Begali").unwrap();
        assert_eq!(begali.total_qsos, 1);

        // Unknown item → zero everything, no distances.
        let none = store.session_item_detail("Nonexistent").unwrap();
        assert_eq!(none.total_qsos, 0);
        assert_eq!(none.unique_entities, 0);
        assert!(none.farthest_km.is_none());
        assert!(none.shortest_km.is_none());
        assert!(none.average_km.is_none());
        assert!(none.band_breakdown.is_empty());
        assert!(none.mode_breakdown.is_empty());
    }

    #[test]
    fn brag_period_metrics_computes_trivial_subset() {
        let store = Store::open_in_memory("k").unwrap();
        // q1: FT8 20m W1AW dxcc291 power5(QRP) rst599 park+their_park (P2P), day1
        let mut q1 = base_qso("q1");
        q1.power = Some(5);
        q1.rst_rcvd = Some("599".to_string());
        q1.park = Some("K-1".to_string());
        q1.their_park = Some("K-2".to_string());
        store.upsert_qso(&q1).unwrap();
        // q2: CW 40m K2XX dxcc1 power0(milliwatt) rst59, day2
        let mut q2 = base_qso("q2");
        q2.callsign = "K2XX".to_string();
        q2.band = Some("40m".to_string());
        q2.mode = Some("CW".to_string());
        q2.dxcc = Some(1);
        q2.power = Some(0);
        q2.rst_rcvd = Some("59".to_string());
        q2.qso_date = 1_700_100_000;
        store.upsert_qso(&q2).unwrap();
        // q3: SSB 20m W1AW, hunts K-2, day1
        let mut q3 = base_qso("q3");
        q3.mode = Some("SSB".to_string());
        q3.their_park = Some("K-2".to_string());
        store.upsert_qso(&q3).unwrap();
        // hidden + metadata excluded
        let mut hidden = base_qso("h");
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut meta = base_qso("m");
        meta.mode = Some("WEATHER".to_string());
        store.upsert_qso(&meta).unwrap();

        let metrics = store.brag_period_metrics(&parse("")).unwrap();
        assert_eq!(metrics.total_qsos, 3);
        assert_eq!(metrics.cw_qsos, 1);
        assert_eq!(metrics.phone_qsos, 1);
        assert_eq!(metrics.digital_qsos, 1);
        assert_eq!(metrics.operating_days, 2); // day1 (q1,q3) + day2 (q2)
        assert_eq!(metrics.active_bands, 2); // 20m, 40m
        assert_eq!(metrics.unique_callsigns, 2); // W1AW, K2XX
        assert_eq!(metrics.dxcc_entities, 2); // 291, 1
        assert_eq!(metrics.qrp_qsos, 2); // q1 (5) + q2 (0)
        assert_eq!(metrics.milliwatt_qsos, 1); // q2 (0)
        assert_eq!(metrics.parks_hunted, 1); // K-2 (q1, q3)
        assert_eq!(metrics.park_to_park, 1); // q1
        assert_eq!(metrics.perfect_reports, 2); // q1 599, q2 59
    }

    #[test]
    fn count_by_month_is_chronological_utc() {
        let store = seed();
        let rows = store
            .qso_count_by(&parse(""), AggregateDimension::Month)
            .unwrap();
        assert!(!rows.is_empty());
        // keys are sorted ascending YYYY-MM
        let keys: Vec<&str> = rows.iter().map(|r| r.key.as_str()).collect();
        let mut sorted = keys.clone();
        sorted.sort_unstable();
        assert_eq!(keys, sorted);
    }

    /// Seed QSOs spanning distance / power / mode / RST variety (all from FN31):
    /// A far high-power FT8, a medium QRP CW, a near QRP CW with a perfect report, a
    /// same-grid milliwatt FT8, plus an excluded hidden + metadata QSO.
    fn seed_distance(store: &Store) {
        let mut far = base_qso("a"); // 20m FT8, DM12 (~4012 km), 100 W
        far.callsign = "A1".to_string();
        far.their_grid = Some("DM12".to_string());
        far.power = Some(100);
        store.upsert_qso(&far).unwrap();

        let mut medium = base_qso("b"); // 20m CW, EM12 (~2400 km), 5 W (QRP)
        medium.callsign = "B1".to_string();
        medium.mode = Some("CW".to_string());
        medium.their_grid = Some("EM12".to_string());
        medium.power = Some(5);
        store.upsert_qso(&medium).unwrap();

        let mut near = base_qso("c"); // 40m CW, FN30 (~100 km), 5 W, perfect report
        near.callsign = "C1".to_string();
        near.band = Some("40m".to_string());
        near.mode = Some("CW".to_string());
        near.their_grid = Some("FN30".to_string());
        near.power = Some(5);
        near.rst_rcvd = Some("599".to_string());
        store.upsert_qso(&near).unwrap();

        let mut same = base_qso("d"); // 20m FT8, FN31 (0 km), 1 W
        same.callsign = "D1".to_string();
        same.their_grid = Some("FN31".to_string());
        same.power = Some(1);
        store.upsert_qso(&same).unwrap();

        let mut hidden = base_qso("h");
        hidden.callsign = "HID".to_string();
        hidden.their_grid = Some("DM12".to_string());
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut meta = base_qso("m");
        meta.mode = Some("WEATHER".to_string());
        meta.their_grid = Some("DM12".to_string());
        store.upsert_qso(&meta).unwrap();
    }

    #[test]
    fn brag_distance_stats_selects_records() {
        let store = Store::open_in_memory("k").unwrap();
        seed_distance(&store);
        let stats = store.brag_distance_stats(&parse("")).unwrap();

        // Furthest overall: A1 (DM12), on 20m.
        let furthest = stats.furthest.unwrap();
        assert_eq!(furthest.callsign, "A1");
        assert_eq!(furthest.band, "20m");
        // QRP / CW / CW+QRP furthest: B1 (EM12 beats the near FN30).
        assert_eq!(stats.furthest_qrp.unwrap().callsign, "B1");
        assert_eq!(stats.furthest_cw.unwrap().callsign, "B1");
        assert_eq!(stats.furthest_cw_qrp.unwrap().callsign, "B1");
        // Perfect-report furthest: only C1 has 599.
        assert_eq!(stats.furthest_perfect_rst.unwrap().callsign, "C1");
        // Per band: 20m winner A1 (DM12) ahead of 40m winner C1.
        assert_eq!(stats.furthest_per_band.len(), 2);
        assert_eq!(stats.furthest_per_band[0].band, "20m");
        assert_eq!(stats.furthest_per_band[0].callsign, "A1");
        assert_eq!(stats.furthest_per_band[1].band, "40m");
        assert_eq!(stats.furthest_per_band[1].callsign, "C1");
        // Average over four computable distances (incl. the 0-km same-grid contact).
        assert!(stats.average_km.unwrap() > 0.0);
        // Lowest power (> 0): D1 at 1 W, same-grid → distance 0.
        let lowest = stats.lowest_power.unwrap();
        assert_eq!(lowest.watts, 1);
        assert_eq!(lowest.callsign, "D1");
        // Best watts-per-mile: B1 (5 W over ~2400 km beats 100 W far and the tiny-distance ones).
        assert_eq!(stats.best_watts_per_mile.unwrap().callsign, "B1");
    }

    #[test]
    fn brag_distance_stats_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        let stats = store.brag_distance_stats(&parse("")).unwrap();
        assert!(stats.furthest.is_none());
        assert!(stats.furthest_qrp.is_none());
        assert!(stats.furthest_cw.is_none());
        assert!(stats.furthest_cw_qrp.is_none());
        assert!(stats.furthest_perfect_rst.is_none());
        assert!(stats.furthest_per_band.is_empty());
        assert!(stats.average_km.is_none());
        assert!(stats.lowest_power.is_none());
        assert!(stats.best_watts_per_mile.is_none());
    }

    /// Noon-UTC unix timestamp for a calendar day (so it buckets unambiguously).
    fn day_ts(year: i32, month: u32, day: u32) -> i64 {
        chrono::NaiveDate::from_ymd_opt(year, month, day)
            .unwrap()
            .and_hms_opt(12, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp()
    }

    fn day(year: i32, month: u32, day: u32) -> chrono::NaiveDate {
        chrono::NaiveDate::from_ymd_opt(year, month, day).unwrap()
    }

    /// Unix timestamp at a specific UTC hour of a calendar day (for time-of-day tests).
    fn ts_at(year: i32, month: u32, day: u32, hour: u32) -> i64 {
        chrono::NaiveDate::from_ymd_opt(year, month, day)
            .unwrap()
            .and_hms_opt(hour, 0, 0)
            .unwrap()
            .and_utc()
            .timestamp()
    }

    #[test]
    fn brag_streaks_on_air_and_modes() {
        let store = Store::open_in_memory("k").unwrap();
        // CW on 06-20, 06-21; FT8 (Digital) on 06-10, 06-19, 06-21.
        let rows = [
            ("c1", "CW", day_ts(2026, 6, 20)),
            ("c2", "CW", day_ts(2026, 6, 21)),
            ("f1", "FT8", day_ts(2026, 6, 19)),
            ("f2", "FT8", day_ts(2026, 6, 21)),
            ("f3", "FT8", day_ts(2026, 6, 10)),
        ];
        for (id, mode, ts) in rows {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.mode = Some(mode.to_string());
            qso.qso_date = ts;
            store.upsert_qso(&qso).unwrap();
        }

        let streaks = store.brag_streaks(&parse(""), day(2026, 6, 21)).unwrap();
        // On-air days {06-10, 06-19, 06-20, 06-21}: longest run is the 3-day tail ending today.
        assert_eq!(streaks.on_air, StreakValue { current: 3, longest: 3 });
        assert!(streaks.activation.is_none()); // no park QSOs
        // CW {06-20, 06-21} consecutive → 2; Digital {06-10, 06-19, 06-21} isolated → 1.
        assert_eq!(
            streaks.modes,
            vec![
                ModeStreak { mode: "CW".to_string(), current: 2, longest: 2 },
                ModeStreak { mode: "Digital".to_string(), current: 1, longest: 1 },
            ]
        );
    }

    #[test]
    fn brag_streaks_activation_requires_ten_unique() {
        let store = Store::open_in_memory("k").unwrap();
        // 06-21: 10 unique park QSOs (qualifies). 06-20: only 3 (does not).
        for idx in 0..10 {
            let mut qso = base_qso(&format!("q21_{idx}"));
            qso.callsign = format!("CALL{idx}");
            qso.park = Some("US-0001".to_string());
            qso.qso_date = day_ts(2026, 6, 21);
            store.upsert_qso(&qso).unwrap();
        }
        for idx in 0..3 {
            let mut qso = base_qso(&format!("q20_{idx}"));
            qso.callsign = format!("DX{idx}");
            qso.park = Some("US-0001".to_string());
            qso.qso_date = day_ts(2026, 6, 20);
            store.upsert_qso(&qso).unwrap();
        }

        let streaks = store.brag_streaks(&parse(""), day(2026, 6, 21)).unwrap();
        // Only 06-21 qualifies → a 1-day activation streak ending today.
        assert_eq!(streaks.activation, Some(StreakValue { current: 1, longest: 1 }));
    }

    #[test]
    fn brag_streaks_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        let streaks = store.brag_streaks(&parse(""), day(2026, 6, 21)).unwrap();
        assert_eq!(streaks.on_air, StreakValue { current: 0, longest: 0 });
        assert!(streaks.activation.is_none());
        assert!(streaks.modes.is_empty());
    }

    #[test]
    fn brag_geographic_counts() {
        let store = Store::open_in_memory("k").unwrap();
        // 291=NA(+VA), 1=NA, 223=EU, 339=AS. 06-21 carries NA+EU+AS; 06-20 only NA.
        let rows = [
            ("g1", 291, Some("VA"), "FN31", day_ts(2026, 6, 21)),
            ("g2", 1, None, "FN20", day_ts(2026, 6, 20)),
            ("g3", 223, None, "IO91", day_ts(2026, 6, 21)),
            ("g4", 339, None, "PM95", day_ts(2026, 6, 21)),
        ];
        for (id, dxcc, state, grid, ts) in rows {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.dxcc = Some(dxcc);
            qso.state = state.map(str::to_string);
            qso.their_grid = Some(grid.to_string());
            qso.qso_date = ts;
            store.upsert_qso(&qso).unwrap();
        }

        let geo = store.brag_geographic(&parse("")).unwrap();
        assert_eq!(geo.dxcc_entities, 4);
        assert_eq!(geo.states_provinces, 1); // only VA is a valid state
        assert_eq!(geo.was_states, 1); // VA on USA (291)
        assert_eq!(geo.grid_squares, 4); // FN31, FN20, IO91, PM95
        assert_eq!(geo.continents, 3); // NA, EU, AS
        assert_eq!(geo.most_continents_day, 3); // 06-21: NA+EU+AS
        assert_eq!(geo.new_dxcc_entities, 4); // empty query → period is all-time, all new
    }

    #[test]
    fn brag_new_dxcc_excludes_pre_period() {
        let store = Store::open_in_memory("k").unwrap();
        // 291 first worked in 2025 (before the period); 1 and 223 first worked in 2026.
        let rows = [
            ("p0", 291, day_ts(2025, 12, 1)),
            ("p1", 291, day_ts(2026, 3, 1)),
            ("p2", 1, day_ts(2026, 3, 2)),
            ("p3", 223, day_ts(2026, 4, 1)),
        ];
        for (id, dxcc, ts) in rows {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.dxcc = Some(dxcc);
            qso.qso_date = ts;
            store.upsert_qso(&qso).unwrap();
        }

        let geo = store.brag_geographic(&parse("date:2026")).unwrap();
        assert_eq!(geo.dxcc_entities, 3); // 291, 1, 223 all have a 2026 QSO
        // 291's all-time earliest is 2025 (< period start) → not new; 1 and 223 are new.
        assert_eq!(geo.new_dxcc_entities, 2);
    }

    #[test]
    fn brag_geographic_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        let geo = store.brag_geographic(&parse("")).unwrap();
        assert_eq!(geo.dxcc_entities, 0);
        assert_eq!(geo.new_dxcc_entities, 0);
        assert_eq!(geo.states_provinces, 0);
        assert_eq!(geo.grid_squares, 0);
        assert_eq!(geo.continents, 0);
        assert_eq!(geo.most_continents_day, 0);
        assert_eq!(geo.was_states, 0);
    }

    #[test]
    fn brag_pota_aggregates() {
        let store = Store::open_in_memory("k").unwrap();
        // US-0001 on 06-21: 10 unique QSOs (activates). US-0002 on 06-21: 3 (does not).
        // One P2P (their_park set), one hunt-only (their_park, no park).
        for idx in 0..10 {
            let mut qso = base_qso(&format!("a{idx}"));
            qso.callsign = format!("CALL{idx}");
            qso.park = Some("US-0001".to_string());
            qso.qso_date = day_ts(2026, 6, 21);
            store.upsert_qso(&qso).unwrap();
        }
        for idx in 0..3 {
            let mut qso = base_qso(&format!("b{idx}"));
            qso.callsign = format!("DX{idx}");
            qso.park = Some("US-0002".to_string());
            qso.qso_date = day_ts(2026, 6, 20);
            store.upsert_qso(&qso).unwrap();
        }
        // P2P: own a park + worked their park. Hunt-only: just their park.
        let mut p2p = base_qso("p2p");
        p2p.callsign = "P2PCALL".to_string();
        p2p.park = Some("US-0001".to_string());
        p2p.their_park = Some("US-9000".to_string());
        p2p.qso_date = day_ts(2026, 6, 21);
        store.upsert_qso(&p2p).unwrap();
        let mut hunt = base_qso("hunt");
        hunt.callsign = "HUNTCALL".to_string();
        hunt.park = None;
        hunt.their_park = Some("US-9001".to_string());
        hunt.qso_date = day_ts(2026, 6, 21);
        store.upsert_qso(&hunt).unwrap();

        let pota = store.brag_pota(&parse("")).unwrap();
        // US-0001's 06-21 group has 11 unique QSOs (10 + the P2P) → activated; US-0002 only 3.
        assert_eq!(pota.parks_activated, 1);
        // Distinct their_park: US-9000, US-9001.
        assert_eq!(pota.parks_hunted, 2);
        // Only the P2P QSO has both columns.
        assert_eq!(pota.park_to_park, 1);
        // Best activation: US-0001 on 06-21 with 11 raw QSOs.
        let best = pota.best_activation.unwrap();
        assert_eq!(best.park, "US-0001");
        assert_eq!(best.day, "2026-06-21");
        assert_eq!(best.count, 11);
    }

    #[test]
    fn brag_new_parks_excludes_pre_period() {
        let store = Store::open_in_memory("k").unwrap();
        // US-0001 first activated in 2025 (before the period); US-0002 first worked in 2026.
        // US-9000 first HUNTED in 2025 (before); US-9001 first hunted in 2026.
        let parked = [("k0", "US-0001", day_ts(2025, 12, 1)), ("k1", "US-0001", day_ts(2026, 3, 1)),
            ("k2", "US-0002", day_ts(2026, 3, 2))];
        for (id, park, ts) in parked {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.park = Some(park.to_string());
            qso.qso_date = ts;
            store.upsert_qso(&qso).unwrap();
        }
        let hunted = [("h0", "US-9000", day_ts(2025, 11, 1)), ("h1", "US-9000", day_ts(2026, 4, 1)),
            ("h2", "US-9001", day_ts(2026, 4, 2))];
        for (id, their, ts) in hunted {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.park = None;
            qso.their_park = Some(their.to_string());
            qso.qso_date = ts;
            store.upsert_qso(&qso).unwrap();
        }

        let pota = store.brag_pota(&parse("date:2026")).unwrap();
        // Period parks: US-0001, US-0002 (activated) + US-9000, US-9001 (hunted).
        // New: US-0002 + US-9001 (US-0001 & US-9000 predate the period).
        assert_eq!(pota.new_parks, 2);
    }

    #[test]
    fn brag_pota_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        let pota = store.brag_pota(&parse("")).unwrap();
        assert_eq!(pota.parks_activated, 0);
        assert_eq!(pota.parks_hunted, 0);
        assert_eq!(pota.park_to_park, 0);
        assert!(pota.best_activation.is_none());
        assert_eq!(pota.new_parks, 0);
    }

    #[test]
    fn brag_records_aggregates() {
        let store = Store::open_in_memory("k").unwrap();
        // 2026-06-19 is a Friday, 06-20 Saturday. Session s1 has 3 QSOs on 06-19;
        // an unsessioned QSO on 06-20. W1AW worked twice (repeat customer).
        let rows = [
            // id, call, band, mode, session, dxcc, ts
            ("r1", "W1AW", "20m", "FT8", Some("s1"), 291, ts_at(2026, 6, 19, 8)),
            ("r2", "K2XX", "20m", "CW", Some("s1"), 1, ts_at(2026, 6, 19, 9)),
            ("r3", "W1AW", "40m", "CW", Some("s1"), 291, ts_at(2026, 6, 19, 23)),
            ("r4", "N3ZZ", "20m", "SSB", None, 223, ts_at(2026, 6, 20, 1)),
        ];
        for (id, call, band, mode, session, dxcc, ts) in rows {
            let mut qso = base_qso(id);
            qso.callsign = call.to_string();
            qso.band = Some(band.to_string());
            qso.mode = Some(mode.to_string());
            qso.logging_session_id = session.map(str::to_string);
            qso.dxcc = Some(dxcc);
            qso.their_grid = Some("EM12".to_string());
            qso.qso_date = ts;
            store.upsert_qso(&qso).unwrap();
        }

        let rec = store.brag_records(&parse("")).unwrap();
        assert_eq!(rec.most_qsos_day, 3); // 06-19 has r1,r2,r3
        assert_eq!(rec.most_qsos_session, 3); // s1
        assert_eq!(rec.most_countries_day, 2); // 06-19: {291, 1}
        assert_eq!(rec.most_bands_day, 2); // 06-19: {20m, 40m}
        assert_eq!(rec.most_active_weekday, Some(ItemTally { name: "Fri".to_string(), count: 3 }));
        assert_eq!(rec.busiest_band, Some(ItemTally { name: "20m".to_string(), count: 3 }));
        // Modes: FT8(1), CW(2), SSB→Phone canonical(1). Busiest canonical mode = CW (2).
        assert_eq!(rec.busiest_mode.as_ref().map(|tally| tally.count), Some(2));
        assert_eq!(rec.repeat_customer, Some(ItemTally { name: "W1AW".to_string(), count: 2 }));
        // Earliest time-of-day: r3 r4? r4 at 01:00 is closest to midnight; latest: r3 at 23:00.
        assert_eq!(rec.earliest_qso, Some(ts_at(2026, 6, 20, 1)));
        assert_eq!(rec.latest_qso, Some(ts_at(2026, 6, 19, 23)));
        assert!(rec.total_distance_km.unwrap() > 0.0);
        assert!(rec.active_modes >= 3); // FT8, CW, SSB-canonical (+ distinct names)
    }

    #[test]
    fn brag_session_stats_folds_sessions() {
        let store = Store::open_in_memory("k").unwrap();
        // Session sa: 10 QSOs one minute apart at a park (US-0001) on 06-19 → fastest-10 and
        // fastest-activation = 9 min (540 s); also a 2nd park later for an Nfer of 2.
        for idx in 0..10 {
            let mut qso = base_qso(&format!("a{idx}"));
            qso.callsign = format!("CALL{idx}");
            qso.logging_session_id = Some("sa".to_string());
            qso.park = Some("US-0001".to_string());
            qso.qso_date = ts_at(2026, 6, 19, 12) + i64::from(idx) * 60;
            store.upsert_qso(&qso).unwrap();
        }
        // Same session, a second park (for largest_nfer = 2), 5 minutes after the 10th.
        let mut extra = base_qso("a_p2");
        extra.callsign = "P2CALL".to_string();
        extra.logging_session_id = Some("sa".to_string());
        extra.park = Some("US-0002".to_string());
        extra.qso_date = ts_at(2026, 6, 19, 12) + 14 * 60; // within the 15-min gap
        store.upsert_qso(&extra).unwrap();

        let stats = store.brag_session_stats(&parse("")).unwrap();
        // Session span: first at +0, last at +14min → 840 s.
        assert_eq!(stats.longest_session_seconds, Some(840.0));
        // Fastest 10 consecutive (the first 10, 1 min apart) → 540 s.
        assert_eq!(stats.fastest_ten_seconds, Some(540.0));
        // Fastest activation (park US-0001, 10 QSOs) → 540 s.
        assert_eq!(stats.fastest_activation_seconds, Some(540.0));
        // Largest Nfer: 2 parks in session sa.
        assert_eq!(stats.largest_nfer, 2);
        // Operating: all 11 QSOs within ≤15-min gaps → 840 s active (one session).
        assert_eq!(stats.operating_seconds, Some(840.0));
        // Peak 15-min window covers all 11 (spread over 14 min).
        assert_eq!(stats.peak_15_min_count, 11);
        // Best session rate: 11 QSOs over 840 s active = 11 / (840/3600) ≈ 47.14/hr.
        let rate = stats.best_session_rate.unwrap();
        assert!((rate - 11.0 / (840.0 / 3_600.0)).abs() < 1e-6, "rate {rate}");
    }

    #[test]
    fn brag_session_stats_single_qso_floor() {
        let store = Store::open_in_memory("k").unwrap();
        let mut qso = base_qso("solo");
        qso.qso_date = ts_at(2026, 6, 19, 12);
        store.upsert_qso(&qso).unwrap();
        let stats = store.brag_session_stats(&parse("")).unwrap();
        assert_eq!(stats.operating_seconds, Some(60.0)); // lone QSO floored at 60 s
        assert!(stats.fastest_ten_seconds.is_none()); // < 10 QSOs
        assert!(stats.best_session_rate.is_none());
        assert!(stats.longest_session_seconds.is_none()); // span 0
        assert_eq!(stats.peak_15_min_count, 1);
        assert_eq!(stats.largest_nfer, 0); // no park
    }

    #[test]
    fn brag_session_stats_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        let stats = store.brag_session_stats(&parse("")).unwrap();
        assert!(stats.operating_seconds.is_none());
        assert!(stats.fastest_ten_seconds.is_none());
        assert!(stats.best_session_rate.is_none());
        assert!(stats.fastest_activation_seconds.is_none());
        assert!(stats.longest_session_seconds.is_none());
        assert_eq!(stats.peak_15_min_count, 0);
        assert_eq!(stats.largest_nfer, 0);
    }

    #[test]
    fn date_window_bounds_brag_aggregates() {
        let store = Store::open_in_memory("k").unwrap();
        // Three QSOs on distinct days; the window selects only the middle one.
        for (id, day) in [("w1", 18u32), ("w2", 20), ("w3", 22)] {
            let mut qso = base_qso(id);
            qso.callsign = id.to_uppercase();
            qso.qso_date = ts_at(2026, 6, day, 12);
            store.upsert_qso(&qso).unwrap();
        }
        // Inclusive window [06-19 00:00, 06-21 00:00] → only w2 (06-20).
        let windowed = parse("").with_date_window(Some(ts_at(2026, 6, 19, 0)), Some(ts_at(2026, 6, 21, 0)));
        assert_eq!(store.qso_distinct_counts(&windowed).unwrap().qsos, 1);
        assert_eq!(store.brag_records(&windowed).unwrap().most_qsos_day, 1);
        // Unbounded sees all three.
        assert_eq!(store.qso_distinct_counts(&parse("")).unwrap().qsos, 3);
    }

    #[test]
    fn brag_records_empty_store() {
        let store = Store::open_in_memory("k").unwrap();
        let rec = store.brag_records(&parse("")).unwrap();
        assert_eq!(rec.most_qsos_day, 0);
        assert_eq!(rec.most_qsos_session, 0);
        assert!(rec.most_active_weekday.is_none());
        assert!(rec.busiest_band.is_none());
        assert!(rec.repeat_customer.is_none());
        assert!(rec.earliest_qso.is_none());
        assert!(rec.total_distance_km.is_none());
        assert_eq!(rec.active_modes, 0);
    }

    #[test]
    fn brag_average_rst_averages_strength_digit() {
        let store = Store::open_in_memory("k").unwrap();
        // "599" → 9, "59" → 9, "5" → skipped (< 2 chars), None → skipped. Avg = 9.0.
        let reports: [(&str, Option<&str>); 4] = [
            ("g1", Some("599")),
            ("g2", Some("59")),
            ("g3", Some("5")),
            ("g4", None),
        ];
        for (id, rst) in reports {
            let mut qso = base_qso(id);
            qso.rst_rcvd = rst.map(str::to_string);
            store.upsert_qso(&qso).unwrap();
        }
        let avg = store.brag_average_rst(&parse("")).unwrap().unwrap();
        assert!((avg - 9.0).abs() < 1e-6, "avg {avg}");

        // A mix that averages to 8.0: "579" → 7, "59" → 9 → mean 8.
        let store2 = Store::open_in_memory("k").unwrap();
        let mut lo = base_qso("lo");
        lo.rst_rcvd = Some("579".to_string());
        store2.upsert_qso(&lo).unwrap();
        let mut hi = base_qso("hi");
        hi.rst_rcvd = Some("59".to_string());
        store2.upsert_qso(&hi).unwrap();
        let avg2 = store2.brag_average_rst(&parse("")).unwrap().unwrap();
        assert!((avg2 - 8.0).abs() < 1e-6, "avg2 {avg2}");

        // No qualifying QSO → None.
        let empty = Store::open_in_memory("k").unwrap();
        assert!(empty.brag_average_rst(&parse("")).unwrap().is_none());
    }

    #[test]
    fn worked_member_callsigns_distinct_upper_sorted() {
        let store = Store::open_in_memory("k").unwrap();
        // Seed QSOs (callsign casing varied; W1AW worked twice to prove DISTINCT).
        for (id, call) in [("w1", "w1aw"), ("w2", "W1AW"), ("w3", "K2XX"), ("w4", "N3ZZ")] {
            let mut qso = base_qso(id);
            qso.callsign = call.to_string();
            store.upsert_qso(&qso).unwrap();
        }
        // Members include matches (mixed case) and a non-worked one.
        let members = vec![
            "w1aw".to_string(),
            "k2xx".to_string(),
            "DX0NE".to_string(),
        ];
        let worked = store.worked_member_callsigns(&parse(""), &members).unwrap();
        // Distinct, uppercased, sorted ascending. N3ZZ is worked but not a member → excluded.
        assert_eq!(worked, vec!["K2XX".to_string(), "W1AW".to_string()]);

        // Empty members → empty vec (no `IN ()`).
        let none = store.worked_member_callsigns(&parse(""), &[]).unwrap();
        assert!(none.is_empty());
    }

    // ---- Task 6: compute_configured_brag ----

    /// Seed ~8 QSOs spanning distance/power/park/streak variety across 3 consecutive UTC
    /// days (06-19, 06-20, 06-21 = "today"), plus a hidden + metadata row (excluded
    /// everywhere). All QSOs originate from `FN31` (the `base_qso` default `my_grid`).
    fn seed_configured_brag(store: &Store) {
        // Day 1 (06-19): CW, QRP (5W), far contact (DM12 ~ 4012 km), perfect report.
        let mut d1 = base_qso("d1");
        d1.callsign = "A1CALL".to_string();
        d1.mode = Some("CW".to_string());
        d1.their_grid = Some("DM12".to_string());
        d1.power = Some(5);
        d1.rst_rcvd = Some("599".to_string());
        d1.qso_date = day_ts(2026, 6, 19);
        store.upsert_qso(&d1).unwrap();

        // Day 2 (06-20): FT8, park activation with 10 unique QSOs (qualifies as "activated").
        for idx in 0..10 {
            let mut qso = base_qso(&format!("d2_{idx}"));
            qso.callsign = format!("PARK{idx}");
            qso.mode = Some("FT8".to_string());
            qso.park = Some("US-1234".to_string());
            qso.their_grid = Some("EM12".to_string());
            qso.qso_date = day_ts(2026, 6, 20);
            store.upsert_qso(&qso).unwrap();
        }

        // Day 3 (06-21, "today"): SSB, same-grid (0 km), high power, DXCC + state.
        let mut d3 = base_qso("d3");
        d3.callsign = "B2CALL".to_string();
        d3.mode = Some("SSB".to_string());
        d3.their_grid = Some("FN31".to_string());
        d3.power = Some(100);
        d3.dxcc = Some(291);
        d3.state = Some("VA".to_string());
        d3.qso_date = day_ts(2026, 6, 21);
        store.upsert_qso(&d3).unwrap();

        // Hidden + metadata rows — must never leak into any stat.
        let mut hidden = base_qso("hid");
        hidden.callsign = "HIDDEN".to_string();
        hidden.their_grid = Some("QQ99".to_string());
        hidden.is_hidden = true;
        store.upsert_qso(&hidden).unwrap();
        let mut meta = base_qso("met");
        meta.callsign = "META".to_string();
        meta.mode = Some("WEATHER".to_string());
        meta.their_grid = Some("QQ99".to_string());
        store.upsert_qso(&meta).unwrap();
    }

    #[test]
    fn compute_configured_brag_all_58_stats_no_panic() {
        let store = Store::open_in_memory("k").unwrap();
        seed_configured_brag(&store);
        let enabled = cw_domain::brag_sheet::BragStatType::all();
        assert_eq!(enabled.len(), 58);

        let results = store.compute_configured_brag(&parse(""), &enabled, day(2026, 6, 21)).unwrap();
        assert_eq!(results.len(), 58);
        // Order mirrors `enabled` (== declaration order).
        for (idx, (stat, _)) in results.iter().enumerate() {
            assert_eq!(*stat, enabled[idx]);
        }
    }

    #[test]
    fn compute_configured_brag_known_values() {
        use cw_domain::brag_sheet::{BragStatType, BragStatValue};

        let store = Store::open_in_memory("k").unwrap();
        seed_configured_brag(&store);
        let enabled = vec![
            BragStatType::TotalQsos,
            BragStatType::FurthestContact,
            BragStatType::ParksActivated,
            BragStatType::CurrentOnAirStreak,
            BragStatType::AverageContactDistance,
            BragStatType::QrpQsoCount,
            BragStatType::DxccEntities,
            BragStatType::FastestCwSpeed,
            BragStatType::ClubMembersWorked,
        ];
        let results = store.compute_configured_brag(&parse(""), &enabled, day(2026, 6, 21)).unwrap();
        let get = |stat: BragStatType| results.iter().find(|(s, _)| *s == stat).unwrap().1.clone();

        // 12 visible QSOs: d1, d3, + 10 park QSOs (hidden + metadata excluded).
        assert_eq!(get(BragStatType::TotalQsos), BragStatValue::Count(12));

        // Furthest contact: d1 to A1CALL at DM12 (~4012 km) beats the park QSOs (EM12) and
        // the same-grid SSB QSO (0 km).
        match get(BragStatType::FurthestContact) {
            BragStatValue::Contact { callsign, distance_km, .. } => {
                assert_eq!(callsign, "A1CALL");
                assert!(distance_km.unwrap() > 3_000.0);
            }
            other => panic!("expected Contact, got {other:?}"),
        }

        // Parks activated: US-1234 has 10 unique QSOs on 06-20 → 1 park activated.
        assert_eq!(get(BragStatType::ParksActivated), BragStatValue::Count(1));

        // On-air streak: QSOs on 06-19, 06-20, 06-21 ("today") → a 3-day streak.
        assert_eq!(
            get(BragStatType::CurrentOnAirStreak),
            BragStatValue::Streak { current: 3, longest: 3 }
        );

        // Average distance > 0 (mix of the far DM12 contact, 0-km SSB, and EM12 park QSOs).
        match get(BragStatType::AverageContactDistance) {
            BragStatValue::Distance { km } => assert!(km > 0.0),
            other => panic!("expected Distance, got {other:?}"),
        }

        // QRP count: only d1 (5 W) — the park QSOs and d3 (100 W) don't qualify.
        assert_eq!(get(BragStatType::QrpQsoCount), BragStatValue::Count(1));

        // DXCC entities: only d3 carries a DXCC id (291); park/CW QSOs have none.
        assert_eq!(get(BragStatType::DxccEntities), BragStatValue::Count(1));

        // Documented gaps: always NoData (no Rust source at this layer).
        assert_eq!(get(BragStatType::FastestCwSpeed), BragStatValue::NoData);
        assert_eq!(get(BragStatType::ClubMembersWorked), BragStatValue::NoData);
    }

    #[test]
    fn compute_configured_brag_empty_store_is_all_no_data() {
        let store = Store::open_in_memory("k").unwrap();
        let enabled = cw_domain::brag_sheet::BragStatType::all();
        let results = store.compute_configured_brag(&parse(""), &enabled, day(2026, 6, 21)).unwrap();
        assert_eq!(results.len(), 58);
        assert!(results.iter().all(|(_, value)| *value == cw_domain::brag_sheet::BragStatValue::NoData));
    }

    #[test]
    fn compute_configured_brag_respects_dsl_filter_and_order() {
        use cw_domain::brag_sheet::{BragStatType, BragStatValue};

        let store = Store::open_in_memory("k").unwrap();
        seed_configured_brag(&store);
        // Filter to CW only: just d1 (the far QRP contact).
        let enabled = vec![BragStatType::TotalCwQsos, BragStatType::TotalQsos];
        let results = store.compute_configured_brag(&parse("mode:CW"), &enabled, day(2026, 6, 21)).unwrap();
        assert_eq!(results[0], (BragStatType::TotalCwQsos, BragStatValue::Count(1)));
        assert_eq!(results[1], (BragStatType::TotalQsos, BragStatValue::Count(1)));
    }

    #[test]
    fn format_duration_label_truncates_like_swift() {
        // Swift's `formatDuration` truncates via `Int(seconds)`, never rounds.
        assert_eq!(format_duration_label(322.0), "5m 22s");
        assert_eq!(format_duration_label(3_900.0), "1h 5m");
        assert_eq!(format_duration_label(59.9), "0m 59s");
    }

    #[test]
    fn compute_configured_brag_furthest_contact_empty_band_is_some_empty_string() {
        use cw_domain::brag_sheet::{BragStatType, BragStatValue};

        // A QSO with no band at all (COALESCE(band, '') → "") that is also the furthest
        // contact: Swift's mapper passes the raw `String` straight through with no empty
        // check, so this must surface as `Some("")`, not `None`.
        let store = Store::open_in_memory("k").unwrap();
        let mut qso = base_qso("no_band");
        qso.band = None;
        qso.their_grid = Some("DM12".to_string()); // far from FN31 — wins FurthestContact
        qso.qso_date = day_ts(2026, 6, 21);
        store.upsert_qso(&qso).unwrap();

        let enabled = vec![BragStatType::FurthestContact];
        let results = store.compute_configured_brag(&parse(""), &enabled, day(2026, 6, 21)).unwrap();
        match &results[0].1 {
            BragStatValue::Contact { band, .. } => assert_eq!(band.as_deref(), Some("")),
            other => panic!("expected Contact, got {other:?}"),
        }
    }
}
