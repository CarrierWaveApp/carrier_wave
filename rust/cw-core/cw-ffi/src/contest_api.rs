//! Contest engine + definitions over UniFFI — the FFI surface backing the
//! Swift contest facades (`ContestEngine`, `ContestExchangeParser`,
//! `CabrilloExportService`, `ContestScheduleEvaluator`, `OffTimeTracker`,
//! `BandChangeTracker`, `ContestCallsign`, `ContestEnrichmentMatcher`) and
//! the definitions pipeline that replaces `ContestDefinitionsStore` +
//! `ActivitiesClient+ContestDefinitions`.
//!
//! Shape notes:
//! - [`ContestApi`] owns fetch + cache (async, tokio) over
//!   `cw_net::ContestsClient` and the `contest_definition` store table.
//! - [`ContestEngineApi`] is the stateful scorer, constructed **by contest
//!   id** from the cache (or from raw JSON): the recursive v0.3 scoring tree
//!   never crosses the FFI. [`FfiContestDefinition`] is a display projection
//!   for UI, carrying `raw_json` so the stateless helpers below can be fed
//!   without re-fetching.
//! - Every "now"-dependent call takes unix seconds so hosts control time.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use chrono::{DateTime, TimeZone, Utc};
use cw_domain::contest::model::{parse_definition, ContestDefinition, ContestSchedule};
use cw_domain::contest::{band_change, cabrillo, callsign, engine, enrichment, exchange_parser,
    off_time, schedule};
use cw_net::{ContestsClient, HttpClient};
use cw_store::ContestDefinitionRow;

use crate::{CwError, FieldStore};

// ---------------------------------------------------------------------------
// Display DTOs
// ---------------------------------------------------------------------------

/// List-row summary of a cached contest definition.
#[derive(uniffi::Record)]
pub struct FfiContestSummary {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub display_name: String,
    pub sponsor_name: Option<String>,
    pub is_active: bool,
    /// Unix seconds, UTC. Server-side `updatedAt`.
    pub updated_at: i64,
    /// Unix seconds, UTC. When the row was last refreshed.
    pub last_synced_at: i64,
}

/// One exchange field (sent or received).
#[derive(uniffi::Record)]
pub struct FfiContestExchangeField {
    pub name: String,
    /// Raw v0.3 type string (`signal_report`, `serial_number`, …).
    pub field_type: String,
    pub label: String,
    pub required: bool,
    pub autofill: Option<String>,
    pub auto_increment: Option<bool>,
    pub list: Option<String>,
    /// String form of the field default, if any.
    pub default_value_string: Option<String>,
    pub pattern: Option<String>,
    /// True if the field value is numeric (serial, zone, age).
    pub is_numeric: bool,
}

#[derive(uniffi::Record)]
pub struct FfiContestCategory {
    pub id: String,
    pub label: String,
    pub band: Option<String>,
    pub power_classes: Vec<String>,
    pub assisted: Option<bool>,
    /// Raw op-count string (`single`, `multi`, `multi_two`, `multi_multi`).
    pub op_count: Option<String>,
}

#[derive(uniffi::Record)]
pub struct FfiContestOverlayCategory {
    pub id: String,
    pub label: String,
    pub max_on_hours: Option<i64>,
    pub max_license_years: Option<i64>,
}

#[derive(uniffi::Enum)]
pub enum FfiContestScheduleKind {
    RecurringWeekly,
    Annual,
    FixedDates,
}

#[derive(uniffi::Record)]
pub struct FfiContestWeeklySession {
    pub day: String,
    pub start_utc: String,
    pub duration_minutes: i64,
}

#[derive(uniffi::Record)]
pub struct FfiContestFixedOccurrence {
    /// ISO-8601 start, verbatim from the definition.
    pub start: String,
    pub duration_hours: f64,
}

/// Polymorphic JSON literal used by scoring-condition values.
#[derive(uniffi::Enum)]
pub enum FfiJsonValue {
    Str { value: String },
    Int { value: i64 },
    Double { value: f64 },
    Bool { value: bool },
    Array { values: Vec<FfiJsonValue> },
    Null,
}

impl From<&cw_domain::contest::model::JsonValue> for FfiJsonValue {
    fn from(value: &cw_domain::contest::model::JsonValue) -> Self {
        use cw_domain::contest::model::JsonValue;
        match value {
            JsonValue::String(text) => FfiJsonValue::Str { value: text.clone() },
            JsonValue::Int(int) => FfiJsonValue::Int { value: *int },
            JsonValue::Double(double) => FfiJsonValue::Double { value: *double },
            JsonValue::Bool(flag) => FfiJsonValue::Bool { value: *flag },
            JsonValue::Array(values) => {
                FfiJsonValue::Array { values: values.iter().map(Into::into).collect() }
            }
            JsonValue::Null => FfiJsonValue::Null,
        }
    }
}

/// One predicate of a per-QSO scoring rule.
#[derive(uniffi::Record)]
pub struct FfiContestCondition {
    pub field: String,
    /// Raw op string (`eq`/`ne`/`in`/`not_in`/`gt`/`gte`/`lt`/`lte`).
    pub op: String,
    pub value: Option<FfiJsonValue>,
    pub reference: Option<String>,
}

#[derive(uniffi::Record)]
pub struct FfiContestScoringRule {
    pub description: Option<String>,
    pub conditions: Vec<FfiContestCondition>,
    pub value: i64,
}

/// Recursive arithmetic tree of an `aggregate` phase.
#[derive(uniffi::Enum)]
pub enum FfiContestAggregateOp {
    Reference { phase: String },
    Literal { value: i64 },
    Add { inputs: Vec<FfiContestAggregateOp> },
    Multiply { inputs: Vec<FfiContestAggregateOp> },
    Max { inputs: Vec<FfiContestAggregateOp> },
}

