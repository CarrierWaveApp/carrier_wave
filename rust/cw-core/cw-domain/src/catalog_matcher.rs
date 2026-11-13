//! Fuzzy equipment-catalog matcher — port of
//! `CarrierWaveData/Utilities/CatalogMatcher.swift`.
//!
//! Matches a user-entered equipment name (e.g. "mtr4b", "kx2") against the
//! canonical catalog with a confidence score. Pure/deterministic string logic;
//! the FFI layer (`cw-ffi` `EquipmentApi`) feeds it the cached catalog entries
//! and maps `CatalogMatch.index` back to the full DTO.
//!
//! Parity is the acceptance bar — the scoring phases, thresholds, and weights
//! mirror the Swift source exactly. Two deliberate, documented deviations:
//!   1. Empty-target `contains` follows Swift semantics (`String.contains("")`
//!      is `false`), not Rust's (`str::contains("")` is `true`).
//!   2. Ties in the final sort break by ascending catalog index for determinism
//!      (Swift's `sorted` is unstable and falls back to input order).

use std::cmp::Ordering;

/// A borrowed view of one catalog entry — lets `cw-domain` score entries without
/// depending on `cw-net`'s wire types or `cw-store`.
pub struct CatalogEntryRef<'a> {
    pub id: &'a str,
    pub name: &'a str,
    /// Empty string when the wire field is absent.
    pub manufacturer: &'a str,
    /// Category raw value (e.g. "radio"); `None` when absent.
    pub category: Option<&'a str>,
    pub aliases: &'a [String],
}

impl CatalogEntryRef<'_> {
    /// Full display name with manufacturer — `"\(manufacturer) \(name)"`.
    fn full_name(&self) -> String {
        format!("{} {}", self.manufacturer, self.name)
    }
}

/// A scored match: `index` into the input slice + confidence in 0.0..=1.0.
#[derive(Debug, Clone, PartialEq)]
pub struct CatalogMatch {
    pub index: usize,
    pub confidence: f64,
}

/// Search the catalog for entries matching `query`, best-confidence first.
/// Returns `[]` for a blank/normalized-empty query. Entries scoring `<= 0.3`
/// are excluded (`> 0.3` to include, matching Swift).
pub fn search(
    query: &str,
    entries: &[CatalogEntryRef<'_>],
    category: Option<&str>,
    limit: usize,
) -> Vec<CatalogMatch> {
    let normalized = normalize(query);
    if normalized.is_empty() {
        return Vec::new();
    }

    let mut scored: Vec<CatalogMatch> = Vec::new();
    for (index, entry) in entries.iter().enumerate() {
        if let Some(cat) = category {
            if entry.category != Some(cat) {
                continue;
            }
        }
        let score = match_score(&normalized, entry);
        if score > 0.3 {
            scored.push(CatalogMatch { index, confidence: score });
        }
    }

    scored.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(Ordering::Equal)
            .then(a.index.cmp(&b.index))
    });
    scored.truncate(limit);
    scored
}

