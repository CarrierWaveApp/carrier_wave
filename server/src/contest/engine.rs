//! Scoring engine for contest definitions.
//!
//! Given a [`Contest`] from the loaded definition, a [`StationConfig`] for
//! the operator, and a [`CallsignResolver`] implementation, the engine
//! tracks dupes, accumulates multipliers, and computes per-phase and total
//! scores as QSOs are logged.
//!
//! ```ignore
//! let mut session = ContestSession::new(contest, station_config, my_resolver);
//! let scored = session.log_qso(QsoRecord { .. });
//! let summary = session.summary();
//! ```
//!
//! The engine never touches the filesystem or network. Callsign-to-DXCC
//! resolution is delegated to the [`CallsignResolver`] trait, which the
//! consumer implements with their own country file parser.

use std::collections::{BTreeMap, HashMap, HashSet};

use serde::Serialize;
use serde_json::Value;

use super::types::*;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Trait the consumer implements to resolve callsigns to DXCC entity info.
///
/// The library calls this once per logged QSO. Implementations should be
/// cheap (lookup in an in-memory map) since the engine itself does no
/// caching.
pub trait CallsignResolver {
    fn resolve(&self, callsign: &str) -> Option<ResolvedStation>;
}

/// DXCC entity information about a station, returned by [`CallsignResolver`].
#[derive(Debug, Clone, Serialize)]
pub struct ResolvedStation {
    pub country: String,
    pub continent: String,
    pub cq_zone: u8,
    pub itu_zone: u8,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub is_wae_entity: bool,
}

/// Operator's own station configuration.
///
/// Provides the `my_*` fields for condition evaluation and the autofill
/// values for sent exchange fields.
#[derive(Debug, Clone, Default)]
pub struct StationConfig {
    pub callsign: String,
    pub country: String,
    pub continent: String,
    pub cq_zone: u8,
    pub itu_zone: u8,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub grid: Option<String>,
    pub state: Option<String>,
    pub province: Option<String>,
    pub section: Option<String>,
    pub name: Option<String>,
    pub power: Option<String>,
    pub class: Option<String>,
}

/// A QSO submitted by the consumer for scoring.
#[derive(Debug, Clone)]
pub struct QsoRecord {
    /// Callsign of the worked station, as logged. May contain `/` suffixes
    /// like `/QRP` or `/M`; the engine normalizes them.
    pub callsign: String,
    pub band: String,
    pub mode: String,
    /// UTC timestamp in milliseconds since epoch.
    pub timestamp_ms: i64,
    pub frequency_khz: Option<u32>,
    /// Received exchange field values, keyed by field name.
    pub received: HashMap<String, Value>,
    /// If `Some`, use this serial as the sent serial. Used during rescore
    /// to preserve previously-assigned serials. If `None`, the engine
    /// assigns the next sequential value when the contest has an
    /// auto-incrementing sent serial.
    pub sent_serial: Option<u32>,
}

/// Result of scoring a single QSO.
#[derive(Debug, Clone, Serialize)]
pub struct ScoredQso {
    pub callsign: String,
    pub normalized_callsign: String,
    pub band: String,
    pub mode: String,
    pub timestamp_ms: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub resolved: Option<ResolvedStation>,
    pub points: i64,
    /// Index into the per_qso phase's `rules` array of the rule that matched,
    /// or `None` if no rule matched.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub matched_rule_index: Option<usize>,
    pub is_dupe: bool,
    /// Phase ids of `multiplier_count` phases that gained a new value
    /// from this QSO.
    pub new_multipliers: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sent_serial: Option<u32>,
}

