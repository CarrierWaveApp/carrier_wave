# Audit Fix-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all issues identified in the performance, style, and HIG audit — DateFormatter allocations, redundant filter scans, missing accessibility labels, Reduce Motion gaps, hardcoded font sizes, and one Dark Mode color violation.

**Architecture:** Pure cleanup — no new types or APIs. Each task is a mechanical find-and-fix with no cross-task dependencies (except Task 7 which is a larger refactor deferred to a branch). Tasks 1–6 can be done in any order and committed independently.

**Tech Stack:** SwiftUI, Swift, SF Symbols

**Note:** The `@Observable` migration (Task 7) is separated because it touches 10 services and ~20 view call sites. It should be done on a feature branch and tested thoroughly. Tasks 1–6 are safe, low-risk fixes.

---

## Task 1: Fix DateFormatter Computed Properties → `static let`

9 files create `DateFormatter()` inside computed properties or helper functions called from view bodies. Each should become a `private static let`.

**Files:**
- Modify: `CarrierWave/Views/Sessions/SessionsView.swift:107-119`
- Modify: `CarrierWave/Views/DXpeditions/DXpeditionsView.swift:51-62`
- Modify: `CarrierWave/Views/Events/EventDetailView.swift:210-244`
- Modify: `CarrierWave/Views/POTAActivations/POTALogEntryRow.swift:35-39`
- Modify: `CarrierWave/Views/Settings/SyncDebugView.swift:368-372`
- Modify: `CarrierWave/Views/Settings/StartupProfileView+Orientation.swift:43-47`
- Modify: `CarrierWave/Views/BragSheet/BragSheetStatRendering.swift:59-68`
- Modify: `CarrierWave/Views/Conditions/ConditionsHistoryChartView.swift:285-299`
- Modify: `CarrierWave/Views/Conditions/ConditionsCard.swift:198-211`

- [ ] **Step 1: Fix SessionsView.swift**

Replace the computed property formatter with a static let:

```swift
// Add static formatter above itemsByMonth
private static let monthYearFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMMM yyyy"
    fmt.timeZone = TimeZone(identifier: "UTC")
    return fmt
}()

// Then in itemsByMonth, replace:
//   let formatter = DateFormatter()
//   formatter.dateFormat = "MMMM yyyy"
//   formatter.timeZone = TimeZone(identifier: "UTC")
// with:
//   (use Self.monthYearFormatter directly)
var itemsByMonth: [(month: String, items: [ListItem])] {
    let grouped = Dictionary(grouping: allItems) { item in
        Self.monthYearFormatter.string(from: item.date)
    }
    return grouped
        .sorted { $0.value[0].date > $1.value[0].date }
        .map { (month: $0.key, items: $0.value) }
}
```

- [ ] **Step 2: Fix DXpeditionsView.swift**

```swift
// Add static formatter
private static let monthYearFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMMM yyyy"
    return fmt
}()

// Replace monthYearLabel body — remove formatter creation, use Self.monthYearFormatter
private var monthYearLabel: String {
    var components = DateComponents()
    components.month = selectedMonth
    components.year = selectedYear
    components.day = 1
    guard let date = Calendar.current.date(from: components) else {
        return "\(selectedMonth)/\(selectedYear)"
    }
    return Self.monthYearFormatter.string(from: date)
}
```

- [ ] **Step 3: Fix EventDetailView.swift**

This file has 3 functions that each create formatters. The timezone varies per-event, so use `Date.formatted()` or a shared helper:

```swift
// Add static formatters
private static let mediumDateTimeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .short
    return fmt
}()

private static let mediumDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .none
    return fmt
}()

private static let timeOnlyFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .none
    fmt.timeStyle = .short
    return fmt
}()

// Update each function to set .timeZone on the static formatter before use.
// DateFormatter is a reference type so setting timeZone is fine — these
// functions are only called on the main thread (view body).
private func formattedDate(_ date: Date, timezone tzId: String) -> String {
    let fmt = Self.mediumDateTimeFormatter
    fmt.timeZone = TimeZone(identifier: tzId)
    let tzAbbrev = TimeZone(identifier: tzId)?.abbreviation() ?? tzId
    return "\(fmt.string(from: date)) \(tzAbbrev)"
}

private func formattedDateOnly(_ date: Date, timezone tzId: String) -> String {
    let fmt = Self.mediumDateFormatter
    fmt.timeZone = TimeZone(identifier: tzId)
    return fmt.string(from: date)
}

private func formattedTimeRange(_ day: EventDay, timezone tzId: String) -> String {
    let fmt = Self.timeOnlyFormatter
    fmt.timeZone = TimeZone(identifier: tzId)
    let start = fmt.string(from: day.startTime)
    if let endTime = day.endTime {
        return "\(start) – \(fmt.string(from: endTime))"
    }
    return start
}
```

- [ ] **Step 4: Fix POTALogEntryRow.swift, SyncDebugView.swift, StartupProfileView+Orientation.swift**

Each has a computed `var ...Formatter: DateFormatter` — convert to `private static let`:

```swift
// POTALogEntryRow.swift — replace lines 35-39
private static let dateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d, HH:mm"
    return fmt
}()
// Update all references from `dateFormatter` to `Self.dateFormatter`

// SyncDebugView.swift — replace lines 368-372
private static let timeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss"
    return fmt
}()

// StartupProfileView+Orientation.swift — replace lines 43-47
private static let orientationTimeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "HH:mm:ss.SSS"
    return fmt
}()
```

- [ ] **Step 5: Fix BragSheetStatRendering.swift**

```swift
// Add to the extension
private static let mediumDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .none
    return fmt
}()

// In parkDetailSubtitle, replace formatter creation with:
private func parkDetailSubtitle(date: Date?, count: Int) -> String {
    var parts: [String] = []
    if let date {
        parts.append(Self.mediumDateFormatter.string(from: date))
    }
    parts.append("\(count) QSOs")
    return parts.joined(separator: " · ")
}
```

- [ ] **Step 6: Fix ConditionsHistoryChartView.swift and ConditionsCard.swift**

Both have identical `dayKey` / `dateFromDayKey` static functions. Fix both:

```swift
// Replace in both files
private static let dayKeyFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.timeZone = TimeZone(identifier: "UTC")
    return fmt
}()

private static func dayKey(_ date: Date) -> String {
    dayKeyFormatter.string(from: date)
}

private static func dateFromDayKey(_ key: String) -> Date {
    let startOfDay = dayKeyFormatter.date(from: key) ?? Date()
    return startOfDay.addingTimeInterval(12 * 3_600)
}
```

- [ ] **Step 7: Run swiftformat and swiftlint**

Run: `swiftformat` on all modified files, then `swiftlint` to check for violations.

- [ ] **Step 8: Commit**

```
fix: use static DateFormatter instances instead of per-render allocations

9 files were creating DateFormatter in computed properties or helper
functions called from view bodies, causing allocation on every SwiftUI
render cycle.
```

---

## Task 2: Consolidate Redundant `.filter()` Scans in OnAirCard and DXpeditionsCard

**Files:**
- Modify: `CarrierWave/Views/Dashboard/OnAirCard.swift:78-124`
- Modify: `CarrierWave/Views/Dashboard/DXpeditionsCard.swift:47-56,73`

- [ ] **Step 1: Fix OnAirCard.swift**

`liveCount` (line 79) and `mergedItems` (line 89) both call `expeditions.filter(\.isOnAir)` separately. The `mergedItems` computed property also calls `.filter` 3 times total. Consolidate into a single partitioning computed property:

```swift
// Replace liveCount and mergedItems with:
private struct ExpeditionPartitions {
    var onAir: [Ham365DXpedition] = []
    var activeToday: [Ham365DXpedition] = []
    var upcoming: [Ham365DXpedition] = []
}

private var partitions: ExpeditionPartitions {
    var result = ExpeditionPartitions()
    for exp in expeditions {
        if exp.isOnAir {
            result.onAir.append(exp)
        } else if exp.isActiveToday {
            result.activeToday.append(exp)
        } else if !exp.activeDays.isEmpty {
            result.upcoming.append(exp)
        }
    }
    return result
}

private var liveCount: Int {
    partitions.onAir.count + contestService.activeContests.count
}

private var mergedItems: [OnAirItem] {
    let parts = partitions
    var items: [OnAirItem] = []

    for dx in parts.onAir.sorted(by: { spotCount($0) > spotCount($1) }) {
        items.append(.dxpedition(dx, isLive: true))
    }
    for contest in contestService.activeContests {
        items.append(.contest(contest, isLive: true))
    }
    for dx in parts.activeToday {
        items.append(.dxpedition(dx, isLive: false))
    }
    for contest in contestService.upcomingContests.prefix(2) {
        items.append(.contest(contest, isLive: false))
    }
    for dx in parts.upcoming {
        items.append(.dxpedition(dx, isLive: false))
    }
    return Array(items.prefix(4))
}
```

- [ ] **Step 2: Fix DXpeditionsCard.swift**

Same pattern — `displayedExpeditions` (line 47) does 3 filters, and `header` (line 73) does a 4th. Consolidate. **Important:** Since `partitions` is a computed property (not memoized), avoid calling it from multiple computed properties independently. Cache it in a local `let` wherever multiple values are needed in the same scope:

```swift
private struct ExpeditionPartitions {
    var onAir: [Ham365DXpedition] = []
    var activeToday: [Ham365DXpedition] = []
    var upcoming: [Ham365DXpedition] = []
}

private var partitions: ExpeditionPartitions {
    var result = ExpeditionPartitions()
    for exp in expeditions {
        if exp.isOnAir { result.onAir.append(exp) }
        else if exp.isActiveToday { result.activeToday.append(exp) }
        else if !exp.activeDays.isEmpty { result.upcoming.append(exp) }
    }
    return result
}

private var displayedExpeditions: [Ham365DXpedition] {
    let parts = partitions
    return Array((parts.onAir + parts.activeToday + parts.upcoming).prefix(5))
}

// In header, use a local let to avoid a second partitions call:
//   let parts = partitions
//   let onAirCount = parts.onAir.count
// Or inline the header into a function that takes the count as a parameter.
```

- [ ] **Step 3: Run swiftformat and swiftlint**

- [ ] **Step 4: Commit**

```
perf: consolidate redundant expedition filter scans into single pass

OnAirCard and DXpeditionsCard were scanning the expeditions array 3-4
times per render. Now partitions once and derives all values from that.
```

---

