# Apple Watch Companion App Design

## Overview

A watchOS companion app for Carrier Wave that provides glanceable amateur radio information in two modes:

1. **Idle mode** (no active session): Solar conditions, band openings, recent spots
2. **Logging mode** (active session): QSO count, activation progress, callsign info, session timer

Data flows from iPhone → Watch via two channels:
- **App Group UserDefaults**: Persistent snapshots (solar, spots, session, streaks) — already used by widgets
- **WatchConnectivity**: Real-time session updates during active logging (instant QSO count, callsign info)

## Architecture

### Data Flow

```
iPhone App
├── WidgetDataWriter (existing) ──→ App Group UserDefaults ──→ Watch reads on launch/refresh
├── WatchConnectivityService (new) ──→ WatchConnectivity ──→ Watch receives real-time updates
└── SolarPollingService (extend) ──→ App Group UserDefaults ──→ Watch reads solar data
```

The Watch app supports **quick session start** — users can begin a logging session from the Watch, which sends a message to the phone to start the session. QSO logging still happens on the phone; the Watch shows live progress.

### New Shared Snapshot Types

Add to WidgetDataWriter/WidgetDataReader alongside existing types:

```swift
// Solar data for Watch (written by SolarPollingService)
struct WidgetSolarSnapshot: Codable, Sendable {
    let kIndex: Double?
    let aIndex: Int?
    let solarFlux: Double?
    let sunspots: Int?
    let bandConditions: [String: WidgetBandCondition]
    let updatedAt: Date
}

struct WidgetBandCondition: Codable, Sendable {
    let day: String
    let night: String
}

// Spots for Watch (written by SpotsService)
struct WidgetSpotSnapshot: Codable, Sendable {
    let spots: [WidgetSpot]
    let updatedAt: Date
}

struct WidgetSpot: Codable, Sendable, Identifiable {
    let id: String
    let callsign: String
    let frequencyMHz: Double
    let mode: String
    let timestamp: Date
    let source: String          // "pota" or "rbn"
    let parkRef: String?        // POTA park reference
    let parkName: String?       // POTA park name
    let snr: Int?               // RBN signal-to-noise
}

// Callsign info for Watch (sent via WatchConnectivity during sessions)
struct WatchCallsignInfo: Codable, Sendable {
    let callsign: String
    let name: String?
    let emoji: String?
    let qth: String?
    let state: String?
    let country: String?
    let grid: String?
}

// Extended session data sent via WatchConnectivity
struct WatchSessionUpdate: Codable, Sendable {
    let qsoCount: Int
    let lastCallsign: String?
    let callsignInfo: WatchCallsignInfo?
    let frequency: String?
    let band: String?
    let mode: String?
    let parkReference: String?
    let parkName: String?
    let activationType: String?
    let isPaused: Bool
    let startedAt: Date?
    // Rove
    let currentStopPark: String?
    let stopNumber: Int?
    let totalStops: Int?
    let currentStopQSOs: Int?
}
```

### File Structure

```
CarrierWaveWatch/
├── CarrierWaveWatchApp.swift              # Entry point
├── ContentView.swift                       # Root: switches idle ↔ logging
├── Info.plist
├── Assets.xcassets/
├── CarrierWaveWatch.entitlements           # App Group
├── Views/
│   ├── IdleView.swift                     # Solar + spots when not logging
│   ├── SolarView.swift                    # Solar gauges and band conditions
│   ├── SpotsListView.swift               # Scrollable recent spots
│   ├── ActiveSessionView.swift            # During logging — main screen
│   └── ActivationProgressRing.swift       # POTA 10-QSO progress ring
├── Services/
│   ├── WatchSessionDelegate.swift         # WCSessionDelegate (Watch side)
│   └── SharedDataReader.swift             # Read from App Group UserDefaults
└── Complications/
    └── ComplicationViews.swift            # WidgetKit complications
```

**iPhone-side additions:**

```
CarrierWave/Services/
├── PhoneSessionDelegate.swift             # WCSessionDelegate (iPhone side)
```

## Screens

### 1. Idle View (TabView with PageTabViewStyle)

