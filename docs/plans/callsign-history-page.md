# Callsign History Page

## Overview

A unified scrollable page for any callsign — replacing `FriendProfileView`. Shows everything we know about our history with a station: identity, friendship, QSOs (with inline recording clips), full recordings, band/mode breakdown, map, activity feed, and notes.

## Entry Points

- Tap callsign in QSO list / QSODetailView
- Tap callsign in logger (LoggerCallsignCard)
- Tap callsign in CW transcript
- Tap friend in friends list
- Tap callsign in dashboard lookup card
- Tap callsign anywhere else it appears as a link

All callsign taps across the app should navigate to this view.

## View: `CallsignHistoryView`

**Replaces:** `FriendProfileView`
**Navigation:** Pushed view (full screen, supports deep navigation)
**File:** `CarrierWave/Views/Callsign/CallsignHistoryView.swift`

### Data Loading

Per performance rules — no `@Query`. Use `@State` + `FetchDescriptor` in `.task`.

```swift
struct CallsignHistoryView: View {
    let callsign: String

    @State private var qsos: [QSO] = []
    @State private var friendship: Friendship?
    @State private var callsignInfo: CallsignInfo?
    @State private var tuneInRecordings: [WebSDRRecording] = []        // They were the spot target
    @State private var sessionRecordings: [RecordingWithSegments] = []  // Our recordings with them detected
    @State private var activityItems: [ActivityItem] = []
    @State private var isLoading = true
}
```

Load all data in `.task` on a background context:
1. Fetch QSOs where `callsign == targetCallsign` (excluding metadata modes), sorted by date desc
2. Fetch Friendship where `friendCallsign == targetCallsign`
3. Lookup callsign info via `CallsignLookupService`
4. Fetch WebSDRRecordings where `spotCallsign == targetCallsign` (Tune In recordings)
5. For each QSO that has a `loggingSessionId`, check if that session has a recording + transcript with a `DetectedQSORange` matching this callsign → build `RecordingWithSegments` list
6. Fetch ActivityItems if friendship is accepted

### Sections (conditional — hide when empty)

---

### 1. Header Card

Identity + relationship.

```
┌─────────────────────────────────────┐
│         ┌──────┐                    │
│         │  W1  │  (initials/avatar) │
│         └──────┘                    │
│        W1AW  🇺🇸                    │
│      John Smith                     │
│   Newington, CT · FN31pr            │
│   ┌──────┐ ┌─────────┐             │
│   │ Extra │ │ ARRL    │   (badges)  │
│   └──────┘ └─────────┘             │
│                                     │
│   👋 Friends since Mar 15, 2025    │
│        — or —                       │
│   ┌──────────────────────┐          │
│   │  Add Friend           │         │
│   └──────────────────────┘          │
└─────────────────────────────────────┘
```

- Callsign (monospaced, large, bold) + country flag
- Name from callsign info (displayName)
- Location: QTH, state + grid
- License class badge, club membership badges
- Polo notes emoji
- Friendship status: "Friends since [date]" if accepted, "Friend request pending" if pending, "Add Friend" button if not friends but user is on Carrier Wave (has activities API account)
- Source indicator (QRZ / HamDB / Polo)

---

### 2. Stats Row

3-column grid with key metrics.

```
┌───────────┬───────────┬───────────┐
│     12    │     4     │  2h 15m   │
│   QSOs    │  Bands    │ Recorded  │
└───────────┴───────────┴───────────┘
```

- **QSOs**: Total contacts (excluding metadata modes)
- **Bands**: Unique bands worked
- **Recorded**: Total recording time involving this callsign (both Tune In + detected segments)

---

### 3. Map Pin

Small map showing the other station's location.

```
┌─────────────────────────────────────┐
│  ┌─────────────────────────────┐    │
│  │         🗺️ Map              │    │
│  │     📍 FN31pr               │    │
│  │                             │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│  ~1,200 mi · 45° NE from you       │
└─────────────────────────────────────┘
```

