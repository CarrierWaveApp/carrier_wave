# CW Decoder Algorithms: Comprehensive Research Analysis

**Date:** 2026-02-21
**Research Team:** Five specialized perspectives (DSP/EE, ML/Pattern Recognition, Communications Engineering, Information Theory, Software Survey)
**Project:** CW-SWL Multi-Receiver SDR Recording Server

## Executive Summary

This document synthesizes research findings from five expert perspectives on CW (Morse code) decoding algorithms. The investigation reveals that our current decoder occupies a unique niche (multi-operator, hand-keyed, multi-receiver) not addressed by existing software, and identifies concrete improvements offering 5-8 dB SNR gains through better signal processing and potential for <2% character error rates via machine learning approaches.

**Key Finding:** The single biggest limitation is **selectivity**. We process a 500 Hz bandwidth where an optimal receiver would use 100-150 Hz per operator, leaving ~5 dB of SNR improvement on the table.

---

## Table of Contents

1. [DSP and Electrical Engineering Perspective](#1-dsp-and-electrical-engineering-perspective)
2. [Machine Learning and Pattern Recognition](#2-machine-learning-and-pattern-recognition)
3. [Communications Engineering](#3-communications-engineering)
4. [Information Theory and Statistical Decoding](#4-information-theory-and-statistical-decoding)
5. [Software Survey: Existing CW Decoders](#5-software-survey-existing-cw-decoders)
6. [Synthesis and Recommendations](#6-synthesis-and-recommendations)

---

## 1. DSP and Electrical Engineering Perspective

### 1.1 The Matched Filter Problem

**Current limitation:** Our fixed 10ms Goertzel window is **not matched-filter optimal**. A dit at 20 WPM is 60ms -- our 10ms window captures only 1/6 of the energy, costing ~7.8 dB vs a matched filter.

**SNR improvement from matched filtering:**
- 60ms dit with 80 Hz bandwidth: processing gain = 60ms x 80 Hz = 4.8, or **6.8 dB**
- Our 10ms window: processing gain = 10ms x 80 Hz = 0.8, or **-1 dB**
- **Gap: ~8 dB of SNR left on the table**

### 1.2 Quadrature Demodulation

**RSCW Algorithm Architecture** (PA3FWM):

The RSCW decoder uses quadrature mixing for frequency-agnostic signal extraction:

```
Input Audio -> I/Q Mixing (cos/sin at carrier freq) -> Lowpass Filter (48-sample MA)
  -> Downsampling (8000 -> 1000 Hz) -> Envelope Detection -> Clock Recovery
```

**Key components:**
- **Quadrature mixing:** Preserves information regardless of received signal phase
- **FFT carrier tracking:** 1-second FFTs, max power detection, linear interpolation between updates (2x/second)
- **Clock recovery:** Exploits Morse structural asymmetry (odd-numbered bit positions more likely ON) via weighted summation
- **Correlation tree search:** Maximum-likelihood decoding for machine-sent CW

**SNR advantage:** 3-8 dB over single-frequency Goertzel energy detection

### 1.3 STFT-Based Multi-Tone Separation

**CW Skimmer approach:** Short-time FFT -> identify peaks per frame -> create per-operator frequency tracks -> decode independently

**Implementation for CW-SWL:**
```
STFT (512-2048 point) -> Peak detection (400-900 Hz) -> Per-operator tracking
  -> NCO downconversion -> Narrowband LPF -> Envelope detection -> Decode
```

**Benefits:**
- Handles 2-4 operators simultaneously at different beat frequencies
- Each operator gets matched bandwidth filtering
- Natural operator separation by frequency

### 1.4 Adaptive Filter Bandwidth

**CW occupied bandwidth formula:** BW = 4 x WPM Hz
- 20 WPM: ~80 Hz
- 25 WPM: ~100 Hz

**Current vs optimal:**
- Current: 500 Hz bandpass (400-900 Hz) for all operators
- Optimal: 100-150 Hz per operator, centered on beat frequency
- **SNR improvement: 10 x log10(500/150) = 5.2 dB** from bandwidth reduction alone

### 1.5 Kalman Filter Frequency Tracking

Handles crystal oscillator drift (10-50 ppm typical for KiwiSDR), maintains frequency lock during key-up periods via prediction. Complements PLL for robust tone tracking through fading and interference.

---

## 2. Machine Learning and Pattern Recognition

### 2.1 CTC (Connectionist Temporal Classification): The Proven Architecture

**Why CTC fits CW perfectly:**
- Maps variable-length input (spectrogram frames) to variable-length output (characters)
- No explicit dit/dah/gap segmentation needed
- Handles variable-speed Morse implicitly
- Produces natural confidence scores

**Benchmark result** (Assayag et al.):
- LSTM-RNN with 740K parameters
- **CER < 2% above -5 dB SNR** on synthetic data
- Graceful degradation: near-perfect above 0 dB, rapid falloff below -5 dB (matches human performance curve)

### 2.2 Published ML CW Decoders

| Project | Architecture | CER/Accuracy | Multi-operator | Notes |
|---------|-------------|--------------|----------------|-------|
| **Assayag et al.** | LSTM-RNN (740K params) | **<2% @ -5dB SNR** | No | Benchmark to beat |
| **MorseNet (Li/Wang)** | Shared CNN + CRNN + CTC | State-of-the-art | Yes (detection) | Detects + decodes separately |
| **YFDM** | Modified YOLOv5s | AP=0.68, P=0.989 | Yes (detection) | Detection only, no decode |
| **nn-morse** | Dense + LSTM + CTC | "Works with errors" | No | Streaming capable |
| **deepmorse (AG1LE)** | CNN + LSTM + CTC | Kaggle benchmark | No | Microphone input |
| **web-deep-cw-decoder** | CRNN + CTC | Not published | No | Browser-based (ONNX.js) |
| **MorseAngel** | 2x LSTM + Dense | "Room for improvement" | No | Element classification |

**Critical finding:** No existing ML decoder handles multiple operators within a narrow band (400-900 Hz). MorseNet/YFDM handle wideband detection (kHz separation), not our problem (10-120 Hz separation).

### 2.3 Spectrogram-Based Approaches

**MorseNet architecture:**
1. Shared convolution backbone
2. Detection branch (multi-channel CNN, locates centerlines)
3. Region extraction (crops detected signals)
4. Recognition branch (CRNN + CTC per region)

**Key insight:** Solves multi-operator by detecting-then-decoding. Each operator gets independent decoding after spatial separation.

**Spectrogram resolution requirement:** 5-10ms time steps to resolve dits at 20+ WPM (YFDM paper confirms 20ms causes dits to "vanish" at 1-2 pixels).

### 2.4 Source Separation for Multi-Operator CW

**Conv-TasNet approach:**
- Time-domain encoder generates separation-optimized representation
- Temporal convolutional network predicts per-source masks
- Linear decoder reconstructs individual waveforms

**CW advantages over speech:**
- Simpler signals (on/off tones vs harmonic mixtures)
- Binary masks sufficient (not continuous)
- Fully parameterizable for synthetic training

**Permutation Invariant Training (PIT):** Handles unknown operator count. For N=4 max operators, 24 permutations is tractable (vs factorial explosion at higher N).

### 2.5 Synthetic Training Data

**All published ML decoders train on synthetic data.** Real CW recordings are scarce and unlabeled.

**Key parameters to vary:**
- WPM: uniform(5, 35)
- Tone frequency: uniform(400, 900) Hz
- Num operators: discrete(1, 4)
- Key type: {perfect, paddle, bug, straight}
- Dit/dah ratio: normal(1/3, sigma by key type)
- Element timing jitter: normal(0, 0.05-0.20)
- SNR: uniform(-10, 30) dB
- Noise: {white, pink, impulse, QSB fading}
- Frequency drift: uniform(0, 50) ppm

**Training volumes:**
- Pre-training: ~10,000 hours synthetic
- Fine-tuning: ~10 hours real recordings

### 2.6 Recommended ML Approaches for CW-SWL

| Approach | Effort | Multi-operator | Confidence | Training Data | Impact |
|----------|--------|---------------|------------|--------------|--------|
| **Neural tone detector** | Low | Per-channel | Per-frame prob | ~1K hours | **High** (replaces weakest link) |
| CRNN + CTC end-to-end | Medium | Per-channel | CTC posteriors | ~50M chars | High |
| MorseNet (detect+decode) | High | Yes (native) | CTC + detection | Large synthetic | Very high |
| Conv-TasNet separation | High | Yes (unmix) | N/A | Synthetic mixtures | Medium |

**Best bang-for-buck:** Replace Goertzel + Otsu + Viterbi with small CNN predicting P(tone_on) per 10ms. Everything downstream unchanged. Trivially real-time on CPU.

---

## 3. Communications Engineering

### 3.1 CW as On-Off Keying (OOK)

**Differs from textbook OOK:**
- Variable symbol length (dits, dahs, gaps all different)
- Non-rectangular pulses (4-5ms rise/fall times)
- No synchronization preamble
- Occupied BW ~ 4 x WPM Hz

### 3.2 Matched Filter vs Our Approach

**Optimal receiver theory:** Matched filter integrates over entire symbol period. For CW, need a bank of matched filters (dit-length, dah-length) at estimated WPM.

**What we do:** Fixed 10ms Goertzel = narrowband energy detector, not matched to symbol duration.

**Processing gain:**
- Matched filter (60ms dit): ~6.8 dB
- Our 10ms window: ~-1 dB
- **Gap: ~8 dB**

### 3.3 Coherent vs Non-Coherent Detection

| Method | BER Formula | Advantage | Challenge |
|--------|-------------|-----------|-----------|
| **Coherent** | Q(sqrt(E_b/2N_0)) | 3 dB better | Needs phase lock |
| **Non-coherent** | 0.5 x exp(-E_b/4N_0) | No PLL needed | 3 dB penalty |

**Our choice:** Non-coherent (Goertzel magnitude) is correct for multi-operator CW because:
- Tone frequency drifts between operators
- Carrier vanishes during spaces (PLL tracking difficult)
- 3 dB penalty acceptable vs multi-receiver combining gain (6 dB)

### 3.4 Digital PLL for Tone Tracking

**Architecture:**
```
Phase detector -> Loop filter (PI controller) -> NCO
```

**CW-specific problem:** Carrier disappears during spaces. Solutions:
- Flywheel mode (freeze NCO during signal-absent periods)
- Narrow loop BW (1-5 Hz for slow drift)
- Aided acquisition (Goertzel estimate initializes NCO)

### 3.5 AGC (Automatic Gain Control)

**What we do:** Normalize to 0.9 peak + log-space Otsu (implicitly adaptive) + adaptive noise floor tracking (rudimentary AGC). Works well; per-operator AGC after separation would be marginal improvement.

### 3.6 Diversity Combining (Our Multi-Receiver Setup)

**What we do:** Correlation-weighted averaging with time-varying weights. Remarkably close to MRC:

| Method | SNR gain (N=4) |
|--------|---------------|
| MRC (optimal) | 4x = +6.0 dB |
| Equal-gain | ~3.2x = +5.0 dB |
| Our approach | ~3.5-3.8x = +5.4 to +5.8 dB |

**Conclusion:** We already capture ~90% of available diversity gain.

### 3.7 Interference Rejection

**Per-operator bandwidth:**
At 20 WPM (BW=80 Hz), using 150 Hz bandpass vs 500 Hz:
- Noise reduction: 10 x log10(500/150) = **5.2 dB**
- Free SNR from better filtering alone

This is what RSCW and CW Skimmer use. We currently skip downconversion and use wideband Goertzel.

### 3.8 Timing Recovery

**Our approach:** No explicit timing recovery. 10ms resolution = ~17% timing uncertainty at 20 WPM.

**Value assessment:** Moderate for machine CW, low for hand-sent. Our Gaussian timing models handle variability better than rigid clock recovery.

---

## 4. Information Theory and Statistical Decoding

### 4.1 Morse Code and Information Theory

Morse code is a **variable-length, prefix-free binary code** over a ternary symbol alphabet (dit, dah, silence). Predates Shannon (1948) but embodies core insight: shorter codewords for frequent symbols.

### 4.2 Hidden Semi-Markov Models (HSMM)

**Why HSMM is the natural model for CW:**

Standard HMMs have geometric duration distributions (P(duration=1) is highest), which is wrong for CW where duration carries primary information.

**5-state HSMM for CW:**
1. DIT (on-duration ~1x unit)
2. DAH (on-duration ~3x unit)
3. ELEMENT_GAP (off-duration ~1x unit)
4. CHAR_GAP (off-duration ~3x unit)
5. WORD_GAP (off-duration ~7x unit)

**Duration models:** Gaussian in log-space (log-normal) to enforce d > 0 and give asymmetric tails.

**Why superior to current 2-stage pipeline:**

Current approach (Viterbi for ON/OFF -> beam search for characters) loses information at stage boundary. HSMM jointly estimates states and durations.

**Viterbi algorithm for HSMM:** O(T x N x D_max) vs O(T x N^2) for standard HMM. For CW, N=5 states, D_max=200 windows -> O(1000T), very manageable.

### 4.3 Language Model Integration

**Character bigram model** trained on amateur radio QSO transcripts:
- Tiny vocabulary (~200 common words/abbreviations)
- Highly constrained protocol (CQ, DE, callsign, RST, 73)

Our BeamDecoder already does this with vocabulary/callsign bonuses. A data-driven bigram model would replace ad hoc bonuses with learned probabilities.

### 4.4 Theoretical Capacity and BER Floors

**OOK non-coherent detection:**
- BER = 10^-3 (readable): needs E_b/N_0 ~ 10 dB
- BER = 10^-5 (error-free): needs E_b/N_0 ~ 13 dB

**Multi-receiver diversity gain:**
With N=4 receivers (MRC): effective SNR = 4 x SNR_single = +6 dB

---

## 5. Software Survey: Existing CW Decoders

### 5.1 Comparison Table

| Decoder | Multi-signal | Hand-keyed | Multi-receiver | Open source | Real-time | Algorithm |
|---------|-------------|-----------|---------------|------------|----------|----------|
| **CW Skimmer** | **Yes (700+)** | Moderate | No | No | Yes | FFT channelization + Bayesian |
| **RSCW** | No | No (machine) | No | Yes | Yes | I/Q mixing + correlation tree |
| **fldigi** | No | Moderate | No | Yes | Yes | Threshold + lookup |
| **AG1LE/Assayag** | No | Yes (ML) | No | Yes | Yes | LSTM + CTC, **CER <2% @ -5dB** |
| **ggmorse** | No | Moderate | No | Yes | Yes | STFT + Goertzel |
| **MorseNet** | Yes (detection) | Unknown | No | Research | Yes | CNN + CRNN + CTC |
| **YFDM** | Yes (detection) | Unknown | No | Research | Yes (72 FPS) | YOLOv5s (detection only) |
| **nn-morse** | No | Moderate | No | Yes | Yes | Dense + LSTM + CTC |
| **CW-SWL (ours)** | **Via segmentation** | **Yes** | **Yes (4+)** | **Yes** | Yes | Goertzel + Viterbi + Beam |

**Our unique niche:** Multi-operator + hand-keyed + multi-receiver. No other decoder addresses all three.

### 5.2 Key Algorithms to Borrow

| Source | Technique | Applicability |
|--------|-----------|--------------|
| **CW Skimmer** | FFT channelization + per-channel Bayesian | High -- solves multi-operator separation |
| **RSCW** | I/Q mixing + correlation-based optimal detection | Medium -- excellent for machine CW |
| **Assayag et al.** | LSTM + CTC architecture (740K params) | High -- proven <2% CER @ -5dB |
| **MorseNet** | Detection branch + recognition branch | High -- architectural pattern for multi-operator |

---

## 6. Synthesis and Recommendations

### 6.1 Cross-Perspective Convergence

All five perspectives independently identify the same core improvements:

**Tier 1: Per-Operator Frequency Separation (5+ dB SNR gain)**

**Tier 2: HSMM Replacing 2-Stage Pipeline (principled unification)**

**Tier 3: Neural Tone Detector (replaces weakest link)**

### 6.2 Implementation Priority Order

1. **Per-operator STFT separation** -- Addresses #1 limitation. Reuses existing code patterns.
2. **Quadrature demodulation per channel** -- 5-8 dB SNR gain. Reuses `NarrowbandExtractor` pattern.
3. **HSMM replacing Viterbi + beam** -- Principled unification, better duration modeling.
4. **Neural tone detector** -- Eliminates most fragile stage. Small model, fast training.
5. **Character bigram LM** -- Data-driven priors from QSO transcripts.
6. **CTC end-to-end decoder** -- Second-opinion system. Natural confidence scores.
7. **RSCW correlation decoder** -- Optimal for machine CW subset.

### 6.3 What We're Already Doing Well

- **Correlation-weighted multi-receiver combining:** ~90% of optimal MRC gain
- **Adaptive threshold (log-space Otsu):** Sound approach for envelope detection
- **Beam search with protocol-aware bonuses:** Architecturally similar to CW Skimmer
- **Per-segment parameter estimation:** Handles multi-operator timing variability
- **Drift correction:** Addresses real-world HF propagation effects

**The gap is not architecture -- it's selectivity.** Moving from 500 Hz to 100-150 Hz per operator closes the largest performance gap.

---

## Appendix: Sources

### Academic Papers

- Connectionist Temporal Classification (Graves, 2006)
- YFDM: YOLO for Detecting Morse (Scientific Reports, 2023)
- MorseNet (IEEE Access, 2020)
- Morse Deep Learning (Assayag et al.)
- Conv-TasNet (IEEE/ACM TASLP, 2019)
- Human-Like Morse Decoding Using ML (NATO STO, 2024)

### Technical References

- RSCW Algorithm (PA3FWM) -- http://www.pa3fwm.nl/software/rscw/algorithm.html
- CW Skimmer Documentation -- http://dxatlas.com/CWSkimmer/Files/CwSkimmer.pdf
- Hidden Semi-Markov Models
- Viterbi Algorithm for HSMMs

### Software Repositories

- ggerganov/ggmorse -- https://github.com/ggerganov/ggmorse
- e04/web-deep-cw-decoder -- https://github.com/e04/web-deep-cw-decoder
- pd0wm/nn-morse -- https://github.com/pd0wm/nn-morse
- ag1le/deepmorse-decoder -- https://github.com/ag1le/deepmorse-decoder
- f4exb/morseangel -- https://github.com/f4exb/morseangel
- MaorAssayag/morse-deep-learning-detect-and-decode -- https://github.com/MaorAssayag/morse-deep-learning-detect-and-decode