impl From<&cw_domain::contest::model::ContestAggregateOp> for FfiContestAggregateOp {
    fn from(op: &cw_domain::contest::model::ContestAggregateOp) -> Self {
        use cw_domain::contest::model::ContestAggregateOp as Op;
        match op {
            Op::Reference { phase } => FfiContestAggregateOp::Reference { phase: phase.clone() },
            Op::Literal { value } => FfiContestAggregateOp::Literal { value: *value },
            Op::Add { inputs } => {
                FfiContestAggregateOp::Add { inputs: inputs.iter().map(Into::into).collect() }
            }
            Op::Multiply { inputs } => {
                FfiContestAggregateOp::Multiply { inputs: inputs.iter().map(Into::into).collect() }
            }
            Op::Max { inputs } => {
                FfiContestAggregateOp::Max { inputs: inputs.iter().map(Into::into).collect() }
            }
        }
    }
}

/// One scoring phase (the scoring-pipeline views render the full tree).
#[derive(uniffi::Enum)]
pub enum FfiContestScoringPhase {
    PerQso {
        id: String,
        description: Option<String>,
        rules: Vec<FfiContestScoringRule>,
    },
    MultiplierCount {
        id: String,
        description: Option<String>,
        source: String,
        /// True = per_band, false = per_contest.
        per_band: bool,
        include_zero_point_qsos: bool,
    },
    Aggregate {
        id: String,
        description: Option<String>,
        operation: FfiContestAggregateOp,
    },
}

fn scoring_phase_to_ffi(
    phase: &cw_domain::contest::model::ContestScoringPhase,
) -> FfiContestScoringPhase {
    use cw_domain::contest::model::{ContestConditionOp, ContestMultiplierScope,
        ContestScoringPhase};
    let op_raw = |op: ContestConditionOp| {
        match op {
            ContestConditionOp::Eq => "eq",
            ContestConditionOp::Ne => "ne",
            ContestConditionOp::In => "in",
            ContestConditionOp::NotIn => "not_in",
            ContestConditionOp::Gt => "gt",
            ContestConditionOp::Gte => "gte",
            ContestConditionOp::Lt => "lt",
            ContestConditionOp::Lte => "lte",
        }
        .to_string()
    };
    match phase {
        ContestScoringPhase::PerQso(per_qso) => FfiContestScoringPhase::PerQso {
            id: per_qso.id.clone(),
            description: per_qso.description.clone(),
            rules: per_qso
                .rules
                .iter()
                .map(|rule| FfiContestScoringRule {
                    description: rule.description.clone(),
                    conditions: rule
                        .conditions
                        .iter()
                        .map(|condition| FfiContestCondition {
                            field: condition.field.clone(),
                            op: op_raw(condition.op),
                            value: condition.value.as_ref().map(Into::into),
                            reference: condition.reference.clone(),
                        })
                        .collect(),
                    value: rule.value,
                })
                .collect(),
        },
        ContestScoringPhase::MultiplierCount(mult) => FfiContestScoringPhase::MultiplierCount {
            id: mult.id.clone(),
            description: mult.description.clone(),
            source: mult.source.clone(),
            per_band: mult.scope == ContestMultiplierScope::PerBand,
            include_zero_point_qsos: mult.include_zero_point_qsos,
        },
        ContestScoringPhase::Aggregate(agg) => FfiContestScoringPhase::Aggregate {
            id: agg.id.clone(),
            description: agg.description.clone(),
            operation: (&agg.operation).into(),
        },
    }
}

/// Display projection of a v0.3 contest definition, including the full
/// scoring tree (the pipeline views render it); `raw_json` feeds the
/// stateless helpers.
#[derive(uniffi::Record)]
pub struct FfiContestDefinition {
    pub id: String,
    pub name: String,
    pub short_name: Option<String>,
    pub display_name: String,
    pub sponsor_name: Option<String>,
    pub sponsor_url: Option<String>,
    pub modes: Vec<String>,
    pub bands: Vec<String>,
    pub exchange_sent: Vec<FfiContestExchangeField>,
    pub exchange_received: Vec<FfiContestExchangeField>,
    /// Raw dupe scope (`session` / `contest`).
    pub dupe_scope: String,
    pub dupe_key: Vec<String>,
    pub scoring_phases: Vec<FfiContestScoringPhase>,
    pub schedule_kind: FfiContestScheduleKind,
    pub weekly_sessions: Vec<FfiContestWeeklySession>,
    pub annual_rule: Option<String>,
    pub annual_start_utc: Option<String>,
    pub annual_start_day: Option<String>,
    pub annual_duration_hours: Option<f64>,
    pub fixed_occurrences: Vec<FfiContestFixedOccurrence>,
    pub categories: Vec<FfiContestCategory>,
    pub overlay_categories: Vec<FfiContestOverlayCategory>,
    pub cabrillo_contest_name: Option<String>,
    pub cabrillo_version: Option<String>,
    pub has_off_time_rules: bool,
    pub off_time_minimum_off_minutes: Option<i64>,
    pub off_time_max_on_hours_by_category: HashMap<String, f64>,
    pub has_band_change_rules: bool,
    pub band_change_applies_to: Vec<String>,
    pub band_change_min_minutes_on_band: Option<i64>,
    pub band_change_max_changes_per_clock_hour: Option<i64>,
    pub experimental: bool,
    /// The full v0.3 body, verbatim — input for the stateless helpers.
    pub raw_json: String,
}

fn field_to_ffi(field: &cw_domain::contest::model::ContestExchangeField) -> FfiContestExchangeField {
    FfiContestExchangeField {
        name: field.name.clone(),
        field_type: field.field_type.raw_value().to_string(),
        label: field.label.clone(),
        required: field.required,
        autofill: field.autofill.clone(),
        auto_increment: field.auto_increment,
        list: field.list.clone(),
        default_value_string: field.default_value.as_ref().map(|value| value.string_value()),
        pattern: field.pattern.clone(),
        is_numeric: field.field_type.is_numeric(),
    }
}

