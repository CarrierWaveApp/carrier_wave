//! Bayesian beam search CW decoder.
//!
//! Maintains K competing hypotheses, scoring each observation (mark/space duration)
//! against Gaussian timing models. Defers dit/dah and gap classification decisions
//! until evidence accumulates, rather than making irrevocable hard decisions.
//!
//! Based on the HamFist algorithm by Jonathan Dawson (MIT License).

use super::morse;
use super::tone_detector::{KeyingEvent, KeyingEventKind};

// ---------------------------------------------------------------------------
// Morse trie for O(1) prefix / complete-character validation
// ---------------------------------------------------------------------------

/// Compact Morse binary trie stored as a flat array.
///
/// Each node at index `i` has:
/// - children: dit → `2*i + 1`, dah → `2*i + 2`
/// - character: `nodes[i]` is `Some(ch)` if this node represents a complete character
///
/// Max Morse code length is 7 elements → tree depth 7 → 255 nodes max.
pub struct MorseTrie {
    /// `nodes[i] = Some(ch)` if the path from root to `i` is a valid Morse code.
    nodes: Vec<Option<char>>,
    /// `valid[i] = true` if node `i` or any descendant has a character.
    valid: Vec<bool>,
}

impl Default for MorseTrie {
    fn default() -> Self {
        Self::new()
    }
}

impl MorseTrie {
    /// Build the trie from all known Morse patterns.
    pub fn new() -> Self {
        let size = 255; // 2^8 - 1
        let mut nodes = vec![None; size];
        let mut valid = vec![false; size];

        for (pattern, ch) in morse::all_patterns() {
            let mut idx = 0usize;
            for b in pattern.bytes() {
                idx = match b {
                    b'.' => 2 * idx + 1,
                    b'-' => 2 * idx + 2,
                    _ => break,
                };
                if idx >= size {
                    break;
                }
            }
            if idx < size {
                nodes[idx] = Some(ch);
            }
        }

        // Mark valid: node or any descendant has a character
        // Work bottom-up
        for i in (0..size).rev() {
            if nodes[i].is_some() {
                valid[i] = true;
            }
            let left = 2 * i + 1;
            let right = 2 * i + 2;
            if left < size && valid[left] {
                valid[i] = true;
            }
            if right < size && valid[right] {
                valid[i] = true;
            }
        }

        Self { nodes, valid }
    }

    /// Navigate from root following the given pattern, returning the node index.
    fn navigate(&self, pattern: &str) -> Option<usize> {
        let mut idx = 0usize;
        for b in pattern.bytes() {
            idx = match b {
                b'.' => 2 * idx + 1,
                b'-' => 2 * idx + 2,
                _ => return None,
            };
            if idx >= self.nodes.len() {
                return None;
            }
        }
        Some(idx)
    }

    /// Returns true if `pattern` is a prefix of (or equal to) any valid Morse code.
    pub fn is_prefix(&self, pattern: &str) -> bool {
        if pattern.is_empty() {
            return true; // empty is prefix of everything
        }
        self.navigate(pattern)
            .map(|idx| self.valid[idx])
            .unwrap_or(false)
    }

    /// Returns true if `pattern` is a complete, valid Morse code.
    pub fn is_complete(&self, pattern: &str) -> bool {
        if pattern.is_empty() {
            return false;
        }
        self.navigate(pattern)
            .and_then(|idx| self.nodes[idx])
            .is_some()
    }

    /// Decode a complete pattern to a character.
    pub fn decode(&self, pattern: &str) -> Option<char> {
        if pattern.is_empty() {
            return None;
        }
        self.navigate(pattern).and_then(|idx| self.nodes[idx])
    }
}

// ---------------------------------------------------------------------------
// Timing model
// ---------------------------------------------------------------------------

/// Gaussian parameters for a duration class.
#[derive(Debug, Clone, Copy)]
struct GaussParam {
    mean: f64,
    sigma: f64,
}

impl GaussParam {
    fn new(mean: f64, sigma: f64) -> Self {
        Self {
            mean,
            sigma: sigma.max(1.0), // prevent division by zero
        }
    }

    /// Log-likelihood of observing duration `x` under this Gaussian.
    /// Normalization constant omitted (same as HamFist).
    fn log_prob(&self, x: f64) -> f64 {
        -0.5 * ((x - self.mean) / self.sigma).powi(2)
    }
}

/// Timing model with Gaussian distributions for all duration classes.
#[derive(Debug, Clone)]
struct TimingModel {
    dit: GaussParam,
    dah: GaussParam,
    gap1: GaussParam, // intra-character (element gap)
    gap3: GaussParam, // inter-character (letter gap)
    gap7: GaussParam, // word gap
}

