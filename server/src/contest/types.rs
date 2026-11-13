//! Data types for the contest definition format (v0.3).
//!
//! See `docs/features/contest-definitions.md` for the canonical reference.
//!
//! Structural validation (required fields, type matching, known enum values)
//! is enforced by serde during deserialization. Semantic validation (phase
//! DAG ordering, condition field vocabulary, exchange completeness, etc.)
//! is performed by [`ContestDefinition::validate`] in `validation.rs`.

use serde::{Deserialize, Serialize};

/// Top-level contest definition file. May contain one or more contests.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ContestDefinition {
    #[serde(rename = "$schema", default, skip_serializing_if = "Option::is_none")]
    pub schema: Option<String>,
    #[serde(rename = "$id", default, skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub version: String,
    pub contests: Vec<Contest>,
}

/// A single contest definition.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Contest {
    pub id: String,
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub short_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sponsor: Option<Sponsor>,
    pub modes: Vec<String>,
    pub bands: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data_dependencies: Option<DataDependencies>,
    pub schedule: Schedule,
    pub exchange: Exchange,
    pub dupe_rules: DupeRules,
    pub scoring: Scoring,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub operating_constraints: Option<OperatingConstraints>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cabrillo: Option<Cabrillo>,
    pub categories: Vec<Category>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub overlay_categories: Vec<OverlayCategory>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub experimental: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Sponsor {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

// ---------------------------------------------------------------------------
// Data dependencies
// ---------------------------------------------------------------------------

/// Map of well-known dependency keys (`country_file`, `prefix_map`,
/// `section_list`, `zone_map`) to descriptors. Unknown keys are preserved
/// in `extra` so future dependency types don't fail to parse.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct DataDependencies {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country_file: Option<DataDependency>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub prefix_map: Option<DataDependency>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub section_list: Option<DataDependency>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub zone_map: Option<DataDependency>,
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DataDependency {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub update_frequency: Option<UpdateFrequency>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub provides: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdateFrequency {
    Static,
    Monthly,
    Weekly,
    BeforeEachContest,
}

// ---------------------------------------------------------------------------
// Schedule
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Schedule {
    RecurringWeekly {
        sessions: Vec<WeeklySession>,
        session_scoring: SessionScoring,
    },
    Annual {
        rule: String,
        start_utc: String,
        start_day: String,
        duration_hours: f64,
    },
    FixedDates {
        occurrences: Vec<FixedOccurrence>,
    },
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct WeeklySession {
    pub day: String,
    pub start_utc: String,
    pub duration_minutes: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionScoring {
    Independent,
    Cumulative,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct FixedOccurrence {
    pub start: String,
    pub duration_hours: f64,
}

// ---------------------------------------------------------------------------
// Exchange
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Exchange {
    pub sent: Vec<ExchangeField>,
    pub received: Vec<ExchangeField>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ExchangeField {
    pub name: String,
    #[serde(rename = "type")]
    pub field_type: String,
    pub label: String,
    #[serde(default = "default_true")]
    pub required: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autofill: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auto_increment: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub list: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default: Option<serde_json::Value>,
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

// ---------------------------------------------------------------------------
// Dupe rules
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DupeRules {
    pub scope: DupeScope,
    pub key: Vec<String>,
    #[serde(default)]
    pub zero_point_qsos_count_for_mults: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DupeScope {
    Session,
    Contest,
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Scoring {
    pub phases: Vec<Phase>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Phase {
    PerQso {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        description: Option<String>,
        rules: Vec<Rule>,
    },
    MultiplierCount {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        description: Option<String>,
        source: String,
        scope: MultiplierScope,
        #[serde(default)]
        include_zero_point_qsos: bool,
    },
    Aggregate {
        id: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        description: Option<String>,
        operation: AggregateOp,
    },
}

impl Phase {
    pub fn id(&self) -> &str {
        match self {
            Phase::PerQso { id, .. }
            | Phase::MultiplierCount { id, .. }
            | Phase::Aggregate { id, .. } => id,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MultiplierScope {
    PerBand,
    PerContest,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Rule {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub conditions: Vec<Condition>,
    pub value: i64,
}

/// A single condition in a per_qso rule.
///
/// Exactly one of `value` or `reference` must be set; this is enforced
/// at semantic validation time, not by serde.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Condition {
    pub field: String,
    pub op: ConditionOp,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<serde_json::Value>,
    #[serde(default, rename = "ref", skip_serializing_if = "Option::is_none")]
    pub reference: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ConditionOp {
    Eq,
    Ne,
    In,
    NotIn,
    Gt,
    Gte,
    Lt,
    Lte,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum AggregateOp {
    Ref { phase: String },
    Literal { value: i64 },
    Add { inputs: Vec<AggregateOp> },
    Multiply { inputs: Vec<AggregateOp> },
    Max { inputs: Vec<AggregateOp> },
}

// ---------------------------------------------------------------------------
// Operating constraints
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct OperatingConstraints {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub off_time: Option<OffTimeRules>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band_changes: Option<BandChangeRules>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct OffTimeRules {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum_off_minutes: Option<u32>,
    #[serde(default, skip_serializing_if = "std::collections::BTreeMap::is_empty")]
    pub maximum_on_hours_by_category: std::collections::BTreeMap<String, f64>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct BandChangeRules {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub applies_to: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min_minutes_on_band: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_changes_per_clock_hour: Option<u32>,
}

// ---------------------------------------------------------------------------
// Cabrillo
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Cabrillo {
    pub contest_name: String,
    pub version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub qso_format: Option<serde_json::Value>,
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Category {
    pub id: String,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub band: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub power_classes: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assisted: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub op_count: Option<OpCount>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum OpCount {
    Single,
    Multi,
    MultiTwo,
    MultiMulti,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct OverlayCategory {
    pub id: String,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_on_hours: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_license_years: Option<u32>,
}
