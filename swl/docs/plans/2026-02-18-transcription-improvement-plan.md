# CW Transcription & Alignment Improvement Plan

> Synthesized from four parallel expert analyses: audio alignment code review,
> transcription pipeline code review, internet research on CW decoding algorithms,
> and internet research on multi-source audio alignment techniques.

## The Problem

Current transcription of a 16-source KiwiSDR combined recording:
```
ECRTPOKDE N4T N4T GEKPOK N4T N4T CQPOTA NXT N4T   E E KD9MUI GE UR 55N5ISNFL KD9WUI DK  U
```

Actual content:
```
CQ POTA DE N4T N4T CQ POTA N4T N4T ... KD9MUI GE UR 559 IN FL KD9MUI DE K  U
```

Two problem domains: **alignment/combining** (garbage in) and **transcription** (garbage out).

---

## Phase 1: Quick Wins (Low Effort, Immediate Impact)

### 1.1 Onset-Aware Alignment — Trim Silence Before Cross-Correlation

**Problem:** Sources have 3-19 seconds of leading zeros from reference-time padding. The global cross-correlation includes this silence, diluting the correlation peak and biasing alignment toward lag=0. This is the primary cause of the garbled beginning ("ECRTPOKDE").

**Fix:** Before `find_lag`, detect each source's signal onset (first 50ms window where RMS exceeds 3x the minimum-RMS window). Run cross-correlation only on the signal-bearing portions. Compute total shift as `onset_offset + fine_lag`.

**Impact:** HIGH — directly fixes the garbled beginning.
**Effort:** LOW — ~50 lines of code in `combine.rs`.

### 1.2 Onset-Aware Weighted Averaging — Don't Dilute With Silence

**Problem:** In `weighted_average_samples`, sources in their silence-padded region contribute `(0 * weight)` to the numerator but `weight` to the denominator, diluting the average. At the recording start, 12 silent sources + 4 real sources = the average is 1/4 of what it should be.

**Fix:** Use a per-source onset mask (from 1.1). Sources in their silence region contribute (0, 0) instead of (0, w) to the weighted average.

**Impact:** HIGH — prevents beginning-of-recording dilution.
**Effort:** LOW — ~20 lines in `combine.rs:weighted_average_samples`.

### 1.3 Raise MIN_CORRELATION from 0.1 to 0.3

**Problem:** r=0.1 means a source shares only 1% of variance with the group. These sources add almost pure noise.

**Fix:** Change constant at `combine.rs:643`.

**Impact:** LOW-MEDIUM — easy quality improvement.
**Effort:** TRIVIAL — one constant.

### 1.4 Increase Off-Debounce from 1 to 2

**Problem:** A single below-threshold 10ms window triggers an Off event, causing false breaks within CW elements during noise dips.

**Fix:** Change `off_debounce: 1` to `off_debounce: 2` in `tone_detector.rs:167`. Tone must be absent for 20ms before Off is declared — still well below the ~60ms dit at 20 WPM.

**Impact:** MEDIUM — reduces false element breaks.
**Effort:** TRIVIAL — one constant.

### 1.5 Scale Merge Gap to WPM

**Problem:** Fixed 30ms merge gap is 63% of a dit at 25 WPM (aggressive) but only 30% at 12 WPM (possibly too small).

**Fix:** After WPM estimation, set merge gap to `0.5 * dit_duration` instead of fixed 30ms.

**Impact:** MEDIUM — better noise tolerance across WPM range.
**Effort:** LOW — small change in `mod.rs`.

---

## Phase 2: Moderate Improvements (Medium Effort, Significant Impact)

### 2.1 Tighter Post-Combine Bandpass

**Problem:** The 400-900 Hz bandpass is 500 Hz wide, but the CW tone occupies ~100-150 Hz. After combining, 70%+ of the bandwidth is noise.

**Fix:** After combining and peak frequency detection, apply a narrow bandpass (100-200 Hz) centered on the detected CW tone frequency. This happens before transcription.

**Impact:** MEDIUM — significant SNR improvement for the transcriber.
**Effort:** LOW — reuse existing `BiquadCascade::bandpass` with tighter parameters.

