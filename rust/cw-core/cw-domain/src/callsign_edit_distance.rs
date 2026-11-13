//! Levenshtein edit distance over uppercased strings, with a near-match
//! helper for spotting callsign typos. Port of `CallsignEditDistance.swift`.

/// Levenshtein distance (case-insensitive).
pub fn distance(s1: &str, s2: &str) -> usize {
    let a: Vec<char> = s1.to_uppercase().chars().collect();
    let b: Vec<char> = s2.to_uppercase().chars().collect();
    let m = a.len();
    let n = b.len();
    if m == 0 {
        return n;
    }
    if n == 0 {
        return m;
    }
    let mut prev: Vec<usize> = (0..=n).collect();
    let mut curr: Vec<usize> = vec![0; n + 1];
    for i in 1..=m {
        curr[0] = i;
        for j in 1..=n {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            curr[j] = (prev[j] + 1).min(curr[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    prev[n]
}

/// Candidates within `max_distance` (exclusive of exact matches), sorted by
/// distance ascending. Returns `(uppercased_candidate, distance)`.
pub fn find_near_matches<'a, I>(callsign: &str, max_distance: usize, candidates: I) -> Vec<(String, usize)>
where
    I: IntoIterator<Item = &'a str>,
{
    let upper = callsign.to_uppercase();
    let upper_len = upper.chars().count();
    let mut results: Vec<(String, usize)> = Vec::new();
    for candidate in candidates {
        let cand_upper = candidate.to_uppercase();
        if cand_upper == upper {
            continue;
        }
        let cand_len = cand_upper.chars().count();
        if cand_len.abs_diff(upper_len) > max_distance {
            continue;
        }
        let dist = distance(&upper, &cand_upper);
        if dist > 0 && dist <= max_distance {
            results.push((cand_upper, dist));
        }
    }
    results.sort_by_key(|&(_, d)| d);
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distance_basics() {
        assert_eq!(distance("", ""), 0);
        assert_eq!(distance("W1AW", "W1AW"), 0);
        assert_eq!(distance("W1AW", "w1aw"), 0); // case-insensitive
        assert_eq!(distance("W1AW", ""), 4);
        assert_eq!(distance("", "K1JT"), 4);
    }

    #[test]
    fn distance_single_edit() {
        assert_eq!(distance("W1AW", "W1AX"), 1); // substitution
        assert_eq!(distance("W1AW", "W1A"), 1);  // deletion
        assert_eq!(distance("W1AW", "W1AWX"), 1); // insertion
    }

    #[test]
    fn distance_multiple_edits() {
        assert_eq!(distance("ABCDE", "AECDB"), 2); // 2 substitutions
        assert_eq!(distance("K6JSV", "W6JSV"), 1);
    }

    #[test]
    fn near_matches_filter_and_sort() {
        let candidates = ["W1AW", "K1JT", "W1AX", "W1ZZ", "W1AWX", "W6JSV"];
        let near = find_near_matches("W1AW", 1, candidates.iter().copied());
        // Expect W1AX (sub, d=1), W1AWX (ins, d=1) — excludes exact match and far
        let names: Vec<&str> = near.iter().map(|(s, _)| s.as_str()).collect();
        assert!(names.contains(&"W1AX"));
        assert!(names.contains(&"W1AWX"));
        assert!(!names.contains(&"W1AW"));   // exact excluded
        assert!(!names.contains(&"W6JSV"));  // too far
        // All distances ≤ 1.
        assert!(near.iter().all(|(_, d)| *d <= 1));
        // Sorted ascending.
        assert!(near.windows(2).all(|w| w[0].1 <= w[1].1));
    }

    #[test]
    fn near_matches_length_skip() {
        let near = find_near_matches("W1AW", 1, ["W1AWXY"].iter().copied());
        assert!(near.is_empty()); // length differs by 2 > 1
    }
}
