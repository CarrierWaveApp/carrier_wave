# Configurable Dashboard Metrics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the hardcoded "Streaks" dashboard card with a configurable metrics card where users pick 1-2 metrics from a catalog of streak and count metrics via Settings.

**Architecture:** New `DashboardMetricType` enum defines all available metrics with display properties. `StatsComputationActor` is extended to compute all metrics on its background thread, storing results in `ComputedStats`. `AsyncQSOStatistics` exposes the computed values. A new `MetricsCard` replaces `StreaksCard`, reading the user's selection from `@AppStorage`. A settings screen lets users pick their metrics.

**Tech Stack:** SwiftUI, SwiftData (read-only for stats), UserDefaults via @AppStorage, CarrierWaveCore `ModeEquivalence` and `StreakCalculator`

**Design doc:** `docs/plans/2026-02-14-configurable-dashboard-metrics-design.md`

---

### Task 1: Add DashboardMetricType enum

**Files:**
- Create: `CarrierWave/Models/DashboardMetricType.swift`

**Step 1: Create the metric type enum**

```swift
import CarrierWaveCore
import Foundation

// MARK: - DashboardMetricType

enum DashboardMetricType: String, CaseIterable, Codable, Identifiable {
    // Streaks
    case onAir
    case activation
    case hunter
    case cw
    case phone
    case digital

    // Counts
    case qsosWeek
    case qsosMonth
    case qsosYear
    case activationsMonth
    case activationsYear
    case huntsWeek
    case huntsMonth
    case newDXCCYear

    // MARK: Internal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onAir: "On-Air Streak"
        case .activation: "Activation Streak"
        case .hunter: "Hunter Streak"
        case .cw: "CW Streak"
        case .phone: "Phone Streak"
        case .digital: "Digital Streak"
        case .qsosWeek: "QSOs This Week"
        case .qsosMonth: "QSOs This Month"
        case .qsosYear: "QSOs This Year"
        case .activationsMonth: "Activations This Month"
        case .activationsYear: "Activations This Year"
        case .huntsWeek: "Parks Hunted This Week"
        case .huntsMonth: "Parks Hunted This Month"
        case .newDXCCYear: "New DXCC This Year"
        }
    }

    var subtitle: String {
        switch self {
        case .onAir: "Days in a row with any contact"
        case .activation: "Days in a row with a valid activation"
        case .hunter: "Days in a row hunting a park"
        case .cw: "Consecutive days on CW"
        case .phone: "Consecutive days on voice"
        case .digital: "Consecutive days on digital"
        case .qsosWeek: "Last 7 days"
        case .qsosMonth: "This calendar month"
        case .qsosYear: "This calendar year"
        case .activationsMonth: "Valid activations this month"
        case .activationsYear: "Valid activations this year"
        case .huntsWeek: "Distinct parks in last 7 days"
        case .huntsMonth: "Distinct parks this month"
        case .newDXCCYear: "First worked this year"
        }
    }

    var icon: String {
        switch self {
        case .onAir: "flame.fill"
        case .activation: "leaf.fill"
        case .hunter: "binoculars.fill"
        case .cw: "waveform.path"
        case .phone: "mic.fill"
        case .digital: "desktopcomputer"
        case .qsosWeek, .qsosMonth, .qsosYear:
            "antenna.radiowaves.left.and.right"
        case .activationsMonth, .activationsYear: "leaf"
        case .huntsWeek, .huntsMonth: "binoculars"
        case .newDXCCYear: "globe"
        }
    }

    var isStreak: Bool {
        switch self {
        case .onAir, .activation, .hunter, .cw, .phone, .digital:
            true
        case .qsosWeek, .qsosMonth, .qsosYear,
             .activationsMonth, .activationsYear,
             .huntsWeek, .huntsMonth, .newDXCCYear:
            false
        }
    }

    static var streakCases: [DashboardMetricType] {
        allCases.filter(\.isStreak)
    }

    static var countCases: [DashboardMetricType] {
        allCases.filter { !$0.isStreak }
    }
}
```

