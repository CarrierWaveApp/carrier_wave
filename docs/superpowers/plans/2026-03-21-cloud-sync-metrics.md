# Cloud Sync Metrics & Activity Log Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add in-app sync metrics dashboard and event timeline to the iCloud sync settings screen.

**Architecture:** New `CloudSyncEvent` struct and `CloudSyncEventLog` actor in CarrierWaveData for persistent event storage. Instrumentation added to `CloudSyncEngine` delegate callbacks. New `CloudSyncSummary` struct computed from events. UI split between inline summary in existing settings view and a new `CloudSyncActivityView` timeline screen.

**Tech Stack:** SwiftUI, SwiftData (existing), CKSyncEngine (existing), JSON file persistence, ContinuousClock for timing.

**Spec:** `docs/superpowers/specs/2026-03-21-cloud-sync-metrics-design.md`

---

### Task 1: CloudSyncEvent and CloudSyncSummary Data Types

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEvent.swift`
- Create: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncSummary.swift`
- Test: `CarrierWaveTests/CloudSyncEventTests.swift`

- [ ] **Step 1: Write tests for CloudSyncEvent Codable round-trip and CloudSyncSummary computation**

```swift
import Foundation
import Testing

@testable import CarrierWaveData

@Suite("CloudSyncEvent")
struct CloudSyncEventTests {
    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let event = CloudSyncEvent(
            category: .fetch,
            entityType: "QSO",
            detail: "Received 42 QSOs",
            recordCount: 42,
            duration: 1.234
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CloudSyncEvent.self, from: data)
        #expect(decoded.id == event.id)
        #expect(decoded.category == .fetch)
        #expect(decoded.entityType == "QSO")
        #expect(decoded.detail == "Received 42 QSOs")
        #expect(decoded.recordCount == 42)
        #expect(decoded.duration == 1.234)
    }

    @Test("Codable round-trip with nil optional fields")
    func codableNilFields() throws {
        let event = CloudSyncEvent(
            category: .accountChange,
            detail: "Signed in"
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(CloudSyncEvent.self, from: data)
        #expect(decoded.entityType == nil)
        #expect(decoded.recordCount == nil)
        #expect(decoded.duration == nil)
    }

    @Test("Summary computes last fetch from events")
    func summaryLastFetch() {
        let events = [
            CloudSyncEvent(
                category: .fetch,
                detail: "Fetch 1",
                recordCount: 10,
                duration: 0.5
            ),
            CloudSyncEvent(
                category: .fetch,
                detail: "Fetch 2",
                recordCount: 20,
                duration: 1.0
            ),
            CloudSyncEvent(
                category: .upload,
                detail: "Upload 1",
                recordCount: 5,
                duration: 0.3
            ),
        ]
        let summary = CloudSyncSummary.from(events: events)
        #expect(summary.lastFetchRecordCount == 20)
        #expect(summary.lastFetchDuration == 1.0)
        #expect(summary.lastUploadRecordCount == 5)
    }

    @Test("Summary counts today's conflicts and errors")
    func summaryTodayCounts() {
        let today = Date()
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1, to: today
        )!
        let events = [
            CloudSyncEvent(
                category: .conflict,
                detail: "Conflict 1"
            ),
            CloudSyncEvent(
                category: .conflict,
                detail: "Conflict 2"
            ),
            CloudSyncEvent(
                category: .error,
                detail: "Error 1"
            ),
            CloudSyncEvent(
                timestamp: yesterday,
                category: .error,
                detail: "Old error"
            ),
        ]
        let summary = CloudSyncSummary.from(events: events)
        #expect(summary.conflictsToday == 2)
        #expect(summary.errorsToday == 1)
    }

    @Test("Empty events produce empty summary")
    func summaryEmpty() {
        let summary = CloudSyncSummary.from(events: [])
        #expect(summary.lastFetchDate == nil)
        #expect(summary.lastUploadDate == nil)
        #expect(summary.conflictsToday == 0)
        #expect(summary.errorsToday == 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xc test-unit` (or verify file doesn't compile since types don't exist yet)
Expected: Compilation failure — `CloudSyncEvent` and `CloudSyncSummary` not defined.