impl TimingModel {
    /// Build from pre-estimated parameters.
    ///
    /// `dit_ms`: estimated dit duration in milliseconds
    /// `char_gap_ms`: estimated character gap in milliseconds
    /// `word_gap_ms`: estimated word gap in milliseconds
    fn from_estimates(dit_ms: f64, char_gap_ms: f64, word_gap_ms: f64) -> Self {
        let dit_sigma = dit_ms * 0.25;
        let dah_mean = dit_ms * 3.0;
        let dah_sigma = dah_mean * 0.20;
        let gap1_mean = dit_ms;
        let gap1_sigma = dit_ms * 0.30;
        let gap3_sigma = char_gap_ms * 0.25;
        let gap7_sigma = word_gap_ms * 0.25;

        Self {
            dit: GaussParam::new(dit_ms, dit_sigma),
            dah: GaussParam::new(dah_mean, dah_sigma),
            gap1: GaussParam::new(gap1_mean, gap1_sigma),
            gap3: GaussParam::new(char_gap_ms, gap3_sigma),
            gap7: GaussParam::new(word_gap_ms, gap7_sigma),
        }
    }

    /// Score a mark (on-duration) as dit.
    fn score_dit(&self, d: f64) -> f64 {
        self.dit.log_prob(d)
    }

    /// Score a mark as dah.
    fn score_dah(&self, d: f64) -> f64 {
        self.dah.log_prob(d)
    }

    /// Score a mark as two merged dits (missed intra-character gap).
    fn score_dit_dit(&self, d: f64) -> f64 {
        let merged_mean = self.dit.mean * 2.0 + self.gap1.mean;
        GaussParam::new(merged_mean, self.dah.sigma).log_prob(d) - 2.0 // penalty
    }

    /// Score a mark as merged dit+dah.
    fn score_dit_dah(&self, d: f64) -> f64 {
        let merged_mean = self.dit.mean + self.dah.mean + self.gap1.mean;
        GaussParam::new(merged_mean, self.dah.sigma).log_prob(d)
    }

    /// Score a mark as two merged dahs.
    fn score_dah_dah(&self, d: f64) -> f64 {
        let merged_mean = self.dah.mean * 2.0 + self.gap1.mean;
        GaussParam::new(merged_mean, self.dah.sigma).log_prob(d)
    }

    /// Score a space as intra-character gap.
    fn score_gap1(&self, g: f64) -> f64 {
        self.gap1.log_prob(g)
    }

    /// Score a space as inter-character gap.
    fn score_gap3(&self, g: f64) -> f64 {
        self.gap3.log_prob(g)
    }

    /// Score a space as word gap (one-sided: anything >= mean scores 0).
    fn score_gap7(&self, g: f64) -> f64 {
        if g >= self.gap7.mean {
            0.0 // certain word boundary
        } else {
            self.gap7.log_prob(g)
        }
    }
}

// ---------------------------------------------------------------------------
// Hypothesis
// ---------------------------------------------------------------------------

/// A word with its timing span in the audio.
#[derive(Debug, Clone)]
pub struct WordSpan {
    pub text: String,
    pub start_sample: usize,
    pub end_sample: usize,
}

/// A single hypothesis in the beam search.
#[derive(Debug, Clone)]
struct Hypothesis {
    /// Committed text (characters where all beam hypotheses agreed).
    text: String,
    /// Current word being assembled (characters since last word gap).
    word: String,
    /// Partial Morse pattern in progress (e.g. ".-").
    pattern: String,
    /// Cumulative log probability.
    log_prob: f64,
    /// Completed words with their sample timing.
    committed_spans: Vec<WordSpan>,
    /// Sample offset of the first On event for the current word.
    word_start_sample: Option<usize>,
}

impl Hypothesis {
    fn new() -> Self {
        Self {
            text: String::new(),
            word: String::new(),
            pattern: String::new(),
            log_prob: 0.0,
            committed_spans: Vec::new(),
            word_start_sample: None,
        }
    }
}

// ---------------------------------------------------------------------------
// Vocabulary for language model bonuses
// ---------------------------------------------------------------------------

/// Known CW vocabulary words (subset for beam scoring).
///
/// NOTE: US state abbreviations were removed because they destroy callsign
/// decoding. Nearly every 2-letter fragment matches a state code, causing
/// the beam search to split callsigns (e.g., W6JSV → WA 6 NJ R VA) and
/// vocabulary words (e.g., POTA → PO AK). State codes are only useful in
/// contest exchanges with known exchange formats; for general CW and POTA
/// transcription they cause massive harm.
static BEAM_VOCAB: &[&str] = &[];

/// Check if `word` is a prefix of any vocabulary word.
fn is_vocab_prefix(word: &str) -> bool {
    if word.is_empty() {
        return true;
    }
    BEAM_VOCAB
        .iter()
        .any(|v| v.starts_with(word) && v.len() > word.len())
}

