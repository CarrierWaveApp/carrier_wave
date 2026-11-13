# POTA Rove Interface Design

## What is a Rove?

A POTA rove is when an activator visits multiple parks in a single outing, making QSOs at each stop. The key constraint: **each park stop is a distinct activation** (POTA groups uploads by park reference), but the operator experiences it as one continuous outing.

## Current State

Today, a rover must:
1. Start a POTA session for Park A
2. Make QSOs
3. End session
4. Start a new POTA session for Park B (re-entering callsign, mode, frequency, equipment)
5. Repeat

This is tedious. Equipment, callsign, suffix, mode, and often frequency stay the same across stops. The rover just changes parks.

---

## Design Proposal: Rove as a Session with Park Stops

### Core Concept

A rove is a **single logging session** that contains an ordered list of **park stops**. Each stop has its own park reference(s), start time, QSO count, and optional grid square. QSOs logged while a stop is active inherit that stop's park reference.

This maps cleanly to how POTA uploads work (grouped by park reference) while giving the operator a single continuous session.

### Data Model

```
LoggingSession (existing, extended)
├── isRove: Bool (new flag)
├── parkReference → now represents the *current* stop's park(s)
└── roveStops: [RoveStop] (new, ordered list)

RoveStop (new model)
├── id: UUID
├── parkReference: String  (e.g. "US-1234" or "US-1234, US-5678" for n-fer)
├── startedAt: Date
├── endedAt: Date?
├── myGrid: String?  (GPS auto-updated per stop)
├── qsoCount: Int
└── notes: String?
```

### Session Start Flow

The existing `SessionStartSheet` gains a new toggle in the activation section:

```
┌─────────────────────────────────────┐
│  Activation                         │
│  ┌─────────┐ ┌──────┐ ┌──────┐     │
│  │  Casual  │ │ POTA │ │ SOTA │     │
│  └─────────┘ └──────┘ └──────┘     │
│                                     │
│  Park    [US-1234        🔍]        │
│          Yosemite National Park     │
│                                     │
│  ┌──────────────────────────────┐   │
│  │ 🏕 This is a rove  [toggle] │   │
│  │ Visit multiple parks in one  │   │
│  │ session. You can add stops   │   │
│  │ as you go.                   │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

The toggle only appears when activation type is POTA. When enabled, the session starts in rove mode with the entered park as the first stop.

### In-Session: The Rove Bar

When a rove session is active, a **rove progress bar** replaces the standard park chip in the session header. This is the primary new UI element.

```
┌─────────────────────────────────────────┐
│  AJ7CM/P  CW  14.060 MHz  20m    [END] │
│                                         │
│  🏕 Rove: Stop 3 of 3 · 27 QSOs total  │
│  ┌───────┐ ┌───────┐ ┌─────────────┐   │
│  │US-1234│ │US-5678│ │◉ US-9012    │   │
│  │  12Q  │ │   8Q  │ │     7Q      │   │
│  └───────┘ └───────┘ └─────────────┘   │
│                            [Next Stop →]│
└─────────────────────────────────────────┘
```

**Design details:**
- Horizontally scrolling pill strip showing all stops
- Current stop has a filled radio indicator (◉) and a slightly larger/highlighted card
- Past stops show in muted style with their QSO counts
- Tapping a past stop shows a popover with park name, time range, QSO count
- The park reference chips reuse the existing `ParkChip` component

### "Next Stop" Action

The primary rove action is **Next Stop**, accessed via:

1. **The "Next Stop →" button** in the rove bar (always visible)
2. **The POTA command** — typing `POTA` in the command input during a rove triggers the next-stop sheet instead of changing the park

This presents a **half-sheet**:

```
┌─────────────────────────────────────┐
│          Next Park Stop             │
│                                     │
│  Park    [____________      🔍]     │
│                                     │
│  Grid    [FN31pr  ] (auto-filled)   │
│                                     │
│  ☑ Post QRT spot for US-9012       │
│  ☑ Auto-spot at new park            │
│                                     │
│        [ Start Stop ]               │
│                                     │
│  ─ or ─                             │
│                                     │
│  [ Finish Rove ]                    │
└─────────────────────────────────────┘
```

When the operator taps **Start Stop**:
1. The current stop gets an `endedAt` timestamp
2. A QRT spot is optionally posted for the old park
3. A new `RoveStop` is created with the entered park
4. The session's `parkReference` is updated to the new park
5. An initial spot is optionally posted for the new park
6. The GPS grid is refreshed (if location services are available)

**Finish Rove** ends the entire session, closing the current stop and the session.

### Logger Command Integration

The existing command system (`POTA`, `FREQ`, `MODE`, etc.) integrates naturally:

| Command | Rove Behavior |
|---------|--------------|
| `POTA`  | Opens "Next Stop" sheet (instead of park edit) |
| `FREQ`  | Changes frequency (carried across stops) |
| `MODE`  | Changes mode (carried across stops) |
| `SPOT`  | Spots at current stop's park |
| `NOTE`  | Adds note tagged to current stop |
| `MAP`   | Shows all stops on map with route line |

### Session Detail / Sessions List

In the Sessions list, a rove session shows distinctly:

```
┌─────────────────────────────────────┐
│  🏕 POTA Rove · Feb 17, 2026       │
│  3 parks · 27 QSOs · 2h 45m        │
│                                     │
│  US-1234 → US-5678 → US-9012       │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━       │
│  12Q        8Q        7Q            │
└─────────────────────────────────────┘
```

The detail view shows a vertical timeline of stops:

```
  ◉ US-1234 · Yosemite NP
  │ 14:00–14:45 UTC · 12 QSOs
  │ FN31pr · 14.060 MHz
  │
  ◉ US-5678 · Sequoia NP
  │ 15:10–15:50 UTC · 8 QSOs
  │ FN32ab · 14.060 MHz
  │
  ◉ US-9012 · Kings Canyon NP
    16:05–16:35 UTC · 7 QSOs
    FN32cd · 14.060 MHz
