//! Semantic validation for contest definitions.
//!
//! Structural validation (required fields, type matching) is handled by serde
//! at deserialization time. This module performs the second pass:
//!
//! - phase DAG ordering (no forward refs)
//! - condition field vocabulary
//! - exchange completeness
//! - data dependency satisfaction
//! - serial number consistency
//! - category id uniqueness
//! - schedule sanity
//!
//! Validation never stops on the first error. Authors get a complete list of
//! problems in one pass via [`ContestDefinition::validate`].

use std::collections::HashSet;

use super::types::*;

/// A single validation problem found in a contest definition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationError {
    pub severity: Severity,
    pub contest_id: Option<String>,
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
}

impl ValidationError {
    fn error(contest_id: Option<&str>, path: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Error,
            contest_id: contest_id.map(|s| s.to_string()),
            path: path.into(),
            message: message.into(),
        }
    }

    fn warning(contest_id: Option<&str>, path: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            severity: Severity::Warning,
            contest_id: contest_id.map(|s| s.to_string()),
            path: path.into(),
            message: message.into(),
        }
    }
}

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let sev = match self.severity {
            Severity::Error => "error",
            Severity::Warning => "warning",
        };
        match &self.contest_id {
            Some(id) => write!(f, "[{sev}] {id}: {}: {}", self.path, self.message),
            None => write!(f, "[{sev}] {}: {}", self.path, self.message),
        }
    }
}

// ---------------------------------------------------------------------------
// Vocabularies
// ---------------------------------------------------------------------------

/// Modes recognized by the format.
const KNOWN_MODES: &[&str] = &["CW", "SSB", "DIGITAL", "RTTY", "BOTH"];

/// Bands recognized by the format.
const KNOWN_BANDS: &[&str] = &[
    "2200m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm", "6mm",
    "4mm", "2.5mm", "2mm", "1mm",
];

const KNOWN_DAYS: &[&str] = &[
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
];

/// Derived condition fields the engine populates from the QSO context.
const DERIVED_FIELDS: &[&str] = &[
    "their_callsign",
    "their_country",
    "their_continent",
    "their_cq_zone",
    "their_itu_zone",
    "my_country",
    "my_continent",
    "my_cq_zone",
    "my_itu_zone",
    "band",
    "mode",
    "mode_group",
    "distance_km",
];

/// Continent codes used as condition literals.
const CONTINENTS: &[&str] = &["NA", "SA", "EU", "AF", "OC", "AS", "AN"];

/// Exchange field types recognized by the format.
const FIELD_TYPES: &[&str] = &[
    "text",
    "signal_report",
    "serial_number",
    "cq_zone",
    "itu_zone",
    "grid_square",
    "state_province",
    "arrl_section",
    "section_list",
    "power",
    "name",
    "age",
    "class",
];

/// `multiplier_count.source` values that are derived (not from the exchange).
const MULTIPLIER_DERIVED_SOURCES: &[&str] = &[
    "their_callsign",
    "their_callsign_wpx",
    "their_country",
    "their_continent",
    "their_cq_zone",
    "their_itu_zone",
    "band",
    "mode",
    "mode_group",
];

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

impl ContestDefinition {
    /// Run semantic validation. Returns all problems found, in stable order.
    /// An empty vec means the definition is valid.
    pub fn validate(&self) -> Vec<ValidationError> {
        let mut errors = Vec::new();
        let mut seen_contest_ids: HashSet<&str> = HashSet::new();

        for (idx, contest) in self.contests.iter().enumerate() {
            if !seen_contest_ids.insert(contest.id.as_str()) {
                errors.push(ValidationError::error(
                    Some(&contest.id),
                    format!("contests[{idx}].id"),
                    format!("duplicate contest id '{}' within file", contest.id),
                ));
            }
            validate_contest(contest, &mut errors);
        }

        errors
    }

    /// Convenience: returns true if there are no `Severity::Error` entries.
    /// Warnings do not affect this.
    pub fn is_valid(&self) -> bool {
        self.validate()
            .iter()
            .all(|e| e.severity != Severity::Error)
    }
}