- [ ] **Step 3: Create CloudSyncEvent.swift**

```swift
// CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEvent.swift
import Foundation

/// A single sync event for the activity log. Stored as JSON, not SwiftData.
public struct CloudSyncEvent: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        timestamp: Date = Date(),
        category: Category,
        entityType: String? = nil,
        detail: String,
        recordCount: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        id = UUID()
        self.timestamp = timestamp
        self.category = category
        self.entityType = entityType
        self.detail = detail
        self.recordCount = recordCount
        self.duration = duration
    }

    // MARK: Public

    public let id: UUID
    public let timestamp: Date
    public let category: Category
    public let entityType: String?
    public let detail: String
    public let recordCount: Int?
    public let duration: TimeInterval?
}

// MARK: CloudSyncEvent.Category

public extension CloudSyncEvent {
    enum Category: String, Codable, Sendable {
        case fetch
        case upload
        case conflict
        case error
        case accountChange
    }
}
```

- [ ] **Step 4: Create CloudSyncSummary.swift**

```swift
// CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncSummary.swift
import Foundation

/// Dashboard summary computed from recent sync events.
public struct CloudSyncSummary: Sendable {
    // MARK: Public

    public static let empty = CloudSyncSummary(
        lastFetchDate: nil, lastFetchDuration: nil,
        lastFetchRecordCount: nil, lastUploadDate: nil,
        lastUploadDuration: nil, lastUploadRecordCount: nil,
        conflictsToday: 0, errorsToday: 0
    )

    public let lastFetchDate: Date?
    public let lastFetchDuration: TimeInterval?
    public let lastFetchRecordCount: Int?
    public let lastUploadDate: Date?
    public let lastUploadDuration: TimeInterval?
    public let lastUploadRecordCount: Int?
    public let conflictsToday: Int
    public let errorsToday: Int

    public static func from(events: [CloudSyncEvent]) -> CloudSyncSummary {
        let todayStart = Calendar.current.startOfDay(for: Date())

        let lastFetch = events.last { $0.category == .fetch }
        let lastUpload = events.last { $0.category == .upload }

        let conflicts = events.reduce(into: 0) { count, event in
            if event.category == .conflict, event.timestamp >= todayStart {
                count += 1
            }
        }
        let errors = events.reduce(into: 0) { count, event in
            if event.category == .error, event.timestamp >= todayStart {
                count += 1
            }
        }

        return CloudSyncSummary(
            lastFetchDate: lastFetch?.timestamp,
            lastFetchDuration: lastFetch?.duration,
            lastFetchRecordCount: lastFetch?.recordCount,
            lastUploadDate: lastUpload?.timestamp,
            lastUploadDuration: lastUpload?.duration,
            lastUploadRecordCount: lastUpload?.recordCount,
            conflictsToday: conflicts,
            errorsToday: errors
        )
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xc test-unit`
Expected: All CloudSyncEventTests pass.

- [ ] **Step 6: Commit**

```
feat: add CloudSyncEvent and CloudSyncSummary data types
```

---

### Task 2: CloudSyncEventLog Actor

**Files:**
- Create: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEventLog.swift`
- Test: `CarrierWaveTests/CloudSyncEventLogTests.swift`

- [ ] **Step 1: Write tests for event log persistence, pruning, and loading**

```swift
import Foundation
import Testing

@testable import CarrierWaveData

@Suite("CloudSyncEventLog")
struct CloudSyncEventLogTests {
    @Test("Append and retrieve events")
    func appendAndRetrieve() async {
        let log = CloudSyncEventLog(
            fileURL: tempFileURL()
        )
        let event = CloudSyncEvent(
            category: .fetch, detail: "Test fetch"
        )
        await log.append(event)
        let events = await log.allEvents()
        #expect(events.count == 1)
        #expect(events[0].detail == "Test fetch")
    }

    @Test("Events persist to disk and reload")
    func persistAndReload() async throws {
        let url = tempFileURL()
        let log1 = CloudSyncEventLog(fileURL: url)
        await log1.append(
            CloudSyncEvent(category: .fetch, detail: "Persisted")
        )

        let log2 = CloudSyncEventLog(fileURL: url)
        await log2.load()
        let events = await log2.allEvents()
        #expect(events.count == 1)
        #expect(events[0].detail == "Persisted")
    }

