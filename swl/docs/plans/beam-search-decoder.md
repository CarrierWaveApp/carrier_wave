# Bayesian Beam Search CW Decoder — Implementation Plan

## Overview

Replace the hard-decision `MorseDecoder` with a Bayesian beam search decoder that
maintains K competing hypotheses, deferring dit/dah/gap classification until
sufficient evidence accumulates. Based on the HamFist algorithm by Jonathan Dawson.

## Current Decoder Limitations

The existing `MorseDecoder` makes irrevocable decisions at every observation:
- **Dit vs dah**: hard threshold at 2× dit. Elements near the boundary are wrong ~50% of the time.
- **Gap classification**: hard thresholds for element/char/word gaps. A single misclassified gap merges or splits characters.
- **No backtracking**: once a decision is made, errors cascade through the rest of the decode.

## Beam Search Approach

Maintain K=5 hypotheses. Each observation (mark or space duration) branches every
hypothesis into multiple candidates scored by Gaussian log-likelihood against the
timing model. Prune to top K after each observation. Characters are emitted only
when all surviving hypotheses agree.

## Files to Create/Modify

### New: `sdr-core/src/transcription/beam.rs`

The beam search decoder. Contains:
- `BeamDecoder` struct with beam state, timing model, Morse trie
- `TimingModel` — Gaussian parameters for dit/dah/gap1/gap3/gap7
- `Hypothesis` — text/word/pattern/log_prob state
- `MorseTrie` — compact tree for O(1) prefix/complete validation
- Scoring functions, expansion logic, pruning, consensus extraction

### Modified: `sdr-core/src/transcription/mod.rs`

- Import `beam::BeamDecoder`
- In per-segment decoding (inside `process_tone()`), use `BeamDecoder` instead of `MorseDecoder::new_fixed_with_gaps()`
- Keep `MorseDecoder` for fallback / comparison

### Modified: `sdr-core/src/transcription/morse.rs`

- Add `all_patterns() -> Vec<(&'static str, char)>` that returns all pattern→char pairs
  (used to build the Morse trie at decoder init)

### Modified: `docs/FILE_INDEX.md`

- Add beam.rs entry

### Modified: `CLAUDE.md`

- Update CW Transcription pipeline description to mention beam search

## Data Structures

```
Hypothesis {
    text: String,       // Committed text (agreed-upon prefix)
    word: String,       // Current word being assembled
    pattern: String,    // Partial Morse pattern in progress (e.g. ".-")
    log_prob: f64,      // Cumulative log probability
}

TimingModel {
    dit: (mean_ms, sigma_ms),
    dah: (mean_ms, sigma_ms),
    gap1: (mean_ms, sigma_ms),   // intra-character (element gap)
    gap3: (mean_ms, sigma_ms),   // inter-character (letter gap)
    gap7: (mean_ms, sigma_ms),   // word gap
}

MorseTrie {
    // Compact array-based binary tree (like HamFist's flat array)
    // Supports: is_prefix(pattern), is_complete(pattern), decode(pattern)
}
```

## Algorithm Detail

### Initialization

Build `TimingModel` from pre-estimated dit/gap parameters (already computed per-segment
by `estimate_dit_otsu` and `estimate_gap_thresholds`):

```
dit_mean = dit_ms from segment estimation
dit_sigma = dit_mean * 0.25  (25% CV, typical for hand-sent CW)
dah_mean = dit_mean * 3.0
dah_sigma = dah_mean * 0.20
gap1_mean = dit_mean
gap1_sigma = dit_mean * 0.30
gap3_mean = char_gap_ms from segment estimation
gap3_sigma = gap3_mean * 0.25
gap7_mean = word_gap_ms from segment estimation
gap7_sigma = gap7_mean * 0.25
```

### Mark Observation (On→Off duration d_ms)

Compute Gaussian log-likelihoods:
```
score_dit      = log_gauss(d, dit_mean, dit_sigma)
score_dah      = log_gauss(d, dah_mean, dah_sigma)
score_dit_dit  = log_gauss(d, 2*dit_mean + gap1_mean, dah_sigma) - 2.0  // penalty
score_dit_dah  = log_gauss(d, dit_mean + dah_mean + gap1_mean, dah_sigma)
score_dah_dah  = log_gauss(d, 2*dah_mean + gap1_mean, dah_sigma)
```

