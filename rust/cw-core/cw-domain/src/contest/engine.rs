//! Pure-logic scoring, dupe, and multiplier engine for server-defined
//! contest definitions (format v0.3). Port of
//! `Services/Contest/ContestEngine.swift` + `ContestEngine+Phases.swift`.
//!
//! Unlike the Swift actor, "now"-dependent entry points (`rate`,
//! `rate_time_series`) take an explicit timestamp so the engine stays pure.

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Duration, Utc};

use super::callsign;
use super::condition::{rule_matches, ContestConditionContext};
use super::model::{ContestAggregateOp, ContestDefinition, ContestMultiplierScope,
    ContestPerQsoPhase, ContestScoringPhase};

// ---- Value types ---------------------------------------------------------

/// Lightweight snapshot of a QSO for contest engine processing. Includes
/// derived fields (country, continent, zones) resolved by the caller before
/// registration — the engine doesn't perform country-file lookups.
/// Port of `ContestQSORecord`.
#[derive(Debug, Clone, PartialEq)]
pub struct ContestQsoRecord {
    pub callsign: String,
    pub band: String,
    pub mode: String,
    pub timestamp: DateTime<Utc>,
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

impl ContestQsoRecord {
    pub fn new(callsign: &str, band: &str, mode: &str, timestamp: DateTime<Utc>) -> Self {
        Self {
            callsign: callsign.to_string(),
            band: band.to_string(),
            mode: mode.to_string(),
            timestamp,
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

    /// Collapsed mode group: `CW`, `PHONE`, or `DIGITAL`.
    pub fn mode_group(&self) -> &'static str {
        mode_group(&self.mode)
    }
}

/// Collapsed mode group for an arbitrary mode string.
pub fn mode_group(mode: &str) -> &'static str {
    match mode.to_uppercase().as_str() {
        "CW" => "CW",
        "SSB" | "USB" | "LSB" | "AM" | "FM" | "PH" => "PHONE",
        _ => "DIGITAL",
    }
}

/// Operating-station context used by the contest engine to evaluate scoring
/// conditions that reference `my_*` fields. Port of `MyStationContext` —
/// the Swift initializer uppercases everything except `country` and `name`,
/// which the `with_*` builders reproduce.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct MyStationContext {
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

impl MyStationContext {
    pub fn new(callsign: &str) -> Self {
        Self { callsign: callsign.to_string(), ..Self::default() }
    }

    /// Construct with every field, applying the same normalization as the
    /// Swift initializer (uppercase all but `country` and `name`).
    #[allow(clippy::too_many_arguments)]
    pub fn from_parts(
        callsign: String,
        country: Option<String>,
        continent: Option<String>,
        cq_zone: Option<i64>,
        itu_zone: Option<i64>,
        grid: Option<String>,
        state: Option<String>,
        province: Option<String>,
        section: Option<String>,
        power: Option<String>,
        class_label: Option<String>,
        name: Option<String>,
    ) -> Self {
        Self {
            callsign,
            country,
            continent: continent.map(|value| value.to_uppercase()),
            cq_zone,
            itu_zone,
            grid: grid.map(|value| value.to_uppercase()),
            state: state.map(|value| value.to_uppercase()),
            province: province.map(|value| value.to_uppercase()),
            section: section.map(|value| value.to_uppercase()),
            power: power.map(|value| value.to_uppercase()),
            class_label: class_label.map(|value| value.to_uppercase()),
            name,
        }
    }

    pub fn with_country(mut self, country: &str) -> Self {
        self.country = Some(country.to_string());
        self
    }