    @Test("Prunes to maxEvents FIFO")
    func pruning() async {
        let log = CloudSyncEventLog(
            fileURL: tempFileURL(), maxEvents: 5
        )
        for idx in 0 ..< 8 {
            await log.append(
                CloudSyncEvent(
                    category: .fetch, detail: "Event \(idx)"
                )
            )
        }
        let events = await log.allEvents()
        #expect(events.count == 5)
        #expect(events[0].detail == "Event 3")
        #expect(events[4].detail == "Event 7")
    }

    @Test("Load with missing file returns empty")
    func loadMissingFile() async {
        let log = CloudSyncEventLog(
            fileURL: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).json")
        )
        await log.load()
        let events = await log.allEvents()
        #expect(events.isEmpty)
    }

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sync_events_\(UUID()).json")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Expected: Compilation failure — `CloudSyncEventLog` not defined.

- [ ] **Step 3: Create CloudSyncEventLog.swift**

```swift
// CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEventLog.swift
import Foundation
import os

/// Persists sync events to a JSON file with FIFO retention.
public actor CloudSyncEventLog {
    // MARK: Lifecycle

    public init(
        fileURL: URL? = nil,
        maxEvents: Int = 500
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let libDir = FileManager.default.urls(
                for: .libraryDirectory, in: .userDomainMask
            ).first!
            self.fileURL = libDir
                .appendingPathComponent("CloudSync", isDirectory: true)
                .appendingPathComponent("sync_events.json")
        }
        self.maxEvents = maxEvents
    }

    // MARK: Public

    /// Load events from disk. Call once during service configuration.
    public func load() {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try JSONDecoder().decode(
                [CloudSyncEvent].self, from: data
            )
        } catch {
            logger.warning(
                "Failed to load sync events: \(error.localizedDescription)"
            )
        }
    }

    /// Append an event, prune if over capacity, write to disk.
    public func append(_ event: CloudSyncEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        writeToDisk()
    }

    /// Return current snapshot of all events.
    public func allEvents() -> [CloudSyncEvent] {
        events
    }

    // MARK: Private

    private var events: [CloudSyncEvent] = []
    private let fileURL: URL
    private let maxEvents: Int
    private let logger = Logger(
        subsystem: "com.jsvana.FullDuplex",
        category: "CloudSyncEventLog"
    )

    private func writeToDisk() {
        do {
            let dir = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true
                )
            }
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: .atomic)

            // Exclude from backup
            var resourceURL = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resourceURL.setResourceValues(values)
        } catch {
            logger.warning(
                "Failed to write sync events: \(error.localizedDescription)"
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xc test-unit`
Expected: All CloudSyncEventLogTests pass.

- [ ] **Step 5: Commit**

```
feat: add CloudSyncEventLog actor with JSON persistence and FIFO pruning
```

---

### Task 3: Wire EventLog into CloudSyncEngine and Add Timing Properties

**Files:**
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine.swift`
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+Helpers.swift`

- [ ] **Step 1: Add eventLog, timing properties, and inbound counters to CloudSyncEngine**

In `CloudSyncEngine.swift`, add to the internal properties (after line 162):

```swift
/// Event log for sync metrics
let eventLog = CloudSyncEventLog()

/// Timing: fetch cycle start
var fetchStartTime: ContinuousClock.Instant?
/// Timing: send cycle start
var sendCycleStartTime: ContinuousClock.Instant?
/// Accumulated record count for current send cycle
var sendCycleRecordCount: Int = 0

/// Inbound counters — reset on willFetchChanges, read on didFetchChanges
var fetchInboundCounts: [String: Int] = [:]
var fetchMergeCount: Int = 0
var fetchInsertCount: Int = 0
var fetchDeletionCount: Int = 0
```

- [ ] **Step 2: Replace `break` in willFetchChanges and willSendChanges with timestamp capture**

In `CloudSyncEngine.swift` `handleEvent`, replace the `willFetchChanges` case (line 127):