### 2.2 Histogram-Based Timing with Valley Detection

**Problem:** Our Otsu-on-on-durations approach is a single global split. HamFist (the most architecturally sophisticated open-source CW decoder) uses histogram accumulation with valley detection, which is more robust for sparse/noisy data and naturally handles multi-modal timing distributions.

**How it works:**
1. Accumulate on-durations into a histogram (1ms bins)
2. Smooth the histogram lightly
3. Find local maxima (peaks for dits and dahs)
4. Find the valley between peaks as the natural dit/dah threshold
5. Dit duration = position of the dit peak (not P25 of a cluster)

**Impact:** HIGH — more robust WPM estimation, especially for variable-speed operators.
**Effort:** MEDIUM — replace WPM estimation in `mod.rs`.

### 2.3 Three-Gap Histogram Classification

**Problem:** We use fixed multipliers (1.5x dit for char gaps, 3.5x dit for word gaps) which are a compromise. Real operators have varying gap ratios.

**Fix:** Build a histogram of off-durations. Find clusters for element gaps, character gaps, and word gaps. Use the valleys between clusters as thresholds. Falls back to the fixed multipliers if the histogram is too sparse.

**Impact:** HIGH — directly addresses the character boundary errors ("POKDE" instead of "POTA DE").
**Effort:** MEDIUM — replace gap thresholds in `decoder.rs`.

### 2.4 Time-Varying Source Weights

**Problem:** Source weights are computed once for the entire recording. Sources that fade in/out or develop interference get a single compromise weight.

**Fix:** Divide the recording into 2-second overlapping windows. Compute per-receiver SNR (tone energy / noise energy during CW gaps) in each window. Use these as MRC weights with smooth cross-fades between windows.

**Impact:** HIGH — handles fading, intermittent interference, varying noise levels.
**Effort:** MEDIUM — refactor `compute_source_weights` and `weighted_average_samples`.

### 2.5 Trimmed Mean Combining

**Problem:** Weighted mean is sensitive to impulsive noise (static crashes, QRM bursts) from individual sources.

**Fix:** At each sample position, sort the N source values, discard the top and bottom 10-20%, average the rest. Can be combined with MRC weights: first exclude low-weight sources, then trimmed-mean the rest.

**Impact:** HIGH — robust to interference bursts that contaminate individual sources.
**Effort:** MEDIUM — replace inner loop of `weighted_average_samples`.

### 2.6 Spectral Flatness Gating for Tone Detection

**Problem:** Broadband noise bursts can produce enough energy at the CW tone frequency to trigger false tone-on events, creating phantom elements.

**Fix:** In the Goertzel detector, also compute energy at 2-3 nearby frequencies (e.g., +/- 50 Hz). Require the target-frequency energy to be significantly higher than the off-frequency energy (e.g., 3x ratio) before declaring tone-on. This distinguishes the sharp spectral peak of a CW tone from broadband noise.

**Impact:** MEDIUM — reduces false tone-on events during gaps.
**Effort:** MEDIUM — modify `ToneDetector::process` in `tone_detector.rs`.

### 2.7 Buffered Startup / Retroactive Decoding

**Problem:** The decoder commits to output from the very first element, before it has reliable timing statistics. This is why the beginning is worst.

**Source:** TF3LJ (Guenther 1973) buffers ~20 characters before producing output, learning the operator's timing first. HamFist uses ~100-sample warmup before producing output.

**Fix:** Buffer the first N keying events (e.g., 30-50 on/off transitions). Use them to estimate WPM and gap thresholds. Then decode the buffer retroactively with correct parameters. Continue with incremental decoding from there.

**Impact:** HIGH — fixes garbled beginning of transcription.
**Effort:** MEDIUM — refactor `MorseDecoder` to support two-pass mode.

---

## Phase 3: Architectural Improvements (Higher Effort, Transformative Impact)

### 3.1 Bayesian Beam Search Decoder

**Problem:** Our decoder makes hard decisions at every level (dit vs dah, element vs char vs word gap). Each decision is irrevocable. Ambiguous elements near the dit/dah boundary get classified wrong ~50% of the time, and errors cascade.

