# FT8 app-side correctness audit (local-audio path)

**Date:** 2026-06-03
**Branch:** `s3-devkit-n16r8`
**Scope:** iOS "Field" FT8 implementation vs the canonical WSJT-X FT8 protocol
(QEX 2020 "FT4 and FT8 Communication Protocols", Franke K9AN / Somerville G4WJS /
Taylor K1JT; WSJT-X `lib/ft8/`; cross-checked vs kgoba/ft8_lib). CFT8 C codec is
assumed bit-faithful and was **not** re-audited.
**Status:** Findings only — no source modified.

> Companion doc: [`2026-06-03-ft8-firmware-vs-app-bridge-path.md`](2026-06-03-ft8-firmware-vs-app-bridge-path.md)
> compares this app path against the firmware and recommends adopting the
> bridge codec. Several findings below become **moot** if the app moves to the
> bridge path (noted inline). This doc audits the path **as it exists today**.

---

## Architectural premise (important)

`proto/cwbp.proto:187-195` describes FT8 audio running on the **firmware** over
TRS jacks, with the app exchanging only text + metadata. **The iOS app does not
do that.** The iOS FT8 path is **fully local-audio**: it synthesizes tones in
Swift and plays/captures them through the device speaker/mic via `AVAudioEngine`.
The bridge's `Ft8Send` / `Ft8CaptureStart` / `Ft8Decode` messages are never used.

- `FT8SessionManager` drives `FT8AudioEngine` (local) + `FT8Encoder`/`FT8Decoder`.
- `FT8AudioEngine` taps the device input (`FT8AudioEngine.swift:288`) and plays to
  the device speaker (`FT8AudioEngine.swift:313`).

Consequence: audit items "sample rate" and "TX synth" are live **app-side**
concerns, and the synth has a real deviation.

---

## Findings

### 1. Slot / UTC timing — OK (alignment) / SUSPECT (tolerance)
- UTC alignment correct: `floor(epoch/15)*15`, parity from `Int(seconds/15)`,
  fires at the next boundary then repeats every 15 s
  (`FT8SessionManager.swift:282-288`).
- **SUSPECT:** the slot timer uses `tolerance = 1.5` (`FT8SessionManager.swift:310`).
  The OS may fire the boundary up to 1.5 s late, jittering both TX key-up and the
  RX window. **Fix:** drop tolerance to ≤ 50 ms on the FT8 slot timer.

### 2. TX timing — BUG (non-conformant): keys at slot_start, not +0.5 s
- Encoder emits 79 symbols from sample 0 with **no 0.5 s silence lead**
  (`FT8Encoder.swift:78-80`); `playTones` schedules and plays **immediately**, no
  `atTime` offset (`FT8AudioEngine.swift:136-138`), triggered synchronously at the
  boundary (`FT8SessionManager.swift:381-382`).
- WSJT-X peers decode this at **DT ≈ −0.5 s** (up to +1.0 s with the 1.5 s slop) —
  inside the decode window, so it usually still decodes, but it is non-conformant
  and burns sync margin. **Fix:** prepend ~0.5 s silence to the buffer, or schedule
  playback at `slotStart + 0.5 s`.

### 3. QSO turnaround — BUG (likely): auto-reply fires from stale decode state
- At each boundary the decode of the **just-ended** slot is dispatched
  **asynchronously** (`FT8SessionManager.swift:372-378`), but `transmitIfNeeded()`
  runs **synchronously right after** (`:381-382`) and reads
  `qsoStateMachine.nextTXMessage` **before** that decode lands. The only
  synchronous state updates are user actions; decode-driven state updates via the
  async path (`processMessage`, `:206`). So an auto-sequenced reply reflects RX
  from a full cycle earlier than the slot it should answer — after a partner sends
  their report you re-send your previous message for one more cycle. Not caught by
  `FT8IntegrationTests` (it calls `processMessage` synchronously).
  **Fix:** decode + process the just-ended slot **before** calling
  `transmitIfNeeded()` (single-slot decode is tens of ms; with a +0.5 s lead the
  budget is ample). *Confidence: high from call ordering; confirm with a timed
  two-station test.*