/// Check if `word` is an exact vocabulary match.
fn is_vocab_word(word: &str) -> bool {
    BEAM_VOCAB.binary_search(&word).is_ok() || is_callsign_pattern(word)
}

/// Check if `word` matches amateur callsign pattern.
pub fn is_callsign_pattern(word: &str) -> bool {
    let chars: Vec<char> = word.chars().collect();
    if chars.len() < 3 || chars.len() > 6 {
        return false;
    }
    if !chars.iter().all(|c| c.is_ascii_alphanumeric()) {
        return false;
    }
    let digit_positions: Vec<usize> = chars
        .iter()
        .enumerate()
        .filter(|(_, c)| c.is_ascii_digit())
        .map(|(i, _)| i)
        .collect();
    if digit_positions.len() != 1 {
        return false;
    }
    let dp = digit_positions[0];
    if dp == 0 || dp > 2 {
        return false;
    }
    if !chars[..dp].iter().all(|c| c.is_ascii_alphabetic()) {
        return false;
    }
    let suffix_len = chars.len() - dp - 1;
    if suffix_len == 0 || suffix_len > 3 {
        return false;
    }
    chars[dp + 1..].iter().all(|c| c.is_ascii_alphabetic())
}

/// Check if `word` looks like the beginning of an amateur callsign.
///
/// Only matches patterns that contain a digit (strong callsign signal):
/// - 1-2 alpha + 1 digit (e.g., "W1", "WA9", "N7")
/// - 1-2 alpha + 1 digit + 1-2 alpha (e.g., "W1A", "WA9AG", "N7UN")
///
/// Pure-letter patterns like "WA", "DE" are NOT matched because they're
/// indistinguishable from common CW vocabulary at that point.
fn is_callsign_prefix(word: &str) -> bool {
    let chars: Vec<char> = word.chars().collect();
    if chars.len() < 2 || chars.len() > 5 {
        return false;
    }
    if !chars.iter().all(|c| c.is_ascii_alphanumeric()) {
        return false;
    }

    // Must contain exactly one digit (strong callsign signal)
    let first_digit = chars.iter().position(|c| c.is_ascii_digit());
    match first_digit {
        None => false,    // no digit — too ambiguous
        Some(0) => false, // starts with digit — not a callsign prefix
        Some(dp) if dp <= 2 => {
            if !chars[..dp].iter().all(|c| c.is_ascii_alphabetic()) {
                return false;
            }
            let digit_count = chars.iter().filter(|c| c.is_ascii_digit()).count();
            if digit_count != 1 {
                return false;
            }
            let suffix = &chars[dp + 1..];
            suffix.len() <= 2 && suffix.iter().all(|c| c.is_ascii_alphabetic())
        }
        _ => false,
    }
}

// ---------------------------------------------------------------------------
// Beam search decoder
// ---------------------------------------------------------------------------

/// Beam width (number of hypotheses to maintain).
const BEAM_WIDTH: usize = 10;

/// Bonus added when a word-so-far is a prefix of a vocabulary word.
const PREFIX_BONUS: f64 = 1.0;

/// Bonus added when a completed word is a recognized vocabulary word.
const WORD_BONUS: f64 = 4.0;

/// Bonus for callsign-shaped completed words.
const CALLSIGN_BONUS: f64 = 6.0;

/// Bonus for word-in-progress that looks like a callsign prefix.
/// Safe to be high because the min_char_gap floor prevents this bonus
/// from applying at element gaps. At actual char gaps, must compete with
/// CALLSIGN_BONUS (6.0) to keep callsigns building rather than committing
/// partial callsigns prematurely.
const CALLSIGN_PREFIX_BONUS: f64 = 4.0;

/// Bayesian beam search CW decoder.
///
/// Processes keying events (On/Off with sample offsets) and maintains K
/// competing hypotheses scored by Gaussian log-likelihood against the
/// timing model.
pub struct BeamDecoder {
    beam: Vec<Hypothesis>,
    timing: TimingModel,
    trie: MorseTrie,
    sample_rate: u32,
    /// Sample offset of the last On event processed.
    last_on_offset: Option<usize>,
    /// Sample offset of the last Off event processed.
    last_off_offset: Option<usize>,
}

impl BeamDecoder {
    /// Create a new beam decoder from pre-estimated timing parameters.
    ///
    /// - `dit_ms`: estimated dit duration (milliseconds)
    /// - `char_gap_ms`: estimated character gap (milliseconds)
    /// - `word_gap_ms`: estimated word gap (milliseconds)
    /// - `sample_rate`: audio sample rate (Hz)
    pub fn new(dit_ms: f64, char_gap_ms: f64, word_gap_ms: f64, sample_rate: u32) -> Self {
        let timing = TimingModel::from_estimates(dit_ms, char_gap_ms, word_gap_ms);
        let mut beam = Vec::with_capacity(BEAM_WIDTH);
        beam.push(Hypothesis::new());

        Self {
            beam,
            timing,
            trie: MorseTrie::new(),
            sample_rate,
            last_on_offset: None,
            last_off_offset: None,
        }
    }

