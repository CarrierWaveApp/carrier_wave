//! Callsign extraction + context-based primary-callsign detection from CW
//! transcripts. Port of the regex-based core of `CallsignDetector.swift`.
//! Skips the `CWTextElement` rendering surface (that's UI-side; can be added
//! when that layer is also ported).

use std::collections::HashSet;
use std::sync::OnceLock;

use regex::{Regex, RegexBuilder};

const CALLSIGN_PATTERN: &str = r"[A-Z0-9]{1,3}[0-9][A-Z]{1,4}";
const GRID_PATTERN: &str = r"\b[A-R]{2}[0-9]{2}([A-X]{2})?\b";
const POWER_PATTERN: &str = r"\b[0-9]+K?W\b";
const SIGNAL_REPORT_PATTERN: &str = r"\b[1-5][1-9][1-9]?\b";

fn callsign_regex() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        RegexBuilder::new(CALLSIGN_PATTERN)
            .case_insensitive(true)
            .build()
            .expect("static callsign regex")
    })
}

fn grid_regex() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        RegexBuilder::new(GRID_PATTERN)
            .case_insensitive(true)
            .build()
            .expect("static grid regex")
    })
}

fn power_regex() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| {
        RegexBuilder::new(POWER_PATTERN)
            .case_insensitive(true)
            .build()
            .expect("static power regex")
    })
}

fn signal_report_regex() -> &'static Regex {
    static R: OnceLock<Regex> = OnceLock::new();
    R.get_or_init(|| Regex::new(SIGNAL_REPORT_PATTERN).expect("static rst regex"))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallsignContext {
    CqCall,
    DeIdentifier,
    Response,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DetectedCallsign {
    pub callsign: String,
    pub context: CallsignContext,
}

/// Unique callsigns appearing in `text` in source order, uppercased.
pub fn extract_callsigns(text: &str) -> Vec<String> {
    let upper = text.to_uppercase();
    let mut seen = HashSet::new();
    let mut out = Vec::new();
    for m in callsign_regex().find_iter(&upper) {
        let candidate = m.as_str().to_string();
        if is_valid_callsign(&candidate) && seen.insert(candidate.clone()) {
            out.push(candidate);
        }
    }
    out
}

/// Pick the most likely "other station" callsign from a CW transcript using
/// surrounding-word context. Priority matches Swift: `de_identifier` >
/// `cq_call` > `response` > `unknown`; within a tier, the LAST occurrence
/// wins (Swift uses `.last(where:)`).
pub fn detect_primary_callsign(text: &str) -> Option<DetectedCallsign> {
    let upper = text.to_uppercase();
    let words: Vec<&str> = upper.split_whitespace().collect();
    let mut candidates: Vec<DetectedCallsign> = Vec::new();
    for (idx, word) in words.iter().enumerate() {
        if !is_valid_callsign(word) {
            continue;
        }
        let context = determine_context(idx, &words);
        candidates.push(DetectedCallsign {
            callsign: (*word).to_string(),
            context,
        });
    }
    for target in [
        CallsignContext::DeIdentifier,
        CallsignContext::CqCall,
        CallsignContext::Response,
        CallsignContext::Unknown,
    ] {
        if let Some(c) = candidates.iter().rev().find(|c| c.context == target) {
            return Some(c.clone());
        }
    }
    candidates.last().cloned()
}

/// Extract a grid square (e.g. `EM74`, `FN31pr`) if present.
pub fn extract_grid_square(text: &str) -> Option<String> {
    grid_regex().find(&text.to_uppercase()).map(|m| m.as_str().to_string())
}

/// Extract a power expression (e.g. `100W`, `1KW`) if present.
pub fn extract_power(text: &str) -> Option<String> {
    power_regex().find(&text.to_uppercase()).map(|m| m.as_str().to_string())
}

/// Extract an RST signal report if present.
pub fn extract_rst(text: &str) -> Option<String> {
    signal_report_regex().find(text).map(|m| m.as_str().to_string())
}

fn is_valid_callsign(candidate: &str) -> bool {
    if candidate.chars().count() < 4 {
        return false;
    }
    if !candidate.chars().any(|c| c.is_alphabetic()) {
        return false;
    }
    if !candidate.chars().any(|c| c.is_ascii_digit()) {
        return false;
    }
    const FALSE_POSITIVES: &[&str] = &["1ST", "2ND", "3RD", "4TH", "5TH", "73S", "88S", "599S"];
    !FALSE_POSITIVES.contains(&candidate)
}

fn determine_context(index: usize, words: &[&str]) -> CallsignContext {
    if index > 0 && words[index - 1] == "DE" {
        return CallsignContext::DeIdentifier;
    }
    if index > 0 {
        let start = index.saturating_sub(3);
        if words[start..index].contains(&"CQ") {
            return CallsignContext::CqCall;
        }
    }
    if index + 1 < words.len() && words[index + 1] == "DE" {
        return CallsignContext::Response;
    }
    CallsignContext::Unknown
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_unique_callsigns() {
        let text = "CQ CQ DE W1AW W1AW W1AW K";
        let calls = extract_callsigns(text);
        assert_eq!(calls, vec!["W1AW".to_string()]);
    }

    #[test]
    fn rejects_false_positives() {
        assert!(!is_valid_callsign("CQ")); // too short
        assert!(!is_valid_callsign("ABCD")); // no digit
        assert!(!is_valid_callsign("1234")); // no letter
        assert!(!is_valid_callsign("73S"));
        assert!(is_valid_callsign("W1AW"));
        assert!(is_valid_callsign("VK2ABC"));
    }

    #[test]
    fn de_identifier_wins() {
        let text = "CQ K1JT K1JT K1JT DE W1AW K";
        let primary = detect_primary_callsign(text).unwrap();
        // The DE identifier is W1AW; K1JT appears earlier but DE has highest priority.
        assert_eq!(primary.callsign, "W1AW");
        assert_eq!(primary.context, CallsignContext::DeIdentifier);
    }

    #[test]
    fn cq_call_priority_when_no_de() {
        let text = "CQ CQ K1JT K1JT K";
        let primary = detect_primary_callsign(text).unwrap();
        assert_eq!(primary.callsign, "K1JT");
        assert_eq!(primary.context, CallsignContext::CqCall);
    }

    #[test]
    fn response_context_detected() {
        let text = "K1JT DE W1AW";
        let primary = detect_primary_callsign(text).unwrap();
        // DE-identifier W1AW wins over K1JT's response role.
        assert_eq!(primary.callsign, "W1AW");
    }

    #[test]
    fn extracts_grid_and_power_and_rst() {
        assert_eq!(extract_grid_square("nr Boston FN31"), Some("FN31".to_string()));
        assert_eq!(extract_grid_square("home is FN31pr now"), Some("FN31PR".to_string()));
        assert_eq!(extract_power("running 100W into a vert"), Some("100W".to_string()));
        assert_eq!(extract_power("on the 1KW amp"), Some("1KW".to_string()));
        // RST: between [1-5][1-9][1-9?] — "599" matches.
        assert_eq!(extract_rst("ur 599 in"), Some("599".to_string()));
    }
}