**Step 2: Commit**

```
git add CarrierWave/Models/DashboardMetricType.swift
git commit -m "Add DashboardMetricType enum with display properties (CAR-XX)"
```

---

### Task 2: Extend StreakCategory and StreakInfo for new streak types

**Files:**
- Modify: `CarrierWave/Models/StreakInfo.swift`

The existing `StreakCategory` has `.daily`, `.pota`, `.mode`, `.band`. Add `.hunter` for the new hunter streak.

**Step 1: Add hunter case to StreakCategory**

In `StreakInfo.swift`, add `case hunter = "Hunter"` to `StreakCategory` and an icon mapping:

```swift
enum StreakCategory: String, Identifiable, CaseIterable {
    case daily = "Daily QSOs"
    case pota = "POTA Activations"
    case hunter = "Park Hunts"
    case mode = "Mode"
    case band = "Band"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .daily: "flame.fill"
        case .pota: "leaf.fill"
        case .hunter: "binoculars.fill"
        case .mode: "waveform.path"
        case .band: "antenna.radiowaves.left.and.right"
        }
    }
}
```

**Step 2: Commit**

```
git commit -m "Add hunter streak category to StreakInfo (CAR-XX)"
```

---

### Task 3: Add theirParkReference to StatsQSOSnapshot and capture it during fetch

**Files:**
- Modify: `CarrierWave/Views/Dashboard/StatsComputationActor.swift` (lines 10-25 for snapshot, lines 210-228 for fetch)

**Step 1: Add field to StatsQSOSnapshot**

Add `let theirParkReference: String?` to `StatsQSOSnapshot` (after `parkReference` on line 19).

**Step 2: Capture during fetch**

In `fetchAndConvertToSnapshots`, add `theirParkReference: qso.theirParkReference` to the `StatsQSOSnapshot` initializer (around line 226).

**Step 3: Commit**

```
git commit -m "Add theirParkReference to StatsQSOSnapshot for hunter detection (CAR-XX)"
```

---

### Task 4: Compute hunter streak and mode-family streaks in StatsComputationActor

**Files:**
- Modify: `CarrierWave/Views/Dashboard/StatsComputationActor.swift` (ComputedStats struct, computeStreaks method)

**Step 1: Add new fields to ComputedStats**

Add these fields after the existing POTA streak fields (around line 54):

```swift
// Hunter streak
var hunterStreakCurrent: Int = 0
var hunterStreakLongest: Int = 0
var hunterStreakCurrentStart: Date?
var hunterStreakLongestStart: Date?
var hunterStreakLongestEnd: Date?
var hunterStreakLastActive: Date?

// CW streak
var cwStreakCurrent: Int = 0
var cwStreakLongest: Int = 0
var cwStreakCurrentStart: Date?
var cwStreakLongestStart: Date?
var cwStreakLongestEnd: Date?
var cwStreakLastActive: Date?

// Phone streak
var phoneStreakCurrent: Int = 0
var phoneStreakLongest: Int = 0
var phoneStreakCurrentStart: Date?
var phoneStreakLongestStart: Date?
var phoneStreakLongestEnd: Date?
var phoneStreakLastActive: Date?

// Digital streak
var digitalStreakCurrent: Int = 0
var digitalStreakLongest: Int = 0
var digitalStreakCurrentStart: Date?
var digitalStreakLongestStart: Date?
var digitalStreakLongestEnd: Date?
var digitalStreakLastActive: Date?

// Count metrics
var qsosThisWeek: Int = 0
var qsosThisMonth: Int = 0
var qsosThisYear: Int = 0
var activationsThisMonth: Int = 0
var activationsThisYear: Int = 0
var huntsThisWeek: Int = 0
var huntsThisMonth: Int = 0
var newDXCCThisYear: Int = 0
```

**Step 2: Add hunter streak computation**

Add a `computeHunterStreak` method. A hunter QSO is one where `theirParkReference` is non-nil and non-empty (the user worked someone at a park):

