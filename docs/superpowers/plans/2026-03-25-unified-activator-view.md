# Unified Activator View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the disconnected POTA setup wizard + sessions list with a unified activator view featuring propagation intelligence, band-aware frequency suggestions, and inline session history.

**Architecture:** The `ActivatorLayout` view becomes a two-state container: cold-start (setup row + three-column layout) and operating (existing layout with park dropdown). New propagation views wire existing CarrierWaveCore data sources (`HamQSLClient`, `DONKIClient`, `PropagationEstimator`) into CWSweep for the first time. A `FrequencySuggestionEngine` computes clear-frequency recommendations from `SpotAggregator` data and `BandPlan` segment boundaries. No data model changes needed — `LoggingSession` already supports rove park tracking via `RoveStop`.

**Tech Stack:** SwiftUI, SwiftData, CarrierWaveCore (HamQSLClient, DONKIClient, PropagationEstimator, BandPlan), CWSweep SpotAggregator

**Spec:** `docs/superpowers/specs/2026-03-25-unified-activator-view-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `CWSweep/CWSweep/Services/Propagation/PropagationService.swift` | `@MainActor @Observable` service orchestrating HamQSLClient + DONKIClient + PropagationEstimator. Single source of truth for solar data, band conditions, space weather. |
| `CWSweep/CWSweep/Services/Propagation/FrequencySuggestionEngine.swift` | Pure logic: given a band, mode, and recent spots, find the best General+ frequency. No UI dependency. |
| `CWSweep/CWSweep/Views/Activation/ColdStartView.swift` | Top-level cold-start layout: setup row + HSplitView(past activations \| center \| band map). |
| `CWSweep/CWSweep/Views/Activation/ColdStartView+SetupRow.swift` | Setup essentials row: park search, frequency, mode, callsign, equipment button, start button. |
| `CWSweep/CWSweep/Views/Activation/ColdStartView+SessionSetup.swift` | Scrollable session setup fields: equipment grid, power/grid/attendees, operators, rove toggle, notes. |
| `CWSweep/CWSweep/Views/Activation/PropagationPanelView.swift` | Solar indices bar + band conditions grid + space weather alerts. |
| `CWSweep/CWSweep/Views/Activation/BandConditionTile.swift` | Single clickable band tile with day/night condition labels. |
| `CWSweep/CWSweep/Views/Activation/SpaceWeatherView.swift` | Three DONKI status cards (geomagnetic, flares, CME). |
| `CWSweep/CWSweep/Views/Activation/VerticalBandMapView.swift` | Vertical-axis Canvas band map with spot markers, activity density, and frequency recommendation highlight. |
| `CWSweep/CWSweep/Views/Activation/FrequencySuggestionView.swift` | Card showing recommended frequency + reasoning text. |
| `CWSweep/CWSweep/Views/Activation/PastActivationsListView.swift` | Scrollable list of past sessions with qualified indicators. |
| `CWSweep/CWSweep/Views/Activation/ParkChangeDropdown.swift` | Popover for mid-session park changes: current park summary, search, visited parks. |
| `CWSweep/CWSweep/Views/Activation/SessionHistoryPopover.swift` | Toolbar popover showing past activations (reuses PastActivationsListView). |

### Modified Files

| File | Change |
|------|--------|
| `CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift` | Replace `POTASetupView` branch with `ColdStartView`. Pass propagation service. |
| `CWSweep/CWSweep/Views/Activation/ActivationHeader.swift` | Extract from `ActivatorLayout.swift`. Add park chip dropdown + history popover icon. |
| `CWSweep/CWSweep/Views/Workspace/WorkspaceView.swift` | Create and inject `PropagationService` into environment. |
| `CWSweep/CWSweep/Models/LayoutConfiguration.swift` | Remove `SidebarItem.sessions` (or gate it to non-activator roles). |
| `CWSweep/CWSweep/Views/Workspace/SidebarView.swift` | Remove sessions item from activator sidebar section. |
| `CWSweep/CWSweep/Views/Workspace/ContentAreaView.swift` | Remove or gate `.sessions` case. |
| `CWSweep/CWSweep/Views/Logger/QSOLogTableView.swift` | Add park reference column for rove sessions. |
| `CWSweep/FILE_INDEX.md` | Add new files, update modified files. |

### Files to Eventually Remove (after migration verified)

| File | Replaced By |
|------|-------------|
| `CWSweep/CWSweep/Views/Activation/POTASetupView.swift` | `ColdStartView.swift` |
| `CWSweep/CWSweep/Views/Activation/POTASetupView+Essentials.swift` | `ColdStartView+SetupRow.swift` |
| `CWSweep/CWSweep/Views/Activation/POTASetupView+FullSetup.swift` | `ColdStartView+SessionSetup.swift` |
| `CWSweep/CWSweep/Views/Activation/POTASetupView+Actions.swift` | Logic moves to `ColdStartView` |
| `CWSweep/CWSweep/Views/Sessions/SessionsListView.swift` | `PastActivationsListView` + `SessionHistoryPopover` |

---

## Tasks

### Task 1: PropagationService

**Files:**
- Create: `CWSweep/CWSweep/Services/Propagation/PropagationService.swift`

This is the data backbone for the entire feature. Wire three existing CarrierWaveCore clients into a single `@Observable` service.

- [ ] **Step 1: Create PropagationService**

```swift
// CWSweep/CWSweep/Services/Propagation/PropagationService.swift
import CarrierWaveCore
import SwiftUI

