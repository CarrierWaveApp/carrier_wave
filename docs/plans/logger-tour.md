# Interactive Logger Tour — Design Plan

## Overview

An interactive, guided tour of the session logger led by a tour guide character named **Les**. Unlike the existing mini tours (static page sheets), this is a **live walkthrough** where the user sees real UI with mock data, and Les narrates each step. The existing `logger` mini tour (8 static pages) would be replaced by this.

**Critical constraint:** MUST NOT write to SwiftData, call any API, trigger spots, or upload anything. Pure dry run with ephemeral mock state.

---

## Les — The Tour Guide

- Appears as a floating speech bubble anchored to the bottom of the screen
- Avatar: a small circular icon (could be an SF Symbol like `person.wave.2` or a custom asset)
- Speech bubble contains Les's narration + a "Next" / "Got it" button
- Les can point at specific UI elements via a subtle highlight or pulse animation
- Personality: friendly, concise, uses ham radio lingo naturally ("Let's get you on the air!")

### UI Component: `TourGuideBubble`

```
┌─────────────────────────────────┐
│  🧑‍🏫 Les:                        │
│  "Let's start a new session.   │
│   Tap Start to begin!"         │
│                                 │
│              [Next →]  [Skip]   │
└─────────────────────────────────┘
```

Rendered as an overlay at the bottom of LoggerView, above the tab bar. Uses `.transition(.move(edge: .bottom))` for entrance/exit.

---

## Tour Flow — Steps

The tour uses a state machine (`LoggerTourStep` enum) that drives which mock state is visible and what Les says.

### Step 1: Welcome
- **State:** Logger shown with no active session (empty state)
- **Les says:** "Hey, I'm Les — your tour guide! I'll walk you through running a POTA activation session. Nothing here is real, so don't worry about messing anything up."
- **Action:** User taps "Next"

### Step 2: Start a Session
- **State:** SessionStartSheet appears, pre-filled with mock data
- **Mock data:** Callsign "W1LES", Mode CW, Frequency 14.060
- **Les says:** "This is where you set up your session. I've filled in a callsign and frequency. You can set your mode, power, and equipment here."
- **Action:** User taps "Next" (sheet auto-advances, not interactive)

### Step 3: Pick Equipment
- **State:** SessionStartSheet scrolls/highlights the equipment section
- **Mock data:** Radio "Elecraft KX3", Antenna "EFHW 40/20/15/10", Key "CW Morse Pocket Paddle"
- **Les says:** "Add your radio, antenna, and key. These are saved with every QSO so you can track what gear works best."
- **Action:** User taps "Next"

### Step 4: Set a Park
- **State:** SessionStartSheet shows activation section with POTA selected
- **Mock data:** Park "US-0189 — Saguaro National Park", activation type POTA
- **Les says:** "Pick your activation program and park reference. Carrier Wave handles POTA, SOTA, WWFF, and AoA."
- **Action:** User taps "Next" → sheet dismisses, session "starts"

### Step 5: Active Session
- **State:** LoggerView shows an active session header with the mock session
- **Mock header:** W1LES · 14.060 CW · US-0189 · Elecraft KX3
- **Les says:** "You're on the air! The header shows your session at a glance. Tap any capsule to change it mid-session."
- **Action:** User taps "Next"

### Step 6: Log a QSO
- **State:** Callsign field auto-fills with "AJ7CM", then a mock QSO appears in the list
- **Mock QSO:** AJ7CM, RST 599/599, QTH AZ, Grid DM42
- **Les says:** "Type a callsign and press Return to log. You can also type everything at once — try 'AJ7CM 579 WA' for quick entry. Callsign info is looked up automatically."
- **Action:** User taps "Next" → more QSOs appear

### Step 7: Show More QSOs + Duplicate Warning
- **State:** 3-4 mock QSOs visible in the list, one shows a duplicate indicator
- **Mock QSOs:** AJ7CM, K5YAA (POTA P2P badge), N3FJP, AJ7CM (dupe)
- **Les says:** "QSOs stack up in your log. Park-to-park contacts get a special badge. And if you work someone twice on the same band, Carrier Wave flags the dupe."
- **Action:** User taps "Next"

### Step 8: Commands
- **State:** Callsign field shows "HELP" typed, command list overlay appears
- **Les says:** "The callsign field doubles as a command line. Type FREQ to change frequency, SPOT to self-spot, MAP to see your contacts on a map, and more."
- **Action:** User taps "Next"

