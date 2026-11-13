//! Contest exchange token classification. Port of
//! `Services/Contest/ContestExchangeParser.swift`.

use std::collections::HashMap;

use regex::Regex;

use super::model::{ContestDefinition, ContestExchangeField, ContestExchangeFieldType};

/// Result of parsing contest exchange tokens against a definition.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ContestExchangeParseResult {
    /// Received-field values keyed by `ContestExchangeField.name`.
    pub fields: HashMap<String, String>,
    pub serial_received: Option<i64>,
    pub unmatched_tokens: Vec<String>,
}

/// ARRL section identifiers (incl. Canadian sections).
pub const ARRL_SECTIONS: [&str; 84] = [
    "CT", "EMA", "ME", "NH", "RI", "VT", "WMA",
    "ENY", "NLI", "NNJ", "NNY", "SNJ", "WNY",
    "IL", "IN", "WI", "MN", "ND", "SD",
    "AR", "LA", "MS", "TN",
    "MI", "OH", "WV", "EPA", "MDC", "WPA",
    "IA", "KS", "MO", "NE",
    "AK", "EWA", "ID", "MT", "OR", "WWA", "WY",
    "EB", "LAX", "ORG", "PAC", "SB", "SCV", "SDG", "SF", "SJV", "SV",
    "NC", "SC", "VA",
    "CO", "NM", "UT",
    "AL", "GA", "KY", "NFL", "PR", "SFL", "VI", "WCF",
    "AZ", "NV",
    "NTX", "OK", "STX", "WTX",
    "AB", "BC", "GH", "MAR", "MB", "NL", "NT",
    "ONE", "ONN", "ONS", "PE", "QC", "SK", "TER",
];

pub const US_STATES: [&str; 51] = [
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
    "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
    "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
    "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
    "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC",
];

pub const CA_PROVINCES: [&str; 13] = [
    "AB", "BC", "MB", "NB", "NL", "NS", "NT",
    "NU", "ON", "PE", "QC", "SK", "YT",
];

/// Parse space-separated tokens against a contest's received-field list.
pub fn parse(tokens: &[String], definition: &ContestDefinition) -> ContestExchangeParseResult {
    let mut result = ContestExchangeParseResult::default();
    let mut remaining: Vec<String> = tokens.to_vec();
    for field in &definition.exchange.received {
        if remaining.is_empty() {
            break;
        }
        match_field(field, &mut remaining, &mut result);
    }
    result.unmatched_tokens = remaining;
    result
}

fn match_field(
    field: &ContestExchangeField,
    remaining: &mut Vec<String>,
    result: &mut ContestExchangeParseResult,
) {
    if let Some(validator) = matcher(field) {
        if let Some(idx) = remaining.iter().position(|token| validator(token)) {
            let token = remaining[idx].clone();
            result
                .fields
                .insert(field.name.clone(), normalize(&token, field));
            if field.field_type == ContestExchangeFieldType::SerialNumber {
                if let Ok(serial) = token.parse::<i64>() {
                    result.serial_received = Some(serial);
                }
            }
            remaining.remove(idx);
            return;
        }
    }
    // Fallback: consume first remaining token.
    if !remaining.is_empty() {
        let first = remaining.remove(0);
        result.fields.insert(field.name.clone(), first);
    }
}

fn normalize(token: &str, field: &ContestExchangeField) -> String {
    use ContestExchangeFieldType as FieldType;
    match field.field_type {
        FieldType::StateProvince
        | FieldType::ArrlSection
        | FieldType::SectionList
        | FieldType::Power
        | FieldType::Class
        | FieldType::GridSquare => token.to_uppercase(),
        _ => token.to_string(),
    }
}

type TokenMatcher = Box<dyn Fn(&str) -> bool>;