fn validate_contest(contest: &Contest, errors: &mut Vec<ValidationError>) {
    let cid = Some(contest.id.as_str());

    validate_modes(contest, cid, errors);
    validate_bands(contest, cid, errors);
    validate_schedule(contest, cid, errors);
    validate_exchange(contest, cid, errors);
    validate_dupe_rules(contest, cid, errors);
    validate_scoring(contest, cid, errors);
    validate_data_dependency_satisfaction(contest, cid, errors);
    validate_categories(contest, cid, errors);
}

// ---------------------------------------------------------------------------
// Modes / bands
// ---------------------------------------------------------------------------

fn validate_modes(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    if contest.modes.is_empty() {
        errors.push(ValidationError::error(
            cid,
            "modes",
            "must declare at least one mode",
        ));
    }
    for (i, mode) in contest.modes.iter().enumerate() {
        if !KNOWN_MODES.contains(&mode.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("modes[{i}]"),
                format!("unknown mode '{mode}'"),
            ));
        }
    }
}

fn validate_bands(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    if contest.bands.is_empty() {
        errors.push(ValidationError::error(
            cid,
            "bands",
            "must declare at least one band",
        ));
    }
    for (i, band) in contest.bands.iter().enumerate() {
        if !KNOWN_BANDS.contains(&band.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("bands[{i}]"),
                format!("unknown band '{band}'"),
            ));
        }
    }
}

// ---------------------------------------------------------------------------
// Schedule
// ---------------------------------------------------------------------------

fn validate_schedule(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    match &contest.schedule {
        Schedule::RecurringWeekly { sessions, .. } => {
            if sessions.is_empty() {
                errors.push(ValidationError::error(
                    cid,
                    "schedule.sessions",
                    "recurring_weekly must declare at least one session",
                ));
            }
            for (i, session) in sessions.iter().enumerate() {
                if !KNOWN_DAYS.contains(&session.day.as_str()) {
                    errors.push(ValidationError::error(
                        cid,
                        format!("schedule.sessions[{i}].day"),
                        format!("unknown day '{}' (must be lowercase)", session.day),
                    ));
                }
                if !is_hh_mm(&session.start_utc) {
                    errors.push(ValidationError::error(
                        cid,
                        format!("schedule.sessions[{i}].start_utc"),
                        format!("invalid HH:MM value '{}'", session.start_utc),
                    ));
                }
                if session.duration_minutes == 0 {
                    errors.push(ValidationError::error(
                        cid,
                        format!("schedule.sessions[{i}].duration_minutes"),
                        "must be positive",
                    ));
                }
            }
        }
        Schedule::Annual {
            start_utc,
            start_day,
            duration_hours,
            ..
        } => {
            if !is_hh_mm(start_utc) {
                errors.push(ValidationError::error(
                    cid,
                    "schedule.start_utc",
                    format!("invalid HH:MM value '{start_utc}'"),
                ));
            }
            if !KNOWN_DAYS.contains(&start_day.as_str()) {
                errors.push(ValidationError::error(
                    cid,
                    "schedule.start_day",
                    format!("unknown day '{start_day}' (must be lowercase)"),
                ));
            }
            if *duration_hours <= 0.0 {
                errors.push(ValidationError::error(
                    cid,
                    "schedule.duration_hours",
                    "must be positive",
                ));
            }
        }
        Schedule::FixedDates { occurrences } => {
            if occurrences.is_empty() {
                errors.push(ValidationError::error(
                    cid,
                    "schedule.occurrences",
                    "fixed_dates must declare at least one occurrence",
                ));
            }
            for (i, occ) in occurrences.iter().enumerate() {
                if occ.duration_hours <= 0.0 {
                    errors.push(ValidationError::error(
                        cid,
                        format!("schedule.occurrences[{i}].duration_hours"),
                        "must be positive",
                    ));
                }
            }
        }
    }
}

fn is_hh_mm(s: &str) -> bool {
    let bytes = s.as_bytes();
    if bytes.len() != 5 || bytes[2] != b':' {
        return false;
    }
    let hh: u8 = match s[..2].parse() {
        Ok(h) => h,
        Err(_) => return false,
    };
    let mm: u8 = match s[3..].parse() {
        Ok(m) => m,
        Err(_) => return false,
    };
    hh < 24 && mm < 60
}

// ---------------------------------------------------------------------------
// Exchange
// ---------------------------------------------------------------------------