/// Snapshot of the current score for a [`ContestSession`].
#[derive(Debug, Clone, Default, Serialize)]
pub struct ScoreSummary {
    pub qso_count: u32,
    pub dupe_count: u32,
    /// Per-phase results in definition order.
    pub phases: Vec<PhaseResult>,
    pub total: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct PhaseResult {
    pub id: String,
    pub kind: PhaseKind,
    pub value: i64,
    /// For multiplier_count phases with `per_band` scope: counts per band.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub per_band: BTreeMap<String, usize>,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PhaseKind {
    PerQso,
    MultiplierCount,
    Aggregate,
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

/// Mutable scoring state for a contest in progress.
pub struct ContestSession<R: CallsignResolver> {
    contest: Contest,
    station: StationConfig,
    resolver: R,

    qsos: Vec<ScoredQso>,
    dupe_index: HashSet<Vec<String>>,
    multiplier_acc: HashMap<String, MultiplierAcc>,
    next_serial: u32,
}

impl<R: CallsignResolver> ContestSession<R> {
    pub fn new(contest: Contest, station: StationConfig, resolver: R) -> Self {
        let multiplier_acc = contest
            .scoring
            .phases
            .iter()
            .filter_map(|p| match p {
                Phase::MultiplierCount { id, scope, .. } => {
                    Some((id.clone(), MultiplierAcc::new(*scope)))
                }
                _ => None,
            })
            .collect();

        Self {
            contest,
            station,
            resolver,
            qsos: Vec::new(),
            dupe_index: HashSet::new(),
            multiplier_acc,
            next_serial: 1,
        }
    }

    pub fn contest(&self) -> &Contest {
        &self.contest
    }

    pub fn station(&self) -> &StationConfig {
        &self.station
    }

    pub fn qsos(&self) -> &[ScoredQso] {
        &self.qsos
    }

    /// Score a single QSO and add it to the session log.
    ///
    /// Dupes are flagged but still appended to the log so the consumer can
    /// see them. Dupe QSOs do not contribute points or multipliers.
    pub fn log_qso(&mut self, record: QsoRecord) -> ScoredQso {
        let normalized = normalize_callsign(&record.callsign);
        let resolved = self.resolver.resolve(&normalized);

        let dupe_key = build_dupe_key(&self.contest.dupe_rules.key, &normalized, &record);
        let is_dupe = !self.dupe_index.insert(dupe_key);

        // Build the QSO context for condition evaluation.
        let ctx = QsoContext {
            station: &self.station,
            their_callsign: &normalized,
            band: &record.band,
            mode: &record.mode,
            resolved: resolved.as_ref(),
            received: &record.received,
        };

        // Per-QSO scoring (skipped for dupes).
        let (points, matched_rule_index) = if is_dupe {
            (0, None)
        } else {
            evaluate_per_qso_phase(&self.contest.scoring.phases, &ctx)
        };

        let counts_for_mults = !is_dupe
            && (points > 0 || self.contest.dupe_rules.zero_point_qsos_count_for_mults);

        // Multiplier accumulation.
        let mut new_multipliers = Vec::new();
        if counts_for_mults {
            for phase in &self.contest.scoring.phases {
                if let Phase::MultiplierCount {
                    id,
                    source,
                    include_zero_point_qsos,
                    ..
                } = phase
                {
                    if points == 0 && !include_zero_point_qsos {
                        continue;
                    }
                    let value = match ctx.get_string(source) {
                        Some(v) => v,
                        None => continue,
                    };
                    if let Some(acc) = self.multiplier_acc.get_mut(id) {
                        if acc.try_insert(&record.band, &value) {
                            new_multipliers.push(id.clone());
                        }
                    }
                }
            }
        }

        // Sent serial assignment.
        let sent_serial = if !is_dupe && self.has_auto_serial() {
            let value = record.sent_serial.unwrap_or(self.next_serial);
            self.next_serial = value.max(self.next_serial) + 1;
            Some(value)
        } else {
            None
        };

        let scored = ScoredQso {
            callsign: record.callsign,
            normalized_callsign: normalized,
            band: record.band,
            mode: record.mode,
            timestamp_ms: record.timestamp_ms,
            resolved,
            points,
            matched_rule_index,
            is_dupe,
            new_multipliers,
            sent_serial,
        };
        self.qsos.push(scored.clone());
        scored
    }

    /// Replace the session's log with a fresh score over the given records.
    /// Used after edits or deletions. Multipliers, dupes, and serial
    /// numbers are rebuilt from scratch.
    ///
    /// Records that already have a `sent_serial` set keep it; this matches
    /// real-world behavior where a previously-sent serial is already on
    /// the air and must not be reassigned.
    pub fn rescore(&mut self, records: Vec<QsoRecord>) {
        self.qsos.clear();
        self.dupe_index.clear();
        for acc in self.multiplier_acc.values_mut() {
            acc.clear();
        }
        self.next_serial = 1;
        for record in records {
            self.log_qso(record);
        }
    }

    /// Snapshot the current score across all phases.
    pub fn summary(&self) -> ScoreSummary {
        let mut phase_results: HashMap<String, i64> = HashMap::new();
        let mut phases = Vec::with_capacity(self.contest.scoring.phases.len());

        for phase in &self.contest.scoring.phases {
            match phase {
                Phase::PerQso { id, .. } => {
                    let total: i64 = self.qsos.iter().map(|q| q.points).sum();
                    phase_results.insert(id.clone(), total);
                    phases.push(PhaseResult {
                        id: id.clone(),
                        kind: PhaseKind::PerQso,
                        value: total,
                        per_band: BTreeMap::new(),
                    });
                }
                Phase::MultiplierCount { id, .. } => {
                    let acc = self
                        .multiplier_acc
                        .get(id)
                        .expect("multiplier accumulator initialized in new()");
                    let count = acc.count() as i64;
                    phase_results.insert(id.clone(), count);
                    phases.push(PhaseResult {
                        id: id.clone(),
                        kind: PhaseKind::MultiplierCount,
                        value: count,
                        per_band: acc.per_band_counts(),
                    });
                }
                Phase::Aggregate { id, operation, .. } => {
                    let value = evaluate_aggregate(operation, &phase_results);
                    phase_results.insert(id.clone(), value);
                    phases.push(PhaseResult {
                        id: id.clone(),
                        kind: PhaseKind::Aggregate,
                        value,
                        per_band: BTreeMap::new(),
                    });
                }
            }
        }

        let qso_count = self.qsos.iter().filter(|q| !q.is_dupe).count() as u32;
        let dupe_count = self.qsos.iter().filter(|q| q.is_dupe).count() as u32;
        let total = phases.last().map(|p| p.value).unwrap_or(0);

        ScoreSummary {
            qso_count,
            dupe_count,
            phases,
            total,
        }
    }

    fn has_auto_serial(&self) -> bool {
        self.contest.exchange.sent.iter().any(|f| {
            f.field_type == "serial_number" && f.auto_increment.unwrap_or(false)
        })
    }
}

// ---------------------------------------------------------------------------
// Callsign normalization
// ---------------------------------------------------------------------------

/// Strip portable suffixes that don't change DXCC entity, then uppercase.
///
/// Examples:
/// - `K1ABC/QRP` → `K1ABC`
/// - `K1ABC/M` → `K1ABC`
/// - `K1ABC/P` → `K1ABC`
/// - `VE3XYZ/W1` → `W1/VE3XYZ` is *not* handled here; the leading `W1/`
///   form is a different entity. We only strip trailing single-letter and
///   well-known short suffixes.
pub fn normalize_callsign(call: &str) -> String {
    let upper = call.to_uppercase();
    let stripped = match upper.rsplit_once('/') {
        Some((base, suffix)) if is_strippable_suffix(suffix) => base.to_string(),
        _ => upper,
    };
    stripped
}

fn is_strippable_suffix(suffix: &str) -> bool {
    matches!(suffix, "P" | "M" | "MM" | "AM" | "QRP" | "QRPP" | "A")
}

// ---------------------------------------------------------------------------
// WPX prefix
// ---------------------------------------------------------------------------

/// Derive the CQ WPX contest prefix from a callsign, following the WPX
/// prefix rules:
/// - Simple call: letters/numerals up to and including the last digit
///   (`K4XL` → `K4`, `VE3XYZ` → `VE3`, `4U1UN` → `4U1`, `OE25XYZ` → `OE25`).
/// - No digit anywhere: a zero after the first two letters (`RAEM` → `RA0`).
/// - Portable host designator (letters): that designator forms the prefix
///   (`KH6/N8BJQ` → `KH6`, `PA/N8BJQ` → `PA0`, `VP2E/K4XL` → `VP2`).
/// - Single-number portable: home-call letters + that digit
///   (`N8BJQ/9` → `N9`, `WB8XYZ/4` → `WB4`).
///
/// The bare-number portable case can only be resolved exactly with a country
/// file (the official rule maps it to the operating country's prefix). We
/// approximate with the home call's leading letters, which yields a valid and
/// distinct prefix for multiplier purposes.
pub fn wpx_prefix(call: &str) -> String {
    let normalized = normalize_callsign(call);
    match normalized.split_once('/') {
        Some((left, right)) => wpx_prefix_portable(left, right),
        None => prefix_from_designator(&normalized),
    }
}

fn wpx_prefix_portable(left: &str, right: &str) -> String {
    if is_all_digits(left) {
        return format!("{}{}", alpha_lead(right), left);
    }
    if is_all_digits(right) {
        return format!("{}{}", alpha_lead(left), right);
    }
    // Both sides are alphanumeric designators/calls. The shorter side is the
    // operating prefix; ties go to the leading side (the host designator by
    // signing convention, e.g. `KH6/N8BJQ`).
    let designator = if left.chars().count() <= right.chars().count() {
        left
    } else {
        right
    };
    prefix_from_designator(designator)
}

/// Prefix from a designator that is not a bare number: letters/numerals up to
/// and including the last digit, or — when there is no digit — a zero after
/// the first two letters.
fn prefix_from_designator(designator: &str) -> String {
    match designator.rfind(|c: char| c.is_ascii_digit()) {
        Some(idx) => designator[..=idx].to_string(),
        None => {
            let head: String = designator.chars().take(2).collect();
            format!("{head}0")
        }
    }
}

/// Leading alphabetic characters of a callsign (the part before the first digit).
fn alpha_lead(call: &str) -> String {
    let lead: String = call.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    if lead.is_empty() {
        call.to_string()
    } else {
        lead
    }
}

fn is_all_digits(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_digit())
}

// ---------------------------------------------------------------------------
// Dupe key
// ---------------------------------------------------------------------------

fn build_dupe_key(key_parts: &[String], normalized_call: &str, record: &QsoRecord) -> Vec<String> {
    key_parts
        .iter()
        .map(|part| match part.as_str() {
            "callsign" => normalized_call.to_string(),
            "band" => record.band.clone(),
            "mode" => record.mode.clone(),
            "mode_group" => collapse_mode_group(&record.mode).to_string(),
            other => other.to_string(),
        })
        .collect()
}

fn collapse_mode_group(mode: &str) -> &'static str {
    match mode.to_uppercase().as_str() {
        "CW" => "CW",
        "SSB" | "USB" | "LSB" | "AM" | "FM" => "PHONE",
        _ => "DIGITAL",
    }
}

