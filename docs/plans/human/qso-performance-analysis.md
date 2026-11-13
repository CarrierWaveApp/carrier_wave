# QSO Performance Analysis

**Date:** 2026-01-31
**Status:** ✅ IMPLEMENTED (2026-01-31)
**Context:** App performance with 15k+ QSOs

---

## Executive Summary

Analysis of the codebase reveals **multiple performance bottlenecks** that scale linearly or worse with QSO count. At 15k QSOs, these issues compound to create significant UI lag, especially on:

- Dashboard load and tab switches
- Statistics calculations
- Map rendering
- Sync operations

The root causes are:

1. **Repeated full-array iterations** in computed properties
2. **Lack of caching** for expensive grouping operations
3. **Eager evaluation** of NavigationLink destinations
4. **O(n²) algorithms** in deduplication

---

## Critical Issues

### 1. QSOStatistics - Cascading O(n) Operations

**File:** `CarrierWave/Views/Dashboard/QSOStatistics.swift`
**Severity:** 🔴 Critical

The `QSOStatistics` struct has severe performance issues:

```swift
// realQSOs is computed on EVERY property access
private var realQSOs: [QSO] {
    qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
}

var uniqueEntities: Int {
    Set(realQSOs.compactMap { $0.dxccEntity?.number }).count  // filters 15k, then iterates 15k
}

var uniqueGrids: Int {
    Set(realQSOs.compactMap(\.theirGrid).filter { !$0.isEmpty }).count  // filters 15k, then iterates 15k
}
```

**Impact:** Each dashboard render triggers:
- `totalQSOs` → 1x filter (15k ops)
- `uniqueEntities` → 1x filter + 1x compactMap + dxccEntity lookups (45k+ ops)
- `uniqueGrids` → 1x filter + 1x compactMap + 1x filter (45k ops)
- `uniqueBands` → 1x filter + 1x map (30k ops)
- `confirmedQSLs` → 1x filter + 1x filter (30k ops)
- `uniqueParks` → 1x filter + 1x compactMap + 1x filter (45k ops)
- `successfulActivations` → 1x filter + 1x filter + 1x grouping (60k+ ops)
- `attemptedActivations` → Same as above (60k+ ops) - **duplicated work!**
- `activityByDate` → 1x iteration (15k ops)
- `items(for: .frequencies)` → 1x filter + 1x filter + 1x grouping (45k+ ops)
- ...and more for each stat category

**Estimated operations per dashboard render:** 400k-600k+ with 15k QSOs

**Additional issue:** `successfulActivations` and `attemptedActivations` perform identical grouping operations but filter differently. The grouping should be done once.

**Additional issue:** DateFormatter is created inside `groupedByPark()` on each call:
```swift
private func groupedByPark() -> [StatCategoryItem] {
    let dateFormatter = DateFormatter()  // Created every time!
    dateFormatter.dateStyle = .medium
    // ...
}
```

---

### 2. DashboardView - Stats Recomputed on Every Render

**File:** `CarrierWave/Views/Dashboard/DashboardView.swift`
**Severity:** 🔴 Critical

While DashboardView has QSOStatistics caching, it's only keyed on `qsos.count`:

```swift
var stats: QSOStatistics {
    if let cached = cachedStats, qsos.count == lastQSOCount {
        return cached
    }
    return QSOStatistics(qsos: qsos)  // Still computes everything on cache miss
}
```

**Problem 1:** Cache invalidates on ANY QSO count change, even when stats don't need full recompute.

**Problem 2:** Multiple stats properties accessed in body still trigger internal iterations:
```swift
var body: some View {
    // ...
    Text("\(stats.totalQSOs) QSOs")     // triggers realQSOs filter
    ActivityGrid(activityData: stats.activityByDate)  // iterates all QSOs
    StreaksCard(dailyStreak: stats.dailyStreak, ...)  // not shown but likely expensive
    // ...
}
```

