# Performance Guidelines

> **Goal**: Keep the app responsive at 60fps. View bodies should complete in <16ms.

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

DateFormatter and NumberFormatter are expensive to create (~1-2ms each). Create once, reuse.

**DO:**
```swift
// In a shared location or view model
private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()

var formattedDate: String {
    Self.dateFormatter.string(from: date)
}
```

**DON'T:**
```swift
var body: some View {
    let formatter = DateFormatter()  // Created every render!
    formatter.dateStyle = .short
    Text(formatter.string(from: date))
}
```

### Observable Dependencies

Each view should depend only on the data it needs. Whole-collection dependencies cause unnecessary updates.

**DO:**
```swift
// Per-item view model
@Observable
class QSORowViewModel {
    let qso: QSO
    var isFavorite: Bool = false
}

// View depends only on its own view model
struct QSORow: View {
    let viewModel: QSORowViewModel
    
    var body: some View {
        // Only updates when THIS qso's data changes
    }
}
```

**DON'T:**
```swift
struct QSORow: View {
    @Environment(DataStore.self) var store
    let qsoID: UUID
    
    var body: some View {
        // Accesses store.allQSOs - updates when ANY qso changes
        if let qso = store.allQSOs.first(where: { $0.id == qsoID }) {
            // ...
        }
    }
}
```

### Collection Operations

**DO:**
```swift
// Reserve capacity when size is known
var results: [QSO] = []
results.reserveCapacity(input.count)

// Use lazy for short-circuit operations
let firstMatch = items.lazy.filter { $0.isValid }.first
```

**DON'T:**
```swift
// Multiple reallocations
var results: [QSO] = []
for item in input {
    results.append(transform(item))  // Reallocates ~14 times for 10k items
}
```

### Async/Actor Operations

**DO:**
```swift
// Batch actor calls
await syncService.uploadBatch(qsos)  // Single actor hop

// Keep synchronous operations synchronous
func computeTotal() -> Int {  // No async needed
    items.reduce(0, +)
}
```

**DON'T:**
```swift
// Individual actor calls in a loop
for qso in qsos {
    await syncService.upload(qso)  // N actor hops!
}
```

### Background Computation with Cooperative Yielding