## Task 3: Add Missing Accessibility Labels to Icon-Only Buttons

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView+SessionHeader.swift:143-155`
- Modify: `CarrierWave/Views/Logger/LoggerView+FormFields.swift:192-205`

- [ ] **Step 1: Fix LoggerView+SessionHeader.swift**

Add `.accessibilityLabel` to the ellipsis menu button (after the closing brace of the `label:` closure, before line 156):

```swift
// After the } label: { ... } closing brace, add:
.accessibilityLabel("Session options")
```

- [ ] **Step 2: Fix LoggerView+FormFields.swift**

Add `.accessibilityLabel` to the chevron expand/collapse button (after `.buttonStyle(.plain)` on line 205):

```swift
// After .buttonStyle(.plain), add:
.accessibilityLabel(showMoreFields ? "Hide additional fields" : "Show additional fields")
```

- [ ] **Step 3: Run swiftformat and swiftlint**

- [ ] **Step 4: Commit**

```
a11y: add accessibility labels to icon-only logger buttons
```

---

## Task 4: Add `relativeTo:` to Hardcoded Font Sizes

Hardcoded `.font(.system(size: N))` without `relativeTo:` doesn't scale with Dynamic Type. Add the parameter to each. Where sizes are large decorative icons (48pt), use `@ScaledMetric` instead.

**Files:**
- Modify: `CarrierWave/Views/Contests/ContestsCard.swift:204`
- Modify: `CarrierWave/Views/Events/EventMapAnnotation.swift:22`
- Modify: `CarrierWave/Views/Tour/LoggerTourOverlay.swift:97,120`
- Modify: `CarrierWave/Views/Tour/TourSheetView.swift:37`
- Modify: `CarrierWave/Views/Tour/TourGuideBubble.swift:19`
- Modify: `CarrierWave/Views/Logger/EndSessionFlowView.swift:139,147`
- Modify: `CarrierWave/Views/Logger/LoggerView+Landscape.swift:92`
- Modify: `CarrierWave/Views/Dashboard/OnAirCard.swift:318,323`
- Modify: `CarrierWave/Views/Dashboard/BandOpeningsCard.swift:167`
- Modify: `CarrierWave/Views/TuneIn/TuneInExpandedPlayerView.swift:217`

- [ ] **Step 1: Fix small font sizes — add `relativeTo:` parameter**

For each file, find `.font(.system(size: N))` and add the appropriate `relativeTo:`:

| File | Line | Current | Fix |
|------|------|---------|-----|
| ContestsCard.swift | 204 | `size: 9` | `size: 9, relativeTo: .caption2` |
| EventMapAnnotation.swift | 22 | `size: 8` | `size: 8, relativeTo: .caption2` |
| TourGuideBubble.swift | 19 | `size: 14, weight: .semibold` | `size: 14, weight: .semibold, relativeTo: .subheadline` |
| LoggerView+Landscape.swift | 92 | `size: 7` | `size: 7, relativeTo: .caption2` |
| OnAirCard.swift | 318 | `size: 10` | `size: 10, relativeTo: .caption2` |
| OnAirCard.swift | 323 | `size: 10` | `size: 10, relativeTo: .caption2` |
| BandOpeningsCard.swift | 167 | `size: 10, weight: .medium` | `size: 10, weight: .medium, relativeTo: .caption2` |
| TuneInExpandedPlayerView.swift | 217 | `size: 10, weight: .bold` | `size: 10, weight: .bold, relativeTo: .caption2` |

- [ ] **Step 2: Fix large icon sizes — add `@ScaledMetric`**

For 48pt icons, add a `@ScaledMetric` property to the view struct and use it:

```swift
// LoggerTourOverlay.swift — add property:
@ScaledMetric(relativeTo: .largeTitle) private var largeIconSize: CGFloat = 48
// Replace .font(.system(size: 48)) with .font(.system(size: largeIconSize))

// TourSheetView.swift — add property:
@ScaledMetric(relativeTo: .largeTitle) private var pageIconSize: CGFloat = 48
// Replace .font(.system(size: 48)) with .font(.system(size: pageIconSize))

// EndSessionFlowView.swift — add property:
@ScaledMetric(relativeTo: .largeTitle) private var summaryIconSize: CGFloat = 48
// Replace .font(.system(size: 48)) with .font(.system(size: summaryIconSize))
```

- [ ] **Step 3: Run swiftformat and swiftlint**

- [ ] **Step 4: Commit**

```
a11y: add Dynamic Type scaling to hardcoded font sizes

Adds relativeTo: parameter for small sizes and @ScaledMetric for large
decorative icons so text and icons scale with Dynamic Type preferences.
```

---

## Task 5: Add Reduce Motion Support to Unprotected Animations

32 `.animation()` modifiers don't check `accessibilityReduceMotion`. The existing pattern in the codebase (e.g., `SyncProgressCard.swift:33`) is:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
.animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: ...)
```

**Files to modify** (each needs `@Environment(\.accessibilityReduceMotion) private var reduceMotion` added to the struct if not already present, then each `.animation()` call wrapped):