fn validate_exchange(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    validate_exchange_side(&contest.exchange.sent, "exchange.sent", true, cid, errors);
    validate_exchange_side(
        &contest.exchange.received,
        "exchange.received",
        false,
        cid,
        errors,
    );
}

fn validate_exchange_side(
    fields: &[ExchangeField],
    base: &str,
    is_sent: bool,
    cid: Option<&str>,
    errors: &mut Vec<ValidationError>,
) {
    let mut seen_names: HashSet<&str> = HashSet::new();
    for (i, field) in fields.iter().enumerate() {
        let path = format!("{base}[{i}]");

        if !seen_names.insert(field.name.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("{path}.name"),
                format!("duplicate field name '{}'", field.name),
            ));
        }

        if !FIELD_TYPES.contains(&field.field_type.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("{path}.type"),
                format!("unknown field type '{}'", field.field_type),
            ));
        }

        if field.field_type == "section_list" && field.list.is_none() {
            errors.push(ValidationError::error(
                cid,
                format!("{path}.list"),
                "section_list field requires a 'list' name",
            ));
        }

        // Serial number consistency.
        if field.field_type == "serial_number" {
            let auto_inc = field.auto_increment.unwrap_or(false);
            if !is_sent && auto_inc {
                errors.push(ValidationError::error(
                    cid,
                    format!("{path}.auto_increment"),
                    "auto_increment is only allowed on the sent side",
                ));
            }
        } else if field.auto_increment.unwrap_or(false) {
            errors.push(ValidationError::error(
                cid,
                format!("{path}.auto_increment"),
                "auto_increment is only valid for serial_number fields",
            ));
        }

        if !is_sent && field.autofill.is_some() {
            errors.push(ValidationError::warning(
                cid,
                format!("{path}.autofill"),
                "autofill on a received field has no effect",
            ));
        }
    }
}

// ---------------------------------------------------------------------------
// Dupe rules
// ---------------------------------------------------------------------------

fn validate_dupe_rules(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    if contest.dupe_rules.key.is_empty() {
        errors.push(ValidationError::error(
            cid,
            "dupe_rules.key",
            "must declare at least one key component",
        ));
    }
    let allowed_keys = ["callsign", "band", "mode", "mode_group"];
    for (i, k) in contest.dupe_rules.key.iter().enumerate() {
        if !allowed_keys.contains(&k.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("dupe_rules.key[{i}]"),
                format!(
                    "unknown dupe key component '{k}' (allowed: {})",
                    allowed_keys.join(", ")
                ),
            ));
        }
    }
}

// ---------------------------------------------------------------------------
// Scoring (phases, rules, conditions, aggregate refs)
// ---------------------------------------------------------------------------

fn validate_scoring(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    let phases = &contest.scoring.phases;
    if phases.is_empty() {
        errors.push(ValidationError::error(
            cid,
            "scoring.phases",
            "must declare at least one phase",
        ));
        return;
    }

    // Build the set of received exchange field names for validating
    // received.* references in conditions and multiplier sources.
    let received_fields: HashSet<&str> = contest
        .exchange
        .received
        .iter()
        .map(|f| f.name.as_str())
        .collect();

    // Phase id uniqueness + collect allowed earlier-phase ids for each index.
    let mut phase_ids: HashSet<&str> = HashSet::new();
    for (i, phase) in phases.iter().enumerate() {
        let id = phase.id();
        if !phase_ids.insert(id) {
            errors.push(ValidationError::error(
                cid,
                format!("scoring.phases[{i}].id"),
                format!("duplicate phase id '{id}'"),
            ));
        }
    }

    let mut earlier: HashSet<&str> = HashSet::new();
    for (i, phase) in phases.iter().enumerate() {
        let path = format!("scoring.phases[{i}]");
        match phase {
            Phase::PerQso { rules, .. } => {
                validate_per_qso_rules(rules, &path, &received_fields, cid, errors);
            }
            Phase::MultiplierCount { source, .. } => {
                if !is_valid_multiplier_source(source, &received_fields) {
                    errors.push(ValidationError::error(
                        cid,
                        format!("{path}.source"),
                        format!(
                            "multiplier source '{source}' is not a derived field or a defined received.* field"
                        ),
                    ));
                }
            }
            Phase::Aggregate { operation, .. } => {
                validate_agg_op(operation, &format!("{path}.operation"), &earlier, cid, errors);
            }
        }
        earlier.insert(phase.id());
    }
}