- `Map` view with annotation at their grid square center
- Distance and bearing from user's grid shown below
- Compact height (~150pt)
- Only shown if grid or lat/lon is known

---

### 4. Band/Mode Breakdown

Visual chart of how you've worked them.

```
┌─────────────────────────────────────┐
│ Band/Mode Breakdown                 │
├─────────────────────────────────────┤
│  20m  ████████████░░░  8  CW(5) SSB(3)
│  40m  █████░░░░░░░░░░  3  CW(2) FT8(1)
│  10m  ██░░░░░░░░░░░░░  1  FT8(1)
└─────────────────────────────────────┘
```

- Horizontal bar chart, one row per band
- Bar fill proportional to QSO count
- Mode breakdown as trailing capsule badges with counts
- Sorted by QSO count descending
- Only shown if 2+ QSOs

---

### 5. QSO Timeline

Chronological history, newest first. **This is the core section.**

```
┌─────────────────────────────────────┐
│ QSO History                  See All│
├─────────────────────────────────────┤
│ Mar 8, 2026 · 14:32 UTC            │
│ ┌────┐ ┌──┐  14.060 MHz            │
│ │ 20m│ │CW│  599/599               │
│ └────┘ └──┘  🌿 K-1234             │
│ ┌─ 🎙 0:45–2:12 ─────────────── ▶ │ ← recording clip
│ └───────────────────────────────────│
├─────────────────────────────────────┤
│ Feb 12, 2026 · 20:15 UTC           │
│ ┌────┐ ┌───┐  7.250 MHz            │
│ │ 40m│ │SSB│  59/57                 │
│ └────┘ └───┘                        │
├─────────────────────────────────────┤
│ Jan 3, 2026 · 03:45 UTC            │
│ ┌────┐ ┌───┐  28.074 MHz           │
│ │ 10m│ │FT8│  -12/-08              │
│ └────┘ └───┘                        │
└─────────────────────────────────────┘
```

**Each QSO row shows:**
- Date + UTC time
- Band badge + mode badge
- Frequency (monospaced)
- RST sent/received
- Park reference if POTA
- Service sync status indicators (✓ QRZ, ✓ LoTW, etc.)
- **Inline recording clip** if this QSO has a matching `DetectedQSORange` in a session recording

**Recording clip inline:**
- Small bar showing the segment time range (start–end offset)
- Play button to listen to just that segment
- Tap to expand into the full recording/transcript view, scrolled to that QSO's position

**Shows last 5 by default.** "See All" navigates to a filtered log view showing all QSOs with this callsign.

Each row taps into `QSODetailView`.

---

### 6. Tune In Recordings

Recordings where the user tuned in to listen to this station's activation (via spots).

```
┌─────────────────────────────────────┐
│ 🎙 Tune In Recordings               │
├─────────────────────────────────────┤
│ Mar 8, 2026 · 14.060 MHz CW        │
│ KiwiSDR: W3LPL · 12:45 duration    │
│ 🌿 K-1234 Blue Ridge Parkway       │
│ ┌─▓▓▓▓░░▓▓▓▓▓░░▓▓──────────┐      │
│ └────────────────────────────┘      │
│ 3 segments · 2 QSOs detected   →   │
├─────────────────────────────────────┤
│ Feb 12, 2026 · 7.250 MHz SSB       │
│ KiwiSDR: K1JT · 8:20 duration      │
│ ┌─▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓─────────┐      │
│ └────────────────────────────┘      │
│ 1 segment                       →   │
└─────────────────────────────────────┘
```

- `WebSDRRecording` where `spotCallsign == callsign`
- Shows: date, frequency/mode, KiwiSDR name, duration, park info
- Segment visualization bar (filled = active, gap = silence)
- Detected QSO count from transcript
- Tap opens the full recording player/transcript view
- Only shown if Tune In recordings exist

---

### 7. Activity Feed (friends only)

```
┌─────────────────────────────────────┐
│ Activity                            │
├─────────────────────────────────────┤
│ 🌿 Activated K-1234 · 23 QSOs      │
│    Mar 7, 2026                      │
├─────────────────────────────────────┤
│ 🌿 Activated K-5678 · 45 QSOs      │
│    Feb 28, 2026                     │
│                              See All│
└─────────────────────────────────────┘
```