    /// Value for a given `station_*` autofill source, if available.
    pub fn autofill_value(&self, source: &str) -> Option<String> {
        match source {
            "station_cq_zone" => self.cq_zone.map(|zone| zone.to_string()),
            "station_itu_zone" => self.itu_zone.map(|zone| zone.to_string()),
            "station_country" => self.country.clone(),
            "station_continent" => self.continent.clone(),
            "station_section" => self.section.clone(),
            "station_state" => self.state.clone(),
            "station_province" => self.province.clone(),
            "station_grid" => self.grid.clone(),
            "station_power" => self.power.clone(),
            "station_class" => self.class_label.clone(),
            "station_name" => self.name.clone(),
            _ => None,
        }
    }
}

/// Result of checking or registering a QSO against the contest engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContestDupeStatus {
    NewStation,
    NewMultiplier { phase_id: String, value: String },
    Dupe,
}

/// Current contest score state. Port of `ContestScoreSnapshot`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ContestScoreSnapshot {
    pub total_qsos: i64,
    pub total_points: i64,
    pub multiplier_count: i64,
    pub final_score: i64,
    pub qsos_by_band: HashMap<String, i64>,
    pub points_by_band: HashMap<String, i64>,
    pub mults_by_band: HashMap<String, i64>,
    pub dupe_count: i64,
    /// Per-phase integer result, keyed by phase id.
    pub phase_results: HashMap<String, i64>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct QsoLogEntry {
    timestamp: DateTime<Utc>,
    points: i64,
}

/// One bucket of the rate graph time series.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RateBucket {
    pub date: DateTime<Utc>,
    pub count: i64,
}

// ---- Engine ---------------------------------------------------------------

/// Contest scoring/dupe/multiplier state machine.
#[derive(Debug, Clone)]
pub struct ContestEngine {
    definition: ContestDefinition,
    my_station: Option<MyStationContext>,
    serial_counter: i64,
    dupe_table: HashSet<String>,
    known_exchanges: HashMap<String, HashMap<String, String>>,
    qso_log: Vec<QsoLogEntry>,
    qsos_by_band: HashMap<String, i64>,
    points_by_band: HashMap<String, i64>,
    dupe_count: i64,
    per_qso_totals: HashMap<String, i64>,
    per_qso_by_band: HashMap<String, HashMap<String, i64>>,
    mult_tables_per_band: HashMap<String, HashMap<String, HashSet<String>>>,
    mult_tables_per_contest: HashMap<String, HashSet<String>>,
}

impl ContestEngine {
    pub fn new(
        definition: ContestDefinition,
        my_station: Option<MyStationContext>,
        starting_serial: i64,
    ) -> Self {
        Self {
            definition,
            my_station,
            serial_counter: starting_serial,
            dupe_table: HashSet::new(),
            known_exchanges: HashMap::new(),
            qso_log: Vec::new(),
            qsos_by_band: HashMap::new(),
            points_by_band: HashMap::new(),
            dupe_count: 0,
            per_qso_totals: HashMap::new(),
            per_qso_by_band: HashMap::new(),
            mult_tables_per_band: HashMap::new(),
            mult_tables_per_contest: HashMap::new(),
        }
    }

    pub fn definition(&self) -> &ContestDefinition {
        &self.definition
    }

    pub fn my_station(&self) -> Option<&MyStationContext> {
        self.my_station.as_ref()
    }

    pub fn set_my_station(&mut self, context: Option<MyStationContext>) {
        self.my_station = context;
    }

    /// Check whether a prospective QSO would be a dupe. O(1).
    pub fn dupe_status(&self, callsign: &str, band: &str, mode: &str) -> ContestDupeStatus {
        let key = self.dupe_key(callsign, band, mode);
        if self.dupe_table.contains(&key) {
            ContestDupeStatus::Dupe
        } else {
            ContestDupeStatus::NewStation
        }
    }

    /// Peek at next-sent serial without incrementing.
    pub fn current_serial(&self) -> i64 {
        self.serial_counter + 1
    }

    /// Increment and return the next serial to send.
    pub fn next_serial(&mut self) -> i64 {
        self.serial_counter += 1;
        self.serial_counter
    }

