# Performance Guidelines

> **Goal**: Keep the app responsive at 60fps. View bodies should complete in <16ms.
> CW Sweep shares Carrier Wave's iCloud SwiftData store — expect tens of thousands of QSOs.

---

## BANNED: @Query for QSO or ServicePresence

**`@Query` is BANNED for QSO and ServicePresence tables.** This is the #1 cause of UI freezes in Carrier Wave and applies equally here since both apps share the same iCloud-synced SwiftData store.

```swift
// BANNED - will cause multi-second freezes for users with large databases
@Query var qsos: [QSO]
@Query(filter: #Predicate<QSO> { !$0.isHidden }) var qsos: [QSO]
@Query var presence: [ServicePresence]

// REQUIRED - use @State with manual FetchDescriptor + refresh trigger
@State private var qsos: [QSO] = []

.task {
    var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
    descriptor.fetchLimit = 500
    descriptor.sortBy = [SortDescriptor(\QSO.timestamp, order: .reverse)]
    qsos = (try? modelContext.fetch(descriptor)) ?? []
}
```

**Why @Query is dangerous:**
- Loads ALL matching records into memory synchronously
- Blocks the main thread during fetch
- Re-fetches on ANY SwiftData change, not just relevant changes
- Cannot be paginated or cancelled
- No way to add fetchLimit

**Approved alternatives:**
1. Manual `FetchDescriptor` with `fetchLimit` in `.task`
2. `@Observable` class that computes in background
3. Pass pre-fetched data as parameter from parent view

**Reactive refresh pattern** (used by `QSOLogTableView`):
```swift
// Initial load via .task + notification-based refresh via AsyncSequence.
// Use .task (not .onAppear) for the initial load — .task yields to the run loop
// before executing, giving SwiftData time to process any pending iCloud merges.
// .onAppear fires synchronously and may run before CloudKit data is available,
// resulting in stale/incomplete results.
.task { loadQSOs() }
.task { await observeStoreChanges(.NSPersistentStoreRemoteChange) }
.task { await observeStoreChanges(ModelContext.didSave) }

private func observeStoreChanges(_ name: Notification.Name) async {
    for await _ in NotificationCenter.default.notifications(named: name) {
        try? await Task.sleep(for: .seconds(1))  // Debounce
        guard !Task.isCancelled else { return }
        loadQSOs()
    }
}
```

---

## CRITICAL: No Full Table Scans

These rules are non-negotiable. Violating them causes multi-second UI freezes for users with large QSO databases.

### Rule 1: Always Set fetchLimit on QSO/ServicePresence Descriptors

```swift
// FORBIDDEN - loads ALL QSOs into memory
let descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })

// REQUIRED - paginate or limit
var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
descriptor.fetchLimit = 500
descriptor.sortBy = [SortDescriptor(\QSO.timestamp, order: .reverse)]
```

### Rule 1a: Paginate AFTER Deduplication

CloudKit mirrors every QSO ~3x (local + mirror zones). If you apply `fetchLimit` as the display count, dedup shrinks the result to ~1/3 of what the user expects.

**Always: fetch extra → dedup → then optionally trim.**

```swift
// WRONG - fetchLimit IS the display count, dedup shrinks it
descriptor.fetchLimit = 200          // Fetch 200
let fetched = try context.fetch(descriptor)
displayQSOs = dedup(fetched)         // Only ~67 unique QSOs shown!

// CORRECT - over-fetch generously, dedup, show all unique
descriptor.fetchLimit = 10_000       // Generous upper bound for ~3x duplication
let fetched = try context.fetch(descriptor)
var seen = Set<UUID>()
displayQSOs = fetched.filter { seen.insert($0.id).inserted }
```

This applies everywhere QSOs are fetched for display: tables, lists, maps, exports.

### Rule 1b: fetchCount Includes Duplicates — Dedup for Accurate Counts

`fetchCount` translates to `SELECT COUNT(*)` and counts every CloudKit mirror
record. For user-facing counts, fetch actual records and dedup by UUID:

```swift
// WRONG - shows 3x the real count
qsoCount = try modelContext.fetchCount(descriptor)

// CORRECT - fetch and dedup
var descriptor = FetchDescriptor<QSO>(predicate: ...)
descriptor.fetchLimit = 30_000
let fetched = (try? modelContext.fetch(descriptor)) ?? []
var seen = Set<UUID>()
qsoCount = fetched.filter { seen.insert($0.id).inserted }.count
```

### Rule 2: Never Filter/Map Collections in View Bodies

```swift
// FORBIDDEN - O(n) on every render
var body: some View {
    let filtered = allQSOs.filter { $0.band == "20m" }
    ForEach(filtered) { qso in ... }
}

// REQUIRED - use database predicate
let predicate = #Predicate<QSO> { $0.band == "20m" && !$0.isHidden }
let descriptor = FetchDescriptor(predicate: predicate)
```

### Rule 3: Never Load Data Synchronously in Input Handlers

```swift
// FORBIDDEN - blocks UI on first keystroke
.onChange(of: callsignInput) { _, newValue in
    let results = loadDataFromNetwork()  // Blocks!
}

// REQUIRED - async with cancellation and debounce
.onChange(of: callsignInput) { _, newValue in
    lookupTask?.cancel()
    lookupTask = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let results = await loadDataAsync()
    }
}
```

### Rule 4: Use Persistent Caches for Remote Data

Remote data (HamDB lookups, grid lookups, callsign state) must be cached with TTL:

```swift
actor MyCache {
    static let shared = MyCache()
    private var cache: [String: CacheEntry] = [:]
    private let expirationInterval: TimeInterval = 3_600  // 1 hour

    func get(_ key: String) -> Value?? {
        let normalized = key.uppercased()
        guard let entry = cache[normalized] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > expirationInterval {
            cache.removeValue(forKey: normalized)
            return nil
        }
        return entry.value
    }
}
```

Existing cache implementations: `GridCache`, `CallsignStateCache`, `CallsignInfoCache`.

---

## General Principles

### SwiftUI View Bodies

View bodies run on the main thread. Keep them fast.

**DO:**
```swift
var body: some View {
    Text(viewModel.cachedDisplayString)  // Read pre-computed value
}
```

**DON'T:**
```swift
var body: some View {
    Text(formatDate(date))  // Creates formatter every render
    Text("\(items.filter { $0.isActive }.count)")  // Filters on every render
}
```

### Formatter Caching

DateFormatter and NumberFormatter are expensive (~1-2ms each). Create once, reuse.

### Observable Dependencies

Each view should depend only on the data it needs. Whole-collection dependencies cause unnecessary updates.

### Collection Operations

```swift
// Reserve capacity when size is known
var results: [QSO] = []
results.reserveCapacity(input.count)

// Use lazy for short-circuit operations
let firstMatch = items.lazy.filter { $0.isValid }.first
```

### Async/Actor Operations

```swift
// DO: Batch actor calls
await syncService.uploadBatch(qsos)  // Single actor hop

// DON'T: Individual actor calls in a loop
for qso in qsos {
    await syncService.upload(qso)  // N actor hops!
}
```

---

## Critical Views

### Logger (ParsedEntryView)

Real-time input — must remain responsive during rapid typing.

**Requirements:**
- Text field updates must not trigger full view rebuilds
- Frequency/band changes should update only affected UI elements
- QSO submission should not block the UI
- Callsign lookups via `pendingSpotEntry` are instant (no network)

**Patterns:**
- `@State` for view-local text input
- Debounce network lookups (300-500ms minimum)
- Pre-compute display values in `ParsedFieldSummary`

### Spot Table (SpotListView)

Live-updating table with potentially hundreds of spots.

**Requirements:**
- SpotAggregator polling must not block the main thread
- Table selection must respond instantly
- Filtering (source/band/region/text) should be fast