// ---------------------------------------------------------------------------
// QSO context for condition / multiplier source evaluation
// ---------------------------------------------------------------------------

struct QsoContext<'a> {
    station: &'a StationConfig,
    their_callsign: &'a str,
    band: &'a str,
    mode: &'a str,
    resolved: Option<&'a ResolvedStation>,
    received: &'a HashMap<String, Value>,
}

impl<'a> QsoContext<'a> {
    fn get(&self, field: &str) -> Option<Value> {
        if let Some(name) = field.strip_prefix("received.") {
            return self.received.get(name).cloned();
        }
        match field {
            "their_callsign" => Some(Value::String(self.their_callsign.to_string())),
            "their_callsign_wpx" => Some(Value::String(wpx_prefix(self.their_callsign))),
            "their_country" => self.resolved.map(|r| Value::String(r.country.clone())),
            "their_continent" => self.resolved.map(|r| Value::String(r.continent.clone())),
            "their_cq_zone" => self.resolved.map(|r| Value::from(r.cq_zone)),
            "their_itu_zone" => self.resolved.map(|r| Value::from(r.itu_zone)),
            "my_country" => Some(Value::String(self.station.country.clone())),
            "my_continent" => Some(Value::String(self.station.continent.clone())),
            "my_cq_zone" => Some(Value::from(self.station.cq_zone)),
            "my_itu_zone" => Some(Value::from(self.station.itu_zone)),
            "band" => Some(Value::String(self.band.to_string())),
            "mode" => Some(Value::String(self.mode.to_string())),
            "mode_group" => Some(Value::String(collapse_mode_group(self.mode).to_string())),
            "distance_km" => self.distance_km().map(Value::from),
            _ => None,
        }
    }

