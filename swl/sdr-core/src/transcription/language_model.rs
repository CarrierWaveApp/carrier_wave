//! Character bigram language model for CW decoding.
//!
//! Provides transition log-probabilities between characters based on
//! amateur radio QSO patterns. Used by the HSMM decoder to bias decoding
//! toward likely character sequences.
//!
//! The model covers 38 symbols: A-Z (0-25), 0-9 (26-35), space (36),
//! and a special "start/end" token (37).

/// Number of symbols in the bigram model.
const NUM_SYMBOLS: usize = 38;

/// Map a character to its symbol index (0-37).
/// Returns None for unmapped characters.
fn char_to_idx(ch: char) -> Option<usize> {
    match ch {
        'A'..='Z' => Some(ch as usize - 'A' as usize),
        'a'..='z' => Some(ch as usize - 'a' as usize),
        '0'..='9' => Some(26 + (ch as usize - '0' as usize)),
        ' ' => Some(36),
        _ => None,
    }
}

/// Map a symbol index back to a character.
#[cfg(test)]
fn idx_to_char(idx: usize) -> Option<char> {
    match idx {
        0..=25 => Some((b'A' + idx as u8) as char),
        26..=35 => Some((b'0' + (idx - 26) as u8) as char),
        36 => Some(' '),
        _ => None,
    }
}

/// Start/end-of-sequence symbol index.
const START_END_IDX: usize = 37;

/// Character bigram language model for amateur radio CW.
///
/// Built-in model derived from common amateur radio patterns:
/// - CQ calls: "CQ CQ CQ DE {callsign}"
/// - QSO exchanges: RST, QTH, name, 73, SK
/// - Q-codes: QRZ, QSL, QSO, QTH, QRM, QRN, QRS, QRT, QSB, QSY
/// - Common words: DE, ES, FB, UR, TU, TNX, TKS, HW, OM, 73, 88
/// - Callsign patterns: 1-2 alpha + digit + 1-3 alpha
///
/// The model is a smoothed bigram with Laplace smoothing (add-alpha).
pub struct BigramModel {
    /// Log-probabilities: `log_probs[prev][next]` = log P(next | prev).
    log_probs: [[f64; NUM_SYMBOLS]; NUM_SYMBOLS],
}

impl Default for BigramModel {
    fn default() -> Self {
        Self::new()
    }
}

impl BigramModel {
    /// Build the bigram model from built-in amateur radio QSO patterns.
    pub fn new() -> Self {
        let mut counts = [[0u32; NUM_SYMBOLS]; NUM_SYMBOLS];

        // Training corpus: common amateur radio CW phrases.
        // Each phrase is weighted to reflect frequency of occurrence.
        let corpus: &[(&str, u32)] = &[
            // CQ calls (very common)
            ("CQ CQ CQ DE", 50),
            ("CQ CQ DE", 30),
            ("CQ POTA DE", 20),
            ("CQ SOTA DE", 10),
            ("CQ DX DE", 10),
            ("CQ TEST DE", 10),
            // QSO exchanges
            ("DE", 40),
            ("RST 599", 30),
            ("RST 5NN", 20),
            ("UR RST", 20),
            ("QTH", 15),
            ("NAME", 10),
            ("OP", 10),
            ("RIG", 8),
            ("ANT", 8),
            ("WX", 5),
            // Closers
            ("73", 40),
            ("TU 73", 20),
            ("TNX QSO 73", 10),
            ("TKS FER QSO 73", 8),
            ("FB 73", 10),
            ("VY 73", 5),
            ("88", 3),
            ("SK", 15),
            ("CL", 5),
            // Q-codes
            ("QRZ", 15),
            ("QSL", 10),
            ("QSO", 10),
            ("QSY", 5),
            ("QTH", 10),
            ("QRM", 5),
            ("QRN", 5),
            ("QRS", 5),
            ("QRT", 3),
            ("QRP", 5),
            ("QSB", 3),
            // Common words
            ("ES", 15),
            ("FB", 10),
            ("UR", 10),
            ("TU", 15),
            ("HW", 8),
            ("OM", 8),
            ("HR", 5),
            ("NR", 5),
            ("AGN", 5),
            ("PSE", 5),
            ("SRI", 3),
            ("BK", 8),
            ("AR", 8),
            ("KN", 5),
            ("R R", 10),
            ("K", 20),
            // Callsign-like patterns (character transitions common in callsigns)
            ("W1AW", 5),
            ("K1ABC", 5),
            ("N7XY", 5),
            ("WA9AGG", 5),
            ("KD2RRR", 3),
            ("VE3ABC", 3),
            // Number sequences (RST, signal reports)
            ("599 599", 10),
            ("5NN 5NN", 8),
            ("559", 5),
            ("579", 5),
            ("589", 3),
        ];

        // Count bigrams from corpus
        for &(phrase, weight) in corpus {
            let chars: Vec<usize> = std::iter::once(START_END_IDX)
                .chain(phrase.chars().filter_map(char_to_idx))
                .chain(std::iter::once(START_END_IDX))
                .collect();

            for window in chars.windows(2) {
                counts[window[0]][window[1]] += weight;
            }
        }

        // Laplace smoothing + normalization to log-probabilities
        let alpha = 0.1; // smoothing parameter
        let mut log_probs = [[0.0f64; NUM_SYMBOLS]; NUM_SYMBOLS];

        for prev in 0..NUM_SYMBOLS {
            let row_sum: f64 = counts[prev].iter().map(|&c| c as f64 + alpha).sum::<f64>();
            for next in 0..NUM_SYMBOLS {
                let prob = (counts[prev][next] as f64 + alpha) / row_sum;
                log_probs[prev][next] = prob.ln();
            }
        }

        Self { log_probs }
    }