```swift
case .willFetchChanges:
    await resetFetchCounters()

case .willFetchRecordZoneChanges:
    break
```

Replace the `willSendChanges` case (line 137):

```swift
case .willSendChanges:
    await resetSendCounters()
```

- [ ] **Step 3: Add counter reset methods and fetch/send summary logging**

In `CloudSyncEngine.swift`, add methods:

```swift
private func resetFetchCounters() {
    fetchStartTime = .now
    fetchInboundCounts = [:]
    fetchMergeCount = 0
    fetchInsertCount = 0
    fetchDeletionCount = 0
}

private func resetSendCounters() {
    sendCycleStartTime = .now
    sendCycleRecordCount = 0
}
```

- [ ] **Step 4: Add fetch summary event logging in postSyncNotification**

In `CloudSyncEngine+Helpers.swift`, update `postSyncNotification()` (line 321) to log a fetch summary event before posting:

```swift
func postSyncNotification() async {
    let fetchDuration = fetchStartTime.map {
        $0.duration(to: .now).asSeconds
    }
    let totalInbound = fetchInboundCounts.values.reduce(0, +)

    if totalInbound > 0 || fetchDuration != nil {
        let breakdown = fetchInboundCounts
            .sorted { $0.key < $1.key }
            .map { "\($0.value) \(displayName(for: $0.key))" }
            .joined(separator: ", ")

        var parts: [String] = []
        if totalInbound > 0 {
            parts.append("Received \(breakdown)")
            parts.append(
                "(\(fetchMergeCount) merged, \(fetchInsertCount) inserted"
                + (fetchDeletionCount > 0
                    ? ", \(fetchDeletionCount) deleted)"
                    : ")")
            )
        } else {
            parts.append("Fetch complete (no changes)")
        }

        let detail = parts.joined(separator: " ")
        let event = CloudSyncEvent(
            category: .fetch,
            detail: detail,
            recordCount: totalInbound > 0 ? totalInbound : nil,
            duration: fetchDuration
        )
        await eventLog.append(event)
        await notifyDelegateOfEvents()
    }

    await MainActor.run {
        NotificationCenter.default.post(
            name: .didSyncQSOs, object: nil
        )
    }
    await delegate?.cloudSyncEngineDidFinishFetch(self)
}
```

- [ ] **Step 5: Add upload summary event logging in postSendProgress**

In `CloudSyncEngine+Helpers.swift`, update `postSendProgress` (line 329):

```swift
func postSendProgress(batchSaved: Int = 0) async {
    sendCycleRecordCount += batchSaved

    // Per-batch event is logged from handleSentRecordZoneChanges
    // (see Task 4, Step 6b) — not here, to capture failed count.

    let newCounts = recordCountsImpl()
    await delegate?.cloudSyncEngine(
        self, didUpdateCounts: newCounts, batchSaved: batchSaved
    )

    // On cycle end (called from didSendChanges with batchSaved=0),
    // log summary with duration
    if batchSaved == 0, sendCycleRecordCount > 0 {
        let duration = sendCycleStartTime.map {
            $0.duration(to: .now).asSeconds
        }
        let event = CloudSyncEvent(
            category: .upload,
            detail: "Upload cycle complete: \(sendCycleRecordCount) records",
            recordCount: sendCycleRecordCount,
            duration: duration
        )
        await eventLog.append(event)
        await notifyDelegateOfEvents()
    }
}
```

- [ ] **Step 6: Add helper methods for delegate notification and display names**

In `CloudSyncEngine+Helpers.swift`, add:

```swift
/// Notify delegate with current events and summary snapshot.
func notifyDelegateOfEvents() async {
    let events = await eventLog.allEvents()
    let summary = CloudSyncSummary.from(events: events)
    await delegate?.cloudSyncEngine(
        self, didLogEvents: events, summary: summary
    )
}

private func displayName(for entityType: String) -> String {
    switch entityType {
    case "QSO": "QSOs"
    case "ServicePresence": "ServicePresence"
    case "LoggingSession": "Sessions"
    case "ActivationMetadata": "Activations"
    case "SessionSpot": "Spots"
    case "ActivityLog": "ActivityLogs"
    default: entityType
    }
}
```