    /// Process a single keying event.
    pub fn process_event(&mut self, event: KeyingEvent) {
        match event.kind {
            KeyingEventKind::On => {
                // If we have a previous Off, compute space duration
                if let (Some(off_offset), Some(_on_offset)) =
                    (self.last_off_offset, self.last_on_offset)
                {
                    let gap_samples = event.sample_offset.saturating_sub(off_offset);
                    let gap_ms = gap_samples as f64 / self.sample_rate as f64 * 1000.0;
                    self.process_space(gap_ms);
                }
                self.last_on_offset = Some(event.sample_offset);

                // Mark word start for any hypothesis that doesn't have one yet
                for hyp in &mut self.beam {
                    if hyp.word_start_sample.is_none() {
                        hyp.word_start_sample = Some(event.sample_offset);
                    }
                }
            }
            KeyingEventKind::Off => {
                // Compute mark duration from last On
                if let Some(on_offset) = self.last_on_offset {
                    let mark_samples = event.sample_offset.saturating_sub(on_offset);
                    let mark_ms = mark_samples as f64 / self.sample_rate as f64 * 1000.0;
                    self.process_mark(mark_ms);
                }
                self.last_off_offset = Some(event.sample_offset);
            }
        }
    }

    /// Process a mark (key-down duration in ms).
    fn process_mark(&mut self, d: f64) {
        // Compute scores for each interpretation
        let score_dit = self.timing.score_dit(d);
        let score_dah = self.timing.score_dah(d);
        let score_dit_dit = self.timing.score_dit_dit(d);
        let score_dit_dah = self.timing.score_dit_dah(d);
        let score_dah_dah = self.timing.score_dah_dah(d);

        let mut candidates: Vec<Hypothesis> = Vec::with_capacity(self.beam.len() * 6);

        for hyp in &self.beam {
            // Each mark interpretation: (elements_to_append, score)
            let interpretations: &[(&str, f64)] = &[
                (".", score_dit),
                ("-", score_dah),
                ("..", score_dit_dit),
                (".-", score_dit_dah),
                ("-.", score_dit_dah), // same score as dit_dah
                ("--", score_dah_dah),
            ];

            for &(elements, score) in interpretations {
                let new_pattern = format!("{}{}", hyp.pattern, elements);

                if self.trie.is_prefix(&new_pattern) {
                    // Extended pattern is a valid prefix — continue building
                    let mut cand = hyp.clone();
                    cand.pattern = new_pattern;
                    cand.log_prob += score;
                    candidates.push(cand);
                } else if !hyp.pattern.is_empty() && self.trie.is_complete(&hyp.pattern) {
                    // Current pattern is complete but extension isn't valid —
                    // force-emit the character and start new pattern
                    if let Some(ch) = self.trie.decode(&hyp.pattern) {
                        // Check if new elements alone form a valid prefix
                        if self.trie.is_prefix(elements) {
                            let mut cand = hyp.clone();
                            cand.word.push(ch);
                            cand.pattern = elements.to_string();
                            cand.log_prob += score;
                            candidates.push(cand);
                        }
                    }
                }
                // else: neither prefix nor force-emit possible — skip
            }
        }

        if candidates.is_empty() {
            // No valid candidates — keep beam unchanged (shouldn't happen in practice)
            return;
        }

        self.prune(candidates);
    }