    /// Suggest received-exchange values based on a prior QSO with the same
    /// callsign on another band (useful in multi-band contests).
    pub fn suggested_exchange(&self, callsign: &str) -> Option<&HashMap<String, String>> {
        self.known_exchanges.get(&callsign::normalize(callsign))
    }

    /// Register a completed QSO — updates dupe table, multipliers, phase
    /// totals, and returns the resulting status for UI feedback.
    pub fn register_qso(&mut self, record: &ContestQsoRecord) -> ContestDupeStatus {
        let normalized_call = callsign::normalize(&record.callsign);
        let key = self.dupe_key(&normalized_call, &record.band, &record.mode);

        if self.dupe_table.contains(&key) {
            self.dupe_count += 1;
            return ContestDupeStatus::Dupe;
        }

        self.dupe_table.insert(key);
        if !record.received_exchange.is_empty() {
            self.known_exchanges
                .insert(normalized_call, record.received_exchange.clone());
        }

        let points = self.evaluate_per_qso_phases(record);
        for (phase_id, value) in &points {
            *self.per_qso_totals.entry(phase_id.clone()).or_insert(0) += value;
            *self
                .per_qso_by_band
                .entry(phase_id.clone())
                .or_default()
                .entry(record.band.clone())
                .or_insert(0) += value;
        }

        let total_points: i64 = points.values().sum();
        *self.qsos_by_band.entry(record.band.clone()).or_insert(0) += 1;
        *self.points_by_band.entry(record.band.clone()).or_insert(0) += total_points;
        self.qso_log.push(QsoLogEntry { timestamp: record.timestamp, points: total_points });

        let new_mult = self.update_multipliers(record, total_points);
        new_mult.unwrap_or(ContestDupeStatus::NewStation)
    }

    /// Current score snapshot (recomputes aggregate phases from running
    /// totals).
    pub fn score_snapshot(&self) -> ContestScoreSnapshot {
        let mut phase_results = self.per_qso_totals.clone();
        for phase in &self.definition.scoring.phases {
            match phase {
                ContestScoringPhase::MultiplierCount(mult) => {
                    phase_results
                        .insert(mult.id.clone(), self.count_multipliers(&mult.id, mult.scope));
                }
                ContestScoringPhase::Aggregate(agg) => {
                    let value = evaluate_aggregate(&agg.operation, &phase_results);
                    phase_results.insert(agg.id.clone(), value);
                }
                // Already in per_qso_totals.
                ContestScoringPhase::PerQso(_) => {}
            }
        }

        let total_qsos: i64 = self.qsos_by_band.values().sum();
        let total_points: i64 = self.per_qso_totals.values().sum();
        let final_score = self.final_phase_score(&phase_results);

        ContestScoreSnapshot {
            total_qsos,
            total_points,
            multiplier_count: self.multiplier_total_count(),
            final_score,
            qsos_by_band: self.qsos_by_band.clone(),
            points_by_band: self.points_by_band.clone(),
            mults_by_band: self.count_multipliers_by_band(),
            dupe_count: self.dupe_count,
            phase_results,
        }
    }

    /// QSO rate over the last N minutes, evaluated at `now`.
    pub fn rate(&self, over_minutes: i64, now: DateTime<Utc>) -> f64 {
        if self.qso_log.is_empty() {
            return 0.0;
        }
        let cutoff = now - Duration::seconds(over_minutes * 60);
        let recent = self.qso_log.iter().filter(|entry| entry.timestamp > cutoff).count();
        let fraction = over_minutes as f64 / 60.0;
        recent as f64 / fraction
    }

