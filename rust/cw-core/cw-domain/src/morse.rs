//! Morse code tables + edit distance over morse patterns.
//! Ports `MorseCode.swift` and `MorseEditDistance.swift`.

use std::collections::HashMap;
use std::sync::OnceLock;

/// Morse timing constants. PARIS standard: one unit = 1.2 / WPM seconds.
pub struct MorseTiming;

impl MorseTiming {
    pub const DIT_UNITS: f64 = 1.0;
    pub const DAH_UNITS: f64 = 3.0;
    pub const ELEMENT_GAP_UNITS: f64 = 1.0;
    pub const CHAR_GAP_UNITS: f64 = 3.0;
    pub const WORD_GAP_UNITS: f64 = 7.0;

    pub fn unit_duration_for_wpm(wpm: i32) -> f64 {
        1.2 / wpm as f64
    }

    pub fn wpm_from_unit_duration(duration: f64) -> i32 {
        if duration <= 0.0 {
            return 20;
        }
        (1.2 / duration).clamp(5.0, 60.0) as i32
    }
}

/// Standard International Morse Code (letters, numbers, punctuation, prosigns).
/// Pattern → character. Prosigns are surfaced as `<XX>` strings, matching Swift.
fn morse_table() -> &'static HashMap<&'static str, &'static str> {
    static TABLE: OnceLock<HashMap<&'static str, &'static str>> = OnceLock::new();
    TABLE.get_or_init(|| {
        [
            (".-", "A"), ("-...", "B"), ("-.-.", "C"), ("-..", "D"), (".", "E"),
            ("..-.", "F"), ("--.", "G"), ("....", "H"), ("..", "I"), (".---", "J"),
            ("-.-", "K"), (".-..", "L"), ("--", "M"), ("-.", "N"), ("---", "O"),
            (".--.", "P"), ("--.-", "Q"), (".-.", "R"), ("...", "S"), ("-", "T"),
            ("..-", "U"), ("...-", "V"), (".--", "W"), ("-..-", "X"), ("-.--", "Y"),
            ("--..", "Z"),
            (".----", "1"), ("..---", "2"), ("...--", "3"), ("....-", "4"), (".....", "5"),
            ("-....", "6"), ("--...", "7"), ("---..", "8"), ("----.", "9"), ("-----", "0"),
            (".-.-.-", "."), ("--..--", ","), ("..--..", "?"), (".----.", "'"),
            ("-.-.--", "!"), ("-..-.", "/"), ("-.--.", "("), ("-.--.-", ")"),
            (".-...", "&"), ("---...", ":"), ("-.-.-.", ";"), ("-...-", "="),
            (".-.-.", "+"), ("-....-", "-"), ("..--.-", "_"), (".-..-.", "\""),
            ("...-..-", "$"), (".--.-.", "@"),
            ("-.-.-", "<CT>"), (".-.-", "<AA>"), ("...-.", "<SN>"), ("........", "<HH>"),
        ]
        .into_iter()
        .collect()
    })
}

/// Character → Morse pattern. Skips prosigns.
fn char_table() -> &'static HashMap<char, &'static str> {
    static TABLE: OnceLock<HashMap<char, &'static str>> = OnceLock::new();
    TABLE.get_or_init(|| {
        morse_table()
            .iter()
            .filter(|(_, ch)| !ch.starts_with('<'))
            .filter_map(|(pat, ch)| {
                let single = ch.chars().next()?;
                Some((single, *pat))
            })
            .collect()
    })
}

/// Decode a single Morse pattern to its character (or prosign like `<CT>`).
pub fn decode_pattern(pattern: &str) -> Option<&'static str> {
    morse_table().get(pattern).copied()
}

/// Encode a single character as Morse. Uppercases the input.
pub fn encode_char(ch: char) -> Option<&'static str> {
    char_table().get(&ch.to_ascii_uppercase()).copied()
}

/// Convert a word to its Morse pattern (concatenated, no inter-character gaps).
/// Returns `None` if any character can't be encoded.
pub fn word_to_morse(word: &str) -> Option<String> {
    let mut out = String::new();
    for ch in word.chars() {
        out.push_str(encode_char(ch)?);
    }
    Some(out)
}

/// Levenshtein distance between two Morse patterns (each dit/dah is one symbol).
pub fn pattern_distance(p1: &str, p2: &str) -> usize {
    let a: Vec<char> = p1.chars().collect();
    let b: Vec<char> = p2.chars().collect();
    let m = a.len();
    let n = b.len();
    if m == 0 {
        return n;
    }
    if n == 0 {
        return m;
    }
    let mut dp = vec![vec![0usize; n + 1]; m + 1];
    for (i, row) in dp.iter_mut().enumerate() {
        row[0] = i;
    }
    for (j, cell) in dp[0].iter_mut().enumerate() {
        *cell = j;
    }
    for i in 1..=m {
        for j in 1..=n {
            if a[i - 1] == b[j - 1] {
                dp[i][j] = dp[i - 1][j - 1];
            } else {
                dp[i][j] = 1 + dp[i - 1][j].min(dp[i][j - 1]).min(dp[i - 1][j - 1]);
            }
        }
    }
    dp[m][n]
}