fn definition_to_ffi(definition: &ContestDefinition, raw_json: &str) -> FfiContestDefinition {
    let (schedule_kind, weekly_sessions, annual, fixed) = match &definition.schedule {
        ContestSchedule::RecurringWeekly { sessions, .. } => (
            FfiContestScheduleKind::RecurringWeekly,
            sessions
                .iter()
                .map(|session| FfiContestWeeklySession {
                    day: session.day.clone(),
                    start_utc: session.start_utc.clone(),
                    duration_minutes: session.duration_minutes,
                })
                .collect(),
            None,
            Vec::new(),
        ),
        ContestSchedule::Annual(annual) => {
            (FfiContestScheduleKind::Annual, Vec::new(), Some(annual.clone()), Vec::new())
        }
        ContestSchedule::FixedDates { occurrences } => (
            FfiContestScheduleKind::FixedDates,
            Vec::new(),
            None,
            occurrences
                .iter()
                .map(|occurrence| FfiContestFixedOccurrence {
                    start: occurrence.start.clone(),
                    duration_hours: occurrence.duration_hours,
                })
                .collect(),
        ),
    };

    let off_time_rules =
        definition.operating_constraints.as_ref().and_then(|constraints| constraints.off_time.as_ref());
    let band_rules = definition
        .operating_constraints
        .as_ref()
        .and_then(|constraints| constraints.band_changes.as_ref());

    FfiContestDefinition {
        id: definition.id.clone(),
        name: definition.name.clone(),
        short_name: definition.short_name.clone(),
        display_name: definition.display_name().to_string(),
        sponsor_name: definition.sponsor.as_ref().and_then(|sponsor| sponsor.name.clone()),
        sponsor_url: definition.sponsor.as_ref().and_then(|sponsor| sponsor.url.clone()),
        modes: definition.modes.clone(),
        bands: definition.bands.clone(),
        exchange_sent: definition.exchange.sent.iter().map(field_to_ffi).collect(),
        exchange_received: definition.exchange.received.iter().map(field_to_ffi).collect(),
        dupe_scope: match definition.dupe_rules.scope {
            cw_domain::contest::model::ContestDupeScope::Session => "session".to_string(),
            cw_domain::contest::model::ContestDupeScope::Contest => "contest".to_string(),
        },
        dupe_key: definition.dupe_rules.key.clone(),
        scoring_phases: definition.scoring.phases.iter().map(scoring_phase_to_ffi).collect(),
        schedule_kind,
        weekly_sessions,
        annual_rule: annual.as_ref().map(|schedule| schedule.rule.clone()),
        annual_start_utc: annual.as_ref().map(|schedule| schedule.start_utc.clone()),
        annual_start_day: annual.as_ref().map(|schedule| schedule.start_day.clone()),
        annual_duration_hours: annual.as_ref().map(|schedule| schedule.duration_hours),
        fixed_occurrences: fixed,
        categories: definition
            .categories
            .iter()
            .map(|category| FfiContestCategory {
                id: category.id.clone(),
                label: category.label.clone(),
                band: category.band.clone(),
                power_classes: category.power_classes.clone(),
                assisted: category.assisted,
                op_count: category.op_count.map(|count| {
                    use cw_domain::contest::model::ContestOpCount;
                    match count {
                        ContestOpCount::Single => "single",
                        ContestOpCount::Multi => "multi",
                        ContestOpCount::MultiTwo => "multi_two",
                        ContestOpCount::MultiMulti => "multi_multi",
                    }
                    .to_string()
                }),
            })
            .collect(),
        overlay_categories: definition
            .overlay_categories
            .iter()
            .map(|overlay| FfiContestOverlayCategory {
                id: overlay.id.clone(),
                label: overlay.label.clone(),
                max_on_hours: overlay.max_on_hours,
                max_license_years: overlay.max_license_years,
            })
            .collect(),
        cabrillo_contest_name: definition.cabrillo.as_ref().map(|cab| cab.contest_name.clone()),
        cabrillo_version: definition.cabrillo.as_ref().map(|cab| cab.version.clone()),
        has_off_time_rules: off_time_rules.is_some(),
        off_time_minimum_off_minutes: off_time_rules.and_then(|rules| rules.minimum_off_minutes),
        off_time_max_on_hours_by_category: off_time_rules
            .map(|rules| rules.maximum_on_hours_by_category.clone())
            .unwrap_or_default(),
        has_band_change_rules: band_rules.is_some(),
        band_change_applies_to: band_rules.map(|rules| rules.applies_to.clone()).unwrap_or_default(),
        band_change_min_minutes_on_band: band_rules.and_then(|rules| rules.min_minutes_on_band),
        band_change_max_changes_per_clock_hour: band_rules
            .and_then(|rules| rules.max_changes_per_clock_hour),
        experimental: definition.experimental,
        raw_json: raw_json.to_string(),
    }
}

fn parse_or_query_error(json: &str) -> Result<ContestDefinition, CwError> {
    parse_definition(json)
        .map_err(|error| CwError::Query { reason: format!("contest definition: {error}") })
}

fn ts(seconds: i64) -> DateTime<Utc> {
    Utc.timestamp_opt(seconds, 0)
        .single()
        .unwrap_or_else(|| Utc.timestamp_opt(0, 0).single().expect("epoch is valid"))
}

// ---------------------------------------------------------------------------
// Engine DTOs
// ---------------------------------------------------------------------------

/// Operating-station context for `my_*` scoring conditions + autofill.
#[derive(uniffi::Record)]
pub struct FfiMyStation {
    pub callsign: String,
    pub country: Option<String>,
    pub continent: Option<String>,
    pub cq_zone: Option<i64>,
    pub itu_zone: Option<i64>,
    pub grid: Option<String>,
    pub state: Option<String>,
    pub province: Option<String>,
    pub section: Option<String>,
    pub power: Option<String>,
    pub class_label: Option<String>,
    pub name: Option<String>,
}

impl From<FfiMyStation> for engine::MyStationContext {
    fn from(station: FfiMyStation) -> Self {
        engine::MyStationContext::from_parts(
            station.callsign,
            station.country,
            station.continent,
            station.cq_zone,
            station.itu_zone,
            station.grid,
            station.state,
            station.province,
            station.section,
            station.power,
            station.class_label,
            station.name,
        )
    }
}

