# FT8 Interface Design — Enriched Decode List & Progressive Disclosure

**Date:** 2026-02-25
**Status:** Draft
**Author:** Claude + jsvana

## Overview

Redesign the FT8 session view to prioritize the two primary user stories — **The Hunt** (S&P: scanning for interesting stations) and **The CQ** (calling CQ, managing responses, tracking POTA progress). The core change is shifting from a developer dashboard to an operator-focused interface using progressive disclosure.

**Key differentiator vs. iFTX/FT8CN:** Full GridTracker-style enrichment (DXCC, state, grid, worked-before, distance) built into the decode list, powered by Carrier Wave's existing QSO log. No other mobile FT8 app has this.

## Design Principles

1. **The decode list is the primary interface** — everything else serves it. Maximize its screen real estate.
2. **State-driven progressive disclosure** — debug panel auto-expands on error, QSO card appears during exchanges, POTA counter appears during activations.
3. **Emotional design for achievements** — new DXCC entities, completed QSOs, and activation milestones should feel rewarding, not just update a counter.
4. **Respect the operator's attention** — FT8 operates on 15-second cycles. Information must be scannable in 2-3 seconds.
5. **Desktop familiarity as escape hatch** — compact/raw modes for operators who think in WSJT-X terms.

---

## Layout: Current → Proposed

### Current (top → bottom)

| Element | Height | % Screen |
|---------|--------|----------|
| Band selector | 44pt | 6% |
| Debug panel | ~80pt | 11% |
| Waterfall | 80pt | 11% |
| Cycle indicator | 32pt | 4% |
| Decode list | ~400pt | 53% |
| Active QSO card | ~80pt | 11% |
| Control bar | ~44pt | 6% |

### Proposed (top → bottom)

| Element | Height | % Screen |
|---------|--------|----------|
| Band + status pill | 44pt | 6% |
| Compact waterfall | 48pt | 6% |
| Cycle indicator | 28pt | 4% |
| Active QSO card (conditional) | 72pt | 9% |
| Segmented decode list | ~520pt | 68% |
| Control bar | 48pt | 6% |

**Net gain:** ~30% more vertical space for the decode list by collapsing the debug panel and shrinking the waterfall.

---

## Component Details

### 1. Band + Status Line

Replaces band selector + debug panel. Single line:

```
┌──────────────────────────────────────────┐
│ 20m · 14.074 MHz  FT8   ● OK · 42       │
└──────────────────────────────────────────┘
```

- **Left:** Band dropdown menu (existing), frequency (monospacedDigit), FT8 badge (orange capsule)
- **Right:** Status dot + decode count
  - Green dot: audio healthy, decodes arriving
  - Orange dot: audio level too low/high (auto-expands debug panel)
  - Red dot: no audio or no decodes for 2+ cycles (auto-expands debug panel)
- **Tap the status pill** to expand full debug panel (audio level meter, input picker, decode stats)
- Debug panel slides down with `spring(0.3, 0.7)` animation

### 2. Compact Waterfall (48pt default, expandable)

Same Canvas-based spectrogram with channel markers (green = CQ, cyan = other). Reduced from 80pt to 48pt — enough to show "band is active" at a glance.

- Drag handle on bottom edge to expand to 120pt+ for users who want waterfall detail
- Frequency axis retained below waterfall
- Channel markers remain valuable at compact size

### 3. Cycle Indicator (28pt)

Same as current but slightly tighter. TX/RX status dot, progress bar, seconds remaining.

```
TX ●●●●●●●○○○○○○○○  8s
```

- Orange when transmitting, blue when receiving
- `.caption.monospacedDigit()` for countdown

### 4. Active QSO Card (72pt, conditional)

Appears only when a QSO exchange is in progress. Uses compact status card style.

```
┌─ Active QSO ─────────────────────────────┐
│ W1AW   FN31 · -12 dB · 1,240 mi         │
│ ■ Call → ■ Rpt → ○ 73       Confirming   │
│ ●●●●●●●○○○○○○○○                     8s  │
│                               [Abort]    │
└──────────────────────────────────────────┘
```