For expensive computations that must run on `@MainActor` (e.g., processing SwiftData objects that can't be sent to background threads), use cooperative yielding to prevent UI blocking.

**DO:**
```swift
@MainActor
func computeExpensiveStats() {
    // Show instant results immediately
    totalCount = items.count
    
    // Defer expensive work with yielding
    computeTask = Task {
        expensiveResult1 = computePhase1()
        await Task.yield()  // Let UI update
        guard !Task.isCancelled else { return }
        
        expensiveResult2 = computePhase2()
        await Task.yield()
        guard !Task.isCancelled else { return }
        
        expensiveResult3 = computePhase3()
    }
}
```

**Key principles:**
- Split work into phases with `Task.yield()` between each
- Check `Task.isCancelled` after each yield to support cancellation
- Show placeholder UI (e.g., "--" or dimmed state) for pending values
- Use a threshold to skip yielding for small datasets where it's unnecessary
- Don't cancel on tab switch - let computation finish in background
- Only cancel when new computation supersedes old (e.g., data changed)

**DON'T:**
```swift
// Don't block the main thread with synchronous heavy work
func computeStats() {
    result = items.map { expensiveTransform($0) }  // Blocks UI!
}

// Don't cancel on every onDisappear - user loses progress
.onDisappear {
    computeTask?.cancel()  // User switching tabs loses computation progress
}
```

---

## Critical Views

These views have specific performance requirements due to complexity or frequent updates.

### Logger View

The logger view handles real-time input and must remain responsive during rapid typing.

**Requirements:**
- Text field updates must not trigger full view rebuilds
- Frequency/band changes should update only affected UI elements
- QSO submission should not block the UI

**Patterns to follow:**
```swift
// Isolate text input state
@State private var callsignInput: String = ""  // Local to text field

// Debounce lookups
.onChange(of: callsignInput) { _, newValue in
    lookupTask?.cancel()
    lookupTask = Task {
        try await Task.sleep(for: .milliseconds(300))
        await performLookup(newValue)
    }
}

// Pre-compute display values
// Cache band/mode display strings in view model, not in body
```

**Avoid:**
- SwiftData queries in the view body
- Callsign lookups on every keystroke (debounce)
- Recomputing frequency↔band mappings on each render

### Map View

Map views with many annotations are expensive. The QSO map may display hundreds of pins.

**Requirements:**
- Limit visible annotations to viewport + buffer
- Cluster pins at low zoom levels
- Defer annotation updates during pan/zoom gestures

**Patterns to follow:**
```swift
// Cluster annotations
Map {
    ForEach(visibleClusters) { cluster in
        if cluster.count > 1 {
            ClusterAnnotation(cluster)
        } else {
            QSOAnnotation(cluster.qsos[0])
        }
    }
}

// Update visible set only when region change settles
.onMapCameraChange(frequency: .onEnd) { context in
    updateVisibleQSOs(for: context.region)
}

// Use lightweight annotation views
struct QSOAnnotation: View {
    let qso: QSO
    var body: some View {
        // Simple circle, not complex view hierarchy
        Circle()
            .fill(colorForBand(qso.band))
            .frame(width: 12, height: 12)
    }
}
```

**Avoid:**
- Rendering all QSOs regardless of viewport
- Complex annotation views with multiple subviews
- Updating annotations during active gestures
- Fetching QSO details for each annotation in the body

### Tab Transitions

Tab changes should feel instant. Heavy views should defer loading.

**Requirements:**
- Tab switch should complete in <100ms
- Defer expensive data loading until tab is visible
- Preserve scroll position when returning to tabs

**Patterns to follow:**
```swift
// Lazy initialization
struct DashboardView: View {
    @State private var hasAppeared = false
    
    var body: some View {
        Group {
            if hasAppeared {
                DashboardContent()
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
            }
        }
    }
}

// Use task for async loading
.task {
    await loadDashboardData()
}

// Preserve state with @SceneStorage or view model
@SceneStorage("logsScrollPosition") private var scrollPosition: String?
```

**Avoid:**
- Synchronous data fetching in `onAppear`
- Rebuilding entire view hierarchies on tab switch
- Blocking the main thread during tab transitions
- Loading all data upfront in the tab view itself

---

## Code Review Checklist

When reviewing code for performance, verify:

### View Bodies
- [ ] No formatter creation in body
- [ ] No filtering/sorting/mapping collections in body
- [ ] No SwiftData queries in body
- [ ] Computed properties are cached in view model where appropriate

### Observable/State
- [ ] Views depend only on data they display
- [ ] No whole-collection dependencies for list items
- [ ] `@State` used for view-local ephemeral state
- [ ] `@Environment` values don't change frequently

### Lists and Collections
- [ ] `reserveCapacity` called when size is known
- [ ] Lazy loading for large datasets
- [ ] List rows are lightweight

### Async Operations
- [ ] Actor calls are batched where possible
- [ ] Synchronous functions don't use `async` unnecessarily
- [ ] Long operations show loading state, don't block UI

### Critical Views (Logger, Map, Tabs)
- [ ] Logger: Input is debounced, lookups don't block typing
- [ ] Map: Annotations limited to viewport, clustering enabled
- [ ] Tabs: Heavy content deferred until visible

### Hidden QSOs
- [ ] All QSO queries include `!$0.isHidden` predicate
- [ ] Statistics exclude hidden QSOs
- [ ] No in-memory filtering of `isHidden`

### Large Collections
- [ ] No linear scans of unbounded collections
- [ ] Batch processing for bulk operations
- [ ] Fetch limits used where appropriate
- [ ] Pagination for long lists

---

## Measuring Performance

When investigating slowdowns:

1. **Profile with Instruments** (SwiftUI template)
   - Look at "Long View Body Updates" lane
   - Check for orange/red bars indicating slow updates

2. **Check for unnecessary updates**
   - Add `let _ = Self._printChanges()` temporarily to view body
   - Look for updates when data hasn't changed

3. **Time critical operations**
   ```swift
   let start = CFAbsoluteTimeGetCurrent()
   // operation
   let elapsed = CFAbsoluteTimeGetCurrent() - start
   print("Operation took \(elapsed * 1000)ms")
   ```

4. **Watch for symptoms**
   - Dropped frames during scrolling
   - Delayed response to taps
   - Stuttering animations
   - Slow tab switches

---

## Hidden QSOs

Hidden (soft-deleted) QSOs must never impact UI performance. They exist only for data recovery.

**Requirements:**
- Hidden QSOs must be excluded from all queries via `#Predicate { !$0.isHidden }`
- Never include hidden QSOs in counts, statistics, or aggregations
- Scrolling, searching, and filtering must operate only on visible QSOs
- The hidden QSOs view (Settings → Developer → Hidden QSOs) is the only place they appear

**Patterns to follow:**
```swift
// Always filter out hidden QSOs in queries
@Query(
    filter: #Predicate<QSO> { !$0.isHidden },
    sort: \QSO.timestamp,
    order: .reverse
)
private var visibleQSOs: [QSO]

// Statistics should exclude hidden QSOs
func calculateStats() -> Stats {
    let descriptor = FetchDescriptor<QSO>(
        predicate: #Predicate { !$0.isHidden }
    )
    // ...
}
```

**Avoid:**
- Fetching all QSOs and filtering `isHidden` in memory
- Including hidden QSOs in any user-facing aggregation
- Counting hidden QSOs toward totals or progress

---

## Large Collections

Expect users to have tens or hundreds of thousands of QSOs. Design for scale.

**Requirements:**
- Never scan entire collections - use indexed queries with predicates
- No linear operations (O(n)) on full QSO sets in view bodies
- Work in batches for bulk operations
- Use SwiftData indexes on frequently queried fields

**Patterns to follow:**
```swift
// Use predicates to filter at the database level
let descriptor = FetchDescriptor<QSO>(
    predicate: #Predicate { qso in
        qso.parkReference == targetPark && !qso.isHidden
    },
    sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
)
descriptor.fetchLimit = 100  // Limit results when possible

// Batch operations
let batchSize = 100
for startIndex in stride(from: 0, to: items.count, by: batchSize) {
    let endIndex = min(startIndex + batchSize, items.count)
    let batch = Array(items[startIndex..<endIndex])
    await processBatch(batch)
}

// Use pagination for large lists
@Query(sort: \QSO.timestamp, order: .reverse)
private var qsos: [QSO]

// Only render visible portion
ForEach(qsos.prefix(visibleCount)) { qso in
    QSORow(qso: qso)
}
```

**Indexing:**
SwiftData models should have indexes on frequently queried fields:
```swift
@Model
final class QSO {
    // These fields are frequently used in predicates
    @Attribute(.spotlight) var callsign: String  // Indexed for search
    var timestamp: Date  // Sorted frequently
    var parkReference: String?  // Filtered by park
    var isHidden: Bool  // Filtered in every query
    // ...
}
```

**Avoid:**
- `allQSOs.filter { ... }` in view bodies
- `allQSOs.count` when you only need to check if empty
- Loading all QSOs to find a single match
- Sorting entire collections when only showing top N
- Any O(n) or O(n²) operations on unbounded collections

---

## Memory Considerations

Performance includes memory efficiency:

- **Closures**: Use `[weak self]` to prevent retain cycles
- **Timers**: Invalidate in `deinit` or when view disappears
- **Observers**: Remove NotificationCenter observers
- **Images**: Use appropriate resolution, don't load full-size for thumbnails
- **SwiftData**: Fetch only needed properties with `#Predicate`