/// One QSO snapshot for registration/rescore. Derived fields (country,
/// continent, zones, distance) are caller-resolved, same as Swift.
#[derive(uniffi::Record)]
pub struct FfiContestQsoInput {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    /// Unix seconds, UTC.
    pub timestamp: i64,
    pub sent_exchange: HashMap<String, String>,
    pub received_exchange: HashMap<String, String>,
    pub serial_sent: Option<i64>,
    pub serial_received: Option<i64>,
    pub their_country: Option<String>,
    pub their_continent: Option<String>,
    pub their_cq_zone: Option<i64>,
    pub their_itu_zone: Option<i64>,
    pub distance_km: Option<f64>,
}

impl From<FfiContestQsoInput> for engine::ContestQsoRecord {
    fn from(input: FfiContestQsoInput) -> Self {
        engine::ContestQsoRecord {
            callsign: input.callsign,
            band: input.band,
            mode: input.mode,
            timestamp: ts(input.timestamp),
            sent_exchange: input.sent_exchange,
            received_exchange: input.received_exchange,
            serial_sent: input.serial_sent,
            serial_received: input.serial_received,
            their_country: input.their_country,
            their_continent: input.their_continent,
            their_cq_zone: input.their_cq_zone,
            their_itu_zone: input.their_itu_zone,
            distance_km: input.distance_km,
        }
    }
}

/// Result of checking or registering a QSO.
#[derive(uniffi::Enum)]
pub enum FfiContestDupeStatus {
    NewStation,
    NewMultiplier { phase_id: String, value: String },
    Dupe,
}

impl From<engine::ContestDupeStatus> for FfiContestDupeStatus {
    fn from(status: engine::ContestDupeStatus) -> Self {
        match status {
            engine::ContestDupeStatus::NewStation => FfiContestDupeStatus::NewStation,
            engine::ContestDupeStatus::NewMultiplier { phase_id, value } => {
                FfiContestDupeStatus::NewMultiplier { phase_id, value }
            }
            engine::ContestDupeStatus::Dupe => FfiContestDupeStatus::Dupe,
        }
    }
}

/// Current contest score state.
#[derive(uniffi::Record)]
pub struct FfiContestScore {
    pub total_qsos: i64,
    pub total_points: i64,
    pub multiplier_count: i64,
    pub final_score: i64,
    pub qsos_by_band: HashMap<String, i64>,
    pub points_by_band: HashMap<String, i64>,
    pub mults_by_band: HashMap<String, i64>,
    pub dupe_count: i64,
    pub phase_results: HashMap<String, i64>,
}

impl From<engine::ContestScoreSnapshot> for FfiContestScore {
    fn from(score: engine::ContestScoreSnapshot) -> Self {
        FfiContestScore {
            total_qsos: score.total_qsos,
            total_points: score.total_points,
            multiplier_count: score.multiplier_count,
            final_score: score.final_score,
            qsos_by_band: score.qsos_by_band,
            points_by_band: score.points_by_band,
            mults_by_band: score.mults_by_band,
            dupe_count: score.dupe_count,
            phase_results: score.phase_results,
        }
    }
}

/// One bucket of the rate graph time series.
#[derive(uniffi::Record)]
pub struct FfiContestRateBucket {
    /// Unix seconds, UTC. Bucket start.
    pub date: i64,
    pub count: i64,
}

/// Result of parsing exchange tokens against a definition.
#[derive(uniffi::Record)]
pub struct FfiContestExchangeParseResult {
    pub fields: HashMap<String, String>,
    pub serial_received: Option<i64>,
    pub unmatched_tokens: Vec<String>,
}

/// A concrete schedule occurrence.
#[derive(uniffi::Record)]
pub struct FfiContestOccurrence {
    /// Unix seconds, UTC.
    pub start: i64,
    /// Unix seconds, UTC.
    pub end: i64,
}

impl From<schedule::ContestOccurrence> for FfiContestOccurrence {
    fn from(occurrence: schedule::ContestOccurrence) -> Self {
        FfiContestOccurrence {
            start: occurrence.start.timestamp(),
            end: occurrence.end.timestamp(),
        }
    }
}

// ---- Off-time / band-change DTOs ----

#[derive(uniffi::Record)]
pub struct FfiOffTimePeriod {
    pub start: i64,
    pub end: i64,
}

#[derive(uniffi::Enum)]
pub enum FfiOffTimeViolation {
    OffPeriodTooShort { start: i64, duration_seconds: f64, minimum_seconds: f64 },
    ExceededMaxOnAirTime { actual_seconds: f64, allowed_seconds: f64 },
}

#[derive(uniffi::Record)]
pub struct FfiOffTimeSummary {
    pub total_on_air_seconds: f64,
    pub total_off_seconds: f64,
    pub off_periods: Vec<FfiOffTimePeriod>,
    pub violations: Vec<FfiOffTimeViolation>,
    pub remaining_on_air_seconds: Option<f64>,
}

/// Band + timestamp pair for the band-change tracker.
#[derive(uniffi::Record)]
pub struct FfiContestBandStamp {
    pub band: String,
    /// Unix seconds, UTC.
    pub timestamp: i64,
}

#[derive(uniffi::Record)]
pub struct FfiBandChangeHourBucket {
    /// Unix seconds, UTC. Start of the clock hour.
    pub hour_start: i64,
    pub count: i64,
}

#[derive(uniffi::Enum)]
pub enum FfiBandChangeViolation {
    TooManyChangesInClockHour { hour_start: i64, count: i64, limit: i64 },
    LeftBandTooEarly { band: String, start: i64, duration_seconds: f64, minimum_seconds: f64 },
}

#[derive(uniffi::Record)]
pub struct FfiBandChangeSummary {
    pub total_changes: i64,
    pub changes_per_hour: Vec<FfiBandChangeHourBucket>,
    pub violations: Vec<FfiBandChangeViolation>,
}