**Page 1 — Solar Conditions:**
- K-index, A-index, SFI as circular gauges (reuse existing widget gauge style)
- Band conditions grid (4 rows: 80m-40m, 30m-20m, 17m-15m, 12m-10m)
- Propagation rating text ("Good", "Fair", etc.)
- Timestamp of last update

**Page 2 — Recent Spots:**
- Scrollable list of 10–15 most recent spots
- Each row: callsign (monospaced), frequency, band badge, time ago
- POTA spots show park reference
- RBN spots show SNR
- Tapping a spot does nothing for MVP (future: deep link to phone logger)

**Page 3 — Quick Stats:**
- Current streak (days on air)
- QSOs this week / month
- Activations this month

### 2. Active Session View

When `WidgetSessionSnapshot.isActive == true` or a WatchConnectivity session update arrives, the Watch switches to the active session screen.

**Layout:**
- **Top**: Session timer (elapsed since `startedAt`) and mode badge
- **Center**: Large QSO count number. For POTA activations, show as a progress ring (X/10) that fills and then becomes a counter after 10
- **Middle**: Last callsign logged (large, monospaced) with name/QTH if callsign info available
- **Bottom**: Park reference (if POTA), frequency/band

**Rove variant**: Show current stop park + stop QSO count, small total QSO count.

### 3. Complications

Using WidgetKit (watchOS 10+):

| Family | Content |
|--------|---------|
| `accessoryCircular` | K-index gauge (reuse SolarWidgetAccessoryCircularView logic) |
| `accessoryRectangular` | K/A/SFI gauges row, or during session: "7 QSOs · US-1234" |
| `accessoryInline` | "K 2 · SFI 150" or "Logging: 7 QSOs" |
| `accessoryCorner` | K-index gauge |

Complications update via `WidgetCenter.shared.reloadTimelines()` triggered from WidgetDataWriter.

## Implementation Phases

### Phase 1: Watch Target + Full Functionality (this PR)

1. Create `CarrierWaveWatch` target (watchOS 11.0+, SwiftUI lifecycle)
2. Add App Group entitlement (`group.com.jsvana.FullDuplex`)
3. Add `WidgetSolarSnapshot` and `WidgetSpotSnapshot` types to WidgetDataWriter/Reader
4. Extend `SolarPollingService` to write solar snapshots to App Group
5. Extend `SpotsService` to write top 15 spots to App Group (filtered by user's bands/modes)
6. Implement `SharedDataReader` on Watch (reads all snapshot types from App Group)
7. Build Idle View: solar conditions + filtered spots list + quick stats
8. Build Active Session View with progress ring and callsign info
9. Add `WatchConnectivity` framework to both targets
10. Implement `PhoneSessionDelegate` on iPhone, `WatchSessionDelegate` on Watch
11. Real-time session updates (QSO count, callsign info, frequency changes)
12. Quick session start from Watch (sends start request to phone)

### Phase 2: Complications

1. Create WidgetKit complication bundle for Watch
2. Solar gauge complications (circular, rectangular, inline)
3. Active session complication (QSO count + park)
4. Timeline providers reading from App Group

### Phase 3: Polish + Haptics (future)

1. Haptic tap on QSO logged confirmation
2. Haptic tap on POTA activation threshold (10 QSOs)
3. Haptic for P2P opportunity during session
4. Haptic for spot comment received

## Technical Decisions

**watchOS minimum: 11.0** — Matches iOS 18 minimum (assumed), enables latest WidgetKit complications and SwiftUI features.

**No SwiftData on Watch** — All data comes from the phone via App Group UserDefaults snapshots. This avoids syncing a database to the Watch and keeps the Watch app lightweight.

**WatchConnectivity `sendMessage` for session updates** — Use `sendMessage(_:replyHandler:errorHandler:)` for real-time delivery when both devices are reachable. Fall back to `transferUserInfo` for guaranteed delivery when Watch app is in background.

**Shared types duplicated (not a shared framework)** — Follows the existing widget pattern where `WidgetShared`, `WidgetStreakSnapshot`, etc. are duplicated between the main app and widget extension. A shared Swift package would be cleaner but is a larger refactor for a future PR.

## Decisions

1. **watchOS minimum version**: 11.0 ✓
2. **Quick session start from Watch**: Phase 1 ✓
3. **Spot filtering on Watch**: Filtered to user's preferred bands/modes ✓