```swift
private func computeHunterStreak(from qsos: [StatsQSOSnapshot]) -> StreakResult {
    let hunterQSOs = qsos.filter { qso in
        if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
            return true
        }
        return false
    }
    guard !hunterQSOs.isEmpty else {
        return .empty
    }
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let uniqueDates = Set(hunterQSOs.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
    return computeStreakFromDates(uniqueDates, using: calendar)
}
```

**Step 3: Add mode-family streak computation**

```swift
private func computeModeFamilyStreak(
    from qsos: [StatsQSOSnapshot],
    family: ModeFamily
) -> StreakResult {
    let filtered = qsos.filter { ModeEquivalence.family(for: $0.mode) == family }
    guard !filtered.isEmpty else {
        return .empty
    }
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let uniqueDates = Set(filtered.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
    return computeStreakFromDates(uniqueDates, using: calendar)
}
```

**Step 4: Wire into computeStreaks method**

In `computeStreaks(into:from:onProgress:)`, after the existing POTA streak code, add calls for hunter + mode families and apply results to `stats`.

**Step 5: Commit**

```
git commit -m "Compute hunter, CW, phone, digital streaks in background actor (CAR-XX)"
```

---

### Task 5: Compute count metrics in StatsComputationActor

**Files:**
- Modify: `CarrierWave/Views/Dashboard/StatsComputationActor+Extensions.swift`

Add a new method `computeCountMetrics` called from `computeStatsFromSnapshots`.

**Step 1: Add computeCountMetrics method**

```swift
func computeCountMetrics(
    into stats: inout ComputedStats,
    from realQSOs: [StatsQSOSnapshot],
    onProgress: @escaping @Sendable (Double, String) -> Void
) async throws {
    onProgress(0.95, "Computing count metrics...")
    try Task.checkCancellation()

    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date()
    let today = calendar.startOfDay(for: now)

    // Time boundaries
    let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
    let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!

    // QSO counts
    stats.qsosThisWeek = realQSOs.filter { $0.timestamp >= weekAgo }.count
    stats.qsosThisMonth = realQSOs.filter { $0.timestamp >= monthStart }.count
    stats.qsosThisYear = realQSOs.filter { $0.timestamp >= yearStart }.count

    // Activation counts (park+date combos with 10+ QSOs)
    let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }

    let monthActivations = parksOnly.filter { $0.timestamp >= monthStart }
    let monthGroups = Dictionary(grouping: monthActivations) { qso in
        "\(qso.parkReference!)|\(Self.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
    }
    stats.activationsThisMonth = monthGroups.values.filter { $0.count >= 10 }.count

    let yearActivations = parksOnly.filter { $0.timestamp >= yearStart }
    let yearGroups = Dictionary(grouping: yearActivations) { qso in
        "\(qso.parkReference!)|\(Self.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
    }
    stats.activationsThisYear = yearGroups.values.filter { $0.count >= 10 }.count

    // Hunt counts (distinct theirParkReference values)
    let hunterQSOs = realQSOs.filter { $0.theirParkReference != nil && !$0.theirParkReference!.isEmpty }
    stats.huntsThisWeek = Set(
        hunterQSOs.filter { $0.timestamp >= weekAgo }.compactMap(\.theirParkReference)
    ).count
    stats.huntsThisMonth = Set(
        hunterQSOs.filter { $0.timestamp >= monthStart }.compactMap(\.theirParkReference)
    ).count

    // New DXCC this year: entities where first-ever QSO is in current year
    let byDXCC = Dictionary(grouping: realQSOs.filter { $0.dxcc != nil }) { $0.dxcc! }
    stats.newDXCCThisYear = byDXCC.values.filter { qsos in
        guard let earliest = qsos.min(by: { $0.timestamp < $1.timestamp }) else { return false }
        return earliest.timestamp >= yearStart
    }.count
}
```

**Step 2: Call from computeStatsFromSnapshots**