- **Callsign:** `.title3.bold().monospaced()`
- **Grid, dB, distance:** `.caption`, secondary
- **Step indicator:** Filled squares = complete, outlined-filled = current, empty = pending
- **State label:** "Calling..." → "Report Sent" → "Confirming..." → "Complete!"
- **Cycle progress bar** embedded in card
- **Abort button:** Returns to previous mode
- **On complete:** Background flashes green briefly, auto-dismisses after 2s
- **Tap to expand:** Shows full message exchange history

Background: `Color(.secondarySystemGroupedBackground)`, 12pt corner radius.

### 5. Segmented Decode List (~520pt)

Three collapsible sections:

#### Section 1: "Directed at You" (pinned to top)

Only appears when someone is calling you. Orange 4pt left border.

```
┌──────────────────────────────────────────┐
│ ⚡ JA1XYZ    -15 dB   PM95   calling you │
│    Japan · 6,800 mi                      │
└──────────────────────────────────────────┘
```

- Haptic: `.impact(.medium)` on first appearance
- Auto-scrolls to ensure visibility
- Tapping auto-responds (in CQ mode, auto-sequencer handles it)

#### Section 2: "Calling CQ" (primary scan area)

All CQ decodes with full enrichment. Sorted by interest:

1. New DXCC entities (by SNR descending)
2. New states/grids (by SNR descending)
3. New band-slots (by SNR descending)
4. Other CQ calls (by SNR descending)
5. Dupes (bottom, dimmed at 0.5 opacity)

Each row:

```
┌──────────────────────────────────────────┐
│ W1AW        -12 dB   FN31    CQ       → │
│ USA · Connecticut · 1,240 mi             │
│ [NEW DXCC] [NEW BAND]                   │
└──────────────────────────────────────────┘
```

**Line 1 — Essentials:**
- Callsign: `.headline.monospaced().weight(.semibold)`
- SNR badge: colored rounded rect (green > -5 dB, yellow -5 to -15, orange < -15). `.caption.monospacedDigit()`
- Grid: `.caption.monospaced()`, `.secondary`
- CQ badge: existing blue capsule pattern
- Arrow `→` affordance: `.caption`, `.tertiary`

**Line 2 — Context:**
- Country, state/province, distance
- `.caption`, `.secondary`

**Line 3 — Achievement badges (conditional):**

| Badge | Background | Text | Trigger |
|-------|-----------|------|---------|
| NEW DXCC | `Color.yellow.opacity(0.3)` | `Color.yellow` | Never worked this DXCC entity |
| NEW STATE | `Color.blue.opacity(0.15)` | `.blue` | Never worked this US state (or equivalent) |
| NEW GRID | `Color.cyan.opacity(0.15)` | `.cyan` | Never worked this grid square |
| NEW BAND | `Color.blue` solid | `.white` | Worked callsign but not on current band |
| DUPE | `Color.orange.opacity(0.2)` | `.orange` | Already worked this session |

Badge style: `.caption2.weight(.bold)`, `.padding(.horizontal, 4)`, `.padding(.vertical, 1)`, `RoundedRectangle(cornerRadius: 3)`.

New DXCC gets `.notification(.success)` haptic on first decode (once per callsign per session).

#### Section 3: "All Activity" (collapsed by default)

Non-CQ exchanges between other stations. Shows count when collapsed:

```
ALL ACTIVITY (23)                        ▼
```

When expanded, compact single-line rows:

```
W3LPL → K1ABC  -18 dB  grid exchange
```

`.caption`, `.secondary` color. Not actionable.

### 6. Control Bar (48pt)

```
┌──────────────────────────────────────────┐
│ [Listen] [Call CQ] [Stop]    7/10 🌲      │
└──────────────────────────────────────────┘
```

- Same button styles as current (`.bordered`, `.caption.bold()`)
- Listen/Call CQ toggle: selected button uses `.accentColor` tint, unselected uses `.secondary`
- Stop button: `.bordered`, `.red` tint
- **POTA counter** (when `parkReference != nil`):
  - Shows `N/10` until valid activation
  - At 10: turns green, shows `10/10 ✓`, haptic `.notification(.success)`
  - After 10: shows count with green tint (`14 🌲`)

---

## Enrichment Data Pipeline

All enrichment runs on the `FT8SessionManager` actor, not the main thread. Decode results arrive at the view layer with enrichment already attached.