**Problem 3:** FavoritesCard calls multiple expensive methods:
```swift
// Each of these triggers full array grouping
stats.topFrequencies(limit: 1)
stats.topFriends(limit: 1)
stats.topHunters(limit: 1)
stats.items(for: .frequencies)  // computed for NavigationLink destination
stats.items(for: .bestFriends)
stats.items(for: .bestHunters)
```

**Problem 4:** Service counts iterate all presence records:
```swift
func uploadedCount(for service: ServiceType) -> Int {
    allPresence.filter { $0.serviceType == service && $0.isPresent }.count
}
```
With 15k QSOs × 5 services = 75k presence records, each call is 75k comparisons.

---

### 3. LogsListView - Filtering Without Caching

**File:** `CarrierWave/Views/Logs/LogsListView.swift`
**Severity:** 🟠 High

```swift
private var filteredQSOs: [QSO] {
    qsos.filter { qso in
        let matchesSearch = searchText.isEmpty || qso.callsign.localizedCaseInsensitiveContains(searchText)
            || (qso.parkReference?.localizedCaseInsensitiveContains(searchText) ?? false)
        let matchesBand = selectedBand == nil || qso.band == selectedBand
        let matchesMode = selectedMode == nil || qso.mode == selectedMode
        return matchesSearch && matchesBand && matchesMode
    }
}

private var availableBands: [String] {
    Array(Set(qsos.map(\.band))).sorted()  // 15k map + Set creation + sort
}

private var availableModes: [String] {
    Array(Set(qsos.map(\.mode))).sorted()  // 15k map + Set creation + sort
}
```

**Impact:** Every view body evaluation:
- Filters 15k QSOs (with case-insensitive string comparison)
- Creates sets from 15k items for band/mode menus
- Sorts resulting arrays

---

### 4. QSOMapView - Multiple Expensive Computed Properties

**File:** `CarrierWave/Views/Map/QSOMapView.swift`
**Severity:** 🟠 High

While map has some caching (`cachedAnnotations`, `cachedArcs`), the overlay stats are still computed:

```swift
MapStatsOverlay(
    totalQSOs: allQSOs.count,           // O(1) - fine
    visibleQSOs: filteredQSOs.count,    // Triggers full filter!
    gridCount: cachedAnnotations.count, // O(1) - fine
    stateCount: uniqueStates,           // Filters + compactMaps
    dxccCount: uniqueDXCCEntities       // Filters + compactMaps + lookups
)

private var uniqueStates: Int {
    Set(filteredQSOs.compactMap(\.state).filter { !$0.isEmpty }).count
}

private var uniqueDXCCEntities: Int {
    Set(filteredQSOs.compactMap { $0.dxccEntity?.number }).count
}
```

**Additional issue:** `availableBands`, `availableModes`, `availableParks`, `earliestQSODate` all iterate over `allQSOs` but are only used for filter sheet:

```swift
private var availableBands: [String] {
    Array(Set(allQSOs.map(\.band))).sorted { ... }  // 15k iterations
}
```

---

### 5. StatDetailView - Sorting on Every Render

**File:** `CarrierWave/Views/Dashboard/StatDetailView.swift`
**Severity:** 🟡 Medium

```swift
private var sortedItems: [StatCategoryItem] {
    switch sortMode {
    case .date:
        items.sorted { ... }  // Sorts array on every body evaluation
    case .count:
        items.sorted { $0.count > $1.count }
    case .alphabetical:
        items.sorted { ... }
    }
}
```

For entities view with hundreds of items, this is O(n log n) per render.

---

### 6. StatCategoryItem - Stores Full QSO Arrays

**File:** `CarrierWave/Models/StatCategoryItem.swift`
**Severity:** 🟡 Medium

Each `StatCategoryItem` contains a full array of QSOs:

```swift
struct StatCategoryItem {
    let identifier: String
    let description: String
    let qsos: [QSO]  // Could be thousands for popular entities
    // ...
}
```

For "United States" DXCC entity, this could be 10k+ QSOs stored in the item. When these items are passed through the view hierarchy, they carry substantial memory.

---

### 7. DeduplicationService - O(n²) Worst Case

**File:** `CarrierWave/Services/DeduplicationService.swift`
**Severity:** 🟡 Medium (mitigated by time window)

```swift
for i in 0 ..< allQSOs.count {
    // ...
    for j in (i + 1) ..< allQSOs.count {
        let timeDelta = candidate.timestamp.timeIntervalSince(qso.timestamp)
        if timeDelta > timeWindow {
            break  // Time window helps
        }
        if isDuplicate(qso, candidate) {
            // ...
        }
    }
}
```

While the time window prevents true O(n²), this still scans many records when there's high QSO density.

---

### 8. SyncService+Process - Full Database Scan for Reconciliation

**File:** `CarrierWave/Services/SyncService+Process.swift`
**Severity:** 🟡 Medium

```swift
func reconcileQRZPresence(downloadedKeys: Set<String>) async throws {
    let descriptor = FetchDescriptor<QSO>()
    let allQSOs = try modelContext.fetch(descriptor)  // Fetches ALL 15k QSOs

    for qso in allQSOs {
        guard let presence = qso.presence(for: .qrz), presence.isPresent else {
            continue
        }
        // ...
    }
}
```

---

### 9. QSO.dxccEntity - Lookup on Every Access

**File:** `CarrierWave/Models/QSO.swift`
**Severity:** 🟡 Medium

```swift
var dxccEntity: DXCCEntity? {
    if let dxcc {
        return DescriptionLookup.dxccEntity(forNumber: dxcc)  // Lookup every time
    }
    return nil
}
```

Used frequently in grouping operations, this compounds the problem.

---

## Recommendations

### Immediate Fixes (High Impact)

#### 1. Cache `realQSOs` and Derived Statistics

```swift
struct QSOStatistics {
    let qsos: [QSO]

    // Lazy cached properties
    private lazy var _realQSOs: [QSO] = {
        qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
    }()

    private lazy var _activationGroups: [String: [QSO]] = {
        let parksOnly = _realQSOs.filter { $0.parkReference?.isEmpty == false }
        return Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
    }()

    var successfulActivations: Int {
        _activationGroups.values.filter { $0.count >= 10 }.count
    }

    var attemptedActivations: Int {
        _activationGroups.values.filter { $0.count < 10 }.count
    }
}
```

**Note:** This requires making QSOStatistics a class or using a cache pattern since structs can't have lazy vars with mutation.

#### 2. Pre-compute Dashboard Stats Asynchronously

Move expensive stats computation off the main thread:

```swift
.task(id: qsos.count) {
    let stats = await Task.detached(priority: .userInitiated) {
        QSOStatistics(qsos: qsos)  // Heavy computation
    }.value
    await MainActor.run {
        cachedStats = stats
    }
}
```

#### 3. Make LogsListView Filter Reactive

Cache filtered results with `@State`:

```swift
@State private var filteredQSOs: [QSO] = []

var body: some View {
    List { ... }
    .onChange(of: searchText) { updateFilter() }
    .onChange(of: selectedBand) { updateFilter() }
    .onChange(of: selectedMode) { updateFilter() }
    .task { updateFilter() }
}

private func updateFilter() {
    filteredQSOs = qsos.filter { ... }
}
```

#### 4. Defer NavigationLink Destination Computation

Use lazy destinations:

```swift
NavigationLink {
    // Compute items lazily when navigation occurs
    StatDetailView(
        category: .entities,
        items: stats.items(for: .entities),
        tourState: tourState
    )
} label: {
    StatBox(title: "DXCC Entities", value: "\(stats.uniqueEntities)", icon: "globe")
}
```