// ---- Cabrillo DTOs ----

#[derive(uniffi::Record)]
pub struct FfiCabrilloSession {
    pub my_callsign: String,
    pub contest_operator: Option<String>,
    pub contest_bands: Option<String>,
    pub contest_power: Option<String>,
}

#[derive(uniffi::Record)]
pub struct FfiCabrilloQso {
    pub callsign: String,
    /// MHz, as stored on the QSO.
    pub frequency_mhz: Option<f64>,
    pub mode: String,
    /// Unix seconds, UTC.
    pub timestamp: i64,
    pub rst_sent: Option<String>,
    pub rst_received: Option<String>,
    pub contest_exchange_sent: Option<String>,
    pub contest_exchange_received: Option<String>,
    pub is_contest_qso: bool,
    pub is_hidden: bool,
}

#[derive(uniffi::Record)]
pub struct FfiCabrilloContext {
    pub category_id: Option<String>,
    pub overlay_category_id: Option<String>,
    pub power_class: Option<String>,
    pub assisted: Option<bool>,
    pub location: Option<String>,
    pub operators: Vec<String>,
    pub club_name: Option<String>,
    pub email: Option<String>,
}

// ---------------------------------------------------------------------------
// ContestApi — definitions fetch + cache
// ---------------------------------------------------------------------------

/// Outcome of a [`ContestApi::refresh`] call.
#[derive(uniffi::Record)]
pub struct FfiContestRefreshSummary {
    /// Definitions fetched + upserted this pass.
    pub fetched: i64,
    /// Total definitions now cached.
    pub total: i64,
}

/// Async contest-definitions API bound to a [`FieldStore`] and the
/// activities-server base URL. Endpoints are public — no bearer.
#[derive(uniffi::Object)]
pub struct ContestApi {
    client: ContestsClient,
    store: Arc<FieldStore>,
}

#[uniffi::export]
impl ContestApi {
    /// Build an API against `base_url` (e.g.
    /// `https://activities.carrierwave.app`), writing into `store`.
    #[uniffi::constructor]
    pub fn new(store: Arc<FieldStore>, base_url: String) -> Result<Self, CwError> {
        let http = HttpClient::new()?;
        Ok(ContestApi { client: ContestsClient::new(http, base_url), store })
    }

    /// Cached summaries, ordered by name (offline read).
    pub fn summaries(&self) -> Result<Vec<FfiContestSummary>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        let rows = store.fetch_contest_definitions(cw_store::MAX_FETCH_LIMIT, 0)?;
        Ok(rows.into_iter().map(row_to_summary).collect())
    }

    /// Display projection of one cached definition (offline read).
    pub fn definition(&self, id: String) -> Result<Option<FfiContestDefinition>, CwError> {
        let row = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            store.fetch_contest_definition(&id)?
        };
        let Some(row) = row else {
            return Ok(None);
        };
        let parsed = parse_or_query_error(&row.definition_json)?;
        Ok(Some(definition_to_ffi(&parsed, &row.definition_json)))
    }

    /// Raw cached v0.3 body for one contest (offline read).
    pub fn definition_json(&self, id: String) -> Result<Option<String>, CwError> {
        let store = self.store.inner.lock().expect("store mutex poisoned");
        Ok(store.fetch_contest_definition(&id)?.map(|row| row.definition_json))
    }
}

#[uniffi::export(async_runtime = "tokio")]
impl ContestApi {
    /// Fetch the server list + every definition body, upsert the cache, and
    /// reconcile deletes. Definitions that fail to fetch are skipped (the
    /// cached copy is kept), mirroring the Swift refresher's per-id
    /// tolerance.
    pub async fn refresh(&self) -> Result<FfiContestRefreshSummary, CwError> {
        // Network — no lock held.
        let summaries = self.client.list_contests().await?;
        let mut envelopes = Vec::with_capacity(summaries.len());
        for summary in &summaries {
            match self.client.get_contest(&summary.id).await {
                Ok(envelope) => envelopes.push(envelope),
                Err(_) => continue,
            }
        }

        let now = Utc::now().timestamp();
        let keep_ids: Vec<String> = summaries.iter().map(|summary| summary.id.clone()).collect();
        let fetched = envelopes.len() as i64;

        let total = {
            let store = self.store.inner.lock().expect("store mutex poisoned");
            for envelope in envelopes {
                let definition_json = serde_json::to_string(&envelope.definition)
                    .map_err(|error| CwError::Store { reason: error.to_string() })?;
                store.upsert_contest_definition(&ContestDefinitionRow {
                    id: envelope.id,
                    name: envelope.name,
                    short_name: envelope.short_name,
                    sponsor_name: envelope.sponsor_name,
                    sponsor_url: envelope.sponsor_url,
                    format_version: envelope.format_version,
                    is_active: envelope.is_active,
                    updated_at: envelope.updated_at.timestamp(),
                    definition_json,
                    last_synced_at: now,
                })?;
            }
            store.retain_contest_definitions(&keep_ids)?;
            store.contest_definition_count()?
        };

        Ok(FfiContestRefreshSummary { fetched, total })
    }
}

fn row_to_summary(row: ContestDefinitionRow) -> FfiContestSummary {
    let display_name = row.display_name().to_string();
    FfiContestSummary {
        id: row.id,
        name: row.name,
        short_name: row.short_name,
        display_name,
        sponsor_name: row.sponsor_name,
        is_active: row.is_active,
        updated_at: row.updated_at,
        last_synced_at: row.last_synced_at,
    }
}

// ---------------------------------------------------------------------------
// ContestEngineApi — the stateful scorer
// ---------------------------------------------------------------------------

/// One contest engine instance (dupe table, serials, multipliers, score).
/// Construct per contest session; interior state is mutex-protected.
#[derive(uniffi::Object)]
pub struct ContestEngineApi {
    engine: Mutex<engine::ContestEngine>,
    raw_json: String,
}

