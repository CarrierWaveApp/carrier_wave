//! Condition-field vocabulary resolution + predicate evaluation. Port of
//! `Services/Contest/ContestConditionContext.swift`.

use super::callsign;
use super::engine::{ContestQsoRecord, MyStationContext};
use super::model::{render_number, ContestCondition, ContestConditionOp, ContestScoringRule,
    JsonValue};

/// Read-only view over a QSO + station context, exposing the condition-field
/// vocabulary defined in `docs/features/contest-definitions.md`.
pub(crate) struct ContestConditionContext<'a> {
    pub qso: &'a ContestQsoRecord,
    pub my_station: Option<&'a MyStationContext>,
}

impl ContestConditionContext<'_> {
    /// Resolve a condition-field name to a comparable value. Returns `None`
    /// when the field is unknown or the underlying data is missing.
    pub fn value(&self, field: &str) -> Option<ContestConditionValue> {
        if let Some(name) = field.strip_prefix("received.") {
            return self
                .qso
                .received_exchange
                .get(name)
                .map(|raw| ContestConditionValue::String(raw.clone()));
        }
        self.value_for_known_field(field)
    }

    fn value_for_known_field(&self, field: &str) -> Option<ContestConditionValue> {
        use ContestConditionValue as Value;
        match field {
            "their_callsign" => Some(Value::String(callsign::normalize(&self.qso.callsign))),
            "their_country" => self
                .qso
                .their_country
                .as_ref()
                .map(|country| Value::String(country.to_uppercase())),
            "their_continent" => self
                .qso
                .their_continent
                .as_ref()
                .map(|continent| Value::String(continent.to_uppercase())),
            "their_cq_zone" => self.qso.their_cq_zone.map(Value::Int),
            "their_itu_zone" => self.qso.their_itu_zone.map(Value::Int),
            "my_country" => self
                .my_station
                .and_then(|station| station.country.as_ref())
                .map(|country| Value::String(country.to_uppercase())),
            "my_continent" => self
                .my_station
                .and_then(|station| station.continent.as_ref())
                .map(|continent| Value::String(continent.to_uppercase())),
            "my_cq_zone" => self.my_station.and_then(|station| station.cq_zone).map(Value::Int),
            "my_itu_zone" => self.my_station.and_then(|station| station.itu_zone).map(Value::Int),
            "band" => Some(Value::String(self.qso.band.clone())),
            "mode" => Some(Value::String(self.qso.mode.to_uppercase())),
            "mode_group" => Some(Value::String(self.qso.mode_group().to_string())),
            "distance_km" => self.qso.distance_km.map(Value::Double),
            _ => None,
        }
    }
}

/// Comparable value produced by the condition vocabulary.
#[derive(Debug, Clone, PartialEq)]
pub enum ContestConditionValue {
    String(String),
    Int(i64),
    Double(f64),
}

impl ContestConditionValue {
    /// Case-insensitive string form for comparison.
    pub fn comparable_string(&self) -> String {
        match self {
            Self::String(value) => value.to_uppercase(),
            Self::Int(value) => value.to_string(),
            Self::Double(value) => render_number(*value),
        }
    }

    pub fn numeric_value(&self) -> Option<f64> {
        match self {
            Self::Int(value) => Some(*value as f64),
            Self::Double(value) => Some(*value),
            Self::String(value) => value.parse().ok(),
        }
    }
}

/// Pure-function condition evaluation. Split out from the engine so it can
/// be unit-tested without any state.
pub(crate) fn rule_matches(rule: &ContestScoringRule, context: &ContestConditionContext) -> bool {
    // Empty conditions = always-match (fallback rule).
    if rule.conditions.is_empty() {
        return true;
    }
    rule.conditions
        .iter()
        .all(|condition| condition_matches(condition, context))
}

pub(crate) fn condition_matches(
    condition: &ContestCondition,
    context: &ContestConditionContext,
) -> bool {
    let Some(lhs) = context.value(&condition.field) else {
        return false;
    };

    if let Some(reference) = &condition.reference {
        let Some(rhs) = context.value(reference) else {
            return false;
        };
        return compare(&lhs, &rhs, condition.op);
    }

    let Some(literal) = &condition.value else {
        return false;
    };
    compare_literal(&lhs, literal, condition.op)
}

fn compare(
    lhs: &ContestConditionValue,
    rhs: &ContestConditionValue,
    op: ContestConditionOp,
) -> bool {
    use ContestConditionOp as Op;
    match op {
        Op::Eq => lhs.comparable_string() == rhs.comparable_string(),
        Op::Ne => lhs.comparable_string() != rhs.comparable_string(),
        Op::Gt | Op::Gte | Op::Lt | Op::Lte => numeric_compare(lhs, rhs, op),
        Op::In | Op::NotIn => {
            // ref doesn't make sense for in/not_in, but treat as
            // single-element membership.
            let present = lhs.comparable_string() == rhs.comparable_string();
            if op == Op::In { present } else { !present }
        }
    }
}

fn compare_literal(lhs: &ContestConditionValue, literal: &JsonValue, op: ContestConditionOp) -> bool {
    use ContestConditionOp as Op;
    match op {
        Op::In => membership_match(lhs, literal),
        Op::NotIn => !membership_match(lhs, literal),
        Op::Eq => literal.string_value().map(|value| value.to_uppercase())
            == Some(lhs.comparable_string()),
        Op::Ne => literal.string_value().map(|value| value.to_uppercase())
            != Some(lhs.comparable_string()),
        Op::Gt | Op::Gte | Op::Lt | Op::Lte => {
            let Some(rhs) = json_number(literal) else {
                return false;
            };
            numeric_compare(lhs, &ContestConditionValue::Double(rhs), op)
        }
    }
}