- [ ] **Step 7: Add Duration extension for ContinuousClock**

In `CloudSyncEngine+Helpers.swift`, add at file level:

```swift
extension Duration {
    var asSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
```

- [ ] **Step 8: Update CloudSyncEngineDelegate protocol with new method**

In `CloudSyncEngine.swift`, add to the `CloudSyncEngineDelegate` protocol (after line 16):

```swift
@MainActor func cloudSyncEngine(
    _ engine: CloudSyncEngine,
    didLogEvents events: [CloudSyncEvent],
    summary: CloudSyncSummary
)
```

- [ ] **Step 9: Add eventLog.load() call in start()**

In `CloudSyncEngine.swift`, add at the beginning of `start()` (line 42):

```swift
await eventLog.load()
```

- [ ] **Step 10: Verify build**

Run: `xc build`
Expected: Build succeeds (will have warnings about unimplemented delegate method until Task 5).

- [ ] **Step 11: Commit**

```
feat: wire CloudSyncEventLog into engine with timing and counter properties
```

---

### Task 4: Instrument Inbound, Conflict, Error, and Account Events

**Files:**
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+Inbound.swift`
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+InboundSession.swift`
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+ConflictResolution.swift`
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+Outbound.swift`
- Modify: `CarrierWaveData/Sources/CarrierWaveData/CloudSync/CloudSyncEngine+Helpers.swift`

- [ ] **Step 1: Add inbound counter increments to processInboundRecord**

In `CloudSyncEngine+Inbound.swift`, in `processInboundRecord` (line 40), add a counter increment call at the start of each record type case. Also update `handleFetchedRecordZoneChanges` to track counts.

Replace `handleFetchedRecordZoneChanges` (lines 18-30):

```swift
func handleFetchedRecordZoneChanges(
    _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
) {
    for modification in changes.modifications {
        processInboundRecord(modification.record)
    }

    for deletion in changes.deletions {
        fetchDeletionCount += 1
        processInboundDeletion(deletion.recordID)
    }

    try? modelContext.save()
}
```

- [ ] **Step 2: Track merge vs insert in QSO inbound processing**

In `CloudSyncEngine+Inbound.swift`, in `processInboundQSO` (line 59), add counter increments:

After the `if let existingQSO` branch (line 76): add `fetchMergeCount += 1`
After the `else` in `mergeOrCreateQSO` where `insertNewQSO` is called (line 128): add `fetchInsertCount += 1`
After the merge in `mergeOrCreateQSO` (line 126): add `fetchMergeCount += 1`

Add to the top of `processInboundQSO` after the metadata mode guard:
```swift
fetchInboundCounts["QSO", default: 0] += 1
```

- [ ] **Step 3: Track merge vs insert in ServicePresence inbound**

In `processInboundServicePresence` (line 174), add counter increments:
```swift
fetchInboundCounts["ServicePresence", default: 0] += 1
```

After the `if let existing` branch: `fetchMergeCount += 1`
After the `else` (insert) branch: `fetchInsertCount += 1`

- [ ] **Step 4: Track counts in InboundSession entity types**

In `CloudSyncEngine+InboundSession.swift`:

In `processInboundLoggingSession` (line 9), add at top:
```swift
fetchInboundCounts["LoggingSession", default: 0] += 1
```
After `if let existing` (line 21): `fetchMergeCount += 1`
After `else` (line 24): `fetchInsertCount += 1`

In `processInboundActivationMetadataRecord` (line 84), add at top:
```swift
fetchInboundCounts["ActivationMetadata", default: 0] += 1
```
In `processInboundActivationMetadata` — after `if let existing` (line 104): `fetchMergeCount += 1`
After `else` (line 111): `fetchInsertCount += 1`

In `processInboundSessionSpot` (line 139), add at top:
```swift
fetchInboundCounts["SessionSpot", default: 0] += 1
```
After `if let existing` (line 151): `fetchMergeCount += 1`
After `else` (line 153): `fetchInsertCount += 1`

In `processInboundActivityLog` (line 190), add at top:
```swift
fetchInboundCounts["ActivityLog", default: 0] += 1
```
After `if let existing` (line 202): `fetchMergeCount += 1`
After `else` (line 204): `fetchInsertCount += 1`