### Data Sources

| Enrichment | Source | Performance |
|-----------|--------|-------------|
| DXCC entity | Callsign prefix table (existing in stats) | In-memory lookup, < 1ms |
| State/province | DXCC prefix table or grid derivation | In-memory, < 1ms |
| Distance/bearing | Grid → coordinates via `MaidenheadConverter`, haversine | Pure math, < 1ms |
| Worked-before (call+band) | Preloaded `Set<String>` at session start | Set lookup, < 1ms |
| New DXCC/state/grid | Compare against preloaded sets from QSO history | Set lookup, < 1ms |

### Preloading Strategy

On FT8 session start:
1. Load all unique DXCC entities worked → `Set<String>`
2. Load all unique states worked → `Set<String>`
3. Load all unique grids worked → `Set<String>`
4. Load all callsign+band combos worked → `Set<String>` (e.g., "W1AW-20m")
5. Load all callsigns worked this session → `Set<String>` (for dupe detection)

Update sets incrementally on each logged QSO. Total memory: negligible (even 50k QSOs = ~50k short strings).

### Enriched Decode Result Model

```swift
struct FT8EnrichedDecode: Identifiable, Sendable {
    let decode: FT8DecodeResult
    let dxccEntity: String?        // "United States"
    let stateProvince: String?     // "Connecticut"
    let distanceMiles: Int?        // 1240
    let bearing: Int?              // 045
    let isNewDXCC: Bool
    let isNewState: Bool
    let isNewGrid: Bool
    let isNewBand: Bool
    let isDupe: Bool
}
```

---

## Interaction Model

### Tap-to-Call (The Hunt)

1. Operator taps a CQ row in "Calling CQ" section
2. Row flashes briefly (spring animation), QSO card appears
3. `FT8SessionManager` enters S&P mode, queues TX for next slot
4. Auto-sequencer handles the exchange
5. On completion: green flash on QSO card, `.notification(.success)` haptic, QSO logged
6. Card dismisses after 2s, decode list resumes scanning

**No confirmation dialog.** 15-second timing means "are you sure?" costs an entire TX slot. Tap = call. Abort via QSO card if accidental.

### "Directed at You" Response

- **In CQ mode:** Auto-sequencer handles it automatically. QSO card appears, exchange proceeds.
- **In Listen mode:** Tap the directed decode to respond.
- Haptic `.impact(.medium)` on appearance.

### CQ Mode Flow

1. Tap "Call CQ" → CQ button highlighted, TX begins next slot
2. Responses appear in "Directed at You" section
3. Auto-sequencer handles exchange → QSO logged
4. Auto-returns to calling CQ
5. Tap "Listen" to stop CQing

### Mode Transitions

| From | To | Trigger |
|------|----|---------|
| Listen | S&P | Tap a CQ decode |
| Listen | CQ | Tap "Call CQ" |
| S&P (in QSO) | Listen | Abort or QSO completes |
| CQ (in QSO) | CQ (idle) | QSO completes |
| CQ (idle) | Listen | Tap "Listen" |
| Any | Stopped | Tap "Stop" |

---

## Landscape Layout

When `verticalSizeClass == .compact`, two-column layout:

```
┌────────────────────────────────────────────────────────────┐
│ 20m · 14.074 MHz  FT8  ● OK · 42 │ TX ●●●●○○○  8s  7/10🌲│
├───────────────────────────────────┬────────────────────────┤
│                                   │ DIRECTED AT YOU        │
│   Waterfall (~140pt)              │ ⚡ JA1XYZ  -15dB  ...  │
│                                   │                        │
│                                   │ CALLING CQ             │
├───────────────────────────────────│ W1AW  -12dB  FN31 ... │
│  Active QSO card (compact)        │ K1TTT  -4dB  FN32 ... │
├───────────────────────────────────│ ...                    │
│ [Listen] [Call CQ] [Stop]         │ ALL ACTIVITY (23)   ▼ │
└───────────────────────────────────┴────────────────────────┘
```

- Left column (~40%): Waterfall (expanded ~140pt), QSO card, controls
- Right column (~60%): Full decode list with sections
- Tab bar hidden when FT8 session active (existing convention)
- Uses `.landscapeAdaptiveDetents()` for any sheets