@MainActor @Observable
final class PropagationService {
    // Published state
    var solarData: HamQSLSolarData?
    var donkiEvents: [DONKIEvent] = []
    var bandEstimates: [BandPropagation] = []
    var bestBand: String?
    var mufEstimateMHz: Double?
    var isLoading = false
    var lastError: String?

    // Clients
    private let hamQSL = HamQSLClient()
    private let donki = DONKIClient()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        // Fetch solar data and DONKI events in parallel
        // Note: both clients are actors — calls cross isolation boundaries
        async let solarResult = hamQSL.fetchSolarData()
        async let donkiResult = donki.fetchActiveEvents()

        do {
            solarData = try await solarResult
        } catch {
            lastError = "Solar data unavailable"
        }

        donkiEvents = (try? await donkiResult) ?? []

        // Compute propagation estimates from solar data
        if let solar = solarData {
            let hour = Calendar.current.component(.hour, from: Date())
            let sfi = solar.solarFlux ?? 100
            bandEstimates = PropagationEstimator.estimate(
                sfi: sfi, kIndex: solar.kIndex, utcHour: hour
            )
            bestBand = PropagationEstimator.bestBand(
                sfi: sfi, kIndex: solar.kIndex, utcHour: hour
            )
            mufEstimateMHz = bandEstimates.compactMap(\.mufEstimateMHz).max()
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 3: Commit**

```
feat(cw-sweep): add PropagationService wiring HamQSL + DONKI + estimator
```

---

### Task 2: FrequencySuggestionEngine

**Files:**
- Create: `CWSweep/CWSweep/Services/Propagation/FrequencySuggestionEngine.swift`

Pure logic, no UI. Testable in isolation.

- [ ] **Step 1: Create FrequencySuggestionEngine**

```swift
// CWSweep/CWSweep/Services/Propagation/FrequencySuggestionEngine.swift
import CarrierWaveCore
import Foundation

struct FrequencySuggestion: Sendable {
    let frequencyMHz: Double
    let reason: String
}

enum FrequencySuggestionEngine {
    /// Suggest a clear frequency for activating on the given band/mode.
    /// Always uses General+ segments to maximize hunter reach.
    static func suggest(
        band: String,
        mode: String,
        recentSpotFrequencies: [Double],
        clearanceHz: Double = 500
    ) -> FrequencySuggestion? {
        // For FT8/FT4, return the standard dial frequency
        if mode == "FT8", let freq = BandPlan.ft8Frequencies[band] {
            return FrequencySuggestion(
                frequencyMHz: freq,
                reason: "Standard FT8 dial frequency"
            )
        }
        if mode == "FT4", let freq = BandPlan.ft4Frequencies[band] {
            return FrequencySuggestion(
                frequencyMHz: freq,
                reason: "Standard FT4 dial frequency"
            )
        }

        // Find General+ segments for this band and mode
        let segments = BandPlan.segments.filter { segment in
            segment.band == band
                && segment.minimumLicense != .extra
                && segment.allowsMode(mode)
        }
        guard let minFreq = segments.map(\.startMHz).min(),
              let maxFreq = segments.map(\.endMHz).max()
        else {
            return nil
        }

        // Get POTA calling frequency as fallback
        let callingFreq: Double? = switch mode {
        case "CW": BandPlan.cwCallingFrequencies[band]
        case "SSB": BandPlan.ssbCallingFrequencies[band]
        default: nil
        }

        // Filter spots to the eligible range
        let clearanceMHz = clearanceHz / 1_000_000
        let relevantSpots = recentSpotFrequencies.filter {
            $0 >= minFreq && $0 <= maxFreq
        }.sorted()

        // If no spots, suggest the middle of the range
        if relevantSpots.isEmpty {
            let mid = (minFreq + maxFreq) / 2
            return FrequencySuggestion(
                frequencyMHz: mid,
                reason: "No activity in General+ \(mode) window"
            )
        }

        // Find the largest gap between spots (including edges)
        var gaps: [(start: Double, end: Double, size: Double)] = []

        // Gap before first spot
        let firstGapStart = minFreq
        let firstGapEnd = relevantSpots[0] - clearanceMHz
        if firstGapEnd > firstGapStart {
            gaps.append((firstGapStart, firstGapEnd, firstGapEnd - firstGapStart))
        }

        // Gaps between spots
        for idx in 0 ..< relevantSpots.count - 1 {
            let gapStart = relevantSpots[idx] + clearanceMHz
            let gapEnd = relevantSpots[idx + 1] - clearanceMHz
            if gapEnd > gapStart {
                gaps.append((gapStart, gapEnd, gapEnd - gapStart))
            }
        }

        // Gap after last spot
        let lastGapStart = relevantSpots[relevantSpots.count - 1] + clearanceMHz
        let lastGapEnd = maxFreq
        if lastGapEnd > lastGapStart {
            gaps.append((lastGapStart, lastGapEnd, lastGapEnd - lastGapStart))
        }

        if let best = gaps.max(by: { $0.size < $1.size }) {
            let center = (best.start + best.end) / 2
            return FrequencySuggestion(
                frequencyMHz: center,
                reason: "Clear \(mode) window, no activity within ±\(Int(clearanceHz)) Hz"
            )
        }

        // Fallback: suggest POTA calling frequency
        if let freq = callingFreq {
            return FrequencySuggestion(
                frequencyMHz: freq,
                reason: "Busy band — standard POTA frequency"
            )
        }

        return nil
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 3: Commit**

```
feat(cw-sweep): add FrequencySuggestionEngine with General+ gap finding
```

---

### Task 3: PropagationPanelView + BandConditionTile + SpaceWeatherView

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/PropagationPanelView.swift`
- Create: `CWSweep/CWSweep/Views/Activation/BandConditionTile.swift`
- Create: `CWSweep/CWSweep/Views/Activation/SpaceWeatherView.swift`

The center column's propagation section. These are display-only views reading from `PropagationService`.

- [ ] **Step 1: Create BandConditionTile**

A single clickable tile. Receives band name, day/night conditions from HamQSL, propagation quality from PropagationEstimator, and whether it's selected/best.

```swift
// CWSweep/CWSweep/Views/Activation/BandConditionTile.swift
import CarrierWaveCore
import SwiftUI

struct BandConditionTile: View {
    let bandName: String
    let dayCondition: String
    let nightCondition: String
    let isBest: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text(bandName)
                        .font(.system(.caption, weight: .semibold))
                    if isBest {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 2) {
                    Text(dayCondition)
                        .font(.caption2)
                        .foregroundStyle(conditionColor(dayCondition))
                    Text("/")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                    Text(nightCondition)
                        .font(.caption2)
                        .foregroundStyle(conditionColor(nightCondition))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func conditionColor(_ condition: String) -> Color {
        switch condition.lowercased() {
        case "excellent": .green
        case "good": .green
        case "fair": .yellow
        case "poor": .red
        case "closed": .red
        default: .secondary
        }
    }
}
```

- [ ] **Step 2: Create SpaceWeatherView**

```swift
// CWSweep/CWSweep/Views/Activation/SpaceWeatherView.swift
import CarrierWaveCore
import SwiftUI

struct SpaceWeatherView: View {
    let events: [DONKIEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPACE WEATHER")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 8) {
                weatherCard(
                    title: "Geomagnetic",
                    status: geomagneticStatus,
                    color: geomagneticColor
                )
                weatherCard(
                    title: "Solar Flares",
                    status: flareStatus,
                    color: flareColor
                )
                weatherCard(
                    title: "CME",
                    status: cmeStatus,
                    color: cmeColor
                )
            }
        }
    }

    private func weatherCard(title: String, status: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.primary)
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // DONKIEvent is an enum with cases: .geostorm, .flare, .cme
    // Each case has associated values including summary, radioImpact, peakKp, etc.
    private var geomagneticStatus: String {
        let storms = events.compactMap { if case let .geostorm(storm) = $0 { storm } else { nil } }
        guard let latest = storms.first else { return "Quiet" }
        return "Kp \(latest.peakKp ?? 0)"
    }

    private var geomagneticColor: Color {
        let storms = events.compactMap { if case let .geostorm(storm) = $0 { storm } else { nil } }
        guard let latest = storms.first else { return .green }
        return latest.radioImpact.isMinorOrNone ? .green : (latest.radioImpact == .moderate ? .yellow : .red)
    }

    private var flareStatus: String {
        let flares = events.compactMap { if case let .flare(flare) = $0 { flare } else { nil } }
        guard let latest = flares.first else { return "None active" }
        return latest.summary
    }

    private var flareColor: Color {
        let flares = events.compactMap { if case let .flare(flare) = $0 { flare } else { nil } }
        guard let latest = flares.first else { return .green }
        return latest.radioImpact.isMinorOrNone ? .green : .yellow
    }

    private var cmeStatus: String {
        let cmes = events.compactMap { if case let .cme(cme) = $0 { cme } else { nil } }
        guard let latest = cmes.first else { return "None active" }
        return latest.summary
    }

    private var cmeColor: Color {
        let cmes = events.compactMap { if case let .cme(cme) = $0 { cme } else { nil } }
        guard let latest = cmes.first else { return .green }
        return latest.radioImpact.isMinorOrNone ? .green : .yellow
    }
}

// NOTE: The DONKIEvent enum cases and associated types need to be verified
// against the actual DONKIClient.swift source. The pattern above matches
// the expected structure — adjust property names to match actual API.
```

Full implementation follows the pattern: filter `events` by `.geostorm` / `.flare` / `.cme`, extract the most recent of each, format a summary string and severity color.

- [ ] **Step 3: Create PropagationPanelView**

Composes solar indices bar + band condition grid + space weather. The `selectedBand` binding drives the band map.

```swift
// CWSweep/CWSweep/Views/Activation/PropagationPanelView.swift
import CarrierWaveCore
import SwiftUI

struct PropagationPanelView: View {
    let propagationService: PropagationService
    @Binding var selectedBand: String?

    // Band display order
    private static let bands = [
        "160m", "80m", "40m", "30m", "20m",
        "17m", "15m", "12m", "10m", "6m",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Solar indices bar
            solarIndicesBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()

            // Band conditions grid (5x2)
            bandConditionsGrid
                .padding(14)

            Divider()

            // Space weather
            SpaceWeatherView(events: propagationService.donkiEvents)
                .padding(14)
        }
    }

    // solarIndicesBar: HStack showing SFI, K, A, SSN, MUF
    // bandConditionsGrid: LazyVGrid(columns: 5) of BandConditionTile
    // Map HamQSL band groups to individual bands, merge with PropagationEstimator quality
}
```

- [ ] **Step 4: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 5: Commit**

```
feat(cw-sweep): add propagation panel with band conditions and space weather
```

---

### Task 4: VerticalBandMapView + FrequencySuggestionView

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/VerticalBandMapView.swift`
- Create: `CWSweep/CWSweep/Views/Activation/FrequencySuggestionView.swift`

The right column. Canvas-rendered vertical band map with spots and a frequency recommendation card.

- [ ] **Step 1: Create FrequencySuggestionView**

Simple card displaying the suggestion from `FrequencySuggestionEngine`.

```swift
// CWSweep/CWSweep/Views/Activation/FrequencySuggestionView.swift
import CarrierWaveCore
import SwiftUI

struct FrequencySuggestionView: View {
    let suggestion: FrequencySuggestion?

    var body: some View {
        if let suggestion {
            VStack(alignment: .leading, spacing: 4) {
                Text("SUGGESTED FREQUENCY")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(FrequencyFormatter.format(suggestion.frequencyMHz))
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                    Text("MHz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.green.opacity(0.2))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
```

- [ ] **Step 2: Create VerticalBandMapView**

Canvas-rendered. Frequency on Y-axis, spot markers as horizontal lines, band plan regions as horizontal bands, activity density strip on left edge, suggested frequency highlighted.

Key inputs: `band: String`, `spots: [UnifiedSpot]` (filtered to band + last 30 min), `suggestion: FrequencySuggestion?`.

Uses `BandPlan.segments` to draw sub-band regions. Spots positioned by mapping frequency to Y coordinate within the band's frequency range.

Reference `RegulatedBandMapView+Canvas.swift` and `BandMapView.swift` for existing Canvas rendering patterns in CWSweep.

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 4: Commit**

```
feat(cw-sweep): add vertical band map with frequency suggestion overlay
```

---

### Task 5: PastActivationsListView

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/PastActivationsListView.swift`

Reusable list of past sessions. Used in both the cold-start left column and the session history popover.

- [ ] **Step 1: Create PastActivationsListView**

Port the session loading logic from `SessionsListView.loadSessions()` (including CloudKit dedup). Each row shows: park ref (or "Rove (N parks)"), qualified indicator (green check / red X + count), date, mode, duration.

Add right-click context menu with "Activate This Park" action that calls an `onParkSelected: (String) -> Void` callback.

Follow the existing `SessionRow` pattern for row layout but simplify — remove inline pause/end controls (those belong in `ActivationHeader` only).

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 3: Commit**

```
feat(cw-sweep): add PastActivationsListView with qualified indicators
```

---

### Task 6: ColdStartView (assembly)

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/ColdStartView.swift`
- Create: `CWSweep/CWSweep/Views/Activation/ColdStartView+SetupRow.swift`
- Create: `CWSweep/CWSweep/Views/Activation/ColdStartView+SessionSetup.swift`

Assembles all the pieces into the three-column cold-start layout.

- [ ] **Step 1: Create ColdStartView+SetupRow**

Horizontal bar: `ParkSearchField` + frequency picker (auto-filled from suggestion) + mode toggles (segmented `Picker`) + callsign label with suffix popover + gear icon + Start button.

Port `canStart` and `startDisabledReason` from `POTASetupView+Actions.swift`. Port `fullCallsign` logic from `POTASetupView+Essentials.swift`.

Add `@AppStorage` keys with `lastActivation` prefix for auto-fill persistence. On session start, call `saveDefaults()` to persist equipment/suffix choices.

- [ ] **Step 2: Create ColdStartView+SessionSetup**

Scrollable setup fields: equipment grid (2×2 `EquipmentPickerField`), power/grid/attendees row, operators chips, rove toggle, notes. Reuse `OperatorChipsView` from existing code.

**Important:** `EquipmentPickerField` is currently defined as a `private` struct inside `POTASetupView+FullSetup.swift`. Extract it to `CWSweep/CWSweep/Views/Activation/EquipmentPickerField.swift` as an `internal` struct first, so it can be used here. Also extract the `EquipmentStorage` helper and `EquipmentType` enum if they're co-located. This extraction must happen before Task 11 deletes the old file.

- [ ] **Step 3: Create ColdStartView**

Top-level assembly:

```swift
struct ColdStartView: View {
    let radioManager: RadioManager
    var onSessionStarted: ((LoggingSession) -> Void)?

    @State var selectedBand: String?
    // ... park, callsign, equipment state ...

    var body: some View {
        VStack(spacing: 0) {
            setupRow
            Divider()
            HSplitView {
                PastActivationsListView(onParkSelected: { ref in
                    parkReference = ref
                })
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)

                ScrollView {
                    VStack(spacing: 0) {
                        PropagationPanelView(
                            propagationService: propagationService,
                            selectedBand: $selectedBand
                        )
                        Divider()
                        sessionSetupSection
                    }
                }

                VStack(spacing: 0) {
                    FrequencySuggestionView(suggestion: currentSuggestion)
                    VerticalBandMapView(
                        band: selectedBand ?? bestBand,
                        spots: filteredSpots,
                        suggestion: currentSuggestion
                    )
                }
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            }
        }
        .task { await propagationService.refresh() }
    }
}
```

Wire `selectedBand` changes to recompute `currentSuggestion` via `FrequencySuggestionEngine.suggest()`. Filter `SpotAggregator` spots to the selected band + last 30 minutes.

Port `startSession()` logic from `POTASetupView+Actions.swift`.

- [ ] **Step 4: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 5: Commit**

```
feat(cw-sweep): add ColdStartView assembling propagation + setup + band map
```

---

### Task 7: ParkChangeDropdown + SessionHistoryPopover

**Files:**
- Create: `CWSweep/CWSweep/Views/Activation/ParkChangeDropdown.swift`
- Create: `CWSweep/CWSweep/Views/Activation/SessionHistoryPopover.swift`

Enhancements to the active-session operating view.

- [ ] **Step 1: Create ParkChangeDropdown**

Popover content showing:
- Current park summary (reference, name, QSO count at this park, qualified badge)
- `ParkSearchField` for searching a new park
- "This Session" list of visited parks from `session.roveStops` with per-park QSO counts

On park selection: update `session.parkReference`, add a new `RoveStop` entry. The session continues uninterrupted.

- [ ] **Step 2: Create SessionHistoryPopover**

Simple popover wrapping `PastActivationsListView` with a header. Triggered by a toolbar icon in `ActivationHeader`.

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 4: Commit**

```
feat(cw-sweep): add park change dropdown and session history popover
```

---

### Task 8: QSOLogTableView park reference column

**Files:**
- Modify: `CWSweep/CWSweep/Views/Logger/QSOLogTableView.swift`

Add park reference visibility for multi-park (rove) sessions.

- [ ] **Step 1: Add park reference column to QSOLogTableView**

When the active session has `isRove == true`, add a "Park" column to the table showing each QSO's `parkReference`. When the park changes between adjacent QSOs (sorted by timestamp), show a subtle divider row or a different background tint to visually separate park segments.

Check the existing table column pattern in `QSOLogTableView.swift` — it uses SwiftUI `Table` with `TableColumn`. Add a conditional column:

```swift
if isRoveSession {
    TableColumn("Park", value: \.parkReference.orEmpty)
        .width(min: 60, ideal: 80)
}
```

The `sessionId` is already passed in — fetch the session's `isRove` flag to decide whether to show the column.

- [ ] **Step 2: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 3: Commit**

```
feat(cw-sweep): add park reference column to QSO log for rove sessions
```

---

### Task 9: Wire into ActivatorLayout + ActivationHeader

**Files:**
- Modify: `CWSweep/CWSweep/Views/Roles/ActivatorLayout.swift`
- Modify: `CWSweep/CWSweep/Views/Workspace/WorkspaceView.swift`

Replace the old wizard flow with the new unified view.

- [ ] **Step 1: Extract ActivationHeader to its own file**

`ActivationHeader` is currently defined at the bottom of `ActivatorLayout.swift`. Move it to `CWSweep/CWSweep/Views/Activation/ActivationHeader.swift` (it's already referenced in `FILE_INDEX.md` as if it were its own file). Add the park chip (clickable, opens `ParkChangeDropdown`) and history icon (opens `SessionHistoryPopover`).

Change `parkReference` display from a static `Text` to a `Button` that presents the `ParkChangeDropdown` popover.

- [ ] **Step 2: Update ActivatorLayout**

Replace the `POTASetupView` branch:

```swift
// Before:
if activeSession != nil {
    operatingLayout
} else {
    POTASetupView(onSessionStarted: { session in ... })
}

// After:
if activeSession != nil {
    operatingLayout
} else {
    ColdStartView(radioManager: radioManager, onSessionStarted: { session in
        activationFrequencyMHz = session.frequency
        activationMode = session.mode
        Task { await loadActiveSession() }
    })
}
```

- [ ] **Step 3: Inject PropagationService in WorkspaceView**

Create `PropagationService` in `WorkspaceView` and pass it through the environment so `ColdStartView` and its children can access it.

- [ ] **Step 4: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 5: Commit**

```
feat(cw-sweep): wire ColdStartView into ActivatorLayout, extract ActivationHeader
```

---

### Task 10: Remove Sessions sidebar item

**Files:**
- Modify: `CWSweep/CWSweep/Models/LayoutConfiguration.swift`
- Modify: `CWSweep/CWSweep/Views/Workspace/SidebarView.swift`
- Modify: `CWSweep/CWSweep/Views/Workspace/ContentAreaView.swift`

- [ ] **Step 1: Remove `.sessions` from SidebarItem**

In `LayoutConfiguration.swift`, remove the `case sessions` from `SidebarItem`. Update `displayName` and `icon` switch statements. If other roles reference sessions, gate it behind a role check.

- [ ] **Step 2: Update SidebarView and ContentAreaView**

Remove references to `.sessions` in sidebar section building and content routing.

- [ ] **Step 3: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 4: Commit**

```
refactor(cw-sweep): remove Sessions sidebar item, merged into activator view
```

---

### Task 11: Clean up old wizard files + update FILE_INDEX

**Files:**
- Remove: `POTASetupView.swift`, `POTASetupView+Essentials.swift`, `POTASetupView+FullSetup.swift`, `POTASetupView+Actions.swift`
- Modify: `CWSweep/FILE_INDEX.md`

- [ ] **Step 1: Verify no remaining references to POTASetupView**

Run: `grep -r "POTASetupView" CWSweep/` — should only find the files themselves. If other files reference it, update them first.

- [ ] **Step 2: Delete old files**

Remove the four `POTASetupView` files. Keep `ParkSearchField.swift`, `OperatorChipsView.swift`, `FrequencyModePicker.swift`, `EquipmentPickerField` (in FullSetup), `RegulatedBandMapView.swift`, and `RovePlannerView.swift` — these are reused.

Note: `EquipmentPickerField` is defined in `POTASetupView+FullSetup.swift`. It needs to be extracted to its own file (or into `ColdStartView+SessionSetup.swift`) before deleting.

- [ ] **Step 3: Update FILE_INDEX.md**

Add all new files under `Views/Activation/` and `Services/Propagation/`. Remove deleted files. Update descriptions for modified files.

- [ ] **Step 4: Build to verify compilation**

Run: `cd /Users/jsvana/projects/carrier_wave && xc build`

- [ ] **Step 5: Commit**

```
refactor(cw-sweep): remove old POTASetupView wizard files, update FILE_INDEX
```

---

### Task 12: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add entry under [Unreleased]**

```markdown
### Changed
- CW Sweep: Unified activator view replaces separate setup wizard and sessions list
- CW Sweep: Propagation panel shows real-time band conditions, solar indices, and space weather
- CW Sweep: Frequency suggestion engine recommends clear General+ frequencies based on 30-min spot activity
- CW Sweep: Park change dropdown for mid-session rove park switching
- CW Sweep: Session history available via toolbar popover during operation

### Removed
- CW Sweep: Sessions sidebar item (merged into activator view)
- CW Sweep: Full-screen POTA setup wizard (replaced by inline setup row)
```

- [ ] **Step 2: Commit**

```
docs: update CHANGELOG for unified activator view
```
