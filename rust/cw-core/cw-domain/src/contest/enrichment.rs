//! Contest-exchange prefill from enrichment membership data. Port of
//! `Services/Contest/ContestEnrichmentMatcher.swift`.
//!
//! The Swift matcher pulls the membership out of a `CallsignEnrichmentEntry`;
//! here the host resolves the membership for `source_slug(contest_id)` and
//! passes the name/member-number values in, which breaks the model coupling.

use std::collections::HashMap;

/// Mapping of contest definition IDs to the enrichment source slug whose
/// membership data fills the exchange. Add new pairs here when new contests
/// can be auto-filled.
pub const CONTEST_TO_SOURCE: [(&str, &str); 1] = [("cwops-cwt", "cwops")];

/// Enrichment source slug for a contest id, if the contest supports prefill.
pub fn source_slug(contest_id: &str) -> Option<&'static str> {
    CONTEST_TO_SOURCE
        .iter()
        .find(|(contest, _)| *contest == contest_id)
        .map(|(_, slug)| *slug)
}

/// Membership values the host resolved for the contest's source slug.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct MembershipPrefill {
    /// Registered name from the membership list (e.g. CWops PoLo "TIMOTHY D").
    pub name: Option<String>,
    /// Member number (already digit-only, e.g. "3573").
    pub member_number: Option<String>,
}

/// Populate the name/identifier fields of `values` if they're currently
/// empty. Returns the keys/values that were written so the caller can later
/// clear them (e.g. when the callsign is cleared) without disturbing
/// user-typed entries.
///
/// Sources, in priority order:
/// - `name` ← `preferred_name` (e.g. QRZ nickname → "TIM") overrides the
///   membership-list registered name; falls back to the membership name.
/// - `identifier` ← member number from the matched membership. Falls back
///   to `fallback_identifier` for non-members (state for US, province for
///   Canada, DXCC prefix for DX).
pub fn prefill(
    membership: Option<&MembershipPrefill>,
    contest_id: &str,
    preferred_name: Option<&str>,
    fallback_identifier: Option<&str>,
    values: &mut HashMap<String, String>,
) -> HashMap<String, String> {
    if source_slug(contest_id).is_none() {
        return HashMap::new();
    }

    let mut written: HashMap<String, String> = HashMap::new();

    let name_source = non_empty_trimmed(preferred_name)
        .or_else(|| non_empty_trimmed(membership.and_then(|prefill| prefill.name.as_deref())));
    if let Some(raw) = name_source {
        if values.get("name").map_or(true, String::is_empty) {
            let formatted = format_exchange_name(&raw);
            if !formatted.is_empty() {
                values.insert("name".to_string(), formatted.clone());
                written.insert("name".to_string(), formatted);
            }
        }
    }

    // Members send #N (already digit-only); non-members send a S/P/C code
    // which we uppercase for wire-format consistency.
    let identifier_empty = values.get("identifier").map_or(true, String::is_empty);
    if let Some(number) =
        non_empty_trimmed(membership.and_then(|prefill| prefill.member_number.as_deref()))
    {
        if identifier_empty {
            values.insert("identifier".to_string(), number.clone());
            written.insert("identifier".to_string(), number);
        }
    } else if let Some(fallback) = non_empty_trimmed(fallback_identifier) {
        if identifier_empty {
            let upper = fallback.to_uppercase();
            values.insert("identifier".to_string(), upper.clone());
            written.insert("identifier".to_string(), upper);
        }
    }

    written
}

/// Reduce a member-list / QRZ name to the first whitespace token in ALL
/// CAPS — the CWT wire-format convention. `"Timothy D"` → `"TIMOTHY"`,
/// `"Jay V"` → `"JAY"`, `"Tim"` → `"TIM"`. Callers should prefer the QRZ
/// nickname over the membership-list name where available.
pub fn format_exchange_name(raw_name: &str) -> String {
    raw_name
        .split_whitespace()
        .next()
        .map(str::to_uppercase)
        .unwrap_or_default()
}

fn non_empty_trimmed(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    if trimmed.is_empty() { None } else { Some(trimmed.to_string()) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn source_slug_mapping() {
        assert_eq!(source_slug("cwops-cwt"), Some("cwops"));
        assert_eq!(source_slug("k1usn-sst"), None);
    }

    #[test]
    fn prefill_prefers_nickname_over_membership_name() {
        let membership = MembershipPrefill {
            name: Some("Timothy D".to_string()),
            member_number: Some("3573".to_string()),
        };
        let mut values = HashMap::new();
        let written = prefill(Some(&membership), "cwops-cwt", Some("Tim"), None, &mut values);
        assert_eq!(values.get("name").map(String::as_str), Some("TIM"));
        assert_eq!(values.get("identifier").map(String::as_str), Some("3573"));
        assert_eq!(written.len(), 2);
    }

    #[test]
    fn prefill_falls_back_to_membership_name_and_spc() {
        let mut values = HashMap::new();
        let written = prefill(
            Some(&MembershipPrefill { name: Some("Timothy D".to_string()), member_number: None }),
            "cwops-cwt",
            None,
            Some("or"),
            &mut values,
        );
        assert_eq!(values.get("name").map(String::as_str), Some("TIMOTHY"));
        assert_eq!(values.get("identifier").map(String::as_str), Some("OR"));
        assert_eq!(written.len(), 2);
    }

    #[test]
    fn prefill_never_overwrites_user_typed_values() {
        let membership = MembershipPrefill {
            name: Some("Timothy D".to_string()),
            member_number: Some("3573".to_string()),
        };
        let mut values = HashMap::from([
            ("name".to_string(), "STEVE".to_string()),
            ("identifier".to_string(), "42".to_string()),
        ]);
        let written = prefill(Some(&membership), "cwops-cwt", None, None, &mut values);
        assert!(written.is_empty());
        assert_eq!(values.get("name").map(String::as_str), Some("STEVE"));
        assert_eq!(values.get("identifier").map(String::as_str), Some("42"));
    }

    #[test]
    fn unmapped_contest_writes_nothing() {
        let mut values = HashMap::new();
        let written = prefill(None, "k1usn-sst", Some("Tim"), Some("OR"), &mut values);
        assert!(written.is_empty());
        assert!(values.is_empty());
    }

    #[test]
    fn exchange_name_formatting() {
        assert_eq!(format_exchange_name("Timothy D"), "TIMOTHY");
        assert_eq!(format_exchange_name("  Jay V "), "JAY");
        assert_eq!(format_exchange_name("Tim"), "TIM");
        assert_eq!(format_exchange_name("   "), "");
    }
}