    /// Process a space (key-up duration in ms).
    fn process_space(&mut self, g: f64) {
        let score_gap1 = self.timing.score_gap1(g);
        let score_gap3 = self.timing.score_gap3(g);
        let score_gap7 = self.timing.score_gap7(g);

        // Minimum gap durations before char/word-gap hypotheses are considered.
        // Without these floors, vocabulary/callsign bonuses can overcome timing
        // evidence at clearly intra-character gaps, causing false character
        // boundaries and premature word commits.
        let min_char_gap = self.timing.gap1.mean * 1.5;
        let allow_char_gap = g >= min_char_gap;
        // Word gap floor: 3.5× element gap to prevent standard character gaps
        // (3×dit ≈ 150ms at 24 WPM) from qualifying as word gaps. Previously
        // used 2.5×dit which was too low (allowed char gaps as word gaps,
        // destroying callsigns). Values tested:
        //   2.5×: too low (splits callsigns)
        //   midpoint(gap3,gap7): too high (merges all words)
        //   4.0×: slightly too high (some word gaps missed)
        //   3.5×: good balance
        let min_word_gap = self.timing.gap1.mean * 3.5;
        let allow_word_gap = g >= min_word_gap;

        let mut candidates: Vec<Hypothesis> = Vec::with_capacity(self.beam.len() * 3);

        for hyp in &self.beam {
            // 1. Intra-character gap (element gap) — continue building pattern
            {
                let mut cand = hyp.clone();
                cand.log_prob += score_gap1;
                candidates.push(cand);
            }

            // 2. Inter-character gap — emit character if pattern is complete.
            // Only considered when gap exceeds minimum threshold to prevent
            // callsign prefix bonuses from splitting characters at element gaps.
            if allow_char_gap && self.trie.is_complete(&hyp.pattern) {
                if let Some(ch) = self.trie.decode(&hyp.pattern) {
                    let mut cand = hyp.clone();
                    cand.word.push(ch);

                    // Language model: prefix bonus
                    let bonus = if is_callsign_prefix(&cand.word) {
                        CALLSIGN_PREFIX_BONUS
                    } else if is_vocab_prefix(&cand.word) {
                        PREFIX_BONUS
                    } else {
                        0.0
                    };

                    cand.pattern.clear();
                    cand.log_prob += score_gap3 + bonus;
                    candidates.push(cand);
                }
            }

            // 3. Word gap — emit character + commit word.
            // Only considered when the gap exceeds the minimum threshold
            // (2× element gap) to prevent bonuses from overriding timing.
            if allow_word_gap && self.trie.is_complete(&hyp.pattern) {
                if let Some(ch) = self.trie.decode(&hyp.pattern) {
                    let mut cand = hyp.clone();
                    cand.word.push(ch);

                    // Language model: word completion bonus.
                    // Short words (1-2 chars) get reduced bonus because they
                    // could be the prefix of a callsign (e.g., "WA" in WA9AGG).
                    let bonus = if is_callsign_pattern(&cand.word) {
                        CALLSIGN_BONUS
                    } else if is_vocab_word(&cand.word) {
                        if cand.word.len() <= 2 {
                            WORD_BONUS * 0.5
                        } else {
                            WORD_BONUS
                        }
                    } else {
                        0.0
                    };

                    // Commit word span with timing
                    if let Some(start) = cand.word_start_sample {
                        let end = self.last_off_offset.unwrap_or(start);
                        cand.committed_spans.push(WordSpan {
                            text: cand.word.clone(),
                            start_sample: start,
                            end_sample: end,
                        });
                    }

                    // Commit word to text
                    if !cand.text.is_empty() {
                        cand.text.push(' ');
                    }
                    cand.text.push_str(&cand.word);
                    cand.word.clear();
                    cand.word_start_sample = None;
                    cand.pattern.clear();
                    cand.log_prob += score_gap7 + bonus;
                    candidates.push(cand);
                }
            }
        }

        if candidates.is_empty() {
            return;
        }

        self.prune(candidates);
    }