fn validate_per_qso_rules(
    rules: &[Rule],
    base: &str,
    received_fields: &HashSet<&str>,
    cid: Option<&str>,
    errors: &mut Vec<ValidationError>,
) {
    if rules.is_empty() {
        errors.push(ValidationError::error(
            cid,
            format!("{base}.rules"),
            "per_qso phase must declare at least one rule",
        ));
        return;
    }

    for (i, rule) in rules.iter().enumerate() {
        let rpath = format!("{base}.rules[{i}]");
        for (j, cond) in rule.conditions.iter().enumerate() {
            let cpath = format!("{rpath}.conditions[{j}]");
            validate_condition(cond, &cpath, received_fields, cid, errors);
        }
    }

    // Fallback rule warning: the last rule should have empty conditions.
    if let Some(last) = rules.last() {
        if !last.conditions.is_empty() {
            errors.push(ValidationError::warning(
                cid,
                format!("{base}.rules[{}]", rules.len() - 1),
                "last rule has conditions; QSOs that match no rule will silently score 0",
            ));
        }
    }
}

fn validate_condition(
    cond: &Condition,
    path: &str,
    received_fields: &HashSet<&str>,
    cid: Option<&str>,
    errors: &mut Vec<ValidationError>,
) {
    if !is_known_field(&cond.field, received_fields) {
        errors.push(ValidationError::error(
            cid,
            format!("{path}.field"),
            format!("unknown condition field '{}'", cond.field),
        ));
    }

    match (&cond.value, &cond.reference) {
        (None, None) => errors.push(ValidationError::error(
            cid,
            path,
            "condition must specify either 'value' or 'ref'",
        )),
        (Some(_), Some(_)) => errors.push(ValidationError::error(
            cid,
            path,
            "condition must not specify both 'value' and 'ref'",
        )),
        (None, Some(reference)) => {
            if !is_known_field(reference, received_fields) {
                errors.push(ValidationError::error(
                    cid,
                    format!("{path}.ref"),
                    format!("unknown ref field '{reference}'"),
                ));
            }
        }
        (Some(value), None) => {
            // For continent fields, validate the literal is a known continent code.
            if (cond.field == "their_continent" || cond.field == "my_continent")
                && cond.op == ConditionOp::Eq
            {
                if let Some(s) = value.as_str() {
                    if !CONTINENTS.contains(&s) {
                        errors.push(ValidationError::warning(
                            cid,
                            format!("{path}.value"),
                            format!(
                                "unknown continent code '{s}' (expected one of {})",
                                CONTINENTS.join(", ")
                            ),
                        ));
                    }
                }
            }
            // `in` / `not_in` require an array literal.
            if matches!(cond.op, ConditionOp::In | ConditionOp::NotIn) && !value.is_array() {
                errors.push(ValidationError::error(
                    cid,
                    format!("{path}.value"),
                    "in/not_in operator requires an array literal",
                ));
            }
        }
    }
}

fn is_known_field(field: &str, received_fields: &HashSet<&str>) -> bool {
    if DERIVED_FIELDS.contains(&field) {
        return true;
    }
    if let Some(rest) = field.strip_prefix("received.") {
        return received_fields.contains(rest);
    }
    false
}

fn is_valid_multiplier_source(source: &str, received_fields: &HashSet<&str>) -> bool {
    if MULTIPLIER_DERIVED_SOURCES.contains(&source) {
        return true;
    }
    if let Some(rest) = source.strip_prefix("received.") {
        return received_fields.contains(rest);
    }
    false
}

