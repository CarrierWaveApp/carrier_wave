//! Contest definition model (server format v0.3). Port of
//! `Models/ContestDefinition.swift`, `ContestExchange.swift`,
//! `ContestScoring.swift`, `ContestScoringRule.swift`, `ContestSchedule.swift`,
//! and `ContestOperatingConstraints.swift`.
//!
//! Wire compatibility with the Swift `Codable` decoders is the contract:
//! snake_case keys, tolerant `unknown` exchange-field types, defaulted
//! optional-in-spirit collections, and hard errors on unknown phase types /
//! schedule types / aggregate ops (exactly where Swift throws).

use serde::de::Error as _;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Parse a contest definition from server JSON.
pub fn parse_definition(json: &str) -> Result<ContestDefinition, serde_json::Error> {
    serde_json::from_str(json)
}

// ---- Definition root -------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestDefinition {
    pub id: String,
    pub name: String,
    #[serde(rename = "short_name", default, skip_serializing_if = "Option::is_none")]
    pub short_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sponsor: Option<ContestSponsor>,
    pub modes: Vec<String>,
    pub bands: Vec<String>,
    #[serde(rename = "data_dependencies", default, skip_serializing_if = "Option::is_none")]
    pub data_dependencies: Option<ContestDataDependencies>,
    pub schedule: ContestSchedule,
    pub exchange: ContestExchange,
    #[serde(rename = "dupe_rules")]
    pub dupe_rules: ContestDupeRules,
    pub scoring: ContestScoring,
    #[serde(rename = "operating_constraints", default, skip_serializing_if = "Option::is_none")]
    pub operating_constraints: Option<ContestOperatingConstraints>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cabrillo: Option<ContestCabrillo>,
    #[serde(default)]
    pub categories: Vec<ContestCategory>,
    #[serde(rename = "overlay_categories", default)]
    pub overlay_categories: Vec<ContestOverlayCategory>,
    #[serde(default)]
    pub experimental: bool,
}

impl ContestDefinition {
    /// Display short name if set, otherwise full name.
    pub fn display_name(&self) -> &str {
        self.short_name.as_deref().unwrap_or(&self.name)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ContestSponsor {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ContestDataDependencies {
    #[serde(rename = "country_file", default, skip_serializing_if = "Option::is_none")]
    pub country_file: Option<ContestDataDependency>,
    #[serde(rename = "prefix_map", default, skip_serializing_if = "Option::is_none")]
    pub prefix_map: Option<ContestDataDependency>,
    #[serde(rename = "section_list", default, skip_serializing_if = "Option::is_none")]
    pub section_list: Option<ContestDataDependency>,
    #[serde(rename = "zone_map", default, skip_serializing_if = "Option::is_none")]
    pub zone_map: Option<ContestDataDependency>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestDataDependency {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(rename = "update_frequency", default, skip_serializing_if = "Option::is_none")]
    pub update_frequency: Option<ContestUpdateFrequency>,
    #[serde(default)]
    pub provides: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContestUpdateFrequency {
    #[serde(rename = "static")]
    Static,
    #[serde(rename = "monthly")]
    Monthly,
    #[serde(rename = "weekly")]
    Weekly,
    #[serde(rename = "before_each_contest")]
    BeforeEachContest,
}

// ---- Exchange ---------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestExchange {
    pub sent: Vec<ContestExchangeField>,
    pub received: Vec<ContestExchangeField>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestExchangeField {
    pub name: String,
    #[serde(rename = "type")]
    pub field_type: ContestExchangeFieldType,
    pub label: String,
    #[serde(default = "default_true")]
    pub required: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autofill: Option<String>,
    #[serde(rename = "auto_increment", default, skip_serializing_if = "Option::is_none")]
    pub auto_increment: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub list: Option<String>,
    #[serde(rename = "default", default, skip_serializing_if = "Option::is_none")]
    pub default_value: Option<ContestExchangeDefault>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pattern: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max: Option<f64>,
}

fn default_true() -> bool {
    true
}

/// Known field types from the contest-definitions spec (v0.3).
/// Unknown types decode to `Unknown(raw)` so we don't fail hard on new types.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum ContestExchangeFieldType {
    Text,
    SignalReport,
    SerialNumber,
    CqZone,
    ItuZone,
    GridSquare,
    StateProvince,
    ArrlSection,
    SectionList,
    Power,
    Name,
    Age,
    Class,
    Unknown(String),
}

impl ContestExchangeFieldType {
    pub fn from_raw(raw: &str) -> Self {
        match raw {
            "text" => Self::Text,
            "signal_report" => Self::SignalReport,
            "serial_number" => Self::SerialNumber,
            "cq_zone" => Self::CqZone,
            "itu_zone" => Self::ItuZone,
            "grid_square" => Self::GridSquare,
            "state_province" => Self::StateProvince,
            "arrl_section" => Self::ArrlSection,
            "section_list" => Self::SectionList,
            "power" => Self::Power,
            "name" => Self::Name,
            "age" => Self::Age,
            "class" => Self::Class,
            other => Self::Unknown(other.to_string()),
        }
    }

    pub fn raw_value(&self) -> &str {
        match self {
            Self::Text => "text",
            Self::SignalReport => "signal_report",
            Self::SerialNumber => "serial_number",
            Self::CqZone => "cq_zone",
            Self::ItuZone => "itu_zone",
            Self::GridSquare => "grid_square",
            Self::StateProvince => "state_province",
            Self::ArrlSection => "arrl_section",
            Self::SectionList => "section_list",
            Self::Power => "power",
            Self::Name => "name",
            Self::Age => "age",
            Self::Class => "class",
            Self::Unknown(raw) => raw,
        }
    }

    /// True if the field value is numeric (serial, zone, age).
    pub fn is_numeric(&self) -> bool {
        matches!(self, Self::SerialNumber | Self::CqZone | Self::ItuZone | Self::Age)
    }
}

impl<'de> Deserialize<'de> for ContestExchangeFieldType {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(deserializer)?;
        Ok(Self::from_raw(&raw))
    }
}

impl Serialize for ContestExchangeFieldType {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.raw_value())
    }
}