- Modify: `CarrierWave/Views/Logger/LoggerView+Layout.swift:364-370` (7 animations)
- Modify: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift:47-50` (4 animations)
- Modify: `CarrierWave/Views/Logger/FT8/FT8SetupWizardView.swift:36` (1 animation)
- Modify: `CarrierWave/Views/Logger/FT8/FT8CycleIndicatorView.swift:43` (1 animation)
- Modify: `CarrierWave/Views/Logger/FT8/FT8DebugPanel.swift:56` (1 animation)
- Modify: `CarrierWave/Views/Logger/EndSessionFlowView.swift:74` (1 animation)
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogFT8View.swift:39,59,60` (3 animations)
- Modify: `CarrierWave/Views/CWTranscription/CWWaveformView.swift:138,238,359` (3 animations)
- Modify: `CarrierWave/Views/RecordingPlayer/RecordingPlayerView.swift:256` (1 animation)
- Modify: `CarrierWave/Views/Settings/StartupProfileView.swift:96` (1 animation)
- Modify: `CarrierWave/Views/Challenges/ChallengeDetailHelperViews.swift:22` (1 animation)
- Modify: `CarrierWave/Views/Dashboard/FriendsOnAirCard.swift:87` (1 animation)
- Modify: `CarrierWave/Views/Dashboard/DashboardHelperViews.swift:366` (1 animation)
- Modify: `CarrierWave/Views/Map/QSOMapView.swift:336` (1 animation)
- Modify: `CarrierWave/Views/Map/ParkSearchMapView+Views.swift:33` (1 animation)
- Modify: `CarrierWave/Views/POTAActivations/POTAActivationsHelperViews.swift:283` (1 animation — already `.animation(nil, ...)`, skip)

- [ ] **Step 1: Fix LoggerView+Layout.swift (7 animations)**

This is an extension on `LoggerView`, which may already have `reduceMotion`. If not, add the environment property. Then replace lines 364-370:

```swift
// Before:
.animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
// ... (7 lines)

// After — for each line:
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showSolarPanel)
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showWeatherPanel)
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showMapPanel)
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showPOTAPanel)
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showP2PPanel)
.animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7), value: showWebSDRPanel)
```

- [ ] **Step 2: Fix FT8 views (FT8SessionView, FT8SetupWizardView, FT8CycleIndicatorView, FT8DebugPanel)**

Same pattern — add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to each struct if missing, then wrap each `.animation(X, value:)` with `reduceMotion ? .none : X`.

- [ ] **Step 3: Fix remaining views**

Apply the same pattern to all other files listed above. For each:
1. Check if the struct already has `reduceMotion` — if not, add the `@Environment` property
2. Wrap each `.animation(X, value:)` with `reduceMotion ? .none : X`

Skip `POTAActivationsHelperViews.swift:283` — it's already `.animation(nil, ...)`.

- [ ] **Step 4: Run swiftformat and swiftlint**

- [ ] **Step 5: Commit**

```
a11y: respect Reduce Motion setting for 30+ unprotected animations

Wraps all .animation() modifiers with reduceMotion check so users
with vestibular sensitivities see no motion. Follows existing pattern
from SyncProgressCard and TourSheetView.
```

---

## Task 6: Fix Dark Mode Color Violation

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerToastView.swift:315`

- [ ] **Step 1: Fix `.foregroundStyle(.black)` on yellow background**

Line 315 uses `.foregroundStyle(.black)` on a `Color.yellow` background. While the yellow background is always bright, `.black` violates the design language's ban on hardcoded black/white. Use `.primary` in a forced light appearance on that element, or define a color asset:

```swift
// Option A — force the color environment on the button content:
.foregroundStyle(Color.primary)
.environment(\.colorScheme, .light)