- [ ] **Step 5: Add conflict event logging**

In `CloudSyncEngine+ConflictResolution.swift`, in `handleConflict` (line 10), add after the `switch` statement resolves (before the closing `}` of the method at line 59):

```swift
let event = CloudSyncEvent(
    category: .conflict,
    entityType: entityType,
    detail: "Conflict resolved: \(entityType)"
)
Task { await eventLog.append(event) }
```

Note: Use `Task` here because `handleConflict` is synchronous within the actor but `eventLog.append` is async (different actor).

Actually, `handleConflict` is called from within the `CloudSyncEngine` actor, and `eventLog` is owned by the same actor. But `eventLog` is a separate actor, so we need `await`. Since `handleConflict` is not `async`, wrap in a `Task`:

Add after the switch block, before the closing `}`:
```swift
let conflictEvent = CloudSyncEvent(
    category: .conflict,
    entityType: entityType,
    detail: "Conflict resolved: \(entityType)"
)
Task { [eventLog] in
    await eventLog.append(conflictEvent)
}
```

- [ ] **Step 6a: Add per-batch upload event in handleSentRecordZoneChanges**

In `CloudSyncEngine+Outbound.swift`, in `handleSentRecordZoneChanges` (line 365), add after the `try? modelContext.save()` call (line 384) and before the conflict retry block:

```swift
let savedCount = event.savedRecords.count
let failedCount = event.failedRecordSaves.count
if savedCount > 0 || failedCount > 0 {
    let uploadEvent = CloudSyncEvent(
        category: .upload,
        detail: "Uploaded batch: \(savedCount) saved, \(failedCount) failed",
        recordCount: savedCount
    )
    Task { [eventLog] in
        await eventLog.append(uploadEvent)
    }
}
```