/// Default value for an exchange field. Can be a string, number, or bool.
#[derive(Debug, Clone, PartialEq)]
pub enum ContestExchangeDefault {
    String(String),
    Number(f64),
    Bool(bool),
}

impl ContestExchangeDefault {
    /// String form suitable for display or pre-filling an entry field.
    pub fn string_value(&self) -> String {
        match self {
            Self::String(value) => value.clone(),
            Self::Number(value) => render_number(*value),
            Self::Bool(value) => if *value { "true" } else { "false" }.to_string(),
        }
    }
}

impl<'de> Deserialize<'de> for ContestExchangeDefault {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        match value {
            serde_json::Value::String(text) => Ok(Self::String(text)),
            serde_json::Value::Number(number) => number
                .as_f64()
                .map(Self::Number)
                .ok_or_else(|| D::Error::custom("Unsupported default-value number")),
            serde_json::Value::Bool(flag) => Ok(Self::Bool(flag)),
            _ => Err(D::Error::custom("Unsupported default-value type")),
        }
    }
}

impl Serialize for ContestExchangeDefault {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::String(value) => serializer.serialize_str(value),
            Self::Number(value) => serializer.serialize_f64(*value),
            Self::Bool(value) => serializer.serialize_bool(*value),
        }
    }
}

// ---- Dupe rules -------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestDupeRules {
    /// Whether uniqueness resets every session window (`session`) or spans
    /// the whole contest (`contest`).
    pub scope: ContestDupeScope,
    /// Composite key components (e.g. `["callsign", "band"]`).
    pub key: Vec<String>,
    /// If true, a non-dupe QSO that scores 0 points still contributes to
    /// mult sets.
    #[serde(rename = "zero_point_qsos_count_for_mults", default)]
    pub zero_point_qsos_count_for_mults: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContestDupeScope {
    #[serde(rename = "session")]
    Session,
    #[serde(rename = "contest")]
    Contest,
}

// ---- Scoring ----------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestScoring {
    /// Phase evaluation is DAG-ordered: a later phase may reference the
    /// result of an earlier phase. The last phase (typically `total`) is
    /// the contest's final score.
    pub phases: Vec<ContestScoringPhase>,
}