- Only visible when friendship is accepted
- Reuses existing `ActivityItemRow`
- Last 5, "See All" for full list

---

### 8. Notes

```
┌─────────────────────────────────────┐
│ Notes                         Edit  │
├─────────────────────────────────────┤
│ Great CW operator, always strong    │
│ signal. Met at Dayton 2024.         │
└─────────────────────────────────────┘
```

- Polo notes for this callsign
- Edit button opens note editing
- If no notes, show "Add a note" link

---

## Inline Recording Clips on QSO Cards (Cross-Cutting Feature)

This feature applies **everywhere a QSO card is shown**, not just the history page:

### How it works

1. A QSO has a `loggingSessionId`
2. That session may have a `WebSDRRecording` (via `loggingSessionId` match)
3. That recording may have a transcript with `DetectedQSORange` entries
4. If a `DetectedQSORange.callsign` matches the QSO's callsign AND `DetectedQSORange.loggedQSOId` matches the QSO's id (or callsign + time proximity), we have a clip

### Data type

```swift
struct QSORecordingClip: Sendable {
    let recording: WebSDRRecording  // or just the ID + file URL
    let startOffset: TimeInterval   // from DetectedQSORange.startOffset
    let endOffset: TimeInterval     // from DetectedQSORange.endOffset
    let recordingId: UUID
}
```

### Where to show inline clips

- **CallsignHistoryView** QSO timeline rows
- **QSODetailView** — add a "Recording" section with playable clip
- **Logger** — after logging a QSO, if recording is active, the logged QSO card could show "Recorded" indicator

### Clip UI

Compact inline player:
```
┌─ 🎙 0:45 – 2:12 ──────────────── ▶ ┐
└──────────────────────────────────────┘
```
- Time range label
- Play/pause button
- Tap anywhere else opens full transcript view scrolled to this QSO

---

## File Structure

```
CarrierWave/Views/Callsign/
├── CallsignHistoryView.swift          # Main page (ScrollView + sections)
├── CallsignHistoryHeader.swift        # Header card with identity + friend status
├── CallsignStatsRow.swift             # 3-column stats grid
├── CallsignMapSection.swift           # Map pin with distance/bearing
├── CallsignBandModeChart.swift        # Band/mode horizontal bar chart
├── CallsignQSOTimeline.swift          # QSO list with inline clips
├── CallsignQSORow.swift               # Individual QSO row (reusable)
├── CallsignTuneInRecordings.swift     # Tune In recordings section
├── CallsignActivitySection.swift      # Friend activity feed
├── CallsignNotesSection.swift         # Notes display + edit
├── QSORecordingClipView.swift         # Inline recording clip player (reusable)
└── QSORecordingClipLoader.swift       # Service to find clips for QSOs
```

## Implementation Order

1. **CallsignHistoryView** — scaffold with section structure, data loading
2. **Header** — identity card with friend button
3. **Stats row** — computed from QSOs
4. **QSO timeline** — compact rows with navigation to QSODetailView
5. **QSORecordingClipLoader** — service to find recording clips for QSOs
6. **QSORecordingClipView** — inline player widget
7. **Wire clips into QSO timeline rows**
8. **Tune In recordings section**
9. **Band/mode chart**
10. **Map section**
11. **Activity section** (migrate from FriendProfileView)
12. **Notes section**
13. **Wire up navigation** — replace all callsign taps app-wide
14. **Add clips to QSODetailView and logger**
15. **Remove FriendProfileView**, update all references

## Design Tokens

Per design-language.md:
- Callsign text: `.monospaced()`, bold
- Section backgrounds: `Color(.secondarySystemBackground)`, 12pt corner radius
- Badge capsules: small, colored by type
- Spacing: 24pt between sections, 12pt within
- Stats cards: match existing `StatCard` pattern
- Map: `Map` with `MKCoordinateRegion`, 150pt height
