# CW Transcription Tuning Log

Recording: `/Users/jsvana/tmp/recording-20260219-225603/combined_seg0.wav`
Expected: at least "BK RR TU ... DE WB0RLJ"
SNR: ~10-13 dB, Otsu threshold: 0.047, p75=0.151, p95=0.874

## Session 1 (ran out of context)

| # | Change | Chars | Result |
|---|--------|-------|--------|
| 1 | 1.5× Otsu threshold | ? | garbage |
| 2 | 2× Otsu threshold | ? | garbage |
| 3 | on_debounce=2/3, off_debounce=2/3/4 | ? | various, no improvement |
| 4 | smooth_windows=3 | ? | didn't help much |
| 5 | min_on 30/40ms | ? | marginal |
| 6 | merge gap 1.0× dit | ? | ? |
| 7 | char gap floors 1.5×/2.5×/3.0× dit | ? | ? |

## Session 2 (ran out of context)

| # | Change | Chars | Result |
|---|--------|-------|--------|
| 8 | on_debounce=2 (with spectral gate reset) | 51 | too aggressive, all single elements |
| 9 | on_debounce=1, adaptive min_on=0.6× dit | 94 | similar to before |
| 10 | 2× Otsu on threshold + adaptive min_on | 80 | still garbage |
| 11 | Long-window Goertzel (52ms) | 55 | massive merged patterns (50-70 elements) |
| 12 | Long-window Goertzel (30ms) | 69 | still massive merged patterns |
| 13 | Per-event local SNR filter (2× off-energy) | 52 | removes too many real events |
| 14 | Lower gap floors (2× dit, 5× dit) + re-estimate from 2nd merge | 115 | more chars but still noisy |
| 15 | Raised adaptive min_on to 0.7× dit | — | not tested before context lost |

## Session 3 (ran out of context)

| # | Change | Chars | Result |
|---|--------|-------|--------|
| 16 | 0.7× dit min_on (test of #15) | 111 | mostly garbage E/T |
| 17 | Peak energy filter at 5× Otsu | 78 | removes real events (peak 0.1-0.18) |
| 18 | Moving-avg detection (dit-width, direct new events) | 68 | over-smoothed, biased to dashes |
| 19 | Moving-avg filter on first-pass events (center energy) | 40 | 46 kept/170 removed, timing broken |
| 20 | on_debounce=2 + soft spectral gate (no reset) | 67 | biased to dits |
| 21 | 3× Otsu on / 1× Otsu off (wide hysteresis) | 92 | still garbage, 32ms noise pile at 35 events |

## Session 4 (ran out of context)

| # | Change | Chars | Result |
|---|--------|-------|--------|
| 22 | Viterbi HMM (Otsu cluster split, symmetric transitions) | 108 | 451 raw events, still garbage |
| 23 | 3× dit asymmetric transitions (avg_off=3×dit) | 102 | 281 raw events, better but still noisy |
| 24 | 3× Otsu cluster split + 3× asymmetric | 60 | 139 raw events, TU/B/D/W fragments visible |
| 25 | 3× Otsu + 0.8× dit min_on | 47 | same fragments |
| 26 | 3-window smoothed energies before Viterbi | 36 | REVERTED — compressed energy distribution |
| 27 | 5× dit asymmetric transitions | 47 | near-identical to #25 |
| 28 | Standard gap floors (3×dit char, 7×dit word) | 41 | too many word gaps |
| 29 | 20ms Viterbi windows | 41 | REVERTED — ±20ms timing error too large |
| 30 | Sliding Goertzel (1-dit window, 10ms step) | 78 | REVERTED — boundary smearing, 209 raw events |
| 31 | WPM re-estimation from Viterbi events + 0.8×dit min_on | 31 | refined WPM=19, min_on too aggressive |
| 32 | Refined WPM + 30ms fixed min_on | 41 | wider gaps caused over-merging |
| 33 | Reverted WPM re-estimation | — | back to first-pass WPM (22) |
| 34 | **5× Otsu cluster split** | 37 | **"BKRR" visible for first time** |
| 35 | 5× Otsu + 30ms Viterbi min_on + post-decode cleanup | 34 | "ENFT N TU SN FNH LR6EE BKRR EN 4TW TEE TTTS ?" |

## Session 5 (current)

| # | Change | Chars | Result |
|---|--------|-------|--------|
| 36 | Otsu-based decoder WPM from Viterbi events | 35 | decoder_dit=60ms, WPM=20 (from 22) |
| 37 | Lower gap floors (2×dit char, 5×dit word) | 35 | same — estimate_gap_thresholds returns 125ms > floor |
| 38 | 1.5×dit char floor (90ms) | 35 | same — 125ms estimate > 90ms floor |
| 39 | 40ms Viterbi min_on | 36 | shifted dit median to 70ms, worse |
| 40 | 2.5×dit char floor (150ms) | 35 | same output, floor not binding |
| 41 | 3×dit/7×dit floors (180ms/420ms) | — | BK and RR merge, pattern splits create +/= noise |
| 42 | Word-gap-only + split_pattern | 14 | **MUCH WORSE** — greedy split produces wrong decompositions |
| 43 | **1.5×dit floor + E/T cleanup (final)** | 35 | **"NFT N TU SN FN SE LENBIE BKRR EN E3 W EE TTT IE ?"** |

## Final Pipeline Configuration

- First pass: ToneDetector (10ms windows, Otsu) → merge (30ms gap, 20ms min_on) → WPM=22, dit=52ms
- Viterbi: 5× Otsu cluster split, avg_on=dit_windows, avg_off=5×dit_windows (asymmetric)
- Viterbi merge: 0.5×dit gap (26ms), 30ms min_on
- Decoder dit from Otsu split of Viterbi on-durations: 60ms (WPM=20)
- Gap thresholds: estimated from off-durations, floored at 1.5×dit char, 5×dit word
- Fixed MorseDecoder with decoder WPM
- Post-decode cleanup: removes isolated single-char E/T words

## Key Observations

- Peak energy distribution of on-events: continuous, no clean break between 0.06-0.27
- After bandpass filtering ±40 Hz, noise is in same band as signal → no spectral improvement
- Moving-avg filter correctly identifies ~46 events (≈43 expected), but removing the rest breaks timing
- All threshold-based approaches fail because noise/signal overlap too much at window level
- **Viterbi HMM with elevated cluster split (5× Otsu) is the breakthrough**: reduces raw events from 451 to 98
- **Asymmetric transitions (5× dit for OFF→ON)** penalize entering ON state, suppressing noise spikes
- **Decoder WPM from Viterbi events** (Otsu split → dit cluster median) gives better estimate: 20 WPM vs 22 from noisy first pass
- **Gap threshold trade-off**: 125ms correctly separates BK at 40s but splits K at 27s (170ms internal gap); 180ms keeps K intact but merges BK at 40s (160ms gap). No single threshold works for both.
- **Word-gap-only with split_pattern fails**: greedy longest-prefix produces wrong decompositions for long merged patterns
- Post-decode E/T cleanup removes the most common noise characters without losing real content

## Remaining Limitations

- K at 27s has 170ms internal element gap (2.8× dit), overlapping with 160ms char gaps elsewhere
- No single gap threshold can resolve all character boundaries — would need context-aware (language model) decoder
- "DE" and "WB0RLJ" from expected text not found — likely in low-SNR portions below detection threshold
- Pattern splitting uses greedy longest-prefix which occasionally produces wrong decompositions