fn matcher(field: &ContestExchangeField) -> Option<TokenMatcher> {
    use ContestExchangeFieldType as FieldType;
    match &field.field_type {
        FieldType::SignalReport => Some(Box::new(is_rst)),
        FieldType::SerialNumber | FieldType::Age => Some(Box::new(is_integer)),
        FieldType::CqZone => Some(Box::new(is_cq_zone)),
        FieldType::ItuZone => Some(Box::new(is_itu_zone)),
        FieldType::GridSquare => Some(Box::new(is_grid)),
        FieldType::StateProvince => Some(Box::new(is_state_or_province)),
        FieldType::ArrlSection => Some(Box::new(is_arrl_section)),
        FieldType::SectionList => {
            Some(Box::new(|token| is_arrl_section(token) || is_state_or_province(token)))
        }
        FieldType::Power => Some(Box::new(is_power)),
        FieldType::Class => Some(Box::new(is_field_day_class)),
        FieldType::Name => Some(Box::new(|token| {
            token.chars().all(char::is_alphabetic) && token.chars().count() >= 2
        })),
        FieldType::Text => Some(text_matcher(field.pattern.clone())),
        FieldType::Unknown(_) => None,
    }
}

fn text_matcher(pattern: Option<String>) -> TokenMatcher {
    Box::new(move |token| {
        let Some(pattern) = &pattern else {
            return !token.is_empty();
        };
        // Swift builds `^pattern$` with NSRegularExpression; the `regex`
        // crate covers the same dialect subset contest definitions use.
        match Regex::new(&format!("^{pattern}$")) {
            Ok(regex) => regex.is_match(token),
            Err(_) => false,
        }
    })
}

fn is_rst(token: &str) -> bool {
    if token.is_empty() || !token.chars().all(|ch| ch.is_numeric()) {
        return false;
    }
    let count = token.chars().count();
    count == 2 || count == 3
}

fn is_cq_zone(token: &str) -> bool {
    token.parse::<i64>().is_ok_and(|zone| (1..=40).contains(&zone))
}

fn is_itu_zone(token: &str) -> bool {
    token.parse::<i64>().is_ok_and(|zone| (1..=90).contains(&zone))
}

fn is_integer(token: &str) -> bool {
    token.parse::<i64>().is_ok()
}

fn is_power(token: &str) -> bool {
    let upper = token.to_uppercase();
    ["H", "L", "Q", "HIGH", "LOW", "QRP"].contains(&upper.as_str())
        || upper.parse::<i64>().is_ok()
}

fn is_field_day_class(token: &str) -> bool {
    let chars: Vec<char> = token.to_uppercase().chars().collect();
    if chars.len() < 2 {
        return false;
    }
    let Some(last) = chars.last() else {
        return false;
    };
    if !last.is_alphabetic() {
        return false;
    }
    chars[..chars.len() - 1].iter().all(|ch| ch.is_numeric())
}

fn is_grid(token: &str) -> bool {
    let upper = token.to_uppercase();
    let chars: Vec<char> = upper.chars().collect();
    if chars.len() != 4 && chars.len() != 6 {
        return false;
    }
    if !(chars[0].is_alphabetic()
        && chars[1].is_alphabetic()
        && chars[2].is_numeric()
        && chars[3].is_numeric())
    {
        return false;
    }
    if chars.len() == 6 {
        return chars[4].is_alphabetic() && chars[5].is_alphabetic();
    }
    true
}

fn is_state_or_province(token: &str) -> bool {
    let upper = token.to_uppercase();
    US_STATES.contains(&upper.as_str()) || CA_PROVINCES.contains(&upper.as_str())
}

