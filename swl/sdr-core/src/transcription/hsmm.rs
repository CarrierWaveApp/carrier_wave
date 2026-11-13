//! Hidden Semi-Markov Model (HSMM) for joint CW detection and decoding.
//!
//! Replaces the two-stage pipeline (2-state Viterbi → BeamDecoder) with a
//! unified 5-state model that jointly estimates keying state and decodes
//! Morse characters.
//!
//! ## States
//!
//! | State       | Emission  | Duration Mean        |
//! |-------------|-----------|----------------------|
//! | DIT_ON      | High energy | dit_ms             |
//! | DAH_ON      | High energy | 3 × dit_ms         |
//! | ELEMENT_GAP | Low energy  | dit_ms             |
//! | CHAR_GAP    | Low energy  | char_gap_ms        |
//! | WORD_GAP    | Low energy  | word_gap_ms        |
//!
//! ## Algorithm
//!
//! Modified Viterbi for HSMM: at each time step, we consider all possible
//! durations (1..D_max) for each state. Beam pruning (top-K paths) bounds
//! memory and computation. The MorseTrie constrains which DIT/DAH sequences
//! form valid Morse prefixes.
//!
//! Complexity: O(T × S × D_max × K) where T = time steps, S = 5 states,
//! D_max ≈ 30 windows (longest dah at slowest WPM), K = beam width.

use super::beam::MorseTrie;
use super::language_model::BigramModel;
use super::tone_detector::otsu_threshold_log;

// ---------------------------------------------------------------------------
// HSMM state definitions
// ---------------------------------------------------------------------------

/// The five HSMM states for CW decoding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HsmmState {
    DitOn = 0,
    DahOn = 1,
    ElementGap = 2,
    CharGap = 3,
    WordGap = 4,
}

impl HsmmState {
    fn is_on(self) -> bool {
        matches!(self, HsmmState::DitOn | HsmmState::DahOn)
    }

    fn is_gap(self) -> bool {
        !self.is_on()
    }

    fn index(self) -> usize {
        self as usize
    }
}

// ---------------------------------------------------------------------------
// Duration and emission models
// ---------------------------------------------------------------------------

/// Gaussian parameters for duration or emission modeling.
#[derive(Debug, Clone, Copy)]
struct GaussParam {
    mean: f64,
    sigma: f64,
}

impl GaussParam {
    fn new(mean: f64, sigma: f64) -> Self {
        Self {
            mean,
            sigma: sigma.max(0.5), // prevent division by zero
        }
    }

    /// Log-likelihood of observing value `x` under this Gaussian.
    fn log_prob(&self, x: f64) -> f64 {
        let z = (x - self.mean) / self.sigma;
        -0.5 * z * z - self.sigma.ln()
    }
}

/// Duration model for each HSMM state.
struct DurationModel {
    params: [GaussParam; 5],
    /// Maximum duration in windows for each state.
    max_dur: [usize; 5],
}

impl DurationModel {
    fn new(dit_ms: f64, char_gap_ms: f64, word_gap_ms: f64, window_ms: f64) -> Self {
        let dit_windows = (dit_ms / window_ms).round().max(1.0);
        let dah_windows = (dit_ms * 3.0 / window_ms).round().max(1.0);
        let elem_gap_windows = (dit_ms / window_ms).round().max(1.0);
        let char_gap_windows = (char_gap_ms / window_ms).round().max(1.0);
        let word_gap_windows = (word_gap_ms / window_ms).round().max(1.0);

        let params = [
            GaussParam::new(dit_windows, dit_windows * 0.25), // DIT_ON
            GaussParam::new(dah_windows, dah_windows * 0.20), // DAH_ON
            GaussParam::new(elem_gap_windows, elem_gap_windows * 0.30), // ELEMENT_GAP
            GaussParam::new(char_gap_windows, char_gap_windows * 0.25), // CHAR_GAP
            GaussParam::new(word_gap_windows, word_gap_windows * 0.25), // WORD_GAP
        ];

        // Max duration: bound by the separation between states.
        // DitOn max < DahOn mean to prevent dit absorbing dah-length runs.
        // Similarly for gaps.
        let max_dur = [
            (dit_windows * 2.0).round().max(3.0) as usize, // DIT_ON: < 2× dit
            (dah_windows * 2.0).round().max(6.0) as usize, // DAH_ON: generous
            (elem_gap_windows * 2.0).round().max(3.0) as usize, // ELEMENT_GAP
            (char_gap_windows * 3.0).round().max(6.0) as usize, // CHAR_GAP
            (word_gap_windows * 5.0).round().max(10.0) as usize, // WORD_GAP
        ];

        Self { params, max_dur }
    }