/// Edit distance between two words via their Morse representations.
/// `None` if either word can't be encoded (mirrors Swift's `Int.max` sentinel
/// but in a more idiomatic Rust shape).
pub fn word_distance(w1: &str, w2: &str) -> Option<usize> {
    let m1 = word_to_morse(w1)?;
    let m2 = word_to_morse(w2)?;
    Some(pattern_distance(&m1, &m2))
}

/// All candidates within `max_distance` Morse symbols of `word`. Skips exact
/// matches and unencodable candidates. Returns `(candidate, distance)` sorted
/// ascending. Candidates are uppercased on input by the caller in Swift; we
/// uppercase the target here to mirror the comparison semantics.
pub fn find_similar<'a, I>(word: &str, max_distance: usize, candidates: I) -> Vec<(String, usize)>
where
    I: IntoIterator<Item = &'a str>,
{
    let upper = word.to_uppercase();
    let cand_vec: Vec<String> = candidates.into_iter().map(str::to_string).collect();
    if cand_vec.iter().any(|c| c == &upper) {
        return Vec::new();
    }
    let mut results: Vec<(String, usize)> = Vec::new();
    for c in cand_vec {
        if let Some(d) = word_distance(&upper, &c) {
            if d > 0 && d <= max_distance {
                results.push((c, d));
            }
        }
    }
    results.sort_by_key(|&(_, d)| d);
    results
}

/// Best (lowest-distance) match within `max_distance`, or `None`.
pub fn find_best_match<'a, I>(word: &str, max_distance: usize, candidates: I) -> Option<String>
where
    I: IntoIterator<Item = &'a str>,
{
    find_similar(word, max_distance, candidates).into_iter().next().map(|(c, _)| c)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip_letters_and_digits() {
        for ch in ['A', 'E', 'Z', '0', '5', '9'] {
            let pat = encode_char(ch).unwrap();
            let decoded = decode_pattern(pat).unwrap();
            assert_eq!(decoded, ch.to_string(), "round-trip failed for {ch}");
        }
        // Spot-check known patterns
        assert_eq!(encode_char('E'), Some("."));
        assert_eq!(encode_char('T'), Some("-"));
        assert_eq!(decode_pattern("...."), Some("H"));
        assert_eq!(decode_pattern("---"), Some("O"));
    }

    #[test]
    fn prosigns_decode_but_dont_encode() {
        assert_eq!(decode_pattern("-.-.-"), Some("<CT>"));
        // Prosigns aren't in char_table.
        assert!(char_table().values().all(|p| *p != "-.-.-"));
    }

    #[test]
    fn word_to_morse_concatenates_no_gaps() {
        assert_eq!(word_to_morse("CQ"), Some("-.-.--.-".to_string()));
        assert_eq!(word_to_morse("E"), Some(".".to_string()));
        // Non-encodable char → None
        assert_eq!(word_to_morse("CQ?"), Some(format!("{}{}{}",  "-.-.", "--.-", "..--..")));
        assert!(word_to_morse("CQ\u{0}").is_none());
    }

    #[test]
    fn pattern_distance_basic() {
        assert_eq!(pattern_distance("", ""), 0);
        assert_eq!(pattern_distance(".", ""), 1);
        assert_eq!(pattern_distance("", ".-"), 2);
        assert_eq!(pattern_distance(".-", ".-"), 0);
        assert_eq!(pattern_distance(".-", "-."), 2);
    }

    #[test]
    fn word_distance_uses_morse_concat() {
        // CQ vs CZ: -.-.--.-  vs  -.-.--..  → last symbol differs (- vs .)
        assert_eq!(word_distance("CQ", "CZ"), Some(1));
        // Unencodable
        assert_eq!(word_distance("CQ\u{0}", "CQ"), None);
    }

    #[test]
    fn find_similar_sorts_and_filters() {
        let cands = ["CZ", "CK", "DR", "73"];
        let near = find_similar("CQ", 3, cands.iter().copied());
        assert!(!near.is_empty());
        // All distances within cap.
        assert!(near.iter().all(|(_, d)| *d <= 3));
        // Sorted ascending.
        assert!(near.windows(2).all(|w| w[0].1 <= w[1].1));
    }

    #[test]
    fn find_similar_exact_match_returns_empty() {
        let cands = ["CQ", "CZ"];
        let near = find_similar("CQ", 3, cands.iter().copied());
        assert!(near.is_empty());
    }

    #[test]
    fn timing_wpm_round_trip() {
        let u = MorseTiming::unit_duration_for_wpm(20);
        assert_eq!(MorseTiming::wpm_from_unit_duration(u), 20);
        // Clamp range
        assert_eq!(MorseTiming::wpm_from_unit_duration(0.0), 20);
        assert_eq!(MorseTiming::wpm_from_unit_duration(1.0), 5);   // very slow
        assert_eq!(MorseTiming::wpm_from_unit_duration(0.001), 60); // very fast
    }
}