    /// Bucketed time series for the rate graph, evaluated at `now`.
    pub fn rate_time_series(&self, bucket_minutes: i64, now: DateTime<Utc>) -> Vec<RateBucket> {
        let Some(first) = self.qso_log.first().map(|entry| entry.timestamp) else {
            return Vec::new();
        };
        let bucket = Duration::seconds(bucket_minutes * 60);
        let mut result = Vec::new();
        let mut bucket_start = first;
        while bucket_start < now {
            let bucket_end = bucket_start + bucket;
            let count = self
                .qso_log
                .iter()
                .filter(|entry| entry.timestamp >= bucket_start && entry.timestamp < bucket_end)
                .count() as i64;
            result.push(RateBucket { date: bucket_start, count });
            bucket_start = bucket_end;
        }
        result
    }

    /// Full rescore from a QSO list (sorted chronologically first). Used
    /// after edits.
    pub fn rescore(&mut self, records: &[ContestQsoRecord]) {
        self.reset();
        let mut sorted: Vec<&ContestQsoRecord> = records.iter().collect();
        sorted.sort_by_key(|record| record.timestamp);
        for record in sorted {
            self.register_qso(record);
        }
    }

    /// Load already-logged QSOs at session start (same semantics as rescore).
    pub fn load_existing_qsos(&mut self, records: &[ContestQsoRecord]) {
        self.rescore(records);
    }

    // ---- Phase evaluation (port of ContestEngine+Phases.swift) ----------

    /// Run every `per_qso` phase against the record and return a map of
    /// phase id → points awarded.
    fn evaluate_per_qso_phases(&self, record: &ContestQsoRecord) -> HashMap<String, i64> {
        let context = ContestConditionContext { qso: record, my_station: self.my_station.as_ref() };
        let mut result = HashMap::new();
        for phase in &self.definition.scoring.phases {
            let ContestScoringPhase::PerQso(per_qso) = phase else {
                continue;
            };
            result.insert(per_qso.id.clone(), points_for_phase(per_qso, &context));
        }
        result
    }

    /// Update multiplier accumulators for every `multiplier_count` phase.
    /// Returns the first-new-multiplier status for UI feedback, if any.
    fn update_multipliers(
        &mut self,
        record: &ContestQsoRecord,
        qso_points: i64,
    ) -> Option<ContestDupeStatus> {
        let mut first_new = None;
        let phases = self.definition.scoring.phases.clone();
        for phase in &phases {
            let ContestScoringPhase::MultiplierCount(mult) = phase else {
                continue;
            };
            if qso_points <= 0 && !mult.include_zero_point_qsos {
                continue;
            }
            let context =
                ContestConditionContext { qso: record, my_station: self.my_station.as_ref() };
            let Some(value) = resolve_multiplier_source(&mult.source, &context) else {
                continue;
            };
            if self.accumulate(&value, &mult.id, mult.scope, &record.band) && first_new.is_none() {
                first_new = Some(ContestDupeStatus::NewMultiplier {
                    phase_id: mult.id.clone(),
                    value,
                });
            }
        }
        first_new
    }

    /// Count of unique values across all bands for a given phase.
    fn count_multipliers(&self, phase_id: &str, scope: ContestMultiplierScope) -> i64 {
        match scope {
            ContestMultiplierScope::PerContest => self
                .mult_tables_per_contest
                .get(phase_id)
                .map_or(0, |values| values.len() as i64),
            ContestMultiplierScope::PerBand => self
                .mult_tables_per_band
                .get(phase_id)
                .map_or(0, |by_band| by_band.values().map(|values| values.len() as i64).sum()),
        }
    }

    /// Count across all multiplier phases (for a top-line "Mults" display).
    fn multiplier_total_count(&self) -> i64 {
        let mut total = 0;
        for phase in &self.definition.scoring.phases {
            let ContestScoringPhase::MultiplierCount(mult) = phase else {
                continue;
            };
            total += self.count_multipliers(&mult.id, mult.scope);
        }
        total
    }

