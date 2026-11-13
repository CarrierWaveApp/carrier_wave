//! POTA/WWFF park-reference parsing and validation. Port of
//! `ParkReference.swift`.

use std::collections::HashSet;
use std::sync::OnceLock;

use regex::Regex;

fn valid_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^[A-Z]{1,2}-[0-9]{4,5}$").unwrap())
}

fn missing_dash_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"^([A-Z]{1,2})(\d{4,5})$").unwrap())
}

fn anchored_extract_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"\b([A-Z]{1,2}-\d{4,5})\b").unwrap())
}

fn strip_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"(?i)\b[A-Za-z]{1,2}-\d{4,5}\b").unwrap())
}

/// Split a comma-separated park reference string into individual parks.
/// `"US-1044, US-3791"` -> `["US-1044", "US-3791"]`.
pub fn split(park_ref: &str) -> Vec<String> {
    park_ref
        .split(',')
        .map(|s| s.trim().to_uppercase())
        .filter(|s| !s.is_empty())
        .collect()
}

/// Multi-park reference detection (contains a comma).
pub fn is_multi_park(park_ref: &str) -> bool {
    park_ref.contains(',')
}

/// Validity check: `XX-####` or `XX-#####` after uppercase+trim.
pub fn is_valid(park_ref: &str) -> bool {
    let upper = park_ref.trim().to_uppercase();
    valid_regex().is_match(&upper)
}

/// Normalize: trim + uppercase.
pub fn normalize(park_ref: &str) -> String {
    park_ref.trim().to_uppercase()
}

/// Repair common upstream malformations:
/// - `"US1849"` → `"US-1849"`
/// - bare numbers (`"3687"`) → `None` (ambiguous)
pub fn sanitize(park_ref: &str) -> Option<String> {
    let trimmed = park_ref.trim().to_uppercase();
    if trimmed.is_empty() {
        return None;
    }
    if is_valid(&trimmed) {
        return Some(trimmed);
    }
    if let Some(caps) = missing_dash_regex().captures(&trimmed) {
        let prefix = caps.get(1)?.as_str();
        let digits = caps.get(2)?.as_str();
        let fixed = format!("{prefix}-{digits}");
        if is_valid(&fixed) {
            return Some(fixed);
        }
    }
    None
}

/// Extract park references from free-text (e.g. ADIF comments). Returns a
/// sanitized multi-park string if any valid refs found.
pub fn extract_from_free_text(text: &str) -> Option<String> {
    let upper = text.to_uppercase();
    let mut seen = HashSet::new();
    let mut valid = Vec::new();
    for caps in anchored_extract_regex().captures_iter(&upper) {
        let candidate = caps.get(1)?.as_str().to_string();
        if !is_valid(&candidate) || seen.contains(&candidate) {
            continue;
        }
        seen.insert(candidate.clone());
        valid.push(candidate);
    }
    if valid.is_empty() {
        None
    } else {
        Some(valid.join(", "))
    }
}

/// Strip park-reference patterns from free-text. `None` if nothing remains.
pub fn strip_from_free_text(text: &str) -> Option<String> {
    let stripped = strip_regex().replace_all(text, "");
    let cleaned = stripped.replace("  ", " ").trim().to_string();
    if cleaned.is_empty() {
        None
    } else {
        Some(cleaned)
    }
}

/// Sanitize a potentially multi-park reference, fixing each individual park.
pub fn sanitize_multi(park_ref: &str) -> Option<String> {
    let sanitized: Vec<String> = split(park_ref).iter().filter_map(|p| sanitize(p)).collect();
    if sanitized.is_empty() {
        None
    } else {
        Some(sanitized.join(", "))
    }
}

/// Normalize a potentially multi-park reference (sorts parks for stable
/// comparison).
pub fn normalize_multi(park_ref: &str) -> String {
    let mut parks = split(park_ref);
    parks.sort();
    parks.join(", ")
}

/// Is `subset` a subset of `superset` (set semantics)?
pub fn is_subset(subset: &str, superset: &str) -> bool {
    let subset: HashSet<String> = split(subset).into_iter().collect();
    let superset: HashSet<String> = split(superset).into_iter().collect();
    subset.is_subset(&superset)
}

/// Do the two refs share any parks?
pub fn has_overlap(park_ref1: &str, park_ref2: &str) -> bool {
    let a: HashSet<String> = split(park_ref1).into_iter().collect();
    let b: HashSet<String> = split(park_ref2).into_iter().collect();
    !a.is_disjoint(&b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_and_uppercases() {
        assert_eq!(
            split("us-1044, US-3791 ,  "),
            vec!["US-1044".to_string(), "US-3791".to_string()]
        );
    }

    #[test]
    fn is_valid_matches_xx_dddd() {
        assert!(is_valid("K-1234"));
        assert!(is_valid("US-04567"));
        assert!(!is_valid("ABCD-1234"));
        assert!(!is_valid("K12345"));
        assert!(!is_valid("K-12"));
    }

    #[test]
    fn sanitize_repairs_missing_dash() {
        assert_eq!(sanitize("us1849"), Some("US-1849".to_string()));
        assert_eq!(sanitize("3687"), None);
        assert_eq!(sanitize(" K-1234 "), Some("K-1234".to_string()));
    }

    #[test]
    fn extract_from_free_text_finds_multi() {
        assert_eq!(
            extract_from_free_text("Activated at K-1234 and us-3791 yesterday"),
            Some("K-1234, US-3791".to_string())
        );
    }

    #[test]
    fn strip_from_free_text_returns_remainder_or_none() {
        assert_eq!(
            strip_from_free_text("Activated at K-1234 yesterday"),
            Some("Activated at yesterday".to_string())
        );
        assert_eq!(strip_from_free_text("K-1234"), None);
    }

    #[test]
    fn is_subset_set_semantics() {
        assert!(is_subset("US-1044", "US-1044, US-3791"));
        assert!(is_subset("US-1044, US-3791", "US-3791, US-1044"));
        assert!(!is_subset("US-9999", "US-1044, US-3791"));
    }

    #[test]
    fn has_overlap_uses_set_intersection() {
        assert!(has_overlap("US-1044", "US-1044, US-3791"));
        assert!(!has_overlap("US-1044", "US-3791"));
    }

    #[test]
    fn normalize_multi_sorts() {
        assert_eq!(
            normalize_multi("US-3791, US-1044"),
            "US-1044, US-3791".to_string()
        );
    }
}