    fn get_string(&self, field: &str) -> Option<String> {
        let value = self.get(field)?;
        match value {
            Value::String(s) => Some(s),
            Value::Number(n) => Some(n.to_string()),
            Value::Bool(b) => Some(b.to_string()),
            Value::Null => None,
            _ => Some(value.to_string()),
        }
    }

    fn distance_km(&self) -> Option<i64> {
        let (lat1, lon1) = (self.station.latitude?, self.station.longitude?);
        let resolved = self.resolved?;
        let (lat2, lon2) = (resolved.latitude?, resolved.longitude?);
        Some(great_circle_km(lat1, lon1, lat2, lon2) as i64)
    }
}

fn great_circle_km(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const R: f64 = 6371.0;
    let to_rad = std::f64::consts::PI / 180.0;
    let phi1 = lat1 * to_rad;
    let phi2 = lat2 * to_rad;
    let dphi = (lat2 - lat1) * to_rad;
    let dlam = (lon2 - lon1) * to_rad;
    let a = (dphi / 2.0).sin().powi(2)
        + phi1.cos() * phi2.cos() * (dlam / 2.0).sin().powi(2);
    let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());
    R * c
}

// ---------------------------------------------------------------------------
// Per-QSO rule evaluation
// ---------------------------------------------------------------------------

fn evaluate_per_qso_phase(phases: &[Phase], ctx: &QsoContext) -> (i64, Option<usize>) {
    // The format allows multiple per_qso phases in principle, but in
    // practice every contest in the spec has exactly one. We score the
    // first per_qso phase and ignore any others (they would be summed by
    // an aggregate phase if needed).
    for phase in phases {
        if let Phase::PerQso { rules, .. } = phase {
            return evaluate_rules(rules, ctx);
        }
    }
    (0, None)
}