Or use programmatic navigation to defer entirely.

#### 5. Cache Available Bands/Modes/Parks

These rarely change and shouldn't be recomputed on every render:

```swift
@State private var availableBands: [String] = []
@State private var availableModes: [String] = []

.onChange(of: qsos.count) {
    availableBands = Array(Set(qsos.map(\.band))).sorted()
    availableModes = Array(Set(qsos.map(\.mode))).sorted()
}
```

### Medium-Term Improvements

#### 6. Use SwiftData Queries with Aggregation

Replace in-memory counting with database queries:

```swift
// Instead of iterating all QSOs
let uniqueBands = Set(qsos.map(\.band)).count

// Use SwiftData predicate-based queries
@Query(filter: #Predicate<QSO> { !$0.isHidden })
var qsos: [QSO]

// Or use fetch with specific projections
let descriptor = FetchDescriptor<QSO>(propertiesToFetch: [\QSO.band])
```

#### 7. StatCategoryItem - Store IDs Instead of Objects

```swift
struct StatCategoryItem {
    let identifier: String
    let description: String
    let qsoIds: [UUID]  // Lightweight references
    let count: Int      // Pre-computed count
}
```

Fetch actual QSOs only when expanding the row.

#### 8. Implement Incremental Statistics

Track stats incrementally rather than recomputing:

```swift
class IncrementalQSOStats {
    private var uniqueBands: Set<String> = []
    private var uniqueEntities: Set<Int> = []
    // ...

    func addQSO(_ qso: QSO) {
        uniqueBands.insert(qso.band)
        if let dxcc = qso.dxcc {
            uniqueEntities.insert(dxcc)
        }
    }

    func removeQSO(_ qso: QSO) {
        // More complex - need reference counting
    }
}
```

#### 9. Cache DXCC Entity Lookups

```swift
@Model
final class QSO {
    // Add cached DXCC name
    var cachedDXCCName: String?

    var dxccEntity: DXCCEntity? {
        if let dxcc {
            if cachedDXCCName == nil {
                cachedDXCCName = DescriptionLookup.dxccEntity(forNumber: dxcc)?.name
            }
            return DescriptionLookup.dxccEntity(forNumber: dxcc)
        }
        return nil
    }
}
```

### Long-Term Architecture

#### 10. Dedicated Statistics Service

Create a background service that maintains precomputed statistics:

```swift
@MainActor
class StatisticsService: ObservableObject {
    @Published var totalQSOs: Int = 0
    @Published var uniqueBands: Int = 0
    @Published var uniqueEntities: Int = 0
    @Published var activityByDate: [Date: Int] = [:]
    // ...

    private var observer: Any?

    func startObserving(modelContext: ModelContext) {
        // Listen for SwiftData changes
        // Incrementally update stats
    }
}
```

---

## Testing Approach

1. **Profile with Instruments** (SwiftUI template)
   - Look for view body updates > 16ms
   - Check "Long View Body Updates" lane

2. **Add timing instrumentation:**
```swift
let start = CFAbsoluteTimeGetCurrent()
let stats = QSOStatistics(qsos: qsos)
print("Stats computation: \((CFAbsoluteTimeGetCurrent() - start) * 1000)ms")
```

3. **Test with realistic data:**
   - 5k QSOs (baseline)
   - 15k QSOs (target)
   - 50k QSOs (stress test)

---

## Priority Order

1. 🔴 **QSOStatistics caching** - Highest impact
2. 🔴 **Dashboard async computation** - User-facing
3. 🟠 **LogsListView filter caching** - Common interaction
4. 🟠 **Map stats caching** - User-facing
5. 🟡 **NavigationLink lazy destinations** - Memory + initial compute
6. 🟡 **StatCategoryItem lightweight references** - Memory
7. 🟡 **Service presence query optimization** - Database
8. 🟢 **Incremental stats** - Long-term scalability