    /// Multiplier counts keyed by band, summed across all phases.
    fn count_multipliers_by_band(&self) -> HashMap<String, i64> {
        let mut result = HashMap::new();
        for by_band in self.mult_tables_per_band.values() {
            for (band, values) in by_band {
                *result.entry(band.clone()).or_insert(0) += values.len() as i64;
            }
        }
        result
    }

    fn accumulate(
        &mut self,
        value: &str,
        phase_id: &str,
        scope: ContestMultiplierScope,
        band: &str,
    ) -> bool {
        match scope {
            ContestMultiplierScope::PerContest => self
                .mult_tables_per_contest
                .entry(phase_id.to_string())
                .or_default()
                .insert(value.to_string()),
            ContestMultiplierScope::PerBand => self
                .mult_tables_per_band
                .entry(phase_id.to_string())
                .or_default()
                .entry(band.to_string())
                .or_default()
                .insert(value.to_string()),
        }
    }

    // ---- Private ----------------------------------------------------------

    fn reset(&mut self) {
        self.dupe_table.clear();
        self.known_exchanges.clear();
        self.qso_log.clear();
        self.qsos_by_band.clear();
        self.points_by_band.clear();
        self.dupe_count = 0;
        self.per_qso_totals.clear();
        self.per_qso_by_band.clear();
        self.mult_tables_per_band.clear();
        self.mult_tables_per_contest.clear();
    }

    fn dupe_key(&self, callsign: &str, band: &str, mode: &str) -> String {
        let normalized = callsign::normalize(callsign);
        let mut parts: Vec<String> = Vec::new();
        for component in &self.definition.dupe_rules.key {
            match component.as_str() {
                "callsign" => parts.push(normalized.clone()),
                "band" => parts.push(band.to_string()),
                "mode" => parts.push(mode.to_uppercase()),
                "mode_group" => parts.push(mode_group(mode).to_string()),
                other => parts.push(other.to_string()),
            }
        }
        if parts.is_empty() {
            parts.push(normalized);
        }
        parts.join("|")
    }

    fn final_phase_score(&self, phase_results: &HashMap<String, i64>) -> i64 {
        if let Some(final_id) = self.definition.scoring.final_phase_id() {
            if let Some(value) = phase_results.get(final_id) {
                return *value;
            }
        }
        self.per_qso_totals.values().sum()
    }
}

fn points_for_phase(phase: &ContestPerQsoPhase, context: &ContestConditionContext) -> i64 {
    for rule in &phase.rules {
        if rule_matches(rule, context) {
            return rule.value;
        }
    }
    0
}

fn resolve_multiplier_source(source: &str, context: &ContestConditionContext) -> Option<String> {
    if source == "their_callsign_wpx" {
        return Some(callsign::wpx_prefix(&context.qso.callsign));
    }
    context.value(source).map(|value| value.comparable_string())
}

