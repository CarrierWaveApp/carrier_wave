//! Club-membership cache logic — the portable core of `ClubsSyncService`.
//!
//! Pure functions over the compact membership view the server's
//! `/v1/clubs/membership` endpoint returns (a club name plus its member
//! callsigns). These build the two lookups the UI needs everywhere a callsign
//! appears — callsign → clubs and club → callsigns — and the prior-callsign
//! union the sync uses to expand the request. No I/O; identical on every
//! platform.
//!
//! Callsign comparisons are case-insensitive: keys and values are uppercased so
//! `clubs(for:)`-style lookups match regardless of how a callsign was entered,
//! mirroring `ClubsSyncService`'s `.uppercased()` discipline.

use std::collections::{BTreeMap, BTreeSet};

/// One club and the callsigns that belong to it — the shape of a
/// `/v1/clubs/membership` entry (`ClubMembershipEntry` on the server).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClubMembership {
    pub club_name: String,
    pub callsigns: Vec<String>,
}

impl ClubMembership {
    pub fn new(club_name: impl Into<String>, callsigns: Vec<String>) -> Self {
        ClubMembership { club_name: club_name.into(), callsigns }
    }
}

/// Map of uppercased callsign → the names of clubs it belongs to (deduped,
/// name-sorted). Portable equivalent of `ClubsSyncService.clubsByCallsign`.
pub fn callsign_to_clubs(entries: &[ClubMembership]) -> BTreeMap<String, Vec<String>> {
    // Use a set per callsign to dedup, then flatten to sorted vecs.
    let mut acc: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for entry in entries {
        for callsign in &entry.callsigns {
            acc.entry(normalize(callsign))
                .or_default()
                .insert(entry.club_name.clone());
        }
    }
    acc.into_iter().map(|(call, clubs)| (call, clubs.into_iter().collect())).collect()
}

/// Map of club name → the set of uppercased member callsigns. Portable
/// equivalent of `ClubsSyncService.callsignsByClub`.
pub fn club_to_callsigns(entries: &[ClubMembership]) -> BTreeMap<String, BTreeSet<String>> {
    let mut acc: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
    for entry in entries {
        let set = acc.entry(entry.club_name.clone()).or_default();
        for callsign in &entry.callsigns {
            set.insert(normalize(callsign));
        }
    }
    acc
}

/// Whether `callsign` belongs to the named club (both compared case-insensitively).
pub fn is_member(entries: &[ClubMembership], callsign: &str, club_name: &str) -> bool {
    let target = normalize(callsign);
    entries
        .iter()
        .filter(|entry| entry.club_name.eq_ignore_ascii_case(club_name))
        .any(|entry| entry.callsigns.iter().any(|call| normalize(call) == target))
}

/// The set of clubs a callsign belongs to (deduped, name-sorted). Convenience
/// over [`callsign_to_clubs`] for a single lookup.
pub fn clubs_for(entries: &[ClubMembership], callsign: &str) -> Vec<String> {
    let target = normalize(callsign);
    let mut clubs: BTreeSet<String> = BTreeSet::new();
    for entry in entries {
        if entry.callsigns.iter().any(|call| normalize(call) == target) {
            clubs.insert(entry.club_name.clone());
        }
    }
    clubs.into_iter().collect()
}

/// Union of a primary callsign with any prior callsigns, uppercased and deduped,
/// primary first. Mirrors how the sync expands the `/v1/clubs?callsigns=` request
/// to cover calls the operator has held before.
pub fn union_callsigns(primary: &str, prior: &[String]) -> Vec<String> {
    let mut seen: BTreeSet<String> = BTreeSet::new();
    let mut out = Vec::new();
    for call in std::iter::once(primary).chain(prior.iter().map(String::as_str)) {
        let norm = normalize(call);
        if norm.is_empty() {
            continue;
        }
        if seen.insert(norm.clone()) {
            out.push(norm);
        }
    }
    out
}

/// Uppercase + trim — the canonical form callsign keys are stored and compared in.
fn normalize(callsign: &str) -> String {
    callsign.trim().to_uppercase()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Vec<ClubMembership> {
        vec![
            ClubMembership::new("SKCC", vec!["W6JY".into(), "n6abc".into()]),
            ClubMembership::new("FISTS", vec!["W6JY".into(), "K7XYZ".into()]),
        ]
    }

    #[test]
    fn callsign_to_clubs_dedups_and_sorts() {
        let map = callsign_to_clubs(&fixture());
        // Lookup key is uppercased regardless of source casing.
        assert_eq!(map.get("W6JY"), Some(&vec!["FISTS".to_string(), "SKCC".to_string()]));
        assert_eq!(map.get("N6ABC"), Some(&vec!["SKCC".to_string()]));
        assert_eq!(map.get("K7XYZ"), Some(&vec!["FISTS".to_string()]));
    }

    #[test]
    fn club_to_callsigns_normalizes() {
        let map = club_to_callsigns(&fixture());
        let skcc = map.get("SKCC").unwrap();
        assert!(skcc.contains("W6JY"));
        assert!(skcc.contains("N6ABC"), "lowercase source callsign normalized to upper");
        assert_eq!(skcc.len(), 2);
    }

    #[test]
    fn is_member_is_case_insensitive() {
        let entries = fixture();
        assert!(is_member(&entries, "w6jy", "skcc"));
        assert!(is_member(&entries, "N6ABC", "SKCC"));
        assert!(!is_member(&entries, "N6ABC", "FISTS"));
        assert!(!is_member(&entries, "NOBODY", "SKCC"));
    }

    #[test]
    fn clubs_for_single_callsign() {
        assert_eq!(clubs_for(&fixture(), "w6jy"), vec!["FISTS", "SKCC"]);
        assert!(clubs_for(&fixture(), "unknown").is_empty());
    }

    #[test]
    fn union_callsigns_dedups_keeps_primary_first() {
        let union = union_callsigns("W6JY", &["W6JSV".into(), "w6jy".into(), "  ".into()]);
        assert_eq!(union, vec!["W6JY", "W6JSV"]);
    }
}