For each hypothesis, generate up to 5 candidates:
1. Append "." → score_dit  (if pattern+"." is valid Morse prefix)
2. Append "-" → score_dah  (if pattern+"-" is valid Morse prefix)
3. Append ".." → score_dit_dit  (if valid, merged elements)
4. Append ".-" or "-." → score_dit_dah  (if valid)
5. Append "--" → score_dah_dah  (if valid)

If extended pattern is NOT a valid prefix but current pattern IS a complete character:
force-emit the character (append to word, clear pattern), then try the new element(s).

### Space Observation (Off→On duration g_ms)

Compute scores:
```
score_gap1 = log_gauss(g, gap1_mean, gap1_sigma)
score_gap3 = log_gauss(g, gap3_mean, gap3_sigma) + prefix_bonus
score_gap7 = if g >= gap7_mean { 0.0 } else { log_gauss(g, gap7_mean, gap7_sigma) } + word_bonus
```

For each hypothesis, generate up to 3 candidates:
1. Element gap → pattern unchanged, score_gap1
2. Character gap → decode pattern, append to word, score_gap3  (only if pattern is complete)
3. Word gap → decode pattern, commit word+space to text, score_gap7  (only if pattern is complete)

### Language Bonuses

Reuse vocabulary from `postprocess.rs`:
- `prefix_bonus` = +1.0 if `word + decoded_char` is a prefix of any known word/callsign
- `word_bonus` = +4.0 if complete word is in vocabulary, +2.0 if valid callsign pattern

Build a vocabulary set from the existing `COMMON_WORDS`, `STATE_ABBREVIATIONS`, and
callsign regex in postprocess.rs.

### Pruning

After expansion: sort all candidates by log_prob descending, keep top K=5.
No deduplication needed at K=5 (hypotheses naturally diverge).

### Output Extraction

```
fn get_output(&mut self) -> String:
    let prefix = self.beam[0].text.clone()
    // Remove hypotheses that disagree on committed text
    self.beam.retain(|h| h.text == prefix)
    // Clear committed text from surviving hypotheses
    for h in &mut self.beam { h.text.clear() }
    prefix
```

Called after processing all events in a segment. Final output also includes
the best hypothesis's word + decoded pattern.

## Integration

In `process_tone()`, replace:
```rust
let mut morse_decoder = MorseDecoder::new_fixed_with_gaps(
    seg.wpm, sample_rate,
    seg.char_gap_ms / 1000.0, seg.word_gap_ms / 1000.0,
);
```

With:
```rust
let mut beam_decoder = BeamDecoder::new(
    seg.dit_ms, seg.char_gap_ms, seg.word_gap_ms, sample_rate,
);
```

Both produce `String` output from the same `Vec<KeyingEvent>` input.

## Testing Plan

1. **Unit tests in beam.rs:**
   - `beam_decodes_single_letter` — E, T, A, N
   - `beam_decodes_word` — "SOS", "CQ"
   - `beam_decodes_word_with_space` — "HI HI"
   - `beam_handles_ambiguous_element` — element at exactly 2× dit boundary
   - `beam_handles_merged_elements` — dit+dah detected as single mark
   - `beam_noise_filtered` — very short marks ignored
   - `beam_morse_trie_validation` — prefix/complete checks

2. **Integration tests:**
   - `beam_vs_fixed_on_clean_signal` — beam should match or beat fixed decoder on synthetic CW
   - `single_tone_backwards_compat` — ensure existing test still passes
   - `multi_tone_transcription_finds_both_operators` — ensure multi-tone still works

3. **Quality gates:**
   - `cargo fmt --check && cargo clippy -- -W clippy::all && cargo test`

## Implementation Order

1. Add `all_patterns()` to morse.rs
2. Build `MorseTrie` in beam.rs  (+ trie unit tests)
3. Implement `TimingModel` with Gaussian scoring
4. Implement `Hypothesis` and beam expansion logic
5. Implement `BeamDecoder` with full mark/space handling
6. Add language bonus scoring (vocabulary from postprocess.rs)
7. Wire into `process_tone()` as replacement for `MorseDecoder`
8. Run full test suite, verify no regressions
9. Update docs (FILE_INDEX.md, CLAUDE.md)