**Patterns:**
- `filteredSpots` computed property uses server-side-like filtering (all in-memory but bounded by SpotAggregator's dedup)
- Spot pipeline runs on actors: RBN/POTA/SOTA/WWFF clients are all actors
- SpotAggregator is `@MainActor @Observable` — only stores the final deduplicated array

### Band Map (BandMapView)

Canvas rendering with potentially hundreds of spot markers.

**Requirements:**
- Canvas redraw must complete in <16ms
- Hit testing should use spatial indexing, not linear scan
- Spot updates should only redraw affected regions

### QSO Log Table (QSOLogTableView)

Displays all unique QSOs (up to ~3,000+) with sorting and selection.

**Requirements:**
- Must be reactive to iCloud sync (new QSOs appear without restart)
- Dedup, metadata-mode filtering happen in `loadQSOs()` — NOT in computed properties or view body
- Fetches up to 10,000 rows to compensate for CloudKit mirrors, dedup by UUID, show all unique
- Selection changes must be instant (no data loading)

---

## Metadata Pseudo-Modes

Modes `WEATHER`, `SOLAR`, `NOTE` are Ham2K PoLo activation metadata — NOT actual QSOs.

**NEVER** count in stats, display in tables, or include in any user-facing aggregation. Each filtering site defines its own `metadataModes: Set<String>`:

- `QSOLogTableView` (both `StandardQSOTable` and `ContestQSOTable`)
- `DashboardView.loadStatistics()`
- `SpotDetailInspector` previous QSO lookup (implicitly excluded by callsign predicate)

Keep these filter sets in sync.

---

## Background Thread Data Loading

For large data operations, use a background actor with a fresh ModelContext:

```swift
actor DataLoadingActor {
    func loadData(container: ModelContainer) async throws -> [Snapshot] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var descriptor = FetchDescriptor<QSO>(...)
        descriptor.fetchLimit = batchSize

        let batch = (try? context.fetch(descriptor)) ?? []
        // Convert to Sendable snapshots immediately
        return batch.map { Snapshot(from: $0) }
    }
}
```

**Key principles:**
- Create a fresh `ModelContext` on the background actor from the `ModelContainer`
- Convert managed objects to `Sendable` value types (snapshots) immediately after fetch
- Apply final results atomically on main actor
- Use `Task.checkCancellation()` between batches

**DON'T:**
```swift
// Don't pass ModelContext to background - it's not thread-safe
actor BadActor {
    func compute(context: ModelContext) async { ... }  // WRONG
}

// Don't pass managed objects across actors
let qsos = context.fetch(descriptor)
await backgroundActor.process(qsos)  // WRONG - QSO is not Sendable
```

---

## Hidden QSOs

Hidden (soft-deleted) QSOs must never appear in the UI or affect counts.

- All QSO queries MUST include `!$0.isHidden` predicate
- Statistics exclude hidden QSOs
- No in-memory filtering of `isHidden` — use database predicate

---

## Code Review Checklist

### CRITICAL (reject if violated)
- [ ] No `@Query` for QSO or ServicePresence
- [ ] No `FetchDescriptor` without `fetchLimit` for QSO/ServicePresence
- [ ] Dedup by UUID before display or counting — `fetchCount` includes CloudKit mirrors
- [ ] No network in `onChange` without 300ms+ debounce
- [ ] All QSO queries include `!$0.isHidden`
- [ ] Use `.task` (not `.onAppear`) for initial data loads from iCloud-synced stores

### View Bodies
- [ ] No formatter creation in body
- [ ] No filtering/sorting/mapping collections in body
- [ ] No SwiftData queries in body
- [ ] Computed properties cached where appropriate

### Lists and Collections
- [ ] `reserveCapacity` called when size is known
- [ ] Lazy loading for large datasets
- [ ] List/table rows are lightweight

### Async Operations
- [ ] Actor calls batched where possible
- [ ] Long operations show loading state, don't block UI
- [ ] Input handlers use debouncing

---

## Measuring Performance

1. **Profile with Instruments** (SwiftUI template) — look at "Long View Body Updates"
2. **Check for unnecessary updates** — add `let _ = Self._printChanges()` temporarily
3. **Time critical operations:**
   ```swift
   let start = CFAbsoluteTimeGetCurrent()
   // operation
   let elapsed = CFAbsoluteTimeGetCurrent() - start
   print("Operation took \(elapsed * 1000)ms")
   ```
4. **Watch for symptoms:** dropped frames, delayed taps, stuttering animations, slow role switches