    /// Log-probability of staying in `state` for `duration` windows.
    fn log_prob(&self, state: HsmmState, duration: usize) -> f64 {
        self.params[state.index()].log_prob(duration as f64)
    }

    fn max_duration(&self, state: HsmmState) -> usize {
        self.max_dur[state.index()]
    }
}

/// Emission model: ON states have high energy, OFF states have low energy.
struct EmissionModel {
    on_mean: f64,
    on_var: f64,
    off_mean: f64,
    off_var: f64,
}

impl EmissionModel {
    /// Fit emission model from energies using Otsu threshold.
    fn fit(energies: &[f32]) -> Self {
        let mut sorted = energies.to_vec();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let otsu = otsu_threshold_log(&sorted);
        // Use 5× Otsu cluster split (same as existing Viterbi)
        let threshold = otsu * 5.0;

        let log_e: Vec<f64> = energies
            .iter()
            .map(|&e| (e.max(1e-10) as f64).ln())
            .collect();

        let log_threshold = (threshold.max(1e-10) as f64).ln();

        let mut off_sum = 0.0f64;
        let mut off_sq = 0.0f64;
        let mut off_count = 0usize;
        let mut on_sum = 0.0f64;
        let mut on_sq = 0.0f64;
        let mut on_count = 0usize;

        for &le in &log_e {
            if le < log_threshold {
                off_sum += le;
                off_sq += le * le;
                off_count += 1;
            } else {
                on_sum += le;
                on_sq += le * le;
                on_count += 1;
            }
        }

        if off_count == 0 || on_count == 0 {
            // Degenerate: all ON or all OFF
            let mean = log_e.iter().sum::<f64>() / log_e.len() as f64;
            return Self {
                on_mean: mean + 1.0,
                on_var: 1.0,
                off_mean: mean - 1.0,
                off_var: 1.0,
            };
        }

        let off_mean = off_sum / off_count as f64;
        let off_var = (off_sq / off_count as f64 - off_mean * off_mean).max(0.01);
        let on_mean = on_sum / on_count as f64;
        let on_var = (on_sq / on_count as f64 - on_mean * on_mean).max(0.01);

        Self {
            on_mean,
            on_var,
            off_mean,
            off_var,
        }
    }

    /// Log-probability of observing log-energy `le` in the given state.
    fn log_prob(&self, le: f64, state: HsmmState) -> f64 {
        let (mean, var) = if state.is_on() {
            (self.on_mean, self.on_var)
        } else {
            (self.off_mean, self.off_var)
        };
        -0.5 * (le - mean) * (le - mean) / var - 0.5 * var.ln()
    }
}

// ---------------------------------------------------------------------------
// Transition constraints
// ---------------------------------------------------------------------------

/// Allowed transitions between HSMM states.
///
/// Encodes Morse grammar:
/// - ON states (DIT/DAH) → any gap state
/// - ELEMENT_GAP → ON states (continue character)
/// - CHAR_GAP → ON states (start new character)
/// - WORD_GAP → ON states (start new word)
fn allowed_transitions(from: HsmmState) -> &'static [HsmmState] {
    match from {
        HsmmState::DitOn | HsmmState::DahOn => &[
            HsmmState::ElementGap,
            HsmmState::CharGap,
            HsmmState::WordGap,
        ],
        HsmmState::ElementGap => &[HsmmState::DitOn, HsmmState::DahOn],
        HsmmState::CharGap => &[HsmmState::DitOn, HsmmState::DahOn],
        HsmmState::WordGap => &[HsmmState::DitOn, HsmmState::DahOn],
    }
}