---

## Haptic Feedback

| Event | Haptic | Frequency |
|-------|--------|-----------|
| New DXCC entity decoded | `.notification(.success)` | Once per callsign per session |
| Directed-at-you decode | `.impact(.medium)` | Each occurrence |
| QSO completed + logged | `.notification(.success)` | Each QSO |
| POTA 10-QSO milestone | `.notification(.success)` | Once per session |
| Tap to call a station | `.impact(.light)` | Each tap |

---

## Session Summary

On Stop, show a toast (existing toast pattern):

```
┌──────────────────────────────────────────┐
│ ✓  FT8 Session Complete                  │
│    45 min on 20m · 12 QSOs               │
│    3 new grids · 1 new DXCC (Croatia)    │
│    Best DX: JA1XYZ · 6,800 mi           │
└──────────────────────────────────────────┘
```

Auto-dismiss after 5 seconds. `.ultraThinMaterial`, 12pt corner radius, shadow.

---

## Compact Mode

Toggle in FT8 settings (or long-press section header). Single-line enriched rows:

```
W1AW    -12  FN31  CQ  USA  [NEW DXCC]
K1TTT    -4  FN32  CQ  USA
VE3ABC  -18  FN03  CQ  CAN  [NEW GRID]
```

Raw monospaced mode also available as a third option:

```
-12  CQ W1AW FN31
 -4  CQ K1TTT FN32
```

---

## Explicit Non-Goals

- Map view of decoded stations (future work)
- PSKReporter upload (future work)
- TX frequency selection on waterfall (desktop interaction, doesn't translate to mobile)
- Fox/Hound DXpedition mode (future work)
- FT4 support (same architecture, easy add-on later)
- Audio alerts/chimes (haptics sufficient for mobile)
- Contest-specific exchanges (future work)

---

## New Design Tokens

| Token | Value | Purpose |
|-------|-------|---------|
| SNR strong badge | `Color.green.opacity(0.2)` | SNR > -5 dB |
| SNR medium badge | `Color.yellow.opacity(0.2)` | SNR -5 to -15 dB |
| SNR weak badge | `Color.orange.opacity(0.2)` | SNR < -15 dB |
| New DXCC badge bg | `Color.yellow.opacity(0.3)` | Achievement highlight |
| New DXCC badge text | `Color.yellow` | Achievement highlight |
| Directed-at-you accent | `Color.orange` (existing) | Left border on urgent rows |
| Dupe row opacity | `0.5` | Dimmed duplicate rows |
| Waterfall compact | 48pt | Default height |
| Waterfall expanded | 120pt+ | Expanded via drag |

---

## Research Sources

### Competitive Analysis
- [WSJT-X User Guide](https://wsjt.sourceforge.io/wsjtx-doc/wsjtx-main-2.7.0.html)
- [iFTx App Store](https://apps.apple.com/us/app/iftx/id6446093115) / [iFTx Docs](https://iftx.ch/documentation.html)
- [FT8CN GitHub](https://github.com/N0BOY/FT8CN)
- [GridTracker Call Roster Docs](https://docs.gridtracker.org/latest/Making-GridTracker-Work-For-You/Using-Call-Roster.html)
- [Making FT8 Fun Again with GridTracker](https://ke2yk.com/2024/04/22/making-ft8-fun-again-with-gridtracker/)

### FT8 Protocol & Operating
- [G4IFB FT8 Operating Guide](https://www.g4ifb.com/FT8_Hinson_tips_for_HF_DXers.pdf)
- [KK5JY About FT8](https://www.kk5jy.net/about-ft8/) — automation philosophy analysis
- [K0EHR FT8 for Beginners](https://www.k0ehr.tech/2023/02/ft8-for-beginners-background-and-basic.html)
- [K0NR Why Use FT8 for POTA](https://www.k0nr.com/wordpress/2023/09/why-use-ft8-for-pota/)
- [POTA Digital Modes Guide](https://docs.pota.app/docs/digital_modes.html)
- [What I've Learned About FT8](https://querybang.com/2024/12/what-ive-learned-about-ft8/)
- [WSJT-X Decode Colors](https://ovmrc.ca/2025/02/decode-colours-in-wsjt-x/)