impl ContestScoring {
    /// The phase id that should be surfaced as "final score", if any. By
    /// convention this is the last phase in the array.
    pub fn final_phase_id(&self) -> Option<&str> {
        self.phases.last().map(ContestScoringPhase::id)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ContestScoringPhase {
    #[serde(rename = "per_qso")]
    PerQso(ContestPerQsoPhase),
    #[serde(rename = "multiplier_count")]
    MultiplierCount(ContestMultiplierPhase),
    #[serde(rename = "aggregate")]
    Aggregate(ContestAggregatePhase),
}

impl ContestScoringPhase {
    pub fn id(&self) -> &str {
        match self {
            Self::PerQso(phase) => &phase.id,
            Self::MultiplierCount(phase) => &phase.id,
            Self::Aggregate(phase) => &phase.id,
        }
    }

    pub fn description(&self) -> Option<&str> {
        match self {
            Self::PerQso(phase) => phase.description.as_deref(),
            Self::MultiplierCount(phase) => phase.description.as_deref(),
            Self::Aggregate(phase) => phase.description.as_deref(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestPerQsoPhase {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub rules: Vec<ContestScoringRule>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestMultiplierPhase {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    /// Condition-vocabulary field that produces multiplier values
    /// (e.g. `their_country`, `received.cq_zone`).
    pub source: String,
    pub scope: ContestMultiplierScope,
    #[serde(rename = "include_zero_point_qsos", default)]
    pub include_zero_point_qsos: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContestMultiplierScope {
    #[serde(rename = "per_band")]
    PerBand,
    #[serde(rename = "per_contest")]
    PerContest,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestAggregatePhase {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub operation: ContestAggregateOp,
}

/// Recursive arithmetic tree used by `aggregate` scoring phases.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op")]
pub enum ContestAggregateOp {
    #[serde(rename = "ref")]
    Reference { phase: String },
    #[serde(rename = "literal")]
    Literal { value: i64 },
    #[serde(rename = "add")]
    Add { inputs: Vec<ContestAggregateOp> },
    #[serde(rename = "multiply")]
    Multiply { inputs: Vec<ContestAggregateOp> },
    #[serde(rename = "max")]
    Max { inputs: Vec<ContestAggregateOp> },
}

// ---- Scoring rules ------------------------------------------------------

/// A single rule in a `per_qso` phase. Conditions are evaluated as a
/// conjunction (AND); first rule whose conditions all pass wins.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestScoringRule {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default)]
    pub conditions: Vec<ContestCondition>,
    pub value: i64,
}

/// Predicate evaluated against a QSO + station context.
///
/// Exactly one of `value` or `reference` is set (enforced by the server-side
/// validator; on the client we treat an empty condition as "always match").
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestCondition {
    pub field: String,
    pub op: ContestConditionOp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<JsonValue>,
    #[serde(rename = "ref", default, skip_serializing_if = "Option::is_none")]
    pub reference: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContestConditionOp {
    #[serde(rename = "eq")]
    Eq,
    #[serde(rename = "ne")]
    Ne,
    #[serde(rename = "in")]
    In,
    #[serde(rename = "not_in")]
    NotIn,
    #[serde(rename = "gt")]
    Gt,
    #[serde(rename = "gte")]
    Gte,
    #[serde(rename = "lt")]
    Lt,
    #[serde(rename = "lte")]
    Lte,
}

/// Polymorphic JSON value used by scoring-condition literals. Supports the
/// subset of JSON we actually encounter in contest definitions.
#[derive(Debug, Clone, PartialEq)]
pub enum JsonValue {
    String(String),
    Int(i64),
    Double(f64),
    Bool(bool),
    Array(Vec<JsonValue>),
    Null,
}

impl JsonValue {
    /// A normalized string used for equality comparisons. Numbers are
    /// rendered without unnecessary trailing zeros so that `5 == "5"` in
    /// contest-condition semantics.
    pub fn string_value(&self) -> Option<String> {
        match self {
            Self::String(value) => Some(value.clone()),
            Self::Int(value) => Some(value.to_string()),
            Self::Double(value) => Some(render_number(*value)),
            Self::Bool(value) => Some(if *value { "true" } else { "false" }.to_string()),
            Self::Array(_) | Self::Null => None,
        }
    }

    pub fn array_value(&self) -> Option<&[JsonValue]> {
        match self {
            Self::Array(values) => Some(values),
            _ => None,
        }
    }

    fn from_serde(value: serde_json::Value) -> Result<Self, String> {
        match value {
            serde_json::Value::Null => Ok(Self::Null),
            serde_json::Value::Bool(flag) => Ok(Self::Bool(flag)),
            serde_json::Value::Number(number) => {
                if let Some(int) = number.as_i64() {
                    Ok(Self::Int(int))
                } else if let Some(double) = number.as_f64() {
                    Ok(Self::Double(double))
                } else {
                    Err("Unsupported JSON literal".to_string())
                }
            }
            serde_json::Value::String(text) => Ok(Self::String(text)),
            serde_json::Value::Array(values) => Ok(Self::Array(
                values
                    .into_iter()
                    .map(Self::from_serde)
                    .collect::<Result<Vec<_>, _>>()?,
            )),
            serde_json::Value::Object(_) => Err("Unsupported JSON literal".to_string()),
        }
    }
}

impl<'de> Deserialize<'de> for JsonValue {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        Self::from_serde(value).map_err(D::Error::custom)
    }
}

impl Serialize for JsonValue {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::String(value) => serializer.serialize_str(value),
            Self::Int(value) => serializer.serialize_i64(*value),
            Self::Double(value) => serializer.serialize_f64(*value),
            Self::Bool(value) => serializer.serialize_bool(*value),
            Self::Array(values) => values.serialize(serializer),
            Self::Null => serializer.serialize_none(),
        }
    }
}

/// Render a float the way Swift's `String(Int(value))` / `String(value)`
/// pair does in `stringValue`: integral values drop the fraction entirely.
pub(crate) fn render_number(value: f64) -> String {
    if value.fract() == 0.0 && value.is_finite() {
        format!("{}", value as i64)
    } else {
        format!("{value}")
    }
}

// ---- Schedule ----------------------------------------------------------

/// When the contest runs. One of three shapes, discriminated by `type`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ContestSchedule {
    #[serde(rename = "recurring_weekly")]
    RecurringWeekly {
        sessions: Vec<ContestWeeklySession>,
        #[serde(rename = "session_scoring")]
        scoring: ContestSessionScoring,
    },
    #[serde(rename = "annual")]
    Annual(ContestAnnualSchedule),
    #[serde(rename = "fixed_dates")]
    FixedDates { occurrences: Vec<ContestFixedOccurrence> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestWeeklySession {
    pub day: String,
    #[serde(rename = "start_utc")]
    pub start_utc: String,
    #[serde(rename = "duration_minutes")]
    pub duration_minutes: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContestSessionScoring {
    #[serde(rename = "independent")]
    Independent,
    #[serde(rename = "cumulative")]
    Cumulative,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestAnnualSchedule {
    pub rule: String,
    #[serde(rename = "start_utc")]
    pub start_utc: String,
    #[serde(rename = "start_day")]
    pub start_day: String,
    #[serde(rename = "duration_hours")]
    pub duration_hours: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestFixedOccurrence {
    pub start: String,
    #[serde(rename = "duration_hours")]
    pub duration_hours: f64,
}

// ---- Operating constraints ----------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ContestOperatingConstraints {
    #[serde(rename = "off_time", default, skip_serializing_if = "Option::is_none")]
    pub off_time: Option<ContestOffTimeRules>,
    #[serde(rename = "band_changes", default, skip_serializing_if = "Option::is_none")]
    pub band_changes: Option<ContestBandChangeRules>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ContestOffTimeRules {
    /// A break only counts as off-time if it is at least this many minutes.
    #[serde(rename = "minimum_off_minutes", default, skip_serializing_if = "Option::is_none")]
    pub minimum_off_minutes: Option<i64>,
    /// Map of category id → max on-air hours.
    #[serde(rename = "maximum_on_hours_by_category", default)]
    pub maximum_on_hours_by_category: std::collections::HashMap<String, f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct ContestBandChangeRules {
    /// List of category ids the band-change limits apply to. Empty = all.
    #[serde(rename = "applies_to", default)]
    pub applies_to: Vec<String>,
    /// After changing bands, must remain on new band for at least this long.
    #[serde(rename = "min_minutes_on_band", default, skip_serializing_if = "Option::is_none")]
    pub min_minutes_on_band: Option<i64>,
    /// Max band changes within any clock hour.
    #[serde(rename = "max_changes_per_clock_hour", default, skip_serializing_if = "Option::is_none")]
    pub max_changes_per_clock_hour: Option<i64>,
}

// ---- Cabrillo / categories ------------------------------------------------

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestCabrillo {
    /// Value used in the `CONTEST:` header line.
    #[serde(rename = "contest_name")]
    pub contest_name: String,
    /// Cabrillo version (usually `"3.0"`).
    pub version: String,
    /// Optional explicit QSO line layout override (v0.4+).
    #[serde(rename = "qso_format", default, skip_serializing_if = "Option::is_none")]
    pub qso_format: Option<JsonValue>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestCategory {
    pub id: String,
    pub label: String,
    /// Specific band this category is locked to, if any (e.g. "20m" for SOSB).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band: Option<String>,
    /// Accepted power class identifiers (e.g. `["HIGH", "LOW", "QRP"]`).
    #[serde(rename = "power_classes", default)]
    pub power_classes: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assisted: Option<bool>,
    #[serde(rename = "op_count", default, skip_serializing_if = "Option::is_none")]
    pub op_count: Option<ContestOpCount>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ContestOpCount {
    #[serde(rename = "single")]
    Single,
    #[serde(rename = "multi")]
    Multi,
    #[serde(rename = "multi_two")]
    MultiTwo,
    #[serde(rename = "multi_multi")]
    MultiMulti,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContestOverlayCategory {
    pub id: String,
    pub label: String,
    #[serde(rename = "max_on_hours", default, skip_serializing_if = "Option::is_none")]
    pub max_on_hours: Option<i64>,
    #[serde(rename = "max_license_years", default, skip_serializing_if = "Option::is_none")]
    pub max_license_years: Option<i64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_from_server_json() {
        // Mirror of `contestDefinitionDecodesFromServerJSON`.
        let json = r#"
        {
          "id": "sst",
          "name": "Slow Speed Test",
          "short_name": "SST",
          "modes": ["CW"],
          "bands": ["80m", "40m", "20m"],
          "schedule": {
            "type": "recurring_weekly",
            "sessions": [
              { "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }
            ],
            "session_scoring": "independent"
          },
          "exchange": {
            "sent": [
              { "name": "name", "type": "name", "label": "Name", "autofill": "station_name" },
              { "name": "state", "type": "state_province", "label": "State", "autofill": "station_state" }
            ],
            "received": [
              { "name": "name", "type": "name", "label": "Name" },
              { "name": "state", "type": "state_province", "label": "State" }
            ]
          },
          "dupe_rules": {
            "scope": "session",
            "key": ["callsign"]
          },
          "scoring": {
            "phases": [
              { "id": "qso_points", "type": "per_qso", "rules": [ { "conditions": [], "value": 1 } ] },
              { "id": "total", "type": "aggregate", "operation": { "op": "ref", "phase": "qso_points" } }
            ]
          },
          "categories": [
            { "id": "SO", "label": "Single Op", "power_classes": ["HIGH", "LOW", "QRP"] }
          ]
        }
        "#;

        let definition = parse_definition(json).expect("decode");
        assert_eq!(definition.id, "sst");
        assert_eq!(definition.display_name(), "SST");
        assert_eq!(definition.exchange.received.len(), 2);
        assert_eq!(definition.dupe_rules.scope, ContestDupeScope::Session);
        assert_eq!(definition.scoring.phases.len(), 2);
        assert!(definition.overlay_categories.is_empty());
        assert!(!definition.experimental);
    }

    #[test]
    fn unknown_exchange_field_type_is_tolerated() {
        let field: ContestExchangeField = serde_json::from_str(
            r#"{ "name": "x", "type": "brand_new_type", "label": "X" }"#,
        )
        .expect("decode");
        assert_eq!(
            field.field_type,
            ContestExchangeFieldType::Unknown("brand_new_type".to_string())
        );
        assert!(field.required);
    }

    #[test]
    fn unknown_phase_type_errors() {
        let result: Result<ContestScoringPhase, _> =
            serde_json::from_str(r#"{ "id": "x", "type": "mystery" }"#);
        assert!(result.is_err());
    }

    #[test]
    fn aggregate_op_round_trips_recursively() {
        let json = r#"
        { "op": "multiply", "inputs": [
            { "op": "ref", "phase": "qso_points" },
            { "op": "add", "inputs": [
                { "op": "ref", "phase": "mults" },
                { "op": "literal", "value": 1 }
            ] }
        ] }
        "#;
        let op: ContestAggregateOp = serde_json::from_str(json).expect("decode");
        let encoded = serde_json::to_string(&op).expect("encode");
        let round: ContestAggregateOp = serde_json::from_str(&encoded).expect("re-decode");
        assert_eq!(op, round);
    }

    #[test]
    fn json_value_string_normalization() {
        assert_eq!(JsonValue::Int(5).string_value().as_deref(), Some("5"));
        assert_eq!(JsonValue::Double(5.0).string_value().as_deref(), Some("5"));
        assert_eq!(JsonValue::Double(3.5).string_value().as_deref(), Some("3.5"));
        assert_eq!(JsonValue::Bool(true).string_value().as_deref(), Some("true"));
        assert_eq!(JsonValue::Null.string_value(), None);
    }
}