#[uniffi::export]
impl ContestEngineApi {
    /// Build from the cached definition for `definition_id` in `store`.
    #[uniffi::constructor]
    pub fn new(
        store: Arc<FieldStore>,
        definition_id: String,
        my_station: Option<FfiMyStation>,
        starting_serial: i64,
    ) -> Result<Self, CwError> {
        let row = {
            let store = store.inner.lock().expect("store mutex poisoned");
            store.fetch_contest_definition(&definition_id)?
        };
        let Some(row) = row else {
            return Err(CwError::Store {
                reason: format!("contest definition not cached: {definition_id}"),
            });
        };
        Self::from_json(row.definition_json, my_station, starting_serial)
    }

    /// Build from a raw v0.3 definition body.
    #[uniffi::constructor]
    pub fn from_json(
        definition_json: String,
        my_station: Option<FfiMyStation>,
        starting_serial: i64,
    ) -> Result<Self, CwError> {
        let definition = parse_or_query_error(&definition_json)?;
        let engine =
            engine::ContestEngine::new(definition, my_station.map(Into::into), starting_serial);
        Ok(ContestEngineApi { engine: Mutex::new(engine), raw_json: definition_json })
    }

    /// Display projection of the engine's definition.
    pub fn definition(&self) -> Result<FfiContestDefinition, CwError> {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        Ok(definition_to_ffi(engine.definition(), &self.raw_json))
    }

    pub fn set_my_station(&self, station: Option<FfiMyStation>) {
        let mut engine = self.engine.lock().expect("engine mutex poisoned");
        engine.set_my_station(station.map(Into::into));
    }

    /// Check whether a prospective QSO would be a dupe. O(1).
    pub fn dupe_status(&self, callsign: String, band: String, mode: String) -> FfiContestDupeStatus {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        engine.dupe_status(&callsign, &band, &mode).into()
    }

    /// Peek at next-sent serial without incrementing.
    pub fn current_serial(&self) -> i64 {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        engine.current_serial()
    }

    /// Increment and return the next serial to send.
    pub fn next_serial(&self) -> i64 {
        let mut engine = self.engine.lock().expect("engine mutex poisoned");
        engine.next_serial()
    }

    /// Received exchange from a prior QSO with this callsign, if any.
    pub fn suggested_exchange(&self, callsign: String) -> Option<HashMap<String, String>> {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        engine.suggested_exchange(&callsign).cloned()
    }

    /// Register a completed QSO.
    pub fn register_qso(&self, input: FfiContestQsoInput) -> FfiContestDupeStatus {
        let mut engine = self.engine.lock().expect("engine mutex poisoned");
        engine.register_qso(&input.into()).into()
    }

    /// Current score snapshot.
    pub fn score_snapshot(&self) -> FfiContestScore {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        engine.score_snapshot().into()
    }

    /// QSO rate over the last `over_minutes`, evaluated at `now` (unix secs).
    pub fn rate(&self, over_minutes: i64, now: i64) -> f64 {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        engine.rate(over_minutes, ts(now))
    }

    /// Bucketed rate time series, evaluated at `now` (unix seconds).
    pub fn rate_time_series(&self, bucket_minutes: i64, now: i64) -> Vec<FfiContestRateBucket> {
        let engine = self.engine.lock().expect("engine mutex poisoned");
        engine
            .rate_time_series(bucket_minutes, ts(now))
            .into_iter()
            .map(|bucket| FfiContestRateBucket {
                date: bucket.date.timestamp(),
                count: bucket.count,
            })
            .collect()
    }

    /// Full rescore from scratch (records sorted chronologically first).
    pub fn rescore(&self, records: Vec<FfiContestQsoInput>) {
        let converted: Vec<engine::ContestQsoRecord> =
            records.into_iter().map(Into::into).collect();
        let mut engine = self.engine.lock().expect("engine mutex poisoned");
        engine.rescore(&converted);
    }

    /// Load already-logged QSOs at session start (same semantics as rescore).
    pub fn load_existing_qsos(&self, records: Vec<FfiContestQsoInput>) {
        self.rescore(records);
    }
}

// ---------------------------------------------------------------------------
// Stateless helpers
// ---------------------------------------------------------------------------

/// Display projection of a raw v0.3 definition body.
#[uniffi::export]
pub fn contest_definition_from_json(json: String) -> Result<FfiContestDefinition, CwError> {
    let parsed = parse_or_query_error(&json)?;
    Ok(definition_to_ffi(&parsed, &json))
}

/// Parse space-separated exchange tokens against a definition's
/// received-field list.
#[uniffi::export]
pub fn contest_parse_exchange(
    tokens: Vec<String>,
    definition_json: String,
) -> Result<FfiContestExchangeParseResult, CwError> {
    let definition = parse_or_query_error(&definition_json)?;
    let result = exchange_parser::parse(&tokens, &definition);
    Ok(FfiContestExchangeParseResult {
        fields: result.fields,
        serial_received: result.serial_received,
        unmatched_tokens: result.unmatched_tokens,
    })
}

