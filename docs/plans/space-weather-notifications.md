# Space Weather Notifications — Implementation Plan

## Overview

Add DONKI (NASA Space Weather Database) integration to surface space weather events that affect HF radio conditions. Two user-facing features:

1. **Local notifications** for incoming events (GST, FLR, CME)
2. **In-app condition flash/banner** when active events are degrading propagation

## API

**Base URL:** `https://kauai.ccmc.gsfc.nasa.gov/DONKI/WS/get/`

Three event-specific endpoints (JSON arrays, no auth required):

| Endpoint | Key Fields | Radio Impact |
|----------|-----------|--------------|
| `GST?startDate=&endDate=` | `gstID`, `startTime`, `allKpIndex[].KpIndex`, `link` | HF blackouts, auroral absorption |
| `FLR?startDate=&endDate=` | `flrID`, `beginTime`, `peakTime`, `classType` (M1.0, X2.1…), `link` | Sudden ionospheric disturbance |
| `CME?startDate=&endDate=` | `activityID`, `startTime`, `cmeAnalyses[].speed`, `link` | GST in 1-3 days (advance warning) |

Dates: `yyyy-MM-dd` UTC. Default range: 30 days back. No API key needed (DEMO_KEY rate-limited but sufficient for hourly polls).

## Architecture

### New Files

| File | Location | Purpose |
|------|----------|---------|
| `DONKIClient.swift` | `CarrierWaveCore/Sources/CarrierWaveCore/` | Actor — fetch & parse GST/FLR/CME JSON |
| `DONKIPollingService.swift` | `CarrierWave/Services/` | @MainActor @Observable singleton — poll every 30 min, track active events |
| `SpaceWeatherNotifier.swift` | `CarrierWave/Services/` | @MainActor @Observable — toast + local notifications for new events |
| `SpaceWeatherBannerView.swift` | `CarrierWave/Views/Logger/` | Compact flash banner for active storm/flare overlay |

### Modified Files

| File | Change |
|------|--------|
| `LoggerDetailSettingsView.swift` | Add "Space weather alerts" toggle to Conditions section |
| `CarrierWaveApp.swift` | Start DONKIPollingService in `.task` block |
| `LoggerToastView.swift` | Add `spaceWeather` toast type (orange/red icon) |
| `SolarPanelView.swift` | Show active DONKI events below existing solar data |
| `FILE_INDEX.md` | Add new file entries |
| `CHANGELOG.md` | Add entry under [Unreleased] |

## Step-by-Step

### Step 1: DONKIClient (CarrierWaveCore)

Create `public actor DONKIClient` following `HamQSLClient` pattern:

- **Models** (all `public struct … : Sendable, Codable`):
  - `DONKIGeostorm`: `gstID`, `startTime`, `allKpIndex: [KpObservation]`, `link`
    - `KpObservation`: `observedTime`, `kpIndex: Double`, `source`
  - `DONKIFlare`: `flrID`, `beginTime`, `peakTime`, `endTime`, `classType`, `sourceLocation`, `link`
  - `DONKICME`: `activityID`, `startTime`, `sourceLocation`, `link`, `cmeAnalyses: [CMEAnalysis]?`
    - `CMEAnalysis`: `speed`, `halfAngle`, `type`
  - `DONKIEvent` enum unifying the three, with computed `radioImpact: RadioImpactLevel` (.none, .minor, .moderate, .severe, .extreme) and `eventID: String`

- **Severity mapping** (pure logic, testable):
  - Flare: M-class → moderate, X-class → severe/extreme
  - GST: Kp 5 → moderate, Kp 7 → severe, Kp 8+ → extreme
  - CME: speed > 1000 km/s → moderate, > 1500 → severe

- **Fetch methods**: `fetchGeostorms(startDate:endDate:)`, `fetchFlares(…)`, `fetchCMEs(…)`
  - 30-minute cache (similar to HamQSL 15-min)
  - URLSession with 15s timeout, User-Agent header
  - Parse ISO 8601 dates from DONKI format (`yyyy-MM-dd'T'HH:mm:ssZ`)
  - Return empty arrays on error (never crash polling)