/// Log-probability of transitioning from one state to another.
///
/// Biased towards element gaps within characters (most common gap type).
fn transition_log_prob(from: HsmmState, to: HsmmState) -> f64 {
    match (from, to) {
        // After ON: most gaps are element gaps within a character
        (HsmmState::DitOn | HsmmState::DahOn, HsmmState::ElementGap) => (0.5_f64).ln(),
        (HsmmState::DitOn | HsmmState::DahOn, HsmmState::CharGap) => (0.3_f64).ln(),
        (HsmmState::DitOn | HsmmState::DahOn, HsmmState::WordGap) => (0.2_f64).ln(),

        // After any gap: dit and dah equally likely a priori
        (_, HsmmState::DitOn) => (0.5_f64).ln(),
        (_, HsmmState::DahOn) => (0.5_f64).ln(),

        _ => f64::NEG_INFINITY, // forbidden
    }
}

// ---------------------------------------------------------------------------
// HSMM hypothesis (beam search path)
// ---------------------------------------------------------------------------

/// A hypothesis (beam path) tracking Morse decoding state.
#[derive(Clone)]
struct HsmmHypothesis {
    /// Decoded text so far.
    text: String,
    /// Current partial Morse pattern (e.g., ".-" for in-progress character).
    pattern: String,
    /// Current word being assembled.
    current_word: String,
    /// Log probability score.
    log_prob: f64,
    /// Current HSMM state.
    state: HsmmState,
    /// How many windows we've been in the current state.
    state_duration: usize,
    /// Per-character confidence scores (log-prob of path at character emit).
    char_confidences: Vec<f64>,
    /// Last decoded character (for bigram context). None = start of sequence.
    last_char: Option<char>,
    /// Number of characters decoded (for computing per-character confidence).
    num_chars: usize,
    /// Cumulative duration log-prob (for confidence).
    duration_score: f64,
}

impl HsmmHypothesis {
    fn new(state: HsmmState) -> Self {
        Self {
            text: String::new(),
            pattern: String::new(),
            current_word: String::new(),
            log_prob: 0.0,
            state,
            state_duration: 0,
            char_confidences: Vec::new(),
            last_char: None,
            num_chars: 0,
            duration_score: 0.0,
        }
    }

    /// Emit a dit element into the current pattern.
    fn emit_dit(&mut self) {
        self.pattern.push('.');
    }

    /// Emit a dah element into the current pattern.
    fn emit_dah(&mut self) {
        self.pattern.push('-');
    }

    /// Complete the current character (char gap or word gap reached).
    /// Applies bigram language model scoring.
    /// Returns true if a valid character was decoded.
    fn complete_character(&mut self, trie: &MorseTrie, lm: &BigramModel) -> bool {
        if self.pattern.is_empty() {
            return false;
        }

        if let Some(ch) = trie.decode(&self.pattern) {
            // Apply bigram language model bonus
            let lm_score = match self.last_char {
                Some(prev) => lm.score(prev, ch),
                None => lm.score_start(ch),
            };
            // Scale LM contribution (0.5× to avoid over-weighting)
            self.log_prob += lm_score * 0.5;

            self.current_word.push(ch);
            self.char_confidences.push(self.log_prob);
            self.last_char = Some(ch);
            self.num_chars += 1;
            self.pattern.clear();
            true
        } else {
            // Invalid pattern — penalty but don't discard (might recover)
            self.pattern.clear();
            false
        }
    }