/// Generate Cabrillo 3.0 log text.
#[uniffi::export]
pub fn contest_generate_cabrillo(
    session: FfiCabrilloSession,
    qsos: Vec<FfiCabrilloQso>,
    definition_json: String,
    score: FfiContestScore,
    context: FfiCabrilloContext,
) -> Result<String, CwError> {
    let definition = parse_or_query_error(&definition_json)?;
    let session = cabrillo::CabrilloSession {
        my_callsign: session.my_callsign,
        contest_operator: session.contest_operator,
        contest_bands: session.contest_bands,
        contest_power: session.contest_power,
    };
    let qsos: Vec<cabrillo::CabrilloQso> = qsos
        .into_iter()
        .map(|qso| cabrillo::CabrilloQso {
            callsign: qso.callsign,
            frequency: qso.frequency_mhz,
            mode: qso.mode,
            timestamp: ts(qso.timestamp),
            rst_sent: qso.rst_sent,
            rst_received: qso.rst_received,
            contest_exchange_sent: qso.contest_exchange_sent,
            contest_exchange_received: qso.contest_exchange_received,
            is_contest_qso: qso.is_contest_qso,
            is_hidden: qso.is_hidden,
        })
        .collect();
    let snapshot = engine::ContestScoreSnapshot {
        total_qsos: score.total_qsos,
        total_points: score.total_points,
        multiplier_count: score.multiplier_count,
        final_score: score.final_score,
        qsos_by_band: score.qsos_by_band,
        points_by_band: score.points_by_band,
        mults_by_band: score.mults_by_band,
        dupe_count: score.dupe_count,
        phase_results: score.phase_results,
    };
    let context = cabrillo::CabrilloContext {
        category_id: context.category_id,
        overlay_category_id: context.overlay_category_id,
        power_class: context.power_class,
        assisted: context.assisted,
        location: context.location,
        operators: context.operators,
        club_name: context.club_name,
        email: context.email,
    };
    Ok(cabrillo::generate(&session, &qsos, &definition, &snapshot, &context))
}

/// The currently-active occurrence (if any) at `now` (unix seconds).
#[uniffi::export]
pub fn contest_active_occurrence(
    definition_json: String,
    now: i64,
) -> Result<Option<FfiContestOccurrence>, CwError> {
    let definition = parse_or_query_error(&definition_json)?;
    Ok(schedule::active_occurrence(&definition.schedule, ts(now)).map(Into::into))
}

/// The next upcoming occurrence after `now` (unix seconds), if any.
#[uniffi::export]
pub fn contest_next_occurrence(
    definition_json: String,
    now: i64,
) -> Result<Option<FfiContestOccurrence>, CwError> {
    let definition = parse_or_query_error(&definition_json)?;
    Ok(schedule::next_occurrence(&definition.schedule, ts(now)).map(Into::into))
}

/// Candidate occurrences around `now` (unix seconds).
#[uniffi::export]
pub fn contest_occurrences(
    definition_json: String,
    now: i64,
) -> Result<Vec<FfiContestOccurrence>, CwError> {
    let definition = parse_or_query_error(&definition_json)?;
    Ok(schedule::occurrences(&definition.schedule, ts(now))
        .into_iter()
        .map(Into::into)
        .collect())
}

/// Off-time rules as the host holds them (from
/// `definition.operating_constraints.off_time`).
#[derive(uniffi::Record)]
pub struct FfiOffTimeRulesInput {
    pub minimum_off_minutes: Option<i64>,
    pub maximum_on_hours_by_category: HashMap<String, f64>,
}

/// Off-time compliance summary. `rules: None` applies the default
/// 30-minute minimum, same as Swift. All times unix seconds.
#[uniffi::export]
pub fn contest_off_time_summary(
    qso_timestamps: Vec<i64>,
    session_start: i64,
    session_end: i64,
    category_id: Option<String>,
    rules: Option<FfiOffTimeRulesInput>,
) -> FfiOffTimeSummary {
    let rules = rules.map(|input| cw_domain::contest::model::ContestOffTimeRules {
        minimum_off_minutes: input.minimum_off_minutes,
        maximum_on_hours_by_category: input.maximum_on_hours_by_category,
    });
    let stamps: Vec<DateTime<Utc>> = qso_timestamps.into_iter().map(ts).collect();
    let summary = off_time::summarize(
        &stamps,
        ts(session_start),
        ts(session_end),
        category_id.as_deref(),
        rules.as_ref(),
    );
    FfiOffTimeSummary {
        total_on_air_seconds: summary.total_on_air_seconds,
        total_off_seconds: summary.total_off_seconds,
        off_periods: summary
            .off_periods
            .iter()
            .map(|period| FfiOffTimePeriod {
                start: period.start.timestamp(),
                end: period.end.timestamp(),
            })
            .collect(),
        violations: summary
            .violations
            .into_iter()
            .map(|violation| match violation {
                off_time::OffTimeViolation::OffPeriodTooShort {
                    start,
                    duration_seconds,
                    minimum_seconds,
                } => FfiOffTimeViolation::OffPeriodTooShort {
                    start: start.timestamp(),
                    duration_seconds,
                    minimum_seconds,
                },
                off_time::OffTimeViolation::ExceededMaxOnAirTime {
                    actual_seconds,
                    allowed_seconds,
                } => FfiOffTimeViolation::ExceededMaxOnAirTime { actual_seconds, allowed_seconds },
            })
            .collect(),
        remaining_on_air_seconds: summary.remaining_on_air_seconds,
    }
}

/// Band-change rules as the host holds them (from
/// `definition.operating_constraints.band_changes`).
#[derive(uniffi::Record)]
pub struct FfiBandChangeRulesInput {
    pub applies_to: Vec<String>,
    pub min_minutes_on_band: Option<i64>,
    pub max_changes_per_clock_hour: Option<i64>,
}

/// Band-change compliance summary. `rules: None` yields an empty summary,
/// same as Swift's `guard let rules`.
#[uniffi::export]
pub fn contest_band_change_summary(
    qsos: Vec<FfiContestBandStamp>,
    category_id: Option<String>,
    rules: Option<FfiBandChangeRulesInput>,
) -> FfiBandChangeSummary {
    let rules = rules.map(|input| cw_domain::contest::model::ContestBandChangeRules {
        applies_to: input.applies_to,
        min_minutes_on_band: input.min_minutes_on_band,
        max_changes_per_clock_hour: input.max_changes_per_clock_hour,
    });
    let stamps: Vec<(String, DateTime<Utc>)> =
        qsos.into_iter().map(|stamp| (stamp.band, ts(stamp.timestamp))).collect();
    let summary = band_change::summarize(&stamps, category_id.as_deref(), rules.as_ref());

    let mut buckets: Vec<FfiBandChangeHourBucket> = summary
        .changes_per_hour
        .iter()
        .map(|(hour, count)| FfiBandChangeHourBucket { hour_start: hour.timestamp(), count: *count })
        .collect();
    buckets.sort_by_key(|bucket| bucket.hour_start);

    FfiBandChangeSummary {
        total_changes: summary.total_changes,
        changes_per_hour: buckets,
        violations: summary
            .violations
            .into_iter()
            .map(|violation| match violation {
                band_change::BandChangeViolation::TooManyChangesInClockHour {
                    hour_start,
                    count,
                    limit,
                } => FfiBandChangeViolation::TooManyChangesInClockHour {
                    hour_start: hour_start.timestamp(),
                    count,
                    limit,
                },
                band_change::BandChangeViolation::LeftBandTooEarly {
                    band,
                    start,
                    duration_seconds,
                    minimum_seconds,
                } => FfiBandChangeViolation::LeftBandTooEarly {
                    band,
                    start: start.timestamp(),
                    duration_seconds,
                    minimum_seconds,
                },
            })
            .collect(),
    }
}