In `StatsComputationActor.computeStatsFromSnapshots`, add a Phase 4 call after streaks:

```swift
// Phase 4: Count metrics
try await computeCountMetrics(into: &stats, from: realQSOs, onProgress: onProgress)
```

Adjust progress percentages so Phase 3 (streaks) ends at ~0.90 and Phase 4 (counts) runs 0.90-0.98.

**Step 3: Commit**

```
git commit -m "Compute count metrics (QSOs/activations/hunts per period) in background actor (CAR-XX)"
```

---

### Task 6: Expose new metrics in AsyncQSOStatistics

**Files:**
- Modify: `CarrierWave/Views/Dashboard/AsyncQSOStatistics.swift`

**Step 1: Add published properties for new streaks and counts**

After the existing `potaActivationStreak` property (line 31), add:

```swift
private(set) var hunterStreak: StreakInfo?
private(set) var cwStreak: StreakInfo?
private(set) var phoneStreak: StreakInfo?
private(set) var digitalStreak: StreakInfo?

// Count metrics
private(set) var qsosThisWeek: Int = 0
private(set) var qsosThisMonth: Int = 0
private(set) var qsosThisYear: Int = 0
private(set) var activationsThisMonth: Int = 0
private(set) var activationsThisYear: Int = 0
private(set) var huntsThisWeek: Int = 0
private(set) var huntsThisMonth: Int = 0
private(set) var newDXCCThisYear: Int = 0
```

**Step 2: Apply results in applyResults**

In `applyResults(_ computed:)`, after the existing `potaActivationStreak` assignment (around line 219), add the new streak and count assignments.

**Step 3: Reset new properties in reset()**

In `reset()`, set all new streak properties to nil and count properties to 0.

**Step 4: Add a convenience method for MetricsCard**

```swift
/// Get the display value for a dashboard metric type
func metricValue(for type: DashboardMetricType) -> MetricDisplayValue {
    switch type {
    case .onAir:
        return .streak(dailyStreak)
    case .activation:
        return .streak(potaActivationStreak)
    case .hunter:
        return .streak(hunterStreak)
    case .cw:
        return .streak(cwStreak)
    case .phone:
        return .streak(phoneStreak)
    case .digital:
        return .streak(digitalStreak)
    case .qsosWeek:
        return .count(qsosThisWeek)
    case .qsosMonth:
        return .count(qsosThisMonth)
    case .qsosYear:
        return .count(qsosThisYear)
    case .activationsMonth:
        return .count(activationsThisMonth)
    case .activationsYear:
        return .count(activationsThisYear)
    case .huntsWeek:
        return .count(huntsThisWeek)
    case .huntsMonth:
        return .count(huntsThisMonth)
    case .newDXCCYear:
        return .count(newDXCCThisYear)
    }
}
```

Add a helper enum (can go in `DashboardMetricType.swift` or inline):

```swift
enum MetricDisplayValue {
    case streak(StreakInfo?)
    case count(Int)
}
```

**Step 5: Commit**

```
git commit -m "Expose new streak and count metrics from AsyncQSOStatistics (CAR-XX)"
```

---

### Task 7: Replace StreaksCard with MetricsCard

**Files:**
- Modify: `CarrierWave/Views/Dashboard/DashboardHelperViews.swift` (lines 117-152, StreaksCard)

**Step 1: Replace StreaksCard with MetricsCard**

Delete the `StreaksCard` struct and replace with:

```swift
struct MetricsCard: View {
    let asyncStats: AsyncQSOStatistics
    @AppStorage("dashboardMetric1") private var metric1RawValue = DashboardMetricType.onAir.rawValue
    @AppStorage("dashboardMetric2") private var metric2RawValue = DashboardMetricType.activation.rawValue

    private var metric1: DashboardMetricType {
        DashboardMetricType(rawValue: metric1RawValue) ?? .onAir
    }

    private var metric2: DashboardMetricType? {
        metric2RawValue.isEmpty ? nil : DashboardMetricType(rawValue: metric2RawValue)
    }

    private var cardTitle: String {
        let types = [metric1, metric2].compactMap { $0 }
        if types.allSatisfy(\.isStreak) {
            return "Streaks"
        }
        return "Metrics"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cardTitle)
                .font(.headline)

            HStack(spacing: 12) {
                metricColumn(for: metric1)

                if let m2 = metric2 {
                    Divider()
                    metricColumn(for: m2)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func metricColumn(for type: DashboardMetricType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch asyncStats.metricValue(for: type) {
            case let .streak(info):
                StreakStatBox(streak: info ?? .placeholder)
                    .opacity(info == nil ? 0.6 : 1.0)
            case let .count(value):
                CountStatBox(value: value, subtitle: type.subtitle)
            }
        }
    }
}
```

**Step 2: Add CountStatBox**

Add alongside `StreakStatBox`:

```swift
struct CountStatBox: View {
    let value: Int
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

**Step 3: Commit**

```
git commit -m "Replace StreaksCard with configurable MetricsCard (CAR-XX)"
```

---

### Task 8: Wire MetricsCard into DashboardView

**Files:**
- Modify: `CarrierWave/Views/Dashboard/DashboardView.swift` (lines 91, 303-312, 338-377)

**Step 1: Replace streaksCard computed property**

Replace the `streaksCard` property (lines 303-312) with:

```swift
private var streaksCard: some View {
    NavigationLink {
        LazyStreakDetailView(asyncStats: asyncStats, tourState: tourState)
    } label: {
        MetricsCard(asyncStats: asyncStats)
    }
    .buttonStyle(.plain)
}
```

**Step 2: Update combinedStreaksAndStatsCard**

In `combinedStreaksAndStatsCard` (lines 338-377), replace the hardcoded streaks section with a `MetricsCard` in the left column.

**Step 3: Commit**

```
git commit -m "Wire MetricsCard into DashboardView replacing hardcoded streaks (CAR-XX)"
```

---

### Task 9: Add StreakDetailView hunter section

**Files:**
- Modify: `CarrierWave/Views/Dashboard/StreakDetailView.swift`

**Step 1: Add hunter section**

After the POTA Activations section (around line 33), add:

```swift
Section {
    StreakRow(streak: stats.hunterStreak)
} header: {
    Text("Park Hunts")
}
```

This requires adding `hunterStreak` to `QSOStatistics+Streaks.swift` as well.

**Step 2: Add hunterStreak to QSOStatistics+Streaks.swift**

Add a computed property similar to `potaActivationStreak` but filtering for `theirParkReference`:

```swift
var hunterStreak: StreakInfo {
    if let cached = cachedHunterStreak {
        return cached
    }
    let hunterDates = Set(
        cachedRealQSOs
            .filter { $0.theirParkReference != nil && !$0.theirParkReference!.isEmpty }
            .map(\.utcDateOnly)
    )
    let result = StreakCalculator.calculateStreak(from: hunterDates, useUTC: true)
    let info = makeStreakInfo(id: "hunter", category: .hunter, result: result)
    cachedHunterStreak = info
    return info
}
```

Also add `cachedHunterStreak` to `QSOStatistics` as a cached property (check how other cached properties are declared — look for `cachedDailyStreak` in the main `QSOStatistics.swift`).

**Step 3: Update "About Streaks" section**

Add a note about hunter streaks using UTC dates.

**Step 4: Commit**

```
git commit -m "Add hunter streak section to StreakDetailView (CAR-XX)"
```

---

### Task 10: Add Dashboard Metrics settings view

**Files:**
- Create: `CarrierWave/Views/Settings/DashboardMetricsSettingsView.swift`
- Modify: `CarrierWave/Views/Settings/SettingsView.swift`

**Step 1: Create the settings view**

```swift
import SwiftUI

struct DashboardMetricsSettingsView: View {
    @AppStorage("dashboardMetric1") private var metric1RawValue =
        DashboardMetricType.onAir.rawValue
    @AppStorage("dashboardMetric2") private var metric2RawValue =
        DashboardMetricType.activation.rawValue