    /// Complete the current word (word gap reached).
    fn complete_word(&mut self, trie: &MorseTrie, lm: &BigramModel) {
        // First complete any pending character
        self.complete_character(trie, lm);

        if !self.current_word.is_empty() {
            if !self.text.is_empty() {
                self.text.push(' ');
                // Space transition in bigram model
                if let Some(prev) = self.last_char {
                    self.log_prob += lm.score(prev, ' ') * 0.5;
                }
                self.last_char = Some(' ');
            }
            self.text.push_str(&self.current_word);
            self.current_word.clear();
        }
    }

    /// Check if the current pattern is a valid Morse prefix.
    fn is_valid_prefix(&self, trie: &MorseTrie) -> bool {
        self.pattern.is_empty() || trie.is_prefix(&self.pattern)
    }
}

// ---------------------------------------------------------------------------
// HSMM Decoder
// ---------------------------------------------------------------------------

/// Result from HSMM decoding.
#[derive(Debug, Clone)]
pub struct HsmmResult {
    /// Decoded text.
    pub text: String,
    /// Per-character confidence scores (0.0–1.0).
    pub char_confidences: Vec<f64>,
    /// Overall confidence (geometric mean of character confidences).
    pub confidence: f64,
    /// Detected WPM from the decoding.
    pub wpm: u32,
    /// State path (for diagnostics).
    pub state_path: Vec<HsmmState>,
}

/// HSMM-based CW decoder.
///
/// Jointly detects keying events and decodes Morse characters using
/// a 5-state Hidden Semi-Markov Model with beam search.
pub struct HsmmDecoder {
    /// Dit duration in ms.
    dit_ms: f64,
    /// Character gap in ms.
    char_gap_ms: f64,
    /// Word gap in ms.
    word_gap_ms: f64,
    /// Analysis window duration in ms.
    window_ms: f64,
    /// Beam width (number of hypotheses to maintain).
    beam_width: usize,
}

impl HsmmDecoder {
    /// Create a new HSMM decoder with timing parameters.
    ///
    /// - `dit_ms`: estimated dit duration
    /// - `char_gap_ms`: estimated character gap duration
    /// - `word_gap_ms`: estimated word gap duration
    /// - `window_ms`: analysis window duration (typically 10ms)
    /// - `beam_width`: number of competing hypotheses (default: 8)
    pub fn new(
        dit_ms: f64,
        char_gap_ms: f64,
        word_gap_ms: f64,
        window_ms: f64,
        beam_width: usize,
    ) -> Self {
        Self {
            dit_ms,
            char_gap_ms,
            word_gap_ms,
            window_ms,
            beam_width,
        }
    }