// Option B (simpler) — since .yellow is always bright, just use:
.foregroundStyle(Color(.label))
.environment(\.colorScheme, .light)
```

Either ensures dark text on yellow regardless of system appearance.

- [ ] **Step 2: Run swiftformat and swiftlint**

- [ ] **Step 3: Commit**

```
fix: use .darkText instead of .black for yellow-background toast button
```

---

## Task 7: Migrate ObservableObject Services to @Observable (Branch Work)

**This is a larger refactor. Do on a feature branch (`refactor/observable-migration`).**

10 services use `ObservableObject` + `@Published`. Views using `@ObservedObject` re-render on ANY `@Published` change, even properties they don't read. `@Observable` (iOS 17+) enables fine-grained observation.

**Services to migrate:**
- `CarrierWave/Services/SyncService.swift`
- `CarrierWave/Services/CloudSync/CloudSyncService.swift`
- `CarrierWave/Services/SyncDebugLog.swift`
- `CarrierWave/Services/ActivityProgramStore.swift`
- `CarrierWave/Services/FriendsSyncService.swift`
- `CarrierWave/Services/ClubsSyncService.swift`
- `CarrierWave/Services/ActivitiesSyncService.swift`
- `CarrierWave/Services/ActivityFeedSyncService.swift`
- `CarrierWave/Services/ImportService.swift`
- `CarrierWave/Services/POTAAuthService.swift`

**View call sites to update** (change `@ObservedObject` → plain `var`, `@StateObject` → `@State`):
- `CarrierWave/ContentView.swift:187` (`@StateObject` → `@State`)
- `CarrierWave/Views/Events/EventsView.swift:55` (`@StateObject` → `@State`)
- ~18 views with `@ObservedObject` (see grep results above)

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b refactor/observable-migration
```

- [ ] **Step 2: Migrate one service at a time**

For each service file:

1. Remove `: ObservableObject` conformance
2. Add `@Observable` macro above the class declaration
3. Remove all `@Published` property wrappers
4. If the class inherits from `NSObject` (`POTAAuthService`, `CloudSyncService`), keep `NSObject` and add `@Observable` — they compose fine
5. Remove `import Combine` if no other Combine usage remains

```swift
// Before:
@MainActor
class SyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    // ...
}

// After:
@Observable
@MainActor
class SyncService {
    var isSyncing = false
    var lastSyncDate: Date?
    // ...
}
```

- [ ] **Step 3: Update all view call sites**

For each view that references these services:

```swift
// Before:
@ObservedObject var syncService: SyncService
@StateObject private var potaAuthService = POTAAuthService()

// After:
var syncService: SyncService
@State private var potaAuthService = POTAAuthService()
```

Rules:
- `@ObservedObject` → plain `var` (or `let`)
- `@StateObject` → `@State`
- `@EnvironmentObject` → `@Environment` (if any exist)

- [ ] **Step 4: Handle `CloudSyncService.shared` singleton pattern**

`CloudSyncService.shared` is accessed directly via `@ObservedObject var syncService = CloudSyncService.shared`. With `@Observable`, just access it as a plain property — SwiftUI will track reads automatically:

```swift
// Before:
@ObservedObject private var syncService = CloudSyncService.shared

// After:
private var syncService = CloudSyncService.shared
```

But note: for views that receive the service via init, use `var` (not `let`) so SwiftUI can track mutations if the reference changes. For singletons accessed inline, `let` is fine.

- [ ] **Step 5: Run full build**

Run: `xc build` to verify no compilation errors from the migration.

- [ ] **Step 6: Test key flows**

Test these flows to verify observation still works:
- Dashboard sync progress card updates during sync
- Settings views reflect service connection state changes
- POTA auth login/logout updates UI
- Cloud sync status indicator updates

- [ ] **Step 7: Commit and create PR**

```
refactor: migrate ObservableObject services to @Observable

Migrates 10 services from ObservableObject/@Published to @Observable
macro. Views now only re-render when properties they actually read
change, reducing unnecessary SwiftUI re-renders.
```