### Step 9: SDR Recording
- **State:** Shows the SDR panel/indicator
- **Les says:** "If you have a WebSDR nearby, Carrier Wave can record your signal off the air. Start recording from the session setup or type SDR."
- **Action:** User taps "Next"

### Step 10: Wrap Up
- **State:** Returns to session view
- **Les says:** "That's the basics! When you're done, tap END to close your session. Your log syncs to QRZ, POTA, and LoFi automatically. 73 and good DX!"
- **Action:** User taps "Get Started" → tour ends, mock state cleared

---

## Architecture

### State Machine

```swift
enum LoggerTourStep: Int, CaseIterable {
    case welcome
    case startSession
    case pickEquipment
    case setPark
    case activeSession
    case logQSO
    case moreQSOs
    case commands
    case sdrRecording
    case wrapUp
}
```

### Tour Manager

```swift
@Observable
@MainActor
final class LoggerTourManager {
    var isActive = false
    var currentStep: LoggerTourStep = .welcome

    // Mock state for each step
    var mockSession: MockSessionData?
    var mockQSOs: [MockQSOData] = []
    var showSessionSheet: Bool { ... }
    var showCommandList: Bool { ... }

    func advance() { ... }
    func skip() { ... }
}
```

### Mock Data (NOT SwiftData)

All mock data lives in plain structs — never touches SwiftData or any persistence:

```swift
struct MockSessionData {
    let callsign = "W1LES"
    let frequency = "14.060"
    let mode = "CW"
    let park = "US-0189"
    let parkName = "Saguaro National Park"
    let radio = "Elecraft KX3"
    let antenna = "EFHW 40/20/15/10"
    let key = "CW Morse Pocket Paddle"
}

struct MockQSOData: Identifiable {
    let id = UUID()
    let callsign: String
    let rst: String
    let qth: String
    let grid: String
    let isParkToPark: Bool
    let isDuplicate: Bool
}
```

### Integration with LoggerView

Two approaches (recommend **Option A**):

**Option A: Tour Overlay** — LoggerView renders normally but with a `LoggerTourManager` injected. When the tour is active, LoggerView reads mock data from the tour manager instead of real SwiftData. The tour guide bubble overlays on top.

- Pro: User sees the real UI, learns the actual layout
- Pro: No separate view to maintain
- Con: LoggerView needs `if tourManager.isActive` branches for data sources

**Option B: Separate TourLoggerView** — A standalone view that mimics LoggerView's layout but is hardcoded to the tour flow.

- Pro: Zero risk of accidental writes
- Con: Duplicates UI, gets stale when LoggerView changes

### Replacing the Mini Tour

- Remove `case logger` from `MiniTourContent` (or keep as fallback)
- Add `case loggerInteractive` to `TourState.MiniTourID`
- On first visit to LoggerView, present the interactive tour instead of the sheet tour
- Users can replay via Settings > Debug > Reset Tours

### File Structure

```
CarrierWave/Views/Tour/
├── TourSheetView.swift            (existing — keep for other mini tours)
├── TourGuideBubble.swift          (NEW — Les's speech bubble overlay)
├── LoggerTourManager.swift        (NEW — state machine + mock data)
├── LoggerTourOverlay.swift        (NEW — overlay that wraps LoggerView)
├── LoggerTourMockData.swift       (NEW — mock structs)
└── MiniTourContent.swift          (existing — remove logger pages)
```

---

## Safety — No Writes, No Spots

The tour manager acts as a circuit breaker:

1. **LoggingSessionManager** is NOT called — `mockSession` is a plain struct, not a `LoggingSession` model
2. **No SwiftData writes** — mock QSOs are `[MockQSOData]`, not `QSO` model objects
3. **No network calls** — callsign lookup, spotting, RBN, sync all bypassed
4. **No Live Activity** — tour doesn't start a real iOS Live Activity
5. **No BLE/SDR** — radio connection and WebSDR recording not triggered
6. **LoggerView checks** `tourManager?.isActive` before any write/network path

---

## Open Questions

1. **Should the SessionStartSheet be interactive during the tour?** (User can scroll around and explore, but "Start Session" advances the tour instead of creating a real session) — or fully non-interactive (Les narrates while a snapshot is shown)?

2. **Les's visual identity** — SF Symbol only, or a small custom illustration? A cartoon ham radio operator would be charming but requires design work.

3. **Tour pacing** — auto-advance with delays, or strictly user-driven ("Next" button)? User-driven is more accessible and lets people read at their own pace.

4. **Replay** — available from Settings, or also from a "?" button in LoggerView?

5. **Should the tour show the landscape layout** if the user is in landscape, or force portrait?