/// Recursively evaluate an aggregate operation tree.
fn evaluate_aggregate(op: &ContestAggregateOp, resolved: &HashMap<String, i64>) -> i64 {
    match op {
        ContestAggregateOp::Reference { phase } => resolved.get(phase).copied().unwrap_or(0),
        ContestAggregateOp::Literal { value } => *value,
        ContestAggregateOp::Add { inputs } => inputs
            .iter()
            .fold(0, |acc, input| acc + evaluate_aggregate(input, resolved)),
        ContestAggregateOp::Multiply { inputs } => inputs
            .iter()
            .fold(1, |acc, input| acc * evaluate_aggregate(input, resolved)),
        ContestAggregateOp::Max { inputs } => inputs
            .iter()
            .map(|input| evaluate_aggregate(input, resolved))
            .max()
            .unwrap_or(0),
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;
    use crate::contest::model::{ContestAnnualSchedule, ContestCategory, ContestCondition,
        ContestConditionOp, ContestDupeRules, ContestDupeScope, ContestExchange,
        ContestMultiplierPhase, ContestSchedule, ContestScoring, ContestScoringRule};

    fn make_simple_contest(
        phases: Vec<ContestScoringPhase>,
        dupe_key: Vec<&str>,
    ) -> ContestDefinition {
        ContestDefinition {
            id: "test".to_string(),
            name: "Test Contest".to_string(),
            short_name: None,
            sponsor: None,
            modes: vec!["CW".to_string()],
            bands: vec!["20m".to_string(), "40m".to_string()],
            data_dependencies: None,
            schedule: ContestSchedule::Annual(ContestAnnualSchedule {
                rule: "last_full_weekend_november".to_string(),
                start_utc: "00:00".to_string(),
                start_day: "saturday".to_string(),
                duration_hours: 48.0,
            }),
            exchange: ContestExchange { sent: vec![], received: vec![] },
            dupe_rules: ContestDupeRules {
                scope: ContestDupeScope::Contest,
                key: dupe_key.into_iter().map(str::to_string).collect(),
                zero_point_qsos_count_for_mults: false,
            },
            scoring: ContestScoring { phases },
            operating_constraints: None,
            cabrillo: None,
            categories: vec![ContestCategory {
                id: "SO".to_string(),
                label: "Single Op".to_string(),
                band: None,
                power_classes: vec![],
                assisted: None,
                op_count: None,
            }],
            overlay_categories: vec![],
            experimental: false,
        }
    }

    fn per_qso_phase(id: &str, rules: Vec<ContestScoringRule>) -> ContestScoringPhase {
        ContestScoringPhase::PerQso(ContestPerQsoPhase {
            id: id.to_string(),
            description: None,
            rules,
        })
    }

    fn always_rule(value: i64) -> ContestScoringRule {
        ContestScoringRule { description: None, conditions: vec![], value }
    }

    fn make_record(callsign: &str, band: &str, country: Option<&str>, offset: i64) -> ContestQsoRecord {
        let base = Utc.with_ymd_and_hms(2026, 7, 4, 12, 0, 0).unwrap();
        let mut record = ContestQsoRecord::new(callsign, band, "CW", base + Duration::seconds(offset));
        record.their_country = country.map(str::to_string);
        record
    }

    #[test]
    fn per_qso_phase_awards_first_matching_rule() {
        // Mirror of `perQSOPhaseAwardsFirstMatchingRule`.
        let definition = make_simple_contest(
            vec![per_qso_phase(
                "qso_points",
                vec![
                    ContestScoringRule {
                        description: None,
                        conditions: vec![ContestCondition {
                            field: "their_country".to_string(),
                            op: ContestConditionOp::Eq,
                            value: None,
                            reference: Some("my_country".to_string()),
                        }],
                        value: 0,
                    },
                    always_rule(3),
                ],
            )],
            vec!["callsign"],
        );
        let mut engine = ContestEngine::new(
            definition,
            Some(MyStationContext::new("K4XL").with_country("United States")),
            0,
        );

        engine.register_qso(&make_record("W1ABC", "20m", Some("United States"), 0));
        engine.register_qso(&make_record("DL1ABC", "20m", Some("Germany"), 60));

        let score = engine.score_snapshot();
        assert_eq!(score.total_points, 3);
        assert_eq!(score.total_qsos, 2);
    }

    #[test]
    fn dupe_detection_honors_composite_key() {
        // Mirror of `dupeDetectionHonorsCompositeKey`.
        let definition =
            make_simple_contest(vec![per_qso_phase("qso_points", vec![always_rule(1)])],
                vec!["callsign", "band"]);
        let mut engine = ContestEngine::new(definition, None, 0);

        let first = engine.register_qso(&make_record("K4XL", "20m", None, 0));
        let dupe = engine.register_qso(&make_record("K4XL", "20m", None, 60));
        let cross = engine.register_qso(&make_record("K4XL", "40m", None, 120));

        assert_eq!(first, ContestDupeStatus::NewStation);
        assert_eq!(dupe, ContestDupeStatus::Dupe);
        assert_ne!(cross, ContestDupeStatus::Dupe);
    }

    #[test]
    fn multiplier_phase_accumulates_unique_values() {
        // Mirror of `multiplierPhaseAccumulatesUniqueValues`.
        let definition = make_simple_contest(
            vec![
                per_qso_phase("qso_points", vec![always_rule(1)]),
                ContestScoringPhase::MultiplierCount(ContestMultiplierPhase {
                    id: "mult_countries".to_string(),
                    description: None,
                    source: "their_country".to_string(),
                    scope: ContestMultiplierScope::PerContest,
                    include_zero_point_qsos: false,
                }),
            ],
            vec!["callsign"],
        );
        let mut engine = ContestEngine::new(definition, None, 0);

        engine.register_qso(&make_record("W1ABC", "20m", Some("United States"), 0));
        engine.register_qso(&make_record("DL1ABC", "20m", Some("Germany"), 60));
        engine.register_qso(&make_record("DL2ABC", "20m", Some("Germany"), 120));

        assert_eq!(engine.score_snapshot().multiplier_count, 2);
    }

    #[test]
    fn wpx_prefix_multiplier_counts_unique_prefixes() {
        // Mirror of `wpxPrefixMultiplierCountsUniquePrefixes`.
        let definition = make_simple_contest(
            vec![
                per_qso_phase("qso_points", vec![always_rule(1)]),
                ContestScoringPhase::MultiplierCount(ContestMultiplierPhase {
                    id: "mult_prefixes".to_string(),
                    description: None,
                    source: "their_callsign_wpx".to_string(),
                    scope: ContestMultiplierScope::PerContest,
                    include_zero_point_qsos: false,
                }),
            ],
            vec!["callsign"],
        );
        let mut engine = ContestEngine::new(definition, None, 0);

        engine.register_qso(&make_record("K1XX", "20m", None, 0));
        // Same prefix (K1), different callsign → not a dupe, no new multiplier.
        engine.register_qso(&make_record("K1ZZ", "20m", None, 60));
        engine.register_qso(&make_record("VE3ABC", "20m", None, 120));

        assert_eq!(engine.score_snapshot().multiplier_count, 2);
    }

    #[test]
    fn new_multiplier_status_reports_phase_and_value() {
        let definition = make_simple_contest(
            vec![
                per_qso_phase("qso_points", vec![always_rule(1)]),
                ContestScoringPhase::MultiplierCount(ContestMultiplierPhase {
                    id: "mult_countries".to_string(),
                    description: None,
                    source: "their_country".to_string(),
                    scope: ContestMultiplierScope::PerContest,
                    include_zero_point_qsos: false,
                }),
            ],
            vec!["callsign"],
        );
        let mut engine = ContestEngine::new(definition, None, 0);

        let status = engine.register_qso(&make_record("DL1ABC", "20m", Some("Germany"), 0));
        assert_eq!(
            status,
            ContestDupeStatus::NewMultiplier {
                phase_id: "mult_countries".to_string(),
                value: "GERMANY".to_string(),
            }
        );
        // Second QSO from the same country: new station, not a new mult.
        let repeat = engine.register_qso(&make_record("DL2ABC", "20m", Some("Germany"), 60));
        assert_eq!(repeat, ContestDupeStatus::NewStation);
    }

    #[test]
    fn aggregate_final_phase_drives_final_score() {
        let definition = make_simple_contest(
            vec![
                per_qso_phase("qso_points", vec![always_rule(2)]),
                ContestScoringPhase::MultiplierCount(ContestMultiplierPhase {
                    id: "mults".to_string(),
                    description: None,
                    source: "their_country".to_string(),
                    scope: ContestMultiplierScope::PerContest,
                    include_zero_point_qsos: false,
                }),
                ContestScoringPhase::Aggregate(super::super::model::ContestAggregatePhase {
                    id: "total".to_string(),
                    description: None,
                    operation: ContestAggregateOp::Multiply {
                        inputs: vec![
                            ContestAggregateOp::Reference { phase: "qso_points".to_string() },
                            ContestAggregateOp::Reference { phase: "mults".to_string() },
                        ],
                    },
                }),
            ],
            vec!["callsign"],
        );
        let mut engine = ContestEngine::new(definition, None, 0);

        engine.register_qso(&make_record("DL1ABC", "20m", Some("Germany"), 0));
        engine.register_qso(&make_record("F1ABC", "20m", Some("France"), 60));

        let score = engine.score_snapshot();
        // 2 QSOs × 2 points = 4 points; 2 mults; total = 4 × 2 = 8.
        assert_eq!(score.total_points, 4);
        assert_eq!(score.multiplier_count, 2);
        assert_eq!(score.final_score, 8);
        assert_eq!(score.phase_results.get("total"), Some(&8));
    }

    #[test]
    fn serials_and_suggested_exchange() {
        let definition =
            make_simple_contest(vec![per_qso_phase("qso_points", vec![always_rule(1)])],
                vec!["callsign", "band"]);
        let mut engine = ContestEngine::new(definition, None, 5);
        assert_eq!(engine.current_serial(), 6);
        assert_eq!(engine.next_serial(), 6);
        assert_eq!(engine.current_serial(), 7);

        let mut record = make_record("K1XX", "20m", None, 0);
        record.received_exchange =
            HashMap::from([("state".to_string(), "OR".to_string())]);
        engine.register_qso(&record);
        assert_eq!(
            engine.suggested_exchange("k1xx/qrp"),
            Some(&HashMap::from([("state".to_string(), "OR".to_string())]))
        );
        assert_eq!(engine.suggested_exchange("W9XYZ"), None);
    }

    #[test]
    fn rescore_resets_state() {
        let definition =
            make_simple_contest(vec![per_qso_phase("qso_points", vec![always_rule(1)])],
                vec!["callsign"]);
        let mut engine = ContestEngine::new(definition, None, 0);
        engine.register_qso(&make_record("K1XX", "20m", None, 0));
        engine.register_qso(&make_record("K1XX", "20m", None, 60));
        assert_eq!(engine.score_snapshot().dupe_count, 1);

        // Rescore with out-of-order records: sorted before replay, dupes reset.
        engine.rescore(&[
            make_record("W2AAA", "20m", None, 120),
            make_record("K1XX", "20m", None, 0),
        ]);
        let score = engine.score_snapshot();
        assert_eq!(score.total_qsos, 2);
        assert_eq!(score.dupe_count, 0);
    }

    #[test]
    fn rate_and_time_series_use_injected_now() {
        let definition =
            make_simple_contest(vec![per_qso_phase("qso_points", vec![always_rule(1)])],
                vec!["callsign"]);
        let mut engine = ContestEngine::new(definition, None, 0);
        let base = Utc.with_ymd_and_hms(2026, 7, 4, 12, 0, 0).unwrap();
        engine.register_qso(&make_record("K1XX", "20m", None, 0));
        engine.register_qso(&make_record("K2XX", "20m", None, 600));
        engine.register_qso(&make_record("K3XX", "20m", None, 4200));

        let now = base + Duration::seconds(4260);
        // Last 60 minutes from `now` (cutoff 12:11:00): only the 13:10 QSO
        // is strictly after the cutoff.
        assert_eq!(engine.rate(60, now), 1.0);
        // Widen to 75 minutes (cutoff 11:56:00): all three QSOs count,
        // scaled to a per-hour rate.
        assert_eq!(engine.rate(75, now), 3.0 / 1.25);

        let series = engine.rate_time_series(60, now);
        assert_eq!(series.len(), 2);
        assert_eq!(series[0].count, 2);
        assert_eq!(series[1].count, 1);
    }
}
