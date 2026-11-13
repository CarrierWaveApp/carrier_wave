//! In-memory Super Check Partial database for fast callsign matching.
//! Port of `SCPDatabase.swift`. Holds ~80K callsigns from MASTER.SCP and
//! provides partial, exact, and near-match (edit-distance) lookup.
//!
//! Pure logic — the download/disk caching of MASTER.SCP stays in the Swift/
//! Kotlin app layer; this is the matcher the FFI swaps in.

use std::collections::HashSet;

use crate::callsign_edit_distance;

/// Sorted, de-duplicated, uppercased callsign database.
#[derive(Debug, Clone, Default)]
pub struct ScpDatabase {
    sorted: Vec<String>,
    set: HashSet<String>,
}

impl ScpDatabase {
    /// Build from a collection of callsigns. Deduplicates, uppercases, and
    /// drops empty strings (mirrors the Swift `init(callsigns:)`).
    pub fn new<I, S>(callsigns: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        let mut set = HashSet::new();
        let mut unique: Vec<String> = Vec::new();
        for call in callsigns {
            let upper = call.as_ref().to_uppercase();
            if upper.is_empty() {
                continue;
            }
            if set.insert(upper.clone()) {
                unique.push(upper);
            }
        }
        unique.sort();
        Self { sorted: unique, set }
    }

    /// Number of callsigns in the database.
    pub fn count(&self) -> usize {
        self.sorted.len()
    }

    /// Whether the database has no callsigns loaded.
    pub fn is_empty(&self) -> bool {
        self.sorted.is_empty()
    }

    /// Classic SCP: all callsigns containing the fragment (case-insensitive).
    /// Prefix matches first (alphabetical), then substring matches. Fragments
    /// shorter than 3 characters return empty. Returns up to `limit` matches.
    pub fn partial_match(&self, fragment: &str, limit: usize) -> Vec<String> {
        let upper = fragment.to_uppercase();
        if upper.chars().count() < 3 {
            return Vec::new();
        }

        let mut results: Vec<String> = Vec::with_capacity(limit);

        // Prefix matches first (most relevant).
        for call in &self.sorted {
            if results.len() >= limit {
                break;
            }
            if call.starts_with(&upper) {
                results.push(call.clone());
            }
        }

        // Then substring matches that are not prefixes.
        if results.len() < limit {
            for call in &self.sorted {
                if results.len() >= limit {
                    break;
                }
                if !call.starts_with(&upper) && call.contains(&upper) {
                    results.push(call.clone());
                }
            }
        }

        results
    }

    /// Is this exact callsign in the database? (Case-insensitive.)
    pub fn contains(&self, callsign: &str) -> bool {
        self.set.contains(&callsign.to_uppercase())
    }

    /// Create a new database by merging additional callsigns into this one.
    /// Used to augment MASTER.SCP with the user's repeat contacts.
    pub fn merging<I, S>(&self, additional: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        let mut set = self.set.clone();
        let mut additions: Vec<String> = Vec::new();
        for call in additional {
            let upper = call.as_ref().to_uppercase();
            if upper.is_empty() {
                continue;
            }
            if set.insert(upper.clone()) {
                additions.push(upper);
            }
        }
        if additions.is_empty() {
            return self.clone();
        }
        let mut merged = self.sorted.clone();
        merged.extend(additions);
        merged.sort();
        Self { sorted: merged, set }
    }