fn membership_match(lhs: &ContestConditionValue, literal: &JsonValue) -> bool {
    let needle = lhs.comparable_string();
    match literal {
        JsonValue::Array(values) => values.iter().any(|value| {
            value.string_value().map(|rendered| rendered.to_uppercase()) == Some(needle.clone())
        }),
        JsonValue::String(value) => value.to_uppercase() == needle,
        JsonValue::Int(value) => value.to_string() == needle,
        JsonValue::Double(value) => render_number(*value) == needle,
        JsonValue::Bool(_) | JsonValue::Null => false,
    }
}

fn json_number(value: &JsonValue) -> Option<f64> {
    match value {
        JsonValue::Int(val) => Some(*val as f64),
        JsonValue::Double(val) => Some(*val),
        JsonValue::String(text) => text.parse().ok(),
        JsonValue::Array(_) | JsonValue::Bool(_) | JsonValue::Null => None,
    }
}

fn numeric_compare(
    lhs: &ContestConditionValue,
    rhs: &ContestConditionValue,
    op: ContestConditionOp,
) -> bool {
    let (Some(left), Some(right)) = (lhs.numeric_value(), rhs.numeric_value()) else {
        return false;
    };
    match op {
        ContestConditionOp::Gt => left > right,
        ContestConditionOp::Gte => left >= right,
        ContestConditionOp::Lt => left < right,
        ContestConditionOp::Lte => left <= right,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use chrono::{TimeZone, Utc};

    use super::*;

    fn record() -> ContestQsoRecord {
        ContestQsoRecord {
            callsign: "DL1ABC/QRP".to_string(),
            band: "20m".to_string(),
            mode: "cw".to_string(),
            timestamp: Utc.with_ymd_and_hms(2026, 7, 4, 0, 0, 0).unwrap(),
            sent_exchange: HashMap::new(),
            received_exchange: HashMap::from([("state".to_string(), "OR".to_string())]),
            serial_sent: None,
            serial_received: None,
            their_country: Some("Germany".to_string()),
            their_continent: Some("eu".to_string()),
            their_cq_zone: Some(14),
            their_itu_zone: None,
            distance_km: Some(8000.5),
        }
    }

    fn cond(field: &str, op: ContestConditionOp, value: JsonValue) -> ContestCondition {
        ContestCondition {
            field: field.to_string(),
            op,
            value: Some(value),
            reference: None,
        }
    }

    #[test]
    fn vocabulary_resolution() {
        let qso = record();
        let station = MyStationContext::new("K4XL").with_country("United States");
        let context = ContestConditionContext { qso: &qso, my_station: Some(&station) };

        assert_eq!(
            context.value("their_callsign"),
            Some(ContestConditionValue::String("DL1ABC".to_string()))
        );
        assert_eq!(
            context.value("their_country"),
            Some(ContestConditionValue::String("GERMANY".to_string()))
        );
        assert_eq!(context.value("their_cq_zone"), Some(ContestConditionValue::Int(14)));
        assert_eq!(
            context.value("received.state"),
            Some(ContestConditionValue::String("OR".to_string()))
        );
        assert_eq!(context.value("received.missing"), None);
        assert_eq!(
            context.value("mode_group"),
            Some(ContestConditionValue::String("CW".to_string()))
        );
        assert_eq!(context.value("bogus_field"), None);
    }

    #[test]
    fn literal_comparisons_are_case_insensitive() {
        let qso = record();
        let context = ContestConditionContext { qso: &qso, my_station: None };

        assert!(condition_matches(
            &cond("their_country", ContestConditionOp::Eq, JsonValue::String("germany".into())),
            &context
        ));
        assert!(condition_matches(
            &cond(
                "their_country",
                ContestConditionOp::In,
                JsonValue::Array(vec![
                    JsonValue::String("france".into()),
                    JsonValue::String("GERMANY".into()),
                ])
            ),
            &context
        ));
        assert!(condition_matches(
            &cond("their_cq_zone", ContestConditionOp::Eq, JsonValue::Int(14)),
            &context
        ));
        assert!(condition_matches(
            &cond("distance_km", ContestConditionOp::Gt, JsonValue::Int(8000)),
            &context
        ));
        assert!(!condition_matches(
            &cond("their_itu_zone", ContestConditionOp::Eq, JsonValue::Int(28)),
            &context
        ));
    }

    #[test]
    fn reference_comparison_matches_swift() {
        // Mirrors the same-country rule from `perQSOPhaseAwardsFirstMatchingRule`.
        let qso = record();
        let station = MyStationContext::new("K4XL").with_country("Germany");
        let context = ContestConditionContext { qso: &qso, my_station: Some(&station) };
        let condition = ContestCondition {
            field: "their_country".to_string(),
            op: ContestConditionOp::Eq,
            value: None,
            reference: Some("my_country".to_string()),
        };
        assert!(condition_matches(&condition, &context));
    }

    #[test]
    fn empty_conditions_always_match() {
        let qso = record();
        let context = ContestConditionContext { qso: &qso, my_station: None };
        let rule = ContestScoringRule { description: None, conditions: vec![], value: 3 };
        assert!(rule_matches(&rule, &context));
    }
}