    /// Sort candidates by log_prob descending and keep top K.
    fn prune(&mut self, mut candidates: Vec<Hypothesis>) {
        candidates.sort_by(|a, b| {
            b.log_prob
                .partial_cmp(&a.log_prob)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        candidates.truncate(BEAM_WIDTH);
        self.beam = candidates;
    }

    /// Finalize decoding: emit any remaining pattern/word from best hypothesis.
    /// Returns the full decoded text.
    pub fn finalize(self) -> String {
        self.finalize_with_spans().0
    }

    /// Finalize decoding and return both text and word spans with sample timing.
    pub fn finalize_with_spans(self) -> (String, Vec<WordSpan>) {
        if self.beam.is_empty() {
            return (String::new(), Vec::new());
        }

        let best = self.beam.into_iter().next().unwrap();
        let mut result = best.text.clone();
        let mut spans = best.committed_spans.clone();

        // Pending word
        let mut pending_word = best.word.clone();

        // Pending pattern
        if !best.pattern.is_empty() {
            if let Some(ch) = self.trie.decode(&best.pattern) {
                pending_word.push(ch);
            } else if let Some(chars) = morse::split_pattern(&best.pattern) {
                for ch in chars {
                    pending_word.push(ch);
                }
            }
        }

        if !pending_word.is_empty() {
            if !result.is_empty() {
                result.push(' ');
            }
            result.push_str(&pending_word);

            // Add span for the pending word
            if let Some(start) = best.word_start_sample {
                let end = self.last_off_offset.unwrap_or(start);
                spans.push(WordSpan {
                    text: pending_word,
                    start_sample: start,
                    end_sample: end,
                });
            }
        }

        (result, spans)
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // --- Morse trie tests ---

    #[test]
    fn trie_complete_codes() {
        let trie = MorseTrie::new();
        assert!(trie.is_complete(".-")); // A
        assert!(trie.is_complete("-...")); // B
        assert!(trie.is_complete(".")); // E
        assert!(trie.is_complete("-")); // T
        assert!(trie.is_complete("-----")); // 0
    }

    #[test]
    fn trie_decode() {
        let trie = MorseTrie::new();
        assert_eq!(trie.decode(".-"), Some('A'));
        assert_eq!(trie.decode("-..."), Some('B'));
        assert_eq!(trie.decode("."), Some('E'));
        assert_eq!(trie.decode("-"), Some('T'));
        assert_eq!(trie.decode("..."), Some('S'));
        assert_eq!(trie.decode("---"), Some('O'));
    }

    #[test]
    fn trie_prefix() {
        let trie = MorseTrie::new();
        assert!(trie.is_prefix(".")); // E, but also prefix of I, S, H, etc.
        assert!(trie.is_prefix("-")); // T, but also prefix of N, M, D, etc.
        assert!(trie.is_prefix("..")); // I, prefix of S, H, etc.
        assert!(trie.is_prefix("")); // empty is always a prefix
    }

    #[test]
    fn trie_invalid() {
        let trie = MorseTrie::new();
        assert!(!trie.is_complete(""));
        assert!(!trie.is_complete("........")); // too long
        assert_eq!(trie.decode("........"), None);
    }

    #[test]
    fn trie_all_letters_roundtrip() {
        let trie = MorseTrie::new();
        for ch in 'A'..='Z' {
            let pat = morse::encode_char(ch).unwrap();
            assert_eq!(
                trie.decode(pat),
                Some(ch),
                "trie decode failed for {ch} ({pat})"
            );
            assert!(trie.is_complete(pat), "trie should mark {pat} as complete");
        }
    }

    #[test]
    fn trie_all_digits_roundtrip() {
        let trie = MorseTrie::new();
        for ch in '0'..='9' {
            let pat = morse::encode_char(ch).unwrap();
            assert_eq!(trie.decode(pat), Some(ch));
            assert!(trie.is_complete(pat));
        }
    }

    // --- Timing model tests ---

    #[test]
    fn timing_dit_scores_higher_for_dit_duration() {
        let tm = TimingModel::from_estimates(60.0, 180.0, 420.0);
        // 60ms mark should score higher as dit than dah
        assert!(tm.score_dit(60.0) > tm.score_dah(60.0));
        // 180ms mark should score higher as dah than dit
        assert!(tm.score_dah(180.0) > tm.score_dit(180.0));
    }

    #[test]
    fn timing_gap_scoring() {
        let tm = TimingModel::from_estimates(60.0, 180.0, 420.0);
        // Short gap should score higher as element gap
        assert!(tm.score_gap1(60.0) > tm.score_gap3(60.0));
        // Medium gap should score higher as char gap
        assert!(tm.score_gap3(180.0) > tm.score_gap1(180.0));
        // Long gap should score highest as word gap
        assert!(tm.score_gap7(500.0) > tm.score_gap3(500.0));
    }

    // --- Beam decoder tests ---

    /// Helper: create keying events for a Morse pattern at given WPM.
    fn pattern_events(pattern: &str, wpm: u32, sample_rate: u32) -> Vec<KeyingEvent> {
        let dit_secs = 1.2 / wpm as f64;
        let dit_samples = (dit_secs * sample_rate as f64) as usize;
        let dah_samples = dit_samples * 3;
        let element_gap = dit_samples;
        let char_gap = dit_samples * 3;
        let word_gap = dit_samples * 7;

        let mut events = Vec::new();
        let mut offset = element_gap; // start with a gap so first On has a prior Off

        // Initial Off to establish timing
        events.push(KeyingEvent {
            kind: KeyingEventKind::Off,
            sample_offset: 0,
        });

        for ch in pattern.chars() {
            match ch {
                '.' => {
                    events.push(KeyingEvent {
                        kind: KeyingEventKind::On,
                        sample_offset: offset,
                    });
                    offset += dit_samples;
                    events.push(KeyingEvent {
                        kind: KeyingEventKind::Off,
                        sample_offset: offset,
                    });
                    offset += element_gap;
                }
                '-' => {
                    events.push(KeyingEvent {
                        kind: KeyingEventKind::On,
                        sample_offset: offset,
                    });
                    offset += dah_samples;
                    events.push(KeyingEvent {
                        kind: KeyingEventKind::Off,
                        sample_offset: offset,
                    });
                    offset += element_gap;
                }
                ' ' => {
                    // Character gap (already have 1 element gap, add 2 more)
                    offset += char_gap - element_gap;
                }
                '/' => {
                    // Word gap (already have 1 element gap, add 6 more)
                    offset += word_gap - element_gap;
                }
                _ => {}
            }
        }

        events
    }

    fn decode_with_beam(events: &[KeyingEvent], wpm: u32, sample_rate: u32) -> String {
        let dit_ms = 1200.0 / wpm as f64;
        let char_gap_ms = dit_ms * 3.0;
        let word_gap_ms = dit_ms * 7.0;
        let mut decoder = BeamDecoder::new(dit_ms, char_gap_ms, word_gap_ms, sample_rate);
        for &event in events {
            decoder.process_event(event);
        }
        decoder.finalize()
    }

    #[test]
    fn beam_decodes_letter_e() {
        let sr = 12_000;
        let wpm = 20;
        let events = pattern_events(".", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert_eq!(text, "E", "expected 'E', got '{text}'");
    }

    #[test]
    fn beam_decodes_letter_t() {
        let sr = 12_000;
        let wpm = 20;
        let events = pattern_events("-", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert_eq!(text, "T", "expected 'T', got '{text}'");
    }

    #[test]
    fn beam_decodes_sos() {
        let sr = 12_000;
        let wpm = 20;
        // S = ..., O = ---, S = ...
        let events = pattern_events("... ---/...", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        // The word gap after O might cause different spacing
        assert!(
            text.contains('S') && text.contains('O'),
            "expected S and O in output, got '{text}'"
        );
    }

    #[test]
    fn beam_decodes_cq() {
        let sr = 12_000;
        let wpm = 20;
        // C = -.-., Q = --.-
        let events = pattern_events("-.-. --.-", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert_eq!(text, "CQ", "expected 'CQ', got '{text}'");
    }

    #[test]
    fn beam_decodes_hi_hi() {
        let sr = 12_000;
        let wpm = 20;
        // H = ...., I = ..
        let events = pattern_events(".... ../.... ..", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert_eq!(text, "HI HI", "expected 'HI HI', got '{text}'");
    }

    #[test]
    fn beam_decodes_de() {
        let sr = 12_000;
        let wpm = 20;
        // D = -.., E = .
        let events = pattern_events("-.. .", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert_eq!(text, "DE", "expected 'DE', got '{text}'");
    }

    #[test]
    fn beam_handles_empty() {
        let sr = 12_000;
        let decoder = BeamDecoder::new(60.0, 180.0, 420.0, sr);
        let text = decoder.finalize();
        assert_eq!(text, "", "expected empty output for no events");
    }

    #[test]
    fn beam_vocab_bonus_steers_decode() {
        // With empty vocab, only callsign patterns match
        assert!(!is_vocab_word("CQ"));
        assert!(!is_vocab_word("XYZZY"));
        // Callsign patterns still match
        assert!(is_vocab_word("W1AW"));
    }

    #[test]
    fn beam_callsign_pattern() {
        assert!(is_callsign_pattern("W1AW"));
        assert!(is_callsign_pattern("KD9MUI"));
        assert!(is_callsign_pattern("N5J"));
        assert!(is_callsign_pattern("WA9AGG"));
        assert!(!is_callsign_pattern("CQ"));
        assert!(!is_callsign_pattern(""));
    }

    #[test]
    fn beam_callsign_prefix() {
        // letter + digit (strong callsign signal)
        assert!(is_callsign_prefix("W1"));
        assert!(is_callsign_prefix("N7"));
        assert!(is_callsign_prefix("WA9"));
        assert!(is_callsign_prefix("KD9"));
        // letter + digit + letter(s)
        assert!(is_callsign_prefix("W1A"));
        assert!(is_callsign_prefix("WA9AG"));
        assert!(is_callsign_prefix("N7U"));
        assert!(is_callsign_prefix("N7UN"));
        // NOT callsign prefixes (no digit = too ambiguous)
        assert!(!is_callsign_prefix("W"));
        assert!(!is_callsign_prefix("WA"));
        assert!(!is_callsign_prefix("DE"));
        assert!(!is_callsign_prefix("K"));
        // other non-matches
        assert!(!is_callsign_prefix("")); // empty
        assert!(!is_callsign_prefix("9AGG")); // starts with digit
        assert!(!is_callsign_prefix("POTA")); // no digit, too long
        assert!(!is_callsign_prefix("WA9AGG")); // 6 chars = complete callsign, not prefix
        assert!(!is_callsign_prefix("ABC")); // 3 alpha, no digit
    }

    #[test]
    fn beam_prefix_check() {
        // With empty vocab, nothing is a prefix
        assert!(!is_vocab_prefix("C"));
        assert!(!is_vocab_prefix("PO"));
        assert!(!is_vocab_prefix("QR"));
    }

    #[test]
    fn beam_decodes_callsign_wa9agg() {
        let sr = 12_000;
        let wpm = 15;
        // W=.-- A=.- 9=----. A=.- G=--. G=--.
        // DE W9AGG (simplified callsign test)
        let events = pattern_events("-.. ./.-- .- ----. .- --. --.", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert!(
            text.contains("W9AGG") || text.contains("WA9AGG"),
            "expected callsign in output, got '{text}'"
        );
    }

    #[test]
    fn beam_decodes_de_callsign() {
        let sr = 12_000;
        let wpm = 20;
        // DE N7UN — common CW exchange
        // D=-.., E=., N=-.  7=--..., U=..-, N=-.
        let events = pattern_events("-.. ./-. --... ..- -.", wpm, sr);
        let text = decode_with_beam(&events, wpm, sr);
        assert!(
            text.contains("N7UN"),
            "expected 'N7UN' in output, got '{text}'"
        );
    }

    #[test]
    fn beam_decodes_at_various_speeds() {
        let sr = 12_000;

        for wpm in [10, 15, 20, 25, 30] {
            // Test with "CQ" at each speed
            let events = pattern_events("-.-. --.-", wpm, sr);
            let text = decode_with_beam(&events, wpm, sr);
            assert_eq!(text, "CQ", "expected 'CQ' at {wpm} WPM, got '{text}'");
        }
    }

    #[test]
    fn beam_ambiguous_boundary_element() {
        // Test with a mark duration exactly at the dit/dah boundary.
        // The beam should still produce reasonable output because multiple
        // hypotheses will compete.
        let sr = 12_000u32;
        let wpm = 20;
        let dit_ms = 1200.0 / wpm as f64;
        let dit_samples = (dit_ms / 1000.0 * sr as f64) as usize;
        let element_gap = dit_samples;

        // Create a mark exactly at 2× dit (ambiguous boundary)
        let ambiguous_samples = dit_samples * 2;

        let events = vec![
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: 0,
            },
            KeyingEvent {
                kind: KeyingEventKind::On,
                sample_offset: element_gap,
            },
            KeyingEvent {
                kind: KeyingEventKind::Off,
                sample_offset: element_gap + ambiguous_samples,
            },
        ];

        let text = decode_with_beam(&events, wpm, sr);
        // Should decode as either E, T, I, N, or A — any valid character
        assert!(
            !text.is_empty(),
            "beam should produce output even for ambiguous elements"
        );
    }

    #[test]
    fn finalize_with_spans_returns_word_timing() {
        let wpm = 15;
        let sr = 8000;
        // "CQ DE W1AW" — three words with word gaps
        let events = pattern_events("-.-. --.-/-..- ./.- .----/.- .--", wpm, sr);

        let dit_ms = 1200.0 / wpm as f64;
        let char_gap_ms = dit_ms * 3.0;
        let word_gap_ms = dit_ms * 7.0;

        let mut decoder = BeamDecoder::new(dit_ms, char_gap_ms, word_gap_ms, sr);
        for event in &events {
            decoder.process_event(*event);
        }

        let (text, spans) = decoder.finalize_with_spans();
        assert!(!text.is_empty(), "should produce text");
        assert!(!spans.is_empty(), "should produce word spans");

        // Each span should have start < end
        for span in &spans {
            assert!(
                span.start_sample < span.end_sample,
                "span '{}' has start {} >= end {}",
                span.text,
                span.start_sample,
                span.end_sample
            );
            assert!(!span.text.is_empty(), "span text should not be empty");
        }

        // Spans should be in chronological order
        for pair in spans.windows(2) {
            assert!(
                pair[0].end_sample <= pair[1].start_sample,
                "spans should be chronological: '{}' ends at {} but '{}' starts at {}",
                pair[0].text,
                pair[0].end_sample,
                pair[1].text,
                pair[1].start_sample
            );
        }
    }

    #[test]
    fn finalize_backward_compat() {
        let wpm = 15;
        let sr = 8000;
        let events = pattern_events("-.-. --.-", wpm, sr);

        let dit_ms = 1200.0 / wpm as f64;
        let char_gap_ms = dit_ms * 3.0;
        let word_gap_ms = dit_ms * 7.0;

        // finalize() should still return the same text as before
        let mut d1 = BeamDecoder::new(dit_ms, char_gap_ms, word_gap_ms, sr);
        let mut d2 = BeamDecoder::new(dit_ms, char_gap_ms, word_gap_ms, sr);
        for event in &events {
            d1.process_event(*event);
            d2.process_event(*event);
        }

        let text1 = d1.finalize();
        let (text2, _spans) = d2.finalize_with_spans();
        assert_eq!(
            text1, text2,
            "finalize() and finalize_with_spans().0 should match"
        );
    }
}