/// The single best match at or above `threshold`, else `None`.
pub fn best_match(
    query: &str,
    entries: &[CatalogEntryRef<'_>],
    category: Option<&str>,
    threshold: f64,
) -> Option<CatalogMatch> {
    search(query, entries, category, 1)
        .into_iter()
        .next()
        .filter(|m| m.confidence >= threshold)
}

// ---------- scoring internals (faithful port) ----------

fn normalize(input: &str) -> String {
    input.to_lowercase().replace(['-', '_', ' '], "").trim().to_string()
}

/// `query` is the already-normalized query string (as in the Swift call site).
fn match_score(query: &str, entry: &CatalogEntryRef<'_>) -> f64 {
    // Phase 1: exact (case-insensitive, unnormalized target).
    let query_lower = query.to_lowercase();
    let full_name = entry.full_name();
    if entry.name.to_lowercase() == query_lower || full_name.to_lowercase() == query_lower {
        return 1.0;
    }
    if entry.aliases.iter().any(|alias| alias.to_lowercase() == query_lower) {
        return 1.0;
    }

    // Phase 2: word-level comparison.
    let query_words = tokenize(query);
    let word_score = word_match_score(&query_words, &tokenize(&full_name));
    if word_score >= 0.95 {
        return word_score;
    }

    // Phase 3: fuzzy matching on normalized strings.
    let mut best_score = word_score;
    let normalized_query = normalize(query);

    best_score = best_score.max(string_score(&normalized_query, &normalize(entry.name)));
    best_score = best_score.max(string_score(&normalized_query, &normalize(&full_name)));

    let mfg_score = string_score(&normalized_query, &normalize(entry.manufacturer));
    if mfg_score > 0.8 {
        best_score = best_score.max(mfg_score * 0.7);
    }

    for alias in entry.aliases {
        best_score = best_score.max(string_score(&normalized_query, &normalize(alias)));
    }

    let slug_score = string_score(&normalized_query, &normalize(entry.id));
    best_score = best_score.max(slug_score * 0.9);

    best_score
}

/// Score how well `query` matches `target` (0.0..=1.0, 1.0 exact).
fn string_score(query: &str, target: &str) -> f64 {
    if query == target {
        return 1.0;
    }

    // Substring containment — penalize by length difference. Guard empty operands
    // to match Swift's `String.contains("") == false`.
    if !query.is_empty() && target.contains(query) {
        let len_ratio = char_len(query) as f64 / char_len(target) as f64;
        return 0.7 + (0.25 * len_ratio);
    }
    if !target.is_empty() && query.contains(target) {
        let len_ratio = char_len(target) as f64 / char_len(query) as f64;
        return 0.6 + (0.2 * len_ratio);
    }

    // Levenshtein-based similarity for typo tolerance.
    let distance = edit_distance(query, target);
    let max_len = char_len(query).max(char_len(target));
    if max_len == 0 {
        return 0.0;
    }
    let similarity = 1.0 - (distance as f64 / max_len as f64);
    similarity.max(0.0)
}

/// Split into lowercase alphanumeric tokens.
fn tokenize(input: &str) -> Vec<String> {
    input
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect()
}

/// Average per-word best match. Each query word matches a target word exactly or
/// (for 3+ char tokens) with high edit-distance similarity.
fn word_match_score(query_words: &[String], target_words: &[String]) -> f64 {
    if query_words.is_empty() || target_words.is_empty() {
        return 0.0;
    }

    let mut total_score = 0.0;
    for qw in query_words {
        let mut best_word_score = 0.0_f64;
        for tw in target_words {
            if qw == tw {
                best_word_score = 1.0;
                break;
            }
            if char_len(qw) >= 3 && char_len(tw) >= 3 {
                let dist = edit_distance(qw, tw);
                let max_len = char_len(qw).max(char_len(tw));
                let sim = 1.0 - (dist as f64 / max_len as f64);
                if sim >= 0.75 {
                    best_word_score = best_word_score.max(sim * 0.9);
                }
            }
        }
        total_score += best_word_score;
    }

    total_score / query_words.len() as f64
}

/// Levenshtein edit distance over Unicode scalars.
fn edit_distance(source: &str, target: &str) -> usize {
    let src_chars: Vec<char> = source.chars().collect();
    let tgt_chars: Vec<char> = target.chars().collect();
    let src_len = src_chars.len();
    let tgt_len = tgt_chars.len();

    if src_len == 0 {
        return tgt_len;
    }
    if tgt_len == 0 {
        return src_len;
    }

    let mut prev: Vec<usize> = (0..=tgt_len).collect();
    let mut curr: Vec<usize> = vec![0; tgt_len + 1];

    for si in 1..=src_len {
        curr[0] = si;
        for ti in 1..=tgt_len {
            let cost = if src_chars[si - 1] == tgt_chars[ti - 1] { 0 } else { 1 };
            curr[ti] = (prev[ti] + 1).min(curr[ti - 1] + 1).min(prev[ti - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }

    prev[tgt_len]
}

fn char_len(s: &str) -> usize {
    s.chars().count()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct OwnedEntry {
        id: String,
        name: String,
        manufacturer: String,
        category: Option<String>,
        aliases: Vec<String>,
    }

    impl OwnedEntry {
        fn new(id: &str, name: &str, mfg: &str, category: &str, aliases: &[&str]) -> Self {
            OwnedEntry {
                id: id.to_string(),
                name: name.to_string(),
                manufacturer: mfg.to_string(),
                category: Some(category.to_string()),
                aliases: aliases.iter().map(|s| s.to_string()).collect(),
            }
        }
        fn as_ref(&self) -> CatalogEntryRef<'_> {
            CatalogEntryRef {
                id: &self.id,
                name: &self.name,
                manufacturer: &self.manufacturer,
                category: self.category.as_deref(),
                aliases: &self.aliases,
            }
        }
    }

    fn corpus() -> Vec<OwnedEntry> {
        vec![
            OwnedEntry::new("elecraft-kx2", "KX2", "Elecraft", "radio", &[]),
            OwnedEntry::new("elecraft-k3", "K3", "Elecraft", "radio", &[]),
            OwnedEntry::new("elecraft-kx3", "KX3", "Elecraft", "radio", &[]),
            OwnedEntry::new(
                "mountain-topper-mtr4b",
                "MTR-4B",
                "Mountain Topper",
                "radio",
                &["mtr4b", "mtr 4b"],
            ),
            OwnedEntry::new("efhw-40-10", "EFHW 40-10", "Generic", "antenna", &[]),
        ]
    }

    fn refs(owned: &[OwnedEntry]) -> Vec<CatalogEntryRef<'_>> {
        owned.iter().map(OwnedEntry::as_ref).collect()
    }

    #[test]
    fn normalize_strips_separators_and_case() {
        assert_eq!(normalize("  MTR-4B "), "mtr4b");
        assert_eq!(normalize("Elecraft KX_2"), "elecraftkx2");
        assert_eq!(normalize("\tK3\n"), "k3");
    }

    #[test]
    fn blank_query_returns_empty() {
        let owned = corpus();
        assert!(search("", &refs(&owned), None, 5).is_empty());
        assert!(search("   ", &refs(&owned), None, 5).is_empty());
    }

    #[test]
    fn exact_name_scores_1_0() {
        let owned = corpus();
        let results = search("kx2", &refs(&owned), None, 5);
        assert_eq!(results[0].confidence, 1.0);
        assert_eq!(results[0].index, 0);
    }

    #[test]
    fn alias_matches_mountain_topper() {
        let owned = corpus();
        let results = search("mtr4b", &refs(&owned), None, 5);
        assert!(!results.is_empty());
        // The MTR-4B entry (index 3) should win at full confidence via alias.
        assert_eq!(results[0].index, 3);
        assert_eq!(results[0].confidence, 1.0);
    }

    #[test]
    fn word_level_prefers_exact_model() {
        let owned = corpus();
        let k3 = search("elecraft k3", &refs(&owned), None, 5);
        assert_eq!(k3[0].index, 1); // Elecraft K3, not KX3
    }

    #[test]
    fn substring_length_penalty() {
        // "k3" contained in "k3s" (ratio 2/3) scores higher than in a longer target.
        let short = string_score("k3", "k3s");
        let long = string_score("k3", "k3super");
        assert!(short > long);
    }

    #[test]
    fn threshold_excludes_below_0_3() {
        let owned = corpus();
        // A query unrelated to any entry should be filtered out.
        let results = search("zzzzzzzz", &refs(&owned), None, 5);
        assert!(results.iter().all(|m| m.confidence > 0.3));
    }

    #[test]
    fn best_match_respects_threshold() {
        let owned = corpus();
        assert!(best_match("kx2", &refs(&owned), None, 0.6).is_some());
        assert!(best_match("zzzzzzzz", &refs(&owned), None, 0.6).is_none());
    }

    #[test]
    fn category_filter_narrows_results() {
        let owned = corpus();
        let radios = search("efhw", &refs(&owned), Some("radio"), 5);
        assert!(radios.is_empty()); // EFHW is an antenna
        let antennas = search("efhw", &refs(&owned), Some("antenna"), 5);
        assert_eq!(antennas[0].index, 4);
    }

    #[test]
    fn edit_distance_known_vectors() {
        assert_eq!(edit_distance("kitten", "sitting"), 3);
        assert_eq!(edit_distance("", "abc"), 3);
        assert_eq!(edit_distance("abc", ""), 3);
        assert_eq!(edit_distance("kx2", "kx2"), 0);
    }

    #[test]
    fn tie_break_is_index_ascending() {
        // Two entries with identical scoring content → lower index wins.
        let owned = vec![
            OwnedEntry::new("dup-a", "WIDGET", "Acme", "accessory", &[]),
            OwnedEntry::new("dup-b", "WIDGET", "Acme", "accessory", &[]),
        ];
        let results = search("widget", &refs(&owned), None, 5);
        assert_eq!(results[0].index, 0);
        assert_eq!(results[1].index, 1);
    }
}