    var body: some View {
        List {
            Section {
                metricPicker(label: "Primary Metric", selection: $metric1RawValue)
            } header: {
                Text("Primary Metric")
            } footer: {
                Text("Always shown on the dashboard card.")
            }

            Section {
                Toggle("Show second metric", isOn: showSecondMetric)
                if !metric2RawValue.isEmpty {
                    metricPicker(label: "Second Metric", selection: $metric2RawValue)
                }
            } header: {
                Text("Second Metric")
            } footer: {
                Text("Optionally show a second metric alongside the primary one.")
            }
        }
        .navigationTitle("Dashboard Metrics")
    }

    private var showSecondMetric: Binding<Bool> {
        Binding(
            get: { !metric2RawValue.isEmpty },
            set: { enabled in
                if enabled {
                    metric2RawValue = DashboardMetricType.activation.rawValue
                } else {
                    metric2RawValue = ""
                }
            }
        )
    }

    private func metricPicker(label: String, selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Section("Streaks") {
                ForEach(DashboardMetricType.streakCases) { type in
                    VStack(alignment: .leading) {
                        Text(type.displayName)
                        Text(type.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(type.rawValue)
                }
            }
            Section("Counts") {
                ForEach(DashboardMetricType.countCases) { type in
                    VStack(alignment: .leading) {
                        Text(type.displayName)
                        Text(type.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(type.rawValue)
                }
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
```

**Step 2: Add navigation link in SettingsView**

In `SettingsView.swift`, in the appropriate section (after Logger or in a new "Dashboard" section), add:

```swift
NavigationLink {
    DashboardMetricsSettingsView()
} label: {
    Label("Dashboard Metrics", systemImage: "gauge.with.dots.needle.33percent")
}
```

**Step 3: Commit**

```
git commit -m "Add Dashboard Metrics settings view for metric selection (CAR-XX)"
```

---

### Task 11: Update StreakRow icon color for hunter

**Files:**
- Modify: `CarrierWave/Views/Dashboard/StreakDetailView.swift` (iconColor computed property, ~line 138)

**Step 1: Add hunter case to iconColor**

In the `iconColor` computed property of `StreakRow`, add:

```swift
case .hunter: .teal
```

**Step 2: Commit**

```
git commit -m "Add hunter icon color to StreakRow (CAR-XX)"
```

---

### Task 12: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

**Step 1: Add new files to FILE_INDEX.md**

Add entries for:
- `DashboardMetricType.swift` in Models section
- `DashboardMetricsSettingsView.swift` in Settings section

**Step 2: Update CHANGELOG.md**

Under `[Unreleased]`, add:

```markdown
### Added
- Configurable dashboard metrics card — choose 1-2 metrics from streaks (On-Air, Activation, Hunter, CW, Phone, Digital) and counts (QSOs/activations/hunts per week/month/year, new DXCC)
- Hunter streak tracking — consecutive days working POTA activators
- Dashboard Metrics settings screen for metric selection
```

**Step 3: Commit**

```
git commit -m "Update FILE_INDEX.md and CHANGELOG.md for configurable metrics (CAR-XX)"
```

---

### Task 13: Format, lint, and build

**Step 1: Run format and lint**

```bash
xc format
xc lint
```

Fix any issues.

**Step 2: Build**

```bash
xc build
```

Fix any compilation errors.

**Step 3: Deploy and verify**

```bash
make deploy
```

Verify on device:
- Dashboard shows the metrics card with "On-Air Streak" and "Activation Streak" by default
- Tapping the card navigates to the full streak detail view (with new hunter section)
- Settings > Dashboard Metrics lets you pick different metrics
- Changing the selection updates the dashboard card immediately
- Count metrics show correct values

**Step 4: Commit any fixes**

```
git commit -m "Fix lint/build issues for configurable metrics (CAR-XX)"
```