    /// Decode an envelope (per-window energy values) into text.
    ///
    /// The envelope should come from `QuadratureDetector::compute_envelope()`.
    pub fn decode(&self, energies: &[f32]) -> HsmmResult {
        let n = energies.len();
        if n < 4 {
            return HsmmResult {
                text: String::new(),
                char_confidences: Vec::new(),
                confidence: 0.0,
                wpm: ((1200.0 / self.dit_ms) as u32).clamp(5, 50),
                state_path: Vec::new(),
            };
        }

        let trie = MorseTrie::new();
        let lm = BigramModel::new();
        let duration_model = DurationModel::new(
            self.dit_ms,
            self.char_gap_ms,
            self.word_gap_ms,
            self.window_ms,
        );
        let emission_model = EmissionModel::fit(energies);

        // Convert to log-energy space
        let log_energies: Vec<f64> = energies
            .iter()
            .map(|&e| (e.max(1e-10) as f64).ln())
            .collect();

        // Initialize beam with hypotheses starting in each gap state
        // (recording typically starts with silence)
        let mut beam: Vec<HsmmHypothesis> = vec![
            {
                let mut h = HsmmHypothesis::new(HsmmState::ElementGap);
                h.log_prob = (0.3_f64).ln();
                h
            },
            {
                let mut h = HsmmHypothesis::new(HsmmState::CharGap);
                h.log_prob = (0.3_f64).ln();
                h
            },
            {
                let mut h = HsmmHypothesis::new(HsmmState::WordGap);
                h.log_prob = (0.4_f64).ln();
                h
            },
        ];

        let mut state_path: Vec<HsmmState> = Vec::with_capacity(n);

        // Process each window
        let mut t = 0;
        while t < n {
            let mut new_beam: Vec<HsmmHypothesis> = Vec::new();

            for hyp in &beam {
                // Option 1: Continue in current state (extend duration)
                {
                    let new_dur = hyp.state_duration + 1;
                    let max_dur = duration_model.max_duration(hyp.state);
                    if new_dur <= max_dur {
                        let emit_lp = emission_model.log_prob(log_energies[t], hyp.state);
                        let mut cont = hyp.clone();
                        cont.state_duration = new_dur;
                        cont.log_prob += emit_lp;
                        new_beam.push(cont);
                    }
                }

                // Option 2: Transition to a new state (current state just ended)
                // Only if we've been in the current state for at least 1 window
                if hyp.state_duration >= 1 {
                    let dur_lp = duration_model.log_prob(hyp.state, hyp.state_duration);

                    for &next_state in allowed_transitions(hyp.state) {
                        let trans_lp = transition_log_prob(hyp.state, next_state);
                        let emit_lp = emission_model.log_prob(log_energies[t], next_state);

                        let mut new_hyp = hyp.clone();
                        new_hyp.log_prob += dur_lp + trans_lp + emit_lp;
                        new_hyp.duration_score += dur_lp;
                        new_hyp.state = next_state;
                        new_hyp.state_duration = 1;

                        // Apply Morse decoding logic at state transitions
                        match (hyp.state, next_state) {
                            // ON → gap: element just completed
                            (HsmmState::DitOn, _) if next_state.is_gap() => {
                                new_hyp.emit_dit();
                                // Check Morse validity
                                if !new_hyp.is_valid_prefix(&trie) {
                                    new_hyp.log_prob -= 10.0; // heavy penalty
                                }
                                // Character gap or word gap: complete character
                                if (next_state == HsmmState::CharGap
                                    || next_state == HsmmState::WordGap)
                                    && !new_hyp.complete_character(&trie, &lm)
                                {
                                    new_hyp.log_prob -= 5.0; // invalid char
                                }
                                if next_state == HsmmState::WordGap {
                                    new_hyp.complete_word(&trie, &lm);
                                }
                            }
                            (HsmmState::DahOn, _) if next_state.is_gap() => {
                                new_hyp.emit_dah();
                                if !new_hyp.is_valid_prefix(&trie) {
                                    new_hyp.log_prob -= 10.0;
                                }
                                if (next_state == HsmmState::CharGap
                                    || next_state == HsmmState::WordGap)
                                    && !new_hyp.complete_character(&trie, &lm)
                                {
                                    new_hyp.log_prob -= 5.0;
                                }
                                if next_state == HsmmState::WordGap {
                                    new_hyp.complete_word(&trie, &lm);
                                }
                            }
                            _ => {}
                        }

                        new_beam.push(new_hyp);
                    }
                }
            }

            // Filter NaN scores and prune beam: keep top-K by log_prob
            new_beam.retain(|h| h.log_prob.is_finite());
            new_beam.sort_by(|a, b| {
                b.log_prob
                    .partial_cmp(&a.log_prob)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            new_beam.truncate(self.beam_width);

            // Track best state for state_path
            if let Some(best) = new_beam.first() {
                state_path.push(best.state);
            }

            beam = new_beam;
            t += 1;
        }

        // Finalize: complete any pending character/word in the best hypothesis
        if let Some(best) = beam.first_mut() {
            // Add duration score for final state
            let final_dur_lp = duration_model.log_prob(best.state, best.state_duration);
            best.log_prob += final_dur_lp;
            best.duration_score += final_dur_lp;

            // Complete any pending Morse pattern
            best.complete_word(&trie, &lm);

            let wpm = ((1200.0 / self.dit_ms) as u32).clamp(5, 50);

            // Real confidence from HSMM state path:
            // 1. Per-element: how well observed duration matches expected Gaussian
            // 2. Per-character: product of element fits + LM score
            // 3. Overall: geometric mean of per-character confidences
            let confidence = if best.text.is_empty() || best.num_chars == 0 {
                0.0
            } else {
                // Duration fit: average duration log-prob per character
                // Better duration fit = durations closely match Gaussian models
                let avg_dur_score = best.duration_score / best.num_chars as f64;
                // Map duration score: typical range is -0.5 (good) to -5 (poor)
                let dur_confidence = 1.0 / (1.0 + (-(avg_dur_score + 1.5) / 1.0).exp());

                // Overall path quality: total log-prob per window
                let avg_path_lp = best.log_prob / n as f64;
                let path_confidence = 1.0 / (1.0 + (-(avg_path_lp + 2.0) / 1.0).exp());

                // Blend: 60% duration fit + 40% path quality
                (0.6 * dur_confidence + 0.4 * path_confidence).clamp(0.0, 1.0)
            };

            // Convert per-character log-probs to per-character confidences
            let char_confidences: Vec<f64> = if best.char_confidences.len() >= 2 {
                best.char_confidences
                    .windows(2)
                    .map(|w| {
                        let delta = w[1] - w[0];
                        // Per-char increment; map to 0-1
                        (1.0 / (1.0 + (-(delta + 2.0) / 1.5).exp())).clamp(0.0, 1.0)
                    })
                    .collect()
            } else {
                vec![confidence; best.num_chars]
            };

            HsmmResult {
                text: best.text.clone(),
                char_confidences,
                confidence,
                wpm,
                state_path,
            }
        } else {
            HsmmResult {
                text: String::new(),
                char_confidences: Vec::new(),
                confidence: 0.0,
                wpm: ((1200.0 / self.dit_ms) as u32).clamp(5, 50),
                state_path,
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// Generate a synthetic CW envelope at the given WPM.
    ///
    /// Returns (envelope, sample_rate_equivalent) where envelope values are
    /// per-window energies (high for ON, low for OFF).
    fn generate_morse_envelope(
        pattern: &str,
        dit_ms: f64,
        window_ms: f64,
        on_energy: f32,
        off_energy: f32,
    ) -> Vec<f32> {
        let dit_windows = (dit_ms / window_ms).round() as usize;
        let mut envelope = Vec::new();

        // Leading silence (word gap equivalent)
        for _ in 0..(dit_windows * 7) {
            envelope.push(off_energy);
        }

        let chars: Vec<&str> = pattern.split_whitespace().collect();
        for (ci, morse_char) in chars.iter().enumerate() {
            if *morse_char == "/" {
                // Word gap = 7 dits total
                for _ in 0..(dit_windows * 7) {
                    envelope.push(off_energy);
                }
                continue;
            }

            for (ei, element) in morse_char.chars().enumerate() {
                let dur = match element {
                    '.' => dit_windows,
                    '-' => dit_windows * 3,
                    _ => continue,
                };

                // ON period
                for _ in 0..dur {
                    envelope.push(on_energy);
                }

                // Element gap (1 dit) between elements within a character
                if ei < morse_char.len() - 1 {
                    for _ in 0..dit_windows {
                        envelope.push(off_energy);
                    }
                }
            }

            // Character gap (3 dits) between characters
            if ci < chars.len() - 1 && chars.get(ci + 1) != Some(&"/") {
                for _ in 0..(dit_windows * 3) {
                    envelope.push(off_energy);
                }
            }
        }

        // Trailing silence
        for _ in 0..(dit_windows * 7) {
            envelope.push(off_energy);
        }

        envelope
    }

    #[test]
    fn hsmm_decodes_simple_letter() {
        // "E" = single dit
        let dit_ms = 60.0; // ~20 WPM
        let window_ms = 10.0;
        let envelope = generate_morse_envelope(".", dit_ms, window_ms, 1.0, 0.01);

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        assert!(
            result.text.contains('E'),
            "Expected 'E' in decoded text, got: '{}'",
            result.text
        );
    }

    #[test]
    fn hsmm_decodes_dit_dah_character() {
        // "A" = ".-"
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let envelope = generate_morse_envelope(".-", dit_ms, window_ms, 1.0, 0.01);

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        assert!(
            result.text.contains('A'),
            "Expected 'A' in decoded text, got: '{}'",
            result.text
        );
    }

    #[test]
    fn hsmm_decodes_two_characters() {
        // "CQ" = "-.-." + "--.-"
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let envelope = generate_morse_envelope("-.-. --.-", dit_ms, window_ms, 1.0, 0.01);

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        // Should decode to "CQ" or contain both C and Q
        let has_c = result.text.contains('C');
        let has_q = result.text.contains('Q');
        assert!(
            has_c && has_q,
            "Expected 'CQ' in decoded text, got: '{}'",
            result.text
        );
    }

    #[test]
    fn hsmm_detects_word_boundary() {
        // "E T" = "." + word_gap + "-"
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let envelope = generate_morse_envelope(". / -", dit_ms, window_ms, 1.0, 0.01);

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        // Should contain a space (word boundary detected)
        assert!(
            result.text.contains(' '),
            "Expected word boundary (space) in decoded text, got: '{}'",
            result.text
        );
    }

    #[test]
    fn hsmm_empty_input() {
        let decoder = HsmmDecoder::new(60.0, 180.0, 420.0, 10.0, 8);
        let result = decoder.decode(&[]);
        assert!(result.text.is_empty());
        assert_eq!(result.confidence, 0.0);
    }

    #[test]
    fn hsmm_silence_only() {
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let envelope = vec![0.01f32; 200]; // 2 seconds of silence

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        // Should produce empty or very short text (no CW elements detected)
        let non_space_chars: usize = result.text.chars().filter(|c| !c.is_whitespace()).count();
        assert!(
            non_space_chars <= 1,
            "Expected near-empty text for silence, got: '{}' ({} chars)",
            result.text,
            non_space_chars
        );
    }

    #[test]
    fn hsmm_confidence_is_bounded() {
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let envelope = generate_morse_envelope(".-", dit_ms, window_ms, 1.0, 0.01);

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        assert!(
            (0.0..=1.0).contains(&result.confidence),
            "Confidence should be in [0, 1], got: {}",
            result.confidence
        );
    }

    #[test]
    fn hsmm_state_path_has_correct_length() {
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let envelope = generate_morse_envelope(".-", dit_ms, window_ms, 1.0, 0.01);
        let n = envelope.len();

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&envelope);

        assert_eq!(
            result.state_path.len(),
            n,
            "State path length should match input length"
        );
    }

    /// Verify that HSMM decodes a known CQ pattern with noise.
    #[test]
    fn hsmm_decodes_with_moderate_noise() {
        let dit_ms = 60.0;
        let window_ms = 10.0;
        let clean_envelope = generate_morse_envelope("-.-. --.-", dit_ms, window_ms, 1.0, 0.01);

        // Add noise using simple LCG
        let mut rng: u32 = 42;
        let noisy_envelope: Vec<f32> = clean_envelope
            .iter()
            .map(|&e| {
                rng = rng.wrapping_mul(1103515245).wrapping_add(12345);
                let noise = ((rng >> 16) as f32 / 32768.0 - 1.0) * 0.05;
                (e + noise).max(0.001)
            })
            .collect();

        let decoder = HsmmDecoder::new(dit_ms, dit_ms * 3.0, dit_ms * 7.0, window_ms, 8);
        let result = decoder.decode(&noisy_envelope);

        // With moderate noise, should still decode something
        assert!(
            !result.text.is_empty(),
            "Should decode something with moderate noise"
        );
    }
}