**State of the art:** HamFist and CW Skimmer both use Bayesian beam search. Instead of classifying each element independently, maintain K most-probable hypotheses (K=5-10). Each new observation (mark or gap) updates all hypotheses via Bayesian probability in log space. Pruning eliminates unlikely paths.

**How it works for CW:**
1. Start with one hypothesis: empty string
2. On key-on: for each hypothesis, branch into "this is a new character" and "this continues the current character" (based on gap duration probability)
3. On key-off: for each hypothesis, branch into "this element is a dit" and "this element is a dah" (based on duration probability)
4. Score each branch by P(observed_duration | hypothesis) using Gaussian likelihood centered on expected dit/dah/gap durations
5. Prune to top K hypotheses by cumulative log probability
6. When a character boundary is confident (all top-K hypotheses agree), emit it

**Impact:** TRANSFORMATIVE — handles all ambiguous cases simultaneously instead of committing to wrong answers.
**Effort:** HIGH — significant refactor of `decoder.rs`, but HamFist provides a reference implementation.

### 3.2 CW Protocol-Aware Post-Processing

**Problem:** The decoder treats CW as an arbitrary symbol sequence, ignoring the strong structure of amateur radio contacts.

**Knowledge to exploit:**
- CQ calls: `CQ POTA DE [callsign] [callsign]`
- Callsign patterns: 1-2 letters + digit + 1-3 letters (regex: `[A-Z]{1,2}[0-9][A-Z]{1,3}`)
- RST reports: 3 digits, first is 1-5, second is 1-9, third is 1-9
- Common words: CQ, DE, K, BK, 73, TU, UR, QSL, POTA, QTH
- State abbreviations: FL, IN, CA, TX, etc.

**Implementation:**
1. Build a CW vocabulary dictionary (common words + callsign regex)
2. After initial decode, score each word against the dictionary
3. For low-confidence words, try single-edit-distance corrections
4. For sequences matching RST position (after callsign exchange), constrain to valid RST values
5. For callsign-like sequences, validate against FCC ULS database (optional, via QRZ API)

**Impact:** HIGH — catches many errors that the beam search misses by exploiting domain structure.
**Effort:** MEDIUM — new post-processing module, does not require changing the core decoder.

### 3.3 Adaptive Noise Floor Estimation (Replace Global Otsu)

**Problem:** Our Otsu threshold is computed once from the entire recording. CW signals fade, interference comes and goes, noise floor changes.

**State of the art:** HamFist uses a gated per-bin adaptive noise floor estimator:
- Slow exponential smoothing (99% previous, 1% new) when no signal detected
- Gate off updates when magnitude exceeds ~2x noise estimate
- Faster adaptation after extended gate closure (noise floor may have shifted)

**Impact:** HIGH — handles fading and varying noise conditions.
**Effort:** MEDIUM — refactor `ToneDetector` calibration in `tone_detector.rs`.

### 3.4 Feature-Based Alignment (Event Matching)

**Problem:** Raw waveform cross-correlation is unreliable at recording edges and for narrowband signals where the tone's periodicity can cause cycle ambiguity.

**Fix:** Instead of (or in addition to) raw audio cross-correlation:
1. Run a simple tone detector on each individual source
2. Detect key-on/key-off events per source
3. Cross-correlate the binary on/off envelopes (which have sharp, unambiguous features)
4. Use event-based alignment for coarse correction, then refine with audio cross-correlation

**Impact:** MEDIUM-HIGH — much more robust alignment, especially at edges.
**Effort:** MEDIUM — run tone detection per-source before combining.

### 3.5 SNR-Based Maximum Ratio Combining (MRC)

**Problem:** Correlation-weighted averaging is not theoretically optimal. MRC (weight by SNR) is provably optimal for independent AWGN channels.

**Fix:** For CW, estimate per-source SNR from tone-on energy / tone-off energy. Weight each source by its SNR. Combined SNR = sum of individual SNRs.

**Impact:** MEDIUM — better than correlation weights, especially when sources have similar correlation but different SNR.
**Effort:** MEDIUM — requires SNR estimation per source, modify `compute_source_weights`.

### 3.6 Soft-Decision Combining (Longer Term)