Note: The parameter name `event` shadows `CKSyncEngine.Event.SentRecordZoneChanges`. Use the existing parameter name from the method signature (it's named differently — check the actual code; it may be named `sentChanges` in the call site at line 123 of `CloudSyncEngine.swift`). In the actual method (`handleSentRecordZoneChanges`), the parameter is `_ event: CKSyncEngine.Event.SentRecordZoneChanges`, so use `event.savedRecords.count` and `event.failedRecordSaves.count`.

- [ ] **Step 6b: Add error event logging for failed record saves (non-conflict)**

In `CloudSyncEngine+Outbound.swift`, in `handleFailedRecordSave` (line 413). Add error event logging for the `.zoneNotFound`, `.unknownItem`, and `default` cases. In the `default:` case (line 454) before `break`:

```swift
let errorEvent = CloudSyncEvent(
    category: .error,
    entityType: record.recordType,
    detail: "Save failed: code \(error.code.rawValue) — \(error.localizedDescription)"
)
Task { [eventLog] in
    await eventLog.append(errorEvent)
}
```

Also add the same for the `.zoneNotFound` and `.unknownItem` cases before their existing logic.

- [ ] **Step 7: Add account change event logging**

In `CloudSyncEngine+Helpers.swift`, in `handleAccountChange` (line 238), add event logging for each case. In the `.signIn` case (after line 243):

```swift
let event = CloudSyncEvent(
    category: .accountChange,
    detail: "iCloud account signed in"
)
Task { [eventLog] in await eventLog.append(event) }
```

Similarly for `.signOut` (after line 250):
```swift
let event = CloudSyncEvent(
    category: .accountChange,
    detail: "iCloud account signed out"
)
Task { [eventLog] in await eventLog.append(event) }
```

And `.switchAccounts` (after line 255):
```swift
let event = CloudSyncEvent(
    category: .accountChange,
    detail: "iCloud account switched"
)
Task { [eventLog] in await eventLog.append(event) }
```

- [ ] **Step 8: Verify build**

Run: `xc build`
Expected: Build succeeds.

- [ ] **Step 9: Commit**

```
feat: instrument sync engine with event logging for fetch, upload, conflict, error, and account events
```

---

### Task 5: Wire CloudSyncService to Receive Events

**Files:**
- Modify: `CarrierWave/Services/CloudSync/CloudSyncService.swift`

- [ ] **Step 1: Add published properties for summary and events**

In `CloudSyncService.swift`, add after `uploadedCount` (line 48):

```swift
/// Computed summary of recent sync activity
@Published var syncSummary: CloudSyncSummary = .empty

/// Recent sync events for the activity log
@Published var syncEvents: [CloudSyncEvent] = []
```

- [ ] **Step 2: Implement the new delegate method**

In the `CloudSyncEngineDelegate` extension (line 324), add:

```swift
nonisolated func cloudSyncEngine(
    _ engine: CloudSyncEngine,
    didLogEvents events: [CloudSyncEvent],
    summary: CloudSyncSummary
) {
    Task { @MainActor in
        self.syncEvents = events
        self.syncSummary = summary
    }
}
```

- [ ] **Step 3: Refresh events on startup**

Add a refresh of events/summary in `startIfEnabled()` (after line 81).
Note: `eventLog.load()` is already called in `CloudSyncEngine.start()` (Task 3, Step 9) — no need to duplicate it in `configure()`.

```swift
await refreshSyncEvents()
```

Add the helper method:

```swift
func refreshSyncEvents() async {
    guard let engine else { return }
    let events = await engine.eventLog.allEvents()
    syncEvents = events
    syncSummary = CloudSyncSummary.from(events: events)
}
```

- [ ] **Step 4: Verify build**

Run: `xc build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```
feat: wire CloudSyncService to receive and publish sync events and summary
```

---

### Task 6: Add Activity Summary Section to CloudSyncSettingsView

**Files:**
- Modify: `CarrierWave/Views/Settings/CloudSyncSettingsView.swift`

- [ ] **Step 1: Add the activity summary section**

In `CloudSyncSettingsView.swift`, add `activitySummarySection` inside the existing `if syncService.isEnabled { }` block, between `recordCountsSection` and `actionsSection` (line 17, inside the guard):

```swift
activitySummarySection
```

- [ ] **Step 2: Implement activitySummarySection**

Add to the private sections area (after `recordCountsSection`):

```swift
private var activitySummarySection: some View {
    Section {
        if let fetchDate = syncService.syncSummary.lastFetchDate {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Last Fetch")
                    Spacer()
                    Text(fetchDate, style: .relative)
                        .foregroundStyle(.secondary)
                    Text("ago")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    durationBadge(
                        syncService.syncSummary.lastFetchDuration
                    )
                    if let rc = syncService.syncSummary.lastFetchRecordCount {
                        Text("\(rc) records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let uploadDate = syncService.syncSummary.lastUploadDate {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Last Upload")
                    Spacer()
                    Text(uploadDate, style: .relative)
                        .foregroundStyle(.secondary)
                    Text("ago")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    durationBadge(
                        syncService.syncSummary.lastUploadDuration
                    )
                    if let rc = syncService.syncSummary
                        .lastUploadRecordCount
                    {
                        Text("\(rc) records")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        HStack {
            Text("Today")
            Spacer()
            let cs = syncService.syncSummary.conflictsToday
            let es = syncService.syncSummary.errorsToday
            Text("\(cs) conflicts")
                .foregroundStyle(cs > 0 ? .orange : .secondary)
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(es) errors")
                .foregroundStyle(es > 0 ? .red : .secondary)
        }
        .font(.subheadline)

        NavigationLink {
            CloudSyncActivityView()
        } label: {
            Label("Sync Log", systemImage: "list.bullet.rectangle")
        }
    } header: {
        Text("Activity")
    }
}

private func durationBadge(_ duration: TimeInterval?) -> some View {
    Group {
        if let dur = duration {
            Text(String(format: "%.1fs", dur))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }
}
```

- [ ] **Step 3: Refresh events on appear**

Update the `.onAppear` (line 27) to also refresh events:

```swift
.onAppear {
    Task {
        await syncService.refreshCounts()
        await syncService.refreshSyncEvents()
    }
}
```

- [ ] **Step 4: Verify build**

Run: `xc build`
Expected: Build succeeds (CloudSyncActivityView will be a stub — created in next task).

- [ ] **Step 5: Commit**

```
feat: add activity summary section to iCloud sync settings
```

---

### Task 7: CloudSyncActivityView Timeline Screen

**Files:**
- Create: `CarrierWave/Views/Settings/CloudSyncActivityView.swift`

- [ ] **Step 1: Create CloudSyncActivityView**

```swift
// CarrierWave/Views/Settings/CloudSyncActivityView.swift
import CarrierWaveData
import SwiftUI

/// Timeline of recent sync events, grouped by date, newest first.
struct CloudSyncActivityView: View {
    // MARK: Internal

    var body: some View {
        List {
            if groupedEvents.isEmpty {
                ContentUnavailableView(
                    "No Sync Activity",
                    systemImage: "icloud",
                    description: Text("Sync events will appear here.")
                )
            } else {
                ForEach(groupedEvents, id: \.date) { group in
                    Section {
                        ForEach(group.events) { event in
                            eventRow(event)
                        }
                    } header: {
                        Text(sectionHeader(for: group.date))
                    }
                }
            }
        }
        .navigationTitle("Sync Log")
        .onAppear {
            Task { await syncService.refreshSyncEvents() }
        }
    }

    // MARK: Private

    @ObservedObject private var syncService = CloudSyncService.shared

    private var groupedEvents: [DateGroup] {
        let calendar = Calendar.current
        let sorted = syncService.syncEvents.sorted {
            $0.timestamp > $1.timestamp
        }
        let grouped = Dictionary(grouping: sorted) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return grouped
            .map { DateGroup(date: $0.key, events: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private func eventRow(
        _ event: CloudSyncEvent
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(for: event.category))
                .foregroundStyle(iconColor(for: event.category))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.detail)
                    .font(.subheadline)
                Text(
                    event.timestamp,
                    format: .dateTime.hour().minute().second()
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let count = event.recordCount {
                    Text("\(count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let dur = event.duration {
                    Text(String(format: "%.1fs", dur))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func iconName(
        for category: CloudSyncEvent.Category
    ) -> String {
        switch category {
        case .fetch: "arrow.down.circle"
        case .upload: "arrow.up.circle"
        case .conflict: "arrow.2.squarepath"
        case .error: "exclamationmark.triangle"
        case .accountChange: "person.circle"
        }
    }

    private func iconColor(
        for category: CloudSyncEvent.Category
    ) -> Color {
        switch category {
        case .fetch: .primary
        case .upload: .blue
        case .conflict: .orange
        case .error: .red
        case .accountChange: .primary
        }
    }

    private func sectionHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - DateGroup

private struct DateGroup {
    let date: Date
    let events: [CloudSyncEvent]
}
```

- [ ] **Step 2: Verify build**

Run: `xc build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```
feat: add CloudSyncActivityView timeline screen
```

---

### Task 8: Update FILE_INDEX.md and CHANGELOG.md

**Files:**
- Modify: `docs/FILE_INDEX.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add new files to FILE_INDEX.md**

In the CarrierWaveData CloudSync section, add entries for:
- `CloudSyncEvent.swift` — Sync event struct and Category enum for activity log
- `CloudSyncEventLog.swift` — Actor managing JSON-persisted sync event history with FIFO pruning
- `CloudSyncSummary.swift` — Dashboard summary struct computed from sync events

In the Views/Settings section, add:
- `CloudSyncActivityView.swift` — Timeline view of recent sync events, grouped by date

In the Tests section, add:
- `CloudSyncEventTests.swift` — Tests for CloudSyncEvent Codable and CloudSyncSummary computation
- `CloudSyncEventLogTests.swift` — Tests for CloudSyncEventLog persistence and pruning

- [ ] **Step 2: Add CHANGELOG entry under [Unreleased]**

```markdown
### Added
- iCloud sync activity dashboard showing last fetch/upload timing, today's conflicts/errors
- Sync activity log with timeline of recent sync events (persisted across app restarts)
- Sync events instrumented for fetch, upload, conflict, error, and account changes
```

- [ ] **Step 3: Commit**

```
docs: update FILE_INDEX and CHANGELOG for cloud sync metrics
```