/// Normalize a callsign for dupe-keying (uppercase, strip portable suffixes).
#[uniffi::export]
pub fn contest_normalize_callsign(callsign: String) -> String {
    callsign::normalize(&callsign)
}

/// CQ WPX contest prefix for a callsign.
#[uniffi::export]
pub fn contest_wpx_prefix(callsign: String) -> String {
    callsign::wpx_prefix(&callsign)
}

/// Collapsed mode group: `CW`, `PHONE`, or `DIGITAL`.
#[uniffi::export]
pub fn contest_mode_group(mode: String) -> String {
    engine::mode_group(&mode).to_string()
}

/// Enrichment source slug for a contest id, if prefill is supported.
#[uniffi::export]
pub fn contest_enrichment_source_slug(contest_id: String) -> Option<String> {
    enrichment::source_slug(&contest_id).map(str::to_string)
}

/// First whitespace token of a name in ALL CAPS (CWT wire convention).
#[uniffi::export]
pub fn contest_format_exchange_name(raw_name: String) -> String {
    enrichment::format_exchange_name(&raw_name)
}

/// Prefill name/identifier exchange values from membership data. Returns
/// only the entries that were written (the host merges + remembers them).
#[uniffi::export]
pub fn contest_enrichment_prefill(
    contest_id: String,
    membership_name: Option<String>,
    member_number: Option<String>,
    preferred_name: Option<String>,
    fallback_identifier: Option<String>,
    current_values: HashMap<String, String>,
) -> HashMap<String, String> {
    let membership = enrichment::MembershipPrefill { name: membership_name, member_number };
    let mut values = current_values;
    enrichment::prefill(
        Some(&membership),
        &contest_id,
        preferred_name.as_deref(),
        fallback_identifier.as_deref(),
        &mut values,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const SST_JSON: &str = r#"
    {
      "id": "sst",
      "name": "Slow Speed Test",
      "short_name": "SST",
      "modes": ["CW"],
      "bands": ["40m"],
      "schedule": {
        "type": "recurring_weekly",
        "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
        "session_scoring": "independent"
      },
      "exchange": {
        "sent": [{ "name": "name", "type": "name", "label": "Name" }],
        "received": [{ "name": "name", "type": "name", "label": "Name" }]
      },
      "dupe_rules": { "scope": "session", "key": ["callsign", "band"] },
      "scoring": {
        "phases": [
          { "id": "qso_points", "type": "per_qso", "rules": [{ "conditions": [], "value": 1 }] }
        ]
      },
      "categories": []
    }
    "#;

    fn qso(callsign: &str, offset: i64) -> FfiContestQsoInput {
        FfiContestQsoInput {
            callsign: callsign.to_string(),
            band: "40m".to_string(),
            mode: "CW".to_string(),
            timestamp: 1_780_000_000 + offset,
            sent_exchange: HashMap::new(),
            received_exchange: HashMap::new(),
            serial_sent: None,
            serial_received: None,
            their_country: None,
            their_continent: None,
            their_cq_zone: None,
            their_itu_zone: None,
            distance_km: None,
        }
    }

    #[test]
    fn engine_via_ffi_scores_and_dupes() {
        let engine =
            ContestEngineApi::from_json(SST_JSON.to_string(), None, 0).expect("engine");
        assert!(matches!(
            engine.register_qso(qso("K1USN", 0)),
            FfiContestDupeStatus::NewStation
        ));
        assert!(matches!(engine.register_qso(qso("K1USN", 60)), FfiContestDupeStatus::Dupe));

        let score = engine.score_snapshot();
        assert_eq!(score.total_qsos, 1);
        assert_eq!(score.dupe_count, 1);
        assert_eq!(score.final_score, 1);
    }

    #[test]
    fn definition_dto_projects_display_fields() {
        let dto = contest_definition_from_json(SST_JSON.to_string()).expect("dto");
        assert_eq!(dto.display_name, "SST");
        assert_eq!(dto.dupe_key, vec!["callsign".to_string(), "band".to_string()]);
        assert!(matches!(dto.schedule_kind, FfiContestScheduleKind::RecurringWeekly));
        assert_eq!(dto.weekly_sessions.len(), 1);
        assert_eq!(dto.exchange_received[0].field_type, "name");
        assert_eq!(dto.raw_json, SST_JSON);
    }

    #[test]
    fn stateless_helpers_round_trip() {
        let parsed =
            contest_parse_exchange(vec!["jay".to_string()], SST_JSON.to_string()).expect("parse");
        assert_eq!(parsed.fields.get("name").map(String::as_str), Some("jay"));

        assert_eq!(contest_wpx_prefix("K4XL/QRP".to_string()), "K4");
        assert_eq!(contest_normalize_callsign("k4xl/qrp".to_string()), "K4XL");
        assert_eq!(contest_mode_group("usb".to_string()), "PHONE");
        assert_eq!(
            contest_enrichment_source_slug("cwops-cwt".to_string()).as_deref(),
            Some("cwops")
        );

        let next = contest_next_occurrence(SST_JSON.to_string(), 1_780_000_000).expect("occ");
        assert!(next.is_some());
    }
}