fn is_arrl_section(token: &str) -> bool {
    ARRL_SECTIONS.contains(&token.to_uppercase().as_str())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::contest::model::parse_definition;

    fn sst_definition() -> ContestDefinition {
        parse_definition(
            r#"
            {
              "id": "sst",
              "name": "Slow Speed Test",
              "modes": ["CW"],
              "bands": ["40m"],
              "schedule": {
                "type": "recurring_weekly",
                "sessions": [{ "day": "monday", "start_utc": "00:00", "duration_minutes": 60 }],
                "session_scoring": "independent"
              },
              "exchange": {
                "sent": [],
                "received": [
                  { "name": "name", "type": "name", "label": "Name" },
                  { "name": "state", "type": "state_province", "label": "State" }
                ]
              },
              "dupe_rules": { "scope": "session", "key": ["callsign"] },
              "scoring": { "phases": [] },
              "categories": []
            }
            "#,
        )
        .expect("decode")
    }

    fn serial_definition() -> ContestDefinition {
        parse_definition(
            r#"
            {
              "id": "wpx",
              "name": "WPX",
              "modes": ["CW"],
              "bands": ["40m"],
              "schedule": { "type": "fixed_dates", "occurrences": [] },
              "exchange": {
                "sent": [],
                "received": [
                  { "name": "rst", "type": "signal_report", "label": "RST" },
                  { "name": "serial", "type": "serial_number", "label": "Serial" }
                ]
              },
              "dupe_rules": { "scope": "contest", "key": ["callsign", "band"] },
              "scoring": { "phases": [] },
              "categories": []
            }
            "#,
        )
        .expect("decode")
    }

    fn tokens(raw: &[&str]) -> Vec<String> {
        raw.iter().map(|token| token.to_string()).collect()
    }

    #[test]
    fn classifies_name_then_state() {
        let definition = sst_definition();
        let result = parse(&tokens(&["jay", "or"]), &definition);
        assert_eq!(result.fields.get("name").map(String::as_str), Some("jay"));
        assert_eq!(result.fields.get("state").map(String::as_str), Some("OR"));
        assert!(result.unmatched_tokens.is_empty());

        // Field-order quirk (same as Swift): the name matcher runs first and
        // "or" is all-letters, so it claims the state token; state then
        // falls back to positional consumption without normalization.
        let swapped = parse(&tokens(&["or", "jay"]), &definition);
        assert_eq!(swapped.fields.get("name").map(String::as_str), Some("or"));
        assert_eq!(swapped.fields.get("state").map(String::as_str), Some("jay"));
    }

    #[test]
    fn extracts_serial_and_rst() {
        let definition = serial_definition();
        let result = parse(&tokens(&["599", "42"]), &definition);
        assert_eq!(result.fields.get("rst").map(String::as_str), Some("599"));
        assert_eq!(result.fields.get("serial").map(String::as_str), Some("42"));
        assert_eq!(result.serial_received, Some(42));
    }

    #[test]
    fn falls_back_to_positional_consumption() {
        let definition = sst_definition();
        // "x1" fails the name matcher and there is no state token, so the
        // name field consumes the first token positionally, then state
        // consumes the next one the same way.
        let result = parse(&tokens(&["x1", "zz9"]), &definition);
        assert_eq!(result.fields.get("name").map(String::as_str), Some("x1"));
        assert_eq!(result.fields.get("state").map(String::as_str), Some("zz9"));
    }

    #[test]
    fn leftover_tokens_are_reported() {
        let definition = sst_definition();
        let result = parse(&tokens(&["jay", "or", "extra"]), &definition);
        assert_eq!(result.unmatched_tokens, vec!["extra".to_string()]);
    }

    #[test]
    fn token_validators() {
        assert!(is_rst("599"));
        assert!(is_rst("59"));
        assert!(!is_rst("5999"));
        assert!(!is_rst("59a"));
        assert!(is_cq_zone("14"));
        assert!(!is_cq_zone("41"));
        assert!(is_itu_zone("61"));
        assert!(!is_itu_zone("91"));
        assert!(is_grid("CN85"));
        assert!(is_grid("cn85kj"));
        assert!(!is_grid("C185"));
        assert!(!is_grid("CN85K"));
        assert!(is_power("QRP"));
        assert!(is_power("100"));
        assert!(!is_power("QRO"));
        assert!(is_field_day_class("3A"));
        assert!(!is_field_day_class("A3"));
        assert!(is_state_or_province("or"));
        assert!(is_state_or_province("ON"));
        assert!(is_arrl_section("SCV"));
        assert!(!is_arrl_section("XX"));
    }
}