fn evaluate_rules(rules: &[Rule], ctx: &QsoContext) -> (i64, Option<usize>) {
    for (i, rule) in rules.iter().enumerate() {
        if rule.conditions.iter().all(|c| evaluate_condition(c, ctx)) {
            return (rule.value, Some(i));
        }
    }
    (0, None)
}

fn evaluate_condition(cond: &Condition, ctx: &QsoContext) -> bool {
    let left = match ctx.get(&cond.field) {
        Some(v) => v,
        None => return false,
    };

    if let Some(reference) = &cond.reference {
        let right = match ctx.get(reference) {
            Some(v) => v,
            None => return false,
        };
        return compare(&left, cond.op, &right);
    }
    if let Some(value) = &cond.value {
        return compare(&left, cond.op, value);
    }
    false
}

fn compare(left: &Value, op: ConditionOp, right: &Value) -> bool {
    match op {
        ConditionOp::Eq => values_equal(left, right),
        ConditionOp::Ne => !values_equal(left, right),
        ConditionOp::In => match right {
            Value::Array(items) => items.iter().any(|i| values_equal(left, i)),
            _ => false,
        },
        ConditionOp::NotIn => match right {
            Value::Array(items) => !items.iter().any(|i| values_equal(left, i)),
            _ => false,
        },
        ConditionOp::Gt | ConditionOp::Gte | ConditionOp::Lt | ConditionOp::Lte => {
            match (value_as_f64(left), value_as_f64(right)) {
                (Some(l), Some(r)) => match op {
                    ConditionOp::Gt => l > r,
                    ConditionOp::Gte => l >= r,
                    ConditionOp::Lt => l < r,
                    ConditionOp::Lte => l <= r,
                    _ => unreachable!(),
                },
                _ => false,
            }
        }
    }
}

fn values_equal(left: &Value, right: &Value) -> bool {
    match (left, right) {
        (Value::String(a), Value::String(b)) => a.eq_ignore_ascii_case(b),
        (Value::Number(a), Value::Number(b)) => a == b,
        (Value::Number(a), Value::String(b)) | (Value::String(b), Value::Number(a)) => {
            a.to_string() == *b
        }
        _ => left == right,
    }
}

fn value_as_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// Multiplier accumulator
// ---------------------------------------------------------------------------

enum MultiplierAcc {
    PerContest(HashSet<String>),
    PerBand(HashMap<String, HashSet<String>>),
}

impl MultiplierAcc {
    fn new(scope: MultiplierScope) -> Self {
        match scope {
            MultiplierScope::PerContest => Self::PerContest(HashSet::new()),
            MultiplierScope::PerBand => Self::PerBand(HashMap::new()),
        }
    }

    fn try_insert(&mut self, band: &str, value: &str) -> bool {
        match self {
            Self::PerContest(set) => set.insert(value.to_string()),
            Self::PerBand(map) => map
                .entry(band.to_string())
                .or_default()
                .insert(value.to_string()),
        }
    }

    fn count(&self) -> usize {
        match self {
            Self::PerContest(set) => set.len(),
            Self::PerBand(map) => map.values().map(|s| s.len()).sum(),
        }
    }

    fn per_band_counts(&self) -> BTreeMap<String, usize> {
        match self {
            Self::PerContest(_) => BTreeMap::new(),
            Self::PerBand(map) => map
                .iter()
                .map(|(k, v)| (k.clone(), v.len()))
                .collect(),
        }
    }

    fn clear(&mut self) {
        match self {
            Self::PerContest(set) => set.clear(),
            Self::PerBand(map) => map.clear(),
        }
    }
}

// ---------------------------------------------------------------------------
// Aggregate evaluation
// ---------------------------------------------------------------------------

fn evaluate_aggregate(op: &AggregateOp, phase_results: &HashMap<String, i64>) -> i64 {
    match op {
        AggregateOp::Ref { phase } => *phase_results.get(phase).unwrap_or(&0),
        AggregateOp::Literal { value } => *value,
        AggregateOp::Add { inputs } => inputs
            .iter()
            .map(|i| evaluate_aggregate(i, phase_results))
            .sum(),
        AggregateOp::Multiply { inputs } => inputs
            .iter()
            .map(|i| evaluate_aggregate(i, phase_results))
            .product(),
        AggregateOp::Max { inputs } => inputs
            .iter()
            .map(|i| evaluate_aggregate(i, phase_results))
            .max()
            .unwrap_or(0),
    }
}