**Problem:** We combine raw audio, then detect tone. This is suboptimal for OOK signals.

**Better approach:** Convert each receiver's output to a soft probability of "tone on" per window, then combine probabilities across receivers (independent observations), then threshold.

**Impact:** HIGH — fundamentally better for binary signals.
**Effort:** HIGH — architectural change to the pipeline.

---

## Phase 4: Future / Exploratory

### 4.1 Deep Learning CW Decoder (CNN-LSTM-CTC)

AG1LE's deepmorse-decoder achieved 99.5% accuracy at -6 dB SNR with only 5.2 hours of training data. The CTC loss handles variable-length sequences without requiring precise alignment — it would bypass our entire timing/gap/pattern pipeline.

**Tradeoff:** Requires labeled training data, GPU inference, and a fundamentally different architecture. Best explored as a parallel experimental path.

### 4.2 STFT-Domain Coherence Drift Estimation

Replace windowed time-domain cross-correlation with frequency-domain phase drift tracking. Achieves higher precision for SRO estimation because it uses phase information across all frequency bins simultaneously, weighted by per-bin coherence.

### 4.3 Multichannel Wiener Filter

Per-frequency-bin optimal combining weights computed from estimated signal and noise power spectral densities. The theoretical optimum for linear noise reduction.

---

## Recommended Implementation Order

```
Phase 1 (quick wins, do first):
  1.1 Onset-aware alignment          ← fixes garbled beginning
  1.2 Onset-aware averaging           ← fixes garbled beginning
  1.3 Raise MIN_CORRELATION           ← one constant
  1.4 Increase off-debounce           ← one constant
  1.5 Scale merge gap to WPM          ← small change

Phase 2 (next sprint):
  2.7 Buffered startup decoding       ← fixes garbled beginning (transcription side)
  2.2 Histogram-based timing          ← better WPM estimation
  2.3 Three-gap histogram             ← better character boundaries
  2.1 Tighter post-combine bandpass   ← easy SNR win
  2.5 Trimmed mean combining          ← robust to interference
  2.6 Spectral flatness gating        ← fewer false tone-on events

Phase 3 (major improvements):
  3.2 CW protocol post-processing     ← high impact, moderate effort
  3.3 Adaptive noise floor            ← handles fading
  3.1 Bayesian beam search decoder    ← transformative, high effort
  3.4 Feature-based alignment         ← robust alignment
  2.4 Time-varying source weights     ← handles fading in combining
  3.5 SNR-based MRC                   ← optimal combining weights
```

---

## Key References

### CW Decoding
- [HamFist](https://github.com/dawsonjon/HamFist) — Bayesian beam search, histogram timing, dictionary autocorrect
- [RSCW](http://www.pa3fwm.nl/software/rscw/algorithm.html) — Matched filter + tree search (optimal for machine CW)
- [fldigi CW](http://www.w1hkj.com/FldigiHelp/cw_page.html) — Hysteresis AGC, SOM fuzzy matching
- [AG1LE deepmorse](https://github.com/ag1le/deepmorse-decoder) — CNN-LSTM-CTC, 99.5% at -6dB
- [TF3LJ Guenther](https://sites.google.com/site/lofturj/14-machine-recognition-of-hand-sent-morse-code) — Buffered decoding
- [Bell 1977](https://archive.org/details/optimalbayesiane00bell) — Optimal Bayesian Morse (theoretical foundation)

### Audio Alignment & Combining
- [Coherence Drift SRO Estimation (IEEE 2015)](https://ieeexplore.ieee.org/document/7362791)
- [GCC-PHAT](https://xavieranguera.com/phdthesis/node92.html)
- [MRC Tutorial](https://wirelesspi.com/maximum-ratio-combining-mrc/)
- [Farrow Fractional Delay Filters](https://www.mathworks.com/help/dsp/ug/fractional-delay-filters-using-farrow-structures.html)
- [SDW-MWF](https://link.springer.com/chapter/10.1007/3-540-27489-8_9)
- [Diversity Reception for SDR (LZ1AQ)](https://www.lz1aq.signacor.com/docs/dr/deversity-reception.htm)