### 4. TX audio synth — SUSPECT: continuous-phase FSK, not GFSK; no envelope
- `synthesizeTones` is continuous-phase 8-FSK (good — no mid-tone clicks) but
  applies **no Gaussian shaping (BT=2.0)** and **no amplitude ramp** — full-amplitude
  `sin(phase)` from sample 0 (`FT8Encoder.swift:85-96`). Bits are correct (packed via
  `ftx_message_encode` + `ft8_encode`, `:39-67`).
- Abrupt frequency steps + hard on/off widen the occupied bandwidth well beyond the
  ~50 Hz of true GFSK, splattering onto adjacent 6.25 Hz channels. Decodes, but is a
  dirty neighbor. **Fix:** Gaussian pulse (BT=2.0) over transitions + raised-cosine
  ramp on first/last symbol. *Note: the firmware's own `synthesize_tones` has the
  same gap — see the companion doc.*

### 5. Sample rate — OK (nominal) / SUSPECT (route changes)
- 12 kHz end-to-end is correct: TX synth at 12000 (1920 samp/symbol, 6.25 Hz —
  `FT8Constants.swift:13-31`); RX decimates 48k→12k 4:1 with an anti-alias FIR;
  `configure()` validates an integer ratio and throws on non-integer rates
  (`FT8AudioEngine.swift:34-38`).
- **SUSPECT:** the route-change retap recomputes `decimationRatio = Int(deviceRate/12000)`
  (`FT8AudioEngine.swift:282`) **without re-validating** (`:454`). A switch to a
  44.1 kHz-only route → `Int(44100/12000)=3` → 14.7 kHz treated as 12 kHz → all
  decodes silently fail. **Fix:** re-validate on retap and surface
  `unsupportedSampleRate` (or resample properly).

### 6. Message construction — OK
Builds standard WSJT-X text (CQ / grid / `-NN` / `R-NN` / RRR / RR73 / 73) and hands
it to CFT8 for packing; sign/zero-pad formatting verified; grid validated Maidenhead;
no hand-rolled bit-packing.

### 7. Protocol field semantics — OK where used / N/A for bridge FT8
The local decode model reads `delta_time_s` as seconds, `frequency_hz` as audio Hz,
`snr` as uncalibrated — consistent. But these come from the **local** `FT8Decoder`,
not the bridge `Ft8Decode`, which the app does not consume. The proto FT8 messages
are unused by the app (see companion doc).

### 8. macOS "Sweep" — N/A: no FT8 implementation
CW Sweep is CW/CAT-only. The `Services/FT8/` and `Views/FT8/` entries in
`swift/macos/FILE_INDEX.md` point to files that don't exist; `BridgeFrame.swift`
(macOS) has CW builders but no FT8 ones. "FT8" appears only as a mode label.
**Fix:** mark those FILE_INDEX sections "Not Yet Implemented".

---

## Summary

| # | Item | Status | Severity |
|---|------|--------|----------|
| 1 | UTC slot alignment | OK; timer `tolerance=1.5s` suspect | Med |
| 2 | TX keyed at t=0, not +0.5 s | **BUG** (non-conformant) | Med |
| 3 | Auto-reply uses stale (pre-decode) state | **BUG** (likely; verify w/ test) | **High** |
| 4 | CPFSK not GFSK, no envelope → splatter | SUSPECT | Med |
| 5 | RX decimation unvalidated on route change | SUSPECT | Low–Med |
| 6 | Message construction / bits | OK | — |
| 7 | Local decode field semantics | OK | — |
| 8 | macOS FT8 | N/A (not implemented; stale index) | — |

**Interop bottom line:** the app *will* exchange FT8 with stock WSJT-X stations
(bits and 12 kHz / 6.25 Hz are correct), but three things hold it back from being a
clean, reliable on-air citizen: the −0.5 s timing offset (#2) compounded by the
1.5 s timer slop (#1); the stale-state auto-reply lag (#3, most likely to break
QSOs); and the splattery non-GFSK TX (#4). None require touching the verified C
codec — all are in the Swift timing/synthesis/wiring layer.

Aside (out of scope): `FT8SessionManager`/`FT8AudioEngine` use raw `print(...)`
(`FT8SessionManager.swift:175`, `FT8AudioEngine.swift:157`), violating the iOS
"no print" logging rule.
