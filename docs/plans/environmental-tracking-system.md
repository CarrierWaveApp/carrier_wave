# Environmental Tracking System

**Date:** 2026-02-14
**Status:** Design

## Problem

Currently, solar and weather conditions are recorded **once at session start** as flat fields on `LoggingSession` and `ActivationMetadata`. This gives a single snapshot but misses how conditions change during an activation — K-index can shift, weather can change, and operators have no way to correlate propagation changes with QSO success over time.

## Goals

1. **Time-series recording**: Sample solar and weather conditions every 10 minutes during active logging sessions and activity log sessions
2. **Historical graphing**: Chart conditions over time (within a session, across sessions, over days/weeks)
3. **Location-aware analysis**: View conditions by grid square / geographic region
4. **Correlate with QSOs**: Overlay condition trends with QSO rate to surface propagation insights

## Design

### 1. New Data Model: `EnvironmentalSample`

A new SwiftData model that stores individual time-series data points.

```swift
@Model
final class EnvironmentalSample {
    var id: UUID
    var timestamp: Date

    // Location context
    var gridSquare: String?       // 4- or 6-char Maidenhead grid
    var latitude: Double?         // For map plotting
    var longitude: Double?

    // Session linkage
    var sessionId: UUID?          // Links to LoggingSession.id
    var activityLogDate: Date?    // Links to ActivityLog date (for hunter sessions)

    // Solar fields (from HamQSL)
    var solarKIndex: Double?
    var solarFlux: Double?
    var solarSunspots: Int?
    var solarPropagationRating: String?   // "Excellent", "Good", "Fair", "Poor", "Very Poor"

    // Weather fields (from NOAA)
    var weatherTemperatureF: Double?
    var weatherTemperatureC: Double?
    var weatherHumidity: Int?
    var weatherWindSpeed: Double?
    var weatherWindDirection: String?
    var weatherDescription: String?
}
```