    /// Get log P(next_char | prev_char).
    ///
    /// Returns a log-probability. Higher (less negative) = more likely.
    /// For unmapped characters, returns a uniform low probability.
    pub fn score(&self, prev_char: char, next_char: char) -> f64 {
        let prev_idx = char_to_idx(prev_char).unwrap_or(START_END_IDX);
        let next_idx = match char_to_idx(next_char) {
            Some(idx) => idx,
            None => return -6.0, // very unlikely for unknown chars
        };
        self.log_probs[prev_idx][next_idx]
    }

    /// Score a start-of-sequence → first character transition.
    pub fn score_start(&self, first_char: char) -> f64 {
        let next_idx = match char_to_idx(first_char) {
            Some(idx) => idx,
            None => return -6.0,
        };
        self.log_probs[START_END_IDX][next_idx]
    }

    /// Score a full word by summing bigram log-probabilities.
    ///
    /// Returns the sum of log P(c_i | c_{i-1}) for all character pairs,
    /// including start → first and last → end transitions.
    pub fn score_word(&self, word: &str) -> f64 {
        if word.is_empty() {
            return 0.0;
        }

        let chars: Vec<char> = word.chars().collect();
        let mut score = self.score_start(chars[0]);

        for window in chars.windows(2) {
            score += self.score(window[0], window[1]);
        }

        // End transition
        let last_idx = char_to_idx(*chars.last().unwrap()).unwrap_or(START_END_IDX);
        score += self.log_probs[last_idx][START_END_IDX];

        score
    }

    /// Score a sequence of words (full transcript).
    pub fn score_sequence(&self, text: &str) -> f64 {
        if text.is_empty() {
            return 0.0;
        }

        let chars: Vec<usize> = std::iter::once(START_END_IDX)
            .chain(text.chars().filter_map(char_to_idx))
            .chain(std::iter::once(START_END_IDX))
            .collect();

        let mut score = 0.0;
        for window in chars.windows(2) {
            score += self.log_probs[window[0]][window[1]];
        }
        score
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cq_more_likely_than_xq() {
        let model = BigramModel::new();
        let p_cq = model.score_word("CQ");
        let p_xq = model.score_word("XQ");
        assert!(
            p_cq > p_xq,
            "P(CQ) = {p_cq:.3} should be > P(XQ) = {p_xq:.3}"
        );
    }

    #[test]
    fn de_more_likely_than_dx_after_cq() {
        let model = BigramModel::new();
        // After "Q", "D" (start of DE) should be fairly likely
        let _p_qd = model.score('Q', 'D');
        // After "Q", "X" is less common
        let _p_qx = model.score('Q', 'X');
        // Q→space→D (as in "CQ DE") vs Q→space→X
        let p_space_d = model.score(' ', 'D');
        let p_space_x = model.score(' ', 'X');
        assert!(
            p_space_d > p_space_x,
            "P(D|space) = {p_space_d:.3} should be > P(X|space) = {p_space_x:.3}"
        );
    }

    #[test]
    fn common_phrases_score_higher() {
        let model = BigramModel::new();
        let p_cq_de = model.score_sequence("CQ DE");
        let p_zz_xx = model.score_sequence("ZZ XX");
        assert!(
            p_cq_de > p_zz_xx,
            "P('CQ DE') = {p_cq_de:.3} should be > P('ZZ XX') = {p_zz_xx:.3}"
        );
    }

    #[test]
    fn seventy_three_likely() {
        let model = BigramModel::new();
        let p_73 = model.score_word("73");
        let p_42 = model.score_word("42");
        assert!(
            p_73 > p_42,
            "P(73) = {p_73:.3} should be > P(42) = {p_42:.3}"
        );
    }

    #[test]
    fn q_codes_score_well() {
        let model = BigramModel::new();
        let p_qrz = model.score_word("QRZ");
        let p_qzr = model.score_word("QZR");
        assert!(
            p_qrz > p_qzr,
            "P(QRZ) = {p_qrz:.3} should be > P(QZR) = {p_qzr:.3}"
        );
    }

    #[test]
    fn start_of_sequence_favors_common_starters() {
        let model = BigramModel::new();
        let p_start_c = model.score_start('C'); // CQ
        let p_start_x = model.score_start('X');
        assert!(
            p_start_c > p_start_x,
            "P(C|start) = {p_start_c:.3} should be > P(X|start) = {p_start_x:.3}"
        );
    }

    #[test]
    fn empty_word_scores_zero() {
        let model = BigramModel::new();
        assert_eq!(model.score_word(""), 0.0);
    }

    #[test]
    fn char_to_idx_roundtrip() {
        for ch in 'A'..='Z' {
            let idx = char_to_idx(ch).unwrap();
            assert_eq!(idx_to_char(idx), Some(ch));
        }
        for ch in '0'..='9' {
            let idx = char_to_idx(ch).unwrap();
            assert_eq!(idx_to_char(idx), Some(ch));
        }
        assert_eq!(char_to_idx(' '), Some(36));
        assert_eq!(idx_to_char(36), Some(' '));
    }

    #[test]
    fn all_log_probs_are_negative() {
        let model = BigramModel::new();
        for prev in 0..NUM_SYMBOLS {
            for next in 0..NUM_SYMBOLS {
                assert!(
                    model.log_probs[prev][next] < 0.0,
                    "log_probs[{prev}][{next}] = {} should be negative",
                    model.log_probs[prev][next]
                );
            }
        }
    }
}
