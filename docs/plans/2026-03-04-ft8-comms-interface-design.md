# FT8 Comms Interface Redesign

Date: 2026-03-04
Status: Approved

## Problem

The current FT8 implementation cannot hold a QSO. Critical protocol bugs prevent message exchange from completing, and the UI lacks the controls operators need to manage QSOs.

### Protocol Bugs
1. **S&P TX message wrong** — `reportSent` state sends `+NN` but S&P responder must send `R+NN` (roger prefix). State machine doesn't track CQ vs S&P role.
2. **CQ QSO never completes** — After sending RR73, state machine waits for their 73 which may never come. Should auto-complete when we send RR73.
3. **TX frequency hardcoded** — Always 1500 Hz. S&P must TX at the other station's audio frequency.
4. **TX slot parity inverted** — `transmitOnEven = isEvenSlot` should be `!isEvenSlot` (TX on opposite slot from when we heard them).

### UI Gaps
5. No TX message visibility (operator can't see what's being sent)
6. No manual message override (can't recover from auto-seq failures)
7. No TX/RX frequency control or display
8. No Enable TX / Halt TX concept
9. No CQ modifier selection (POTA, DX, SOTA)

## Design Principles

- **Conversation-centered** — The QSO exchange is the focal point, not frequency management
- **Progressive disclosure** — Complexity unfolds on demand (message override, all-activity)
- **15-second time pressure** — Every interaction must complete within one FT8 cycle
- **Distinctly Carrier Wave** — Monospaced radio data, semantic colors, layered grays, capsule badges

## Competitive Analysis

### vs iFTX
- CW has CAT radio control (CI-V, Kenwood) — iFTX has none
- CW has DXCC/grid entity awareness in decode list — iFTX has none
- CW decode list uses enriched rows with distance, bearing, new-entity badges
- CW waterfall is visual-only (smart defaults) — avoids iFTX's imprecise tap-to-set problem

### vs WSJT-X
- Single conversation-aware decode list replaces confusing two-panel split
- State-based message labels replace cryptic Tx1–Tx6
- Tap-to-call replaces double-click + Enable Tx two-step
- 3-4 color states replace 11-category color system
- Built-in entity/distance context replaces need for GridTracker/JTAlert

---

## Section 1: State Machine & Protocol Fixes

### Role Tracking

```swift
public enum QSORole: Sendable {
    case cqOriginator    // We called CQ, they responded
    case searchAndPounce // They called CQ, we responded
}

public private(set) var role: QSORole?
```

### TX Message Generation by Role

| State | CQ Originator sends | S&P Responder sends |
|-------|-------------------|-------------------|
| `calling` | (N/A) | `THEM MYCALL MYGRID` |
| `reportSent` | `THEM MYCALL -03` (plain) | `THEM MYCALL R-03` (roger + report) |
| `reportReceived` | `THEM MYCALL RR73` | `THEM MYCALL 73` |
| `completing` | (grace 73 if they respond) | (grace 73 if they respond) |

### QSO Completion Logic

- **CQ originator:** Complete when we **send** RR73 (don't wait for their 73)
- **S&P responder:** Complete when we **receive** RR73
- New `completing` state: QSO is logged, send one final 73 if they respond, then reset

### Slot Parity Fix

When calling a station heard during the current slot, TX on the opposite slot:
`transmitOnEven = !isEvenSlot`

### TX Frequency Tracking

```swift
private(set) var rxAudioFrequency: Double = 1500  // Hz offset
private(set) var txAudioFrequency: Double = 1500  // Hz offset
```

Auto-set `txAudioFrequency` to the decoded station's `frequency` when calling.

### TX Event Log

```swift
struct FT8TXEvent: Identifiable, Sendable {
    let id: UUID
    let message: String
    let timestamp: Date
    let audioFrequency: Double
    let cycleIndex: Int
}
```

### State Diagram

```
                    ┌──────────┐
         ┌─────────│   idle   │←─────────────────────┐
         │         └──────────┘                       │
         │              │                             │
    setCQMode()    initiateCall()                  timeout
         │         (S&P)  │                           │
         ▼              ▼                             │
   ┌──────────┐   ┌──────────┐                       │
   │ CQ idle  │   │ calling  │───────────────────────│
   │(TX CQ)   │   │(TX grid) │                       │
   └──────────┘   └──────────┘                       │
         │              │                             │
    handleCQ       recv signal                        │
    Response()     report                             │
         ▼              ▼                             │
   ┌────────────────────────┐                         │
   │      reportSent        │─────────────────────────│
   │ CQ: TX plain report    │                         │
   │ S&P: TX R+report       │                         │
   └────────────────────────┘                         │
              │                                       │
         recv R+report (CQ)                           │
         recv RR73 (S&P) → complete                   │
              │                                       │
              ▼                                       │
   ┌────────────────────────┐                         │
   │    reportReceived      │─────────────────────────┘
   │ CQ: TX RR73 → complete │
   │ S&P: TX 73             │
   └────────────────────────┘
              │
              ▼
   ┌────────────────────────┐
   │      completing        │──→ idle (after 1 cycle grace)
   │ QSO logged, send final │
   └────────────────────────┘
```

---

## Section 2: Conversation Card

Replaces `FT8ActiveQSOCard`. The centerpiece of the comms interface.

### Layout

```
┌─ FT8ConversationCard ──────────────────────┐
│                                             │
│  W1ABC · FN42 · United States · 1,242 mi   │  header
│  -07 dB · 1387 Hz                          │  SNR, audio freq
│                                             │
│  ┌─ transcript ──────────────────────────┐  │
│  │ 22:00:15  → W1ABC W6JSV DM13     TX  │  │  accent bg
│  │ 22:00:30  ← W6JSV W1ABC -07      RX  │  │  gray bg
│  │ 22:00:45  → W1ABC W6JSV R-12     TX  │  │
│  │ 22:01:00  ← W6JSV W1ABC RR73     RX  │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ┌─ next TX ─────────────────────────────┐  │
│  │  W1ABC W6JSV 73          auto · 4/4   │  │  auto-selected
│  │                              [▾]      │  │  tap to override
│  └───────────────────────────────────────┘  │
│                                             │
│               [Halt TX]  [Abort QSO]        │
└─────────────────────────────────────────────┘
```

### Design Tokens

- Header callsign: `.headline.monospaced()`
- Grid/entity/distance: `.caption` secondary
- Transcript timestamps: `.caption2.monospaced()` tertiary
- Transcript messages: `.caption.monospaced()`
- TX rows: `accentColor.opacity(0.15)` background
- RX rows: `Color(.systemGray5)` background
- Card container: `Color(.secondarySystemGroupedBackground)`, `cornerRadius: 12`
- Entry animation: `.move(edge: .top).combined(with: .opacity)`

### Override (Expanded)

```
┌─────────────────────────────────────────┐
│  ◉ W1ABC W6JSV 73         auto · bye    │  selected (radio button)
│  ○ W1ABC W6JSV RR73       end           │  alternative
│  ○ W1ABC W6JSV R-12       re-send rpt   │
│  ○ W1ABC W6JSV DM13       re-send grid  │
└─────────────────────────────────────────┘
```

Override applies for one TX cycle only, then auto-seq resumes. Orange left border when manual override active.

### Controls

- **Halt TX**: Pauses transmission, keeps QSO active. Toggles to "Resume TX."
- **Abort QSO**: Cancels entirely, red text, returns to idle.

### Completion

Green success banner: "QSO Logged — W1ABC · 20m FT8" in CW toast pattern (`.ultraThinMaterial`, spring animation). Dismisses after 3 seconds.

---

## Section 3: Layout Modes

Three modes sharing the same conversation card and override UX.

### Portrait (Conversation — Default)

```
┌─────────────────────────────────────────┐
│ 20m · 14.074 MHz · FT8        [🎯] [⚡] │
├─────────────────────────────────────────┤
│ ▓▓▓▓▓ ▒▒ ▓▓▓  ▓  ▒▒▒▓▓▓              │  waterfall 48pt
│ ████████░░░░░░░░░░░░  5/15  RX          │  cycle bar
├─────────────────────────────────────────┤
│ ┌─ FT8ConversationCard ──────────────┐  │  slides in when active
│ └────────────────────────────────────┘  │
├─────────────────────────────────────────┤
│ DIRECTED AT YOU (1)                     │
│ CALLING CQ (14)                         │
│ ▸ ALL ACTIVITY (23)                     │
├─────────────────────────────────────────┤
│ [Listen]  [Call CQ ▾]         [Stop]    │
│ 3 QSOs · 🌲 3/10                        │
└─────────────────────────────────────────┘
```

### Landscape (Split-Pane — Auto)

Left pane: waterfall + conversation card + controls.
Right pane: cycle indicator + full decode list.

### Focus Mode (🎯 Toggle)

A filter, not a layout change:
- Hides all-activity section entirely
- Hides "worked before" stations from CQ list
- CQ section sorts aggressively: new entities first
- Subtle orange top border indicates active

### Mode Transitions

| Trigger | Result |
|---------|--------|
| Rotate to landscape | Auto split-pane |
| Rotate to portrait | Auto conversation |
| Tap 🎯 | Toggle focus filter |
| Start QSO | Conversation card slides in |
| QSO completes | Toast, then card dismisses |

Spring animation: `duration: 0.3, bounce: 0.0` (CW standard).

---

## Section 4: Control Bar

### Layout by State

```
Listening:
  [🎧 Listen]  [📡 Call CQ ▾]    [Stop]
  3 QSOs · 🌲 3/10

S&P Armed:
  [🎧 Listen]  [📡 Call CQ ▾]    [Stop]
  ● TX armed · W1ABC · 1387 Hz

Transmitting:
  [🎧 Listen]  [📡 CQ POTA ▾]    [Stop]
  ● TX active · W1ABC W6JSV R-12

TX Halted:
  [🎧 Listen]  [📡 Call CQ ▾]    [Stop]
  ◯ TX halted · W1ABC · tap Resume
```

### CQ Modifier Menu

Call CQ `▾` reveals:
- CQ (bare)
- CQ POTA (auto-selected if POTA session active)
- CQ DX
- CQ SOTA
- Custom...

### TX Status Indicators

- Orange dot (●): TX armed or active. Pulses during actual transmission.
- Hollow dot (◯): TX halted.
- Pulsing: opacity `0.4→1.0`, `easeInOut`, 0.8s. Respects `accessibilityReduceMotion`.

---

## Section 5: Decode List Enhancements

### Tap-to-Call Flow

Two-step inline confirmation:

```
Step 1: Tap CQ row → inline expand:
  K5KHK  FN13  -08 dB  1242 Hz
  NEW DXCC · 2,400 mi · United States
  [Call K5KHK]                    [Cancel]

Step 2: Tap [Call K5KHK] → enters S&P
```

Double-tap shortcut: second tap on same row confirms. Tap elsewhere dismisses.

For directed messages: `[Reply to K5KHK]` instead.

### Freshness Aging

| Age | Visual |
|-----|--------|
| Current cycle | Full opacity, blue left border |
| Previous cycle (15-30s) | Full opacity, no border |
| 2-3 cycles ago (30-60s) | 0.6 opacity |
| 4+ cycles ago (60s+) | Removed from CQ section, retained in All Activity |

### CQ Section Priority Sort

1. New DXCC (any band)
2. New DXCC on band
3. New grid
4. Strong signal, not worked (SNR > -10)
5. Normal unworked (by SNR desc)
6. Worked before (dimmed; hidden in focus mode)

### Enhanced Row Data

Add audio frequency: `.caption.monospacedDigit()`, secondary color.

```
Enriched:  K5KHK  FN13  -08 dB  1242 Hz   NEW DXCC · 2,400 mi
Compact:   K5KHK  FN13  -08  1242  NEW DXCC  2.4k
```

### Haptics & Alerts

| Event | Haptic |
|-------|--------|
| Directed message | `.medium` impact |
| New DXCC decoded | `.light` impact |
| QSO complete | `.success` notification |
| 10th POTA QSO | `.warning` notification |

---

## Section 6: Edge Cases

### Compound Callsigns
Match on base callsign (strip `/P`, `/M`, `/QRP`, prefix modifiers). Preserve full compound call for display and logging.

### Simultaneous CQ Callers
First-come-first-served. Other callers shown in directed section. After current QSO completes, operator can tap queued caller.

### Mid-QSO Band Change
Confirmation alert: "Abort QSO with W1ABC and switch to 40m?"

### Clock Drift
Monitor average `abs(deltaTime)` across cycle decodes. Warning banner if >0.8s.

### Audio Disconnection
Zero audio level for 3+ cycles → red dot in status pill.

### TX Without Response
S&P timeout: 4 cycles (60s). CQ timeout: 8 cycles (2 min). Show "no response" indicator after 2 silent cycles in conversation card.

### Duplicate Prevention
Key `workedCallsigns` by `callsign + band`. Show DUPE badge but allow override via inline confirm: "Call K5KHK (dupe on 20m)".

---

## File Impact

### New Files
- `Views/Logger/FT8/FT8ConversationCard.swift`
- `Views/Logger/FT8/FT8TranscriptRow.swift`
- `Views/Logger/FT8/FT8NextTXRow.swift`
- `Views/Logger/FT8/FT8TXStatusLine.swift`

### Modified Files
- `CarrierWaveCore/FT8QSOStateMachine.swift` — role tracking, R-prefix, completing state
- `CarrierWaveCore/FT8Message.swift` — rogerReport generation helper
- `Services/FT8SessionManager.swift` — TX freq, TX events, halt/resume, txState
- `Views/Logger/FT8/FT8SessionView.swift` — layout modes, focus toggle
- `Views/Logger/FT8/FT8DecodeListView.swift` — freshness, inline confirm, sort
- `Views/Logger/FT8/FT8ControlBar.swift` — CQ modifier menu, TX status line
- `Views/Logger/FT8/FT8WaterfallView.swift` — RX/TX frequency markers
- `Views/Logger/FT8/FT8EnrichedDecodeRow.swift` — audio freq display
- `Views/Logger/FT8/FT8CompactDecodeRow.swift` — audio freq display
- `Services/FT8DecodeEnricher.swift` — cycle age tracking

### Deleted Files
- `Views/Logger/FT8/FT8ActiveQSOCard.swift` — replaced by FT8ConversationCard

### Test Files
- `FT8QSOStateMachineTests.swift` — role tracking, R-prefix, completion
- `FT8IntegrationTests.swift` — end-to-end QSO flows