**Key decisions:**
- Flat model, no relationships — keeps it simple and avoids SwiftData relationship pitfalls
- `sessionId` / `activityLogDate` are optional UUIDs/dates, not SwiftData relationships, so samples can outlive sessions
- Grid square + lat/lon enables both text-based filtering and map plotting
- One row per sample covers both solar and weather (they're fetched together and logically paired)

**Storage estimate:** ~20 fields × ~6 samples/hour × 4 hours/session = ~24 rows per session. At 500 bytes/row, a year of weekly activations produces ~600 KB. Negligible.

### 2. Background Polling Service: `EnvironmentalMonitor`

A `@MainActor @Observable` service that polls on a timer during active sessions.

```swift
@MainActor @Observable
final class EnvironmentalMonitor {
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 10 * 60  // 10 minutes
    private let noaaClient = NOAAClient()

    func startMonitoring(sessionId: UUID, grid: String?, modelContext: ModelContext)
    func stopMonitoring()

    // Called on timer tick and at session start
    private func recordSample() async
}
```

**Integration points:**
- `LoggingSessionManager.startSession()` → calls `environmentalMonitor.startMonitoring()`
- `LoggingSessionManager.endSession()` → calls `environmentalMonitor.stopMonitoring()`
- `ActivityLogManager` (hunter workflow) → same start/stop pattern
- First sample recorded immediately on start (replaces current `recordConditions()` behavior)

**Relationship to existing `recordConditions()`:**
- The initial sample **also** writes to the flat fields on `LoggingSession` and `ActivationMetadata` for backward compatibility (existing UI reads those fields)
- Over time, the flat fields become a denormalized cache of the first sample; the time-series is the source of truth

**Timer behavior:**
- Uses `Timer.scheduledTimer` (same pattern as `autoSpotTimer`)
- Timer fires every 10 minutes; on each tick, fetches solar + weather and writes an `EnvironmentalSample`
- Respects `autoRecordConditions` UserDefaults setting
- If fetch fails (network error), skip that sample silently — don't retry or backfill

### 3. Querying and Snapshots

All chart data loading happens on a background actor to avoid blocking the UI (per performance rules).

```swift
actor EnvironmentalDataActor {
    func samplesForSession(
        sessionId: UUID,
        container: ModelContainer
    ) async throws -> [EnvironmentalSnapshot]

    func samplesForDateRange(
        from: Date, to: Date,
        grid: String?,
        container: ModelContainer
    ) async throws -> [EnvironmentalSnapshot]

    func samplesGroupedByGrid(
        from: Date, to: Date,
        container: ModelContainer
    ) async throws -> [String: [EnvironmentalSnapshot]]
}
```

`EnvironmentalSnapshot` is a `Sendable` struct mirroring the model fields — fetched on the actor, then sent to the main thread for charting.

### 4. Chart Views

Using Swift Charts for all visualizations.

#### 4a. Session Conditions Timeline (`SessionConditionsChartView`)

Shown on the session detail view and activation detail view. Plots conditions over the duration of a single session.

```
┌─────────────────────────────────────┐
│  K-Index        ●───●───●───●       │
│  2.0 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │
│  1.0            ●               ●   │
│       14:00  14:10  14:20  14:30    │
├─────────────────────────────────────┤
│  SFI                                │
│  120  ●───●───●───●───●───●         │
│       14:00  14:10  14:20  14:30    │
├─────────────────────────────────────┤
│  Temperature                        │
│  72°F ●───●───●───●                 │
│  68°F                 ●───●         │
│       14:00  14:10  14:20  14:30    │
└─────────────────────────────────────┘
```

**Layout:** Stacked line charts, one per metric. Tappable to see exact values. Optional QSO rate overlay (bar chart behind the line).

**Picker:** Segmented control to switch between Solar / Weather / Combined view.

#### 4b. Historical Trends (`ConditionsHistoryChartView`)

Accessed from the dashboard or a new "Conditions" section. Shows conditions over days/weeks.

```
┌─────────────────────────────────────┐
│  K-Index (last 30 days)             │
│  4 ┤        ■                       │
│  3 ┤     ■  ■  ■                    │
│  2 ┤  ■  ■  ■  ■  ■     ■          │
│  1 ┤  ■  ■  ■  ■  ■  ■  ■  ■      │
│    └──────────────────────────       │
│     Feb 1                Feb 14     │
└─────────────────────────────────────┘
```

**Aggregation:** When viewing > 1 day, samples are averaged per day. Chart shows min/max range band with average line.

**Filters:** Date range picker (7d / 30d / 90d / custom), metric selector.

#### 4c. Location Comparison (`ConditionsByLocationView`)

Groups samples by grid square (4-char) and shows side-by-side or overlaid charts.

```
┌─────────────────────────────────────┐
│  Average K-Index by Location        │
│                                     │
│  FN31  ████████  2.1                │
│  EM85  ██████    1.8                │
│  DN70  ████████████  2.8            │
│                                     │
│  Temperature Range by Location      │
│  FN31  ───[====●====]───  45-72°F   │
│  EM85  ─────[==●==]─────  62-78°F   │
└─────────────────────────────────────┘
```

This view is most useful for operators who activate from multiple locations and want to compare typical conditions.

### 5. Navigation & UI Integration

#### Where charts appear:

| Location | Chart | Trigger |
|----------|-------|---------|
| **Session Detail View** | Session timeline | New section below equipment/photos |
| **Activation Detail View** | Session timeline | New section (same component, filters by session) |
| **Logger panels** | Current + trend mini-chart | Enhance existing SolarPanelView/WeatherPanelView |
| **Dashboard** | Historical trends card | New tappable stat box → drilldown |
| **Conditions tab/section** | Full history + location | New view accessible from dashboard or settings |

#### Logger panel enhancement:

The existing `SolarPanelView` and `WeatherPanelView` gain a small sparkline showing the last few samples from the current session. This gives operators instant visual feedback on whether conditions are trending better or worse.

```
┌─────────────────────────────────────┐
│  ☀ Solar Conditions         ↻  ✕   │
│─────────────────────────────────────│
│  ● Good Propagation                │
│  K: 2.1  │  SFI: 142  │  SSN: 98  │
│                                     │
│  Session trend:  ╱─╲_╱─   (stable) │
│  ▪ 5 samples over 40 min           │
└─────────────────────────────────────┘
```

### 6. Activity Log Integration

The `ActivityLogManager` (hunter workflow) also starts/stops the environmental monitor. Samples are linked via `activityLogDate` instead of `sessionId`.

This enables hunters to see how conditions changed during a day of hunting, correlated with which spots they worked.

### 7. Data Lifecycle

- **Retention:** Keep all samples indefinitely (storage is negligible)
- **iCloud sync:** `EnvironmentalSample` is part of the SwiftData container, so it syncs via iCloud like other models
- **Export:** Include conditions timeline in ADIF export as COMMENT fields (optional, user-controlled)
- **Migration:** No migration needed — new model, additive schema change. Existing flat fields on `LoggingSession` / `ActivationMetadata` remain untouched

### 8. Implementation Plan

#### Phase 1: Data Model + Polling (core infrastructure)
1. Create `EnvironmentalSample` SwiftData model
2. Create `EnvironmentalSnapshot` Sendable struct
3. Create `EnvironmentalMonitor` service with timer-based polling
4. Integrate into `LoggingSessionManager` start/end flow
5. Integrate into `ActivityLogManager` start/end flow
6. Write initial sample to flat fields for backward compat
7. Add model to SwiftData container schema
8. Unit tests for monitor lifecycle, sample creation

#### Phase 2: Session Charts
1. Create `EnvironmentalDataActor` for background data loading
2. Create `SessionConditionsChartView` with Swift Charts
3. Add chart section to `SessionDetailView`
4. Add chart section to `POTAActivationDetailView`
5. Add sparkline to `SolarPanelView` and `WeatherPanelView`

#### Phase 3: Historical Charts + Location
1. Create `ConditionsHistoryChartView` with date range filtering
2. Create `ConditionsByLocationView` with grid grouping
3. Add dashboard stat box for conditions trends
4. Add navigation from dashboard to full history view

#### Phase 4: QSO Correlation
1. Overlay QSO rate on session conditions chart
2. Add "best conditions" insight (which K-index/SFI correlated with highest QSO rate)
3. Optional: propagation prediction based on historical patterns

### 9. Files to Create

| File | Purpose |
|------|---------|
| `CarrierWave/Models/EnvironmentalSample.swift` | SwiftData time-series model |
| `CarrierWave/Services/EnvironmentalMonitor.swift` | Timer-based polling service |
| `CarrierWave/Services/EnvironmentalDataActor.swift` | Background data loading actor |
| `CarrierWave/Services/EnvironmentalSnapshot.swift` | Sendable snapshot struct |
| `CarrierWave/Views/Conditions/SessionConditionsChartView.swift` | Per-session chart |
| `CarrierWave/Views/Conditions/ConditionsHistoryChartView.swift` | Historical trends |
| `CarrierWave/Views/Conditions/ConditionsByLocationView.swift` | Location comparison |
| `CarrierWaveTests/EnvironmentalMonitorTests.swift` | Monitor lifecycle tests |
| `CarrierWaveTests/EnvironmentalDataActorTests.swift` | Data loading tests |

### 10. Open Questions

1. **10-minute interval**: Is this the right cadence? Solar data from HamQSL updates ~every 3 hours, so more frequent solar polling won't yield new data. Weather changes faster. We could poll weather every 10 min but solar every 30 min to reduce API load.

2. **Battery impact**: Timer-based polling on a 10-minute interval is negligible for battery. The actual network requests are lightweight (small XML/JSON). No GPS needed since we use the session's grid square.

3. **Offline handling**: If the device loses connectivity during a session, we skip that sample. We don't backfill — gaps in the timeline are acceptable and even informative (they show connectivity issues during field operations).

4. **Existing `ConditionsBackfillService`**: This one-time migration service parses text solar/weather into structured fields on ActivationMetadata. It doesn't need changes — it operates on a different data path.