```

### POTA Upload Behavior

Rove stops map perfectly to POTA's upload model. The existing `POTAClient+Upload` already groups QSOs by `parkReference`. Since each QSO carries its stop's park reference, uploads work without changes. Each stop becomes a separate POTA activation in their system.

### Activations View

In the POTA Activations list, rove stops appear as individual activations (grouped by park reference, as today). A subtle "Part of rove" badge links back to the full rove session for context.

### What Carries Across Stops (No Re-entry)

- Callsign (including prefix/suffix)
- Mode
- Frequency
- Power
- Equipment (radio, antenna, key, mic)
- Attendees

### What Can Change Per Stop

- Park reference(s) — required
- Grid square — auto-updated via GPS if available
- Notes

### Edge Cases

**N-fer at a rove stop:** A single stop can have multiple park references (e.g., overlapping parks). The existing multi-park `ParkEntryField` handles this in the "Next Stop" sheet.

**Going back to a previous park:** The "Next Stop" sheet shows a warning if the entered park was already a stop. It still allows it (you might return to a park), but notes it for the operator's awareness.

**Session pause/resume:** Pausing a rove pauses the current stop. Resuming picks up where you left off.

**Editing a past stop's park reference:** Available from the session detail view, in case of typos. Reuses the existing `SessionParkEditSheet`.

---

## Implementation Phases

### Phase 1: Data Model + Basic Flow
- Add `RoveStop` SwiftData model
- Extend `LoggingSession` with `isRove` flag and rove stop management
- Extend `LoggingSessionManager` with `nextStop()` and `finishRove()`
- Add rove toggle to `SessionStartSheet`

### Phase 2: In-Session UI
- Rove progress bar in session header
- "Next Stop" half-sheet
- POTA command rove integration
- Auto-spot on stop change

### Phase 3: Session Display
- Rove-specific `SessionRow` variant
- Rove timeline in `SessionDetailView`
- "Part of rove" badge in activations view

### Phase 4: Polish
- MAP command showing route between stops
- GPS grid auto-update on stop change
- Rove share card variant
- Rove statistics (parks/hour, distance covered)