- **Convenience**: `fetchActiveEvents(lookbackDays: Int = 3) -> [DONKIEvent]`
  - Combines all three endpoints, sorted by time descending
  - Filters to events within lookback window

### Step 2: DONKIPollingService

`@MainActor @Observable` singleton following `SolarPollingService` pattern:

- **Published state**: `activeEvents: [DONKIEvent]`, `worstActiveImpact: RadioImpactLevel`
- **Settings key**: `"spaceWeatherAlertsEnabled"` (default: true)
- **Poll interval**: 1800s (30 min) — DONKI updates ~hourly
- **Poll loop**: Same `Task.sleep` + cancellation pattern as SolarPollingService
- **On each poll**: Fetch active events, diff against previous, notify `SpaceWeatherNotifier` of new events
- **Configure**: Accept `ModelContainer` (for future persistence), start in CarrierWaveApp `.task`

### Step 3: SpaceWeatherNotifier

`@MainActor @Observable` following `FriendSpotNotifier` pattern:

- **Cooldown**: Per event ID, 6-hour cooldown (events don't change rapidly)
- **On new event**:
  - Fire toast via `ToastManager.shared.show(.spaceWeather, message:)`
  - Fire local notification: "Solar Flare (X2.1) — HF conditions may degrade"
  - Category/identifier: `spaceWeather-{eventID}`
- **Severity threshold**: Only notify for `.moderate` and above (skip minor Kp=5 storms, C-class flares)
- **Budget**: Simple daily cap of 10 notifications (space weather events are infrequent)

### Step 4: Toast Type

Add to `ToastType` enum in `LoggerToastView.swift`:
- `case spaceWeather` — red/orange color, `exclamationmark.triangle.fill` icon

### Step 5: Space Weather Banner

`SpaceWeatherBannerView` — compact overlay shown in logger when `worstActiveImpact >= .moderate`:

- Horizontal bar: icon + "Storm Active — HF degraded" + severity color
- Background: orange (moderate), red (severe/extreme) with subtle pulse animation
- Tap to expand → show active events list with type, time, severity
- Tap event → open `link` URL in SFSafariViewController or sheet
- Placed in logger view stack (above the QSO entry area, below toolbar)
- Auto-hides when no active events exceed threshold

### Step 6: SolarPanelView Enhancement

Add a "Space Weather Alerts" section below existing solar indices:
- List active DONKI events (icon per type, severity badge, time)
- "No active alerts" when empty
- Link to DONKI dashboard

### Step 7: Settings

In `LoggerDetailSettingsView.swift` conditionsSection, add:
```swift
Toggle("Space weather alerts", isOn: $spaceWeatherAlertsEnabled)
    .onChange(of: spaceWeatherAlertsEnabled) {
        DONKIPollingService.shared.startIfEnabled()
    }
```

Footer update to mention space weather alerts.

### Step 8: App Startup

In `CarrierWaveApp.swift` `.task` block, after solar polling:
```swift
DONKIPollingService.shared.configure(container: sharedModelContainer)
profiler.record("donkiPolling.configured")
```

### Step 9: Update Indexes

- `FILE_INDEX.md`: Add all new files
- `CHANGELOG.md`: Add under `### Added`

## Design Decisions

1. **Separate from SolarPollingService** — DONKI is a different data source with different cadence. Keeps services focused.
2. **No SwiftData persistence** — Active events are transient (3-day lookback). No need to store history. Keeps it simple; can add later if charting is desired.
3. **CarrierWaveCore for client** — Same pattern as HamQSLClient. Testable without iOS.
4. **Banner vs. badge** — Banner is more visible for a safety-relevant feature (missed alerts = wasted operating time). Can be refined to badge later if users find it too prominent.
5. **30-min polling** — Balances freshness with API courtesy. DONKI has no rate limit docs but ~2 req/hour is very conservative.
6. **No API key initially** — DONKI endpoints work without auth. Can add NASA API key support later if rate-limited.

## Out of Scope (Future)

- CME arrival time predictions (requires ENLIL model data)
- Push notifications via backend server
- Historical space weather charting
- Widget integration for space weather
- Watch complication for active storms