fn validate_agg_op(
    op: &AggregateOp,
    path: &str,
    earlier_phases: &HashSet<&str>,
    cid: Option<&str>,
    errors: &mut Vec<ValidationError>,
) {
    match op {
        AggregateOp::Ref { phase } => {
            if !earlier_phases.contains(phase.as_str()) {
                errors.push(ValidationError::error(
                    cid,
                    format!("{path}.phase"),
                    format!(
                        "ref points to phase '{phase}' which is not defined earlier in the phases array"
                    ),
                ));
            }
        }
        AggregateOp::Literal { .. } => {}
        AggregateOp::Add { inputs }
        | AggregateOp::Multiply { inputs }
        | AggregateOp::Max { inputs } => {
            if inputs.is_empty() {
                errors.push(ValidationError::error(
                    cid,
                    format!("{path}.inputs"),
                    "aggregate operation must have at least one input",
                ));
            }
            for (i, input) in inputs.iter().enumerate() {
                validate_agg_op(input, &format!("{path}.inputs[{i}]"), earlier_phases, cid, errors);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Data dependency satisfaction
// ---------------------------------------------------------------------------

fn validate_data_dependency_satisfaction(
    contest: &Contest,
    cid: Option<&str>,
    errors: &mut Vec<ValidationError>,
) {
    // Collect derived fields actually used in conditions and multiplier sources.
    let mut used_derived: HashSet<&str> = HashSet::new();

    for phase in &contest.scoring.phases {
        match phase {
            Phase::PerQso { rules, .. } => {
                for rule in rules {
                    for cond in &rule.conditions {
                        if DERIVED_FIELDS.contains(&cond.field.as_str()) {
                            used_derived.insert(field_to_provides(&cond.field));
                        }
                        if let Some(reference) = &cond.reference {
                            if DERIVED_FIELDS.contains(&reference.as_str()) {
                                used_derived.insert(field_to_provides(reference));
                            }
                        }
                    }
                }
            }
            Phase::MultiplierCount { source, .. } => {
                if MULTIPLIER_DERIVED_SOURCES.contains(&source.as_str()) {
                    used_derived.insert(field_to_provides(source));
                }
            }
            Phase::Aggregate { .. } => {}
        }
    }

    // Build the set of fields actually provided by declared dependencies.
    let mut provided: HashSet<&str> = HashSet::new();
    if let Some(deps) = &contest.data_dependencies {
        for dep in [
            &deps.country_file,
            &deps.prefix_map,
            &deps.section_list,
            &deps.zone_map,
        ]
        .into_iter()
        .flatten()
        {
            for p in &dep.provides {
                provided.insert(p.as_str());
            }
        }
    }

    let needs_resolver = ["their_country", "their_continent", "their_cq_zone", "their_itu_zone"];
    for field in needs_resolver {
        if used_derived.contains(field) && !provided.contains(field) {
            errors.push(ValidationError::warning(
                cid,
                "data_dependencies",
                format!(
                    "scoring uses '{field}' but no data_dependency declares it in 'provides'"
                ),
            ));
        }
    }
}

/// Map a "my_*" field to its "their_*" equivalent for dependency tracking.
/// The data dependencies provide values for the worked station, which
/// implicitly cover both sides via station config.
fn field_to_provides(field: &str) -> &str {
    match field {
        "my_country" => "their_country",
        "my_continent" => "their_continent",
        "my_cq_zone" => "their_cq_zone",
        "my_itu_zone" => "their_itu_zone",
        other => other,
    }
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

fn validate_categories(contest: &Contest, cid: Option<&str>, errors: &mut Vec<ValidationError>) {
    if contest.categories.is_empty() {
        errors.push(ValidationError::error(
            cid,
            "categories",
            "must declare at least one category",
        ));
        return;
    }

    let mut seen: HashSet<&str> = HashSet::new();
    for (i, cat) in contest.categories.iter().enumerate() {
        if !seen.insert(cat.id.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("categories[{i}].id"),
                format!("duplicate category id '{}'", cat.id),
            ));
        }
        if let Some(band) = &cat.band {
            if !KNOWN_BANDS.contains(&band.as_str()) {
                errors.push(ValidationError::error(
                    cid,
                    format!("categories[{i}].band"),
                    format!("unknown band '{band}'"),
                ));
            }
        }
    }

    for (i, ov) in contest.overlay_categories.iter().enumerate() {
        if !seen.insert(ov.id.as_str()) {
            errors.push(ValidationError::error(
                cid,
                format!("overlay_categories[{i}].id"),
                format!(
                    "overlay category id '{}' collides with another category id",
                    ov.id
                ),
            ));
        }
    }
}