    /// Near-misses within edit distance. Only useful for complete callsigns
    /// (4+ chars). Skips exact matches (distance == 0). Sorted by distance.
    pub fn near_matches(&self, callsign: &str, max_distance: usize) -> Vec<(String, usize)> {
        if callsign.chars().count() < 4 {
            return Vec::new();
        }
        callsign_edit_distance::find_near_matches(
            callsign,
            max_distance,
            self.sorted.iter().map(String::as_str),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Mirrors SCPDatabaseTests.swift.

    #[test]
    fn init_dedup_and_uppercase() {
        let db = ScpDatabase::new(["w6jsv", "W6JSV", "k6abc", "K6ABC", "w6jsv"]);
        assert_eq!(db.count(), 2);
    }

    #[test]
    fn init_filters_empty_strings() {
        let db = ScpDatabase::new(["W6JSV", "", "  ", "K6ABC"]);
        assert!(db.contains("W6JSV"));
        assert!(db.contains("K6ABC"));
    }

    #[test]
    fn empty_database() {
        let db = ScpDatabase::new(Vec::<String>::new());
        assert!(db.is_empty());
        assert_eq!(db.count(), 0);
        assert_eq!(db.partial_match("W6J", 20), Vec::<String>::new());
        assert!(!db.contains("W6JSV"));
        assert_eq!(db.near_matches("W6JSV", 1).len(), 0);
    }

    #[test]
    fn partial_match_prefix_first() {
        let db = ScpDatabase::new(["W6JSV", "KW6JS", "W6JTI", "W6JBR", "AA1AA"]);
        let results = db.partial_match("W6J", 20);
        assert!(results.len() >= 3);
        assert_eq!(results[0], "W6JBR"); // alphabetical among prefix matches
        assert_eq!(results[1], "W6JSV");
        assert_eq!(results[2], "W6JTI");
        assert!(results.contains(&"KW6JS".to_string()));
        assert!(!results.contains(&"AA1AA".to_string()));
    }

    #[test]
    fn partial_match_respects_limit() {
        let calls: Vec<String> = (0..50).map(|i| format!("W6J{i:02}")).collect();
        let db = ScpDatabase::new(calls);
        assert_eq!(db.partial_match("W6J", 10).len(), 10);
    }

    #[test]
    fn partial_match_too_short_returns_empty() {
        let db = ScpDatabase::new(["W6JSV", "W6JTI"]);
        assert!(db.partial_match("W6", 20).is_empty());
        assert!(db.partial_match("W", 20).is_empty());
        assert!(db.partial_match("", 20).is_empty());
    }

    #[test]
    fn partial_match_case_insensitive() {
        let db = ScpDatabase::new(["W6JSV", "K6ABC"]);
        assert_eq!(db.partial_match("w6j", 20), vec!["W6JSV".to_string()]);
    }

    #[test]
    fn contains_exact_match() {
        let db = ScpDatabase::new(["W6JSV", "K6ABC", "VE3XYZ"]);
        assert!(db.contains("W6JSV"));
        assert!(db.contains("w6jsv"));
        assert!(!db.contains("W6JSX"));
    }

    #[test]
    fn near_matches_finds_edit_distance_1() {
        let db = ScpDatabase::new(["W6JSV", "W6JSW", "W6JTV", "K6ABC"]);
        let calls: Vec<String> = db.near_matches("W6JSX", 1).into_iter().map(|(call, _)| call).collect();
        assert!(calls.contains(&"W6JSV".to_string()));
        assert!(calls.contains(&"W6JSW".to_string()));
        assert!(!calls.contains(&"W6JTV".to_string())); // distance 2
    }

    #[test]
    fn near_matches_skips_short_callsigns() {
        let db = ScpDatabase::new(["W6JSV"]);
        assert!(db.near_matches("W6J", 1).is_empty());
    }

    #[test]
    fn near_matches_skips_exact_match() {
        let db = ScpDatabase::new(["W6JSV", "W6JSW"]);
        let calls: Vec<String> = db.near_matches("W6JSV", 1).into_iter().map(|(call, _)| call).collect();
        assert!(!calls.contains(&"W6JSV".to_string()));
        assert!(calls.contains(&"W6JSW".to_string()));
    }

    #[test]
    fn merging_adds_new_callsigns() {
        let db = ScpDatabase::new(["W6JSV", "K6ABC"]);
        let merged = db.merging(["VE3XYZ", "JA1ABC"]);
        assert_eq!(merged.count(), 4);
        assert!(merged.contains("VE3XYZ"));
        assert!(merged.contains("JA1ABC"));
        assert!(merged.contains("W6JSV"));
    }

    #[test]
    fn merging_deduplicates_existing() {
        let db = ScpDatabase::new(["W6JSV", "K6ABC"]);
        let merged = db.merging(["w6jsv", "VE3XYZ"]);
        assert_eq!(merged.count(), 3);
        assert!(merged.contains("VE3XYZ"));
    }

    #[test]
    fn merging_with_empty_is_identity() {
        let db = ScpDatabase::new(["W6JSV", "K6ABC"]);
        assert_eq!(db.merging(Vec::<String>::new()).count(), 2);
    }

    #[test]
    fn merged_database_supports_partial_match() {
        let db = ScpDatabase::new(["W6JSV"]);
        let merged = db.merging(["W6JTI", "K6ABC"]);
        let results = merged.partial_match("W6J", 20);
        assert_eq!(results.len(), 2);
        assert!(results.contains(&"W6JSV".to_string()));
        assert!(results.contains(&"W6JTI".to_string()));
    }
}
