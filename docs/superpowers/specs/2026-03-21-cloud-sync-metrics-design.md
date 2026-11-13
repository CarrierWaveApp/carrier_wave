# Cloud Sync Metrics & Activity Log

**Date:** 2026-03-21
**Status:** Approved

## Summary

Add in-app visibility into the iCloud sync pipeline: a summary dashboard inline in iCloud settings showing key stats (last fetch/upload timing, today's conflicts/errors), plus a dedicated sync activity timeline screen showing recent sync events. Events are persisted to a JSON file with FIFO retention (500 events max).

## Goals

- See at a glance whether sync is healthy (last fetch/upload time, duration, record counts)
- Drill into a timeline of recent sync events to understand what happened
- Persist events across app restarts so history survives backgrounding
- Zero impact on sync logic — purely observational instrumentation

## Non-Goals

- No analytics or telemetry sent externally
- No per-record event logging (too noisy; events are aggregated per-batch)
- No changes to sync logic, conflict resolution, or dirty flag protocol
- Adding timestamp captures to `willFetchChanges` / `willSendChanges` handlers IS in scope (observational, no logic change)

## Architecture

### New Types (CarrierWaveData)

#### `CloudSyncEvent` (Codable, Sendable struct)

A single sync event. Stored as JSON, not SwiftData. Must remain a pure value type with all `Sendable` fields (primitives, String, Date, UUID, Optional thereof) since instances cross actor boundaries.

| Field | Type | Description |
|-------|------|-------------|
| `id` | `UUID` | Unique event ID |
| `timestamp` | `Date` | When the event occurred |
| `category` | `CloudSyncEvent.Category` | fetch, upload, conflict, error, accountChange |
| `entityType` | `String?` | e.g. "QSO", "ServicePresence" — nil for non-entity events |
| `detail` | `String` | Human-readable description |
| `recordCount` | `Int?` | Number of records involved |
| `duration` | `TimeInterval?` | How long the operation took |

#### `CloudSyncEvent.Category` (Codable, Sendable enum)

```swift
enum Category: String, Codable, Sendable {
    case fetch
    case upload
    case conflict
    case error
    case accountChange
}
```

#### `CloudSyncEventLog` (actor)

Manages the event array. Responsible for:
- Loading events from disk (via explicit `async func load()` called during service configuration)
- Appending new events
- Pruning to 500 events max (FIFO) on append
- Writing to disk after mutations (silently drops write failures — events are diagnostic, not critical)
- Returning snapshots for UI consumption

```swift
public actor CloudSyncEventLog {
    private var events: [CloudSyncEvent] = []
    private let fileURL: URL  // Library/CloudSync/sync_events.json
    private let maxEvents = 500

    public init()
    public func load()              // Reads from disk; call once during configure()
    public func append(_ event: CloudSyncEvent)  // Appends, prunes, writes
    public func allEvents() -> [CloudSyncEvent]  // Returns current snapshot
}
```

**Initialization lifecycle:** `CloudSyncEventLog` is created in `CloudSyncEngine.init`. `load()` is called from `CloudSyncService.configure()` via `await engine.eventLog.load()`. This avoids async work in init.

**Error handling:** JSON write failures (disk full, permissions) are silently ignored. Events are best-effort diagnostics. A single `logger.warning` is emitted on failure but no error is propagated.

File location: `Library/CloudSync/sync_events.json`, marked `isExcludedFromBackup`.

#### `CloudSyncSummary` (Sendable struct)

Computed from the event log for the dashboard display. Must remain a pure value type with all `Sendable` fields since it crosses actor boundaries.

| Field | Type | Description |
|-------|------|-------------|
| `lastFetchDate` | `Date?` | When the last fetch completed |
| `lastFetchDuration` | `TimeInterval?` | How long the last fetch took |
| `lastFetchRecordCount` | `Int?` | Records received in last fetch |
| `lastUploadDate` | `Date?` | When the last upload completed |
| `lastUploadDuration` | `TimeInterval?` | How long the last upload took |
| `lastUploadRecordCount` | `Int?` | Records sent in last upload |
| `conflictsToday` | `Int` | Conflict events since midnight |
| `errorsToday` | `Int` | Error events since midnight |

Computed via a static method: `CloudSyncSummary.from(events: [CloudSyncEvent]) -> CloudSyncSummary`.

### Instrumentation Points in CloudSyncEngine

Events are logged at cycle/batch granularity, not per-record.

#### Timing approach

For operations that span multiple delegate callbacks (fetch, upload), use stored timestamps on `CloudSyncEngine`:

- `fetchStartTime: ContinuousClock.Instant?` — set on `willFetchChanges`, read on `didFetchChanges`
- `sendCycleStartTime: ContinuousClock.Instant?` — set on `willSendChanges`, read on `didSendChanges`

The existing `break` statements in the `willFetchChanges` and `willSendChanges` cases of `handleEvent` are replaced with timestamp capture. This is purely observational (no logic change).

#### Inbound counting and aggregation

Counters accumulated across potentially multiple `handleFetchedRecordZoneChanges` calls within one fetch cycle:

- `fetchInboundCounts: [String: Int]` — per-entity-type record count (reset on `willFetchChanges`)
- `fetchMergeCount: Int` — records merged into existing (reset on `willFetchChanges`)
- `fetchInsertCount: Int` — new records created (reset on `willFetchChanges`)
- `fetchDeletionCount: Int` — inbound deletions processed (reset on `willFetchChanges`)

Counters are incremented in `processInboundRecord` (merge vs insert) and `processInboundDeletion`. A single aggregate event is logged on `didFetchChanges` (in the existing `postSyncNotification()` path), e.g.:
> "Received 42 QSOs, 15 ServicePresence, 3 LoggingSessions (48 merged, 12 inserted, 2 deleted) in 1.2s"

#### Upload events

Per-batch events are logged from `handleSentRecordZoneChanges`:
> "Uploaded batch: 98 saved, 2 failed"

A summary event with total duration is logged from `didSendChanges` (the existing `postSendProgress()` path at the end of a send cycle):
> "Upload cycle complete: 298 records in 3.4s"

Upload cycle record count is accumulated via a `sendCycleRecordCount: Int` counter reset on `willSendChanges`.

#### Instrumentation table

| Location | Category | Detail | When logged |
|----------|----------|--------|-------------|
| `willFetchChanges` | — | (reset counters, capture start time) | — |
| `handleFetchedRecordZoneChanges` | — | (accumulate per-type counts) | — |
| `didFetchChanges` (postSyncNotification) | fetch | Aggregate inbound summary with duration | End of fetch cycle |
| `willSendChanges` | — | (reset counters, capture start time) | — |
| `handleSentRecordZoneChanges` | upload | Per-batch: N saved, M failed | After each batch |
| `didSendChanges` (postSendProgress) | upload | Cycle summary with total duration | End of send cycle |
| `handleConflict` | conflict | "Conflict resolved: {entityType}" | Per conflict |
| `handleFailedRecordSave` (non-conflict) | error | Error code and description | Per failure |
| `handleAccountChange` | accountChange | "Signed in" / "Signed out" / "Switched accounts" | Per account event |

**Note:** `handleConflict` lives in `CloudSyncEngine+ConflictResolution.swift` (not Helpers).

### Data Flow

```
CloudSyncEngine (actor)
  -> measures timing, aggregates counts
  -> calls eventLog.append(event) after each instrumented operation
  -> eventLog writes JSON, prunes if >500

CloudSyncService (@MainActor)
  -> new @Published properties:
     - summary: CloudSyncSummary
     - recentEvents: [CloudSyncEvent]  (all 500; ~50KB of structs, acceptable)
  -> refreshed via new delegate callback from engine
  -> also refreshed on appear in settings views
```

### New Delegate Method

Add to `CloudSyncEngineDelegate`:

```swift
@MainActor func cloudSyncEngine(
    _ engine: CloudSyncEngine,
    didLogEvents events: [CloudSyncEvent],
    summary: CloudSyncSummary
)
```

**Implementation note:** Following the existing pattern, `CloudSyncService`'s conformance will be `nonisolated` and dispatch to `@MainActor` via `Task`, matching the existing delegate methods (`cloudSyncEngine(_:didUpdateCounts:batchSaved:)` etc.).

Called after events are appended to the log. `CloudSyncService` updates its published properties.

### UI

#### CloudSyncSettingsView — New "Activity" Section

Added between the existing "Records" and "Actions" sections:

```
┌─────────────────────────────────────┐
│ Activity                            │
├─────────────────────────────────────┤
│ Last Fetch      2 min ago · 1.2s   │
│                 42 records received │
│ Last Upload     5 min ago · 3.4s   │
│                 100 records sent    │
│ Today           3 conflicts · 0 err│
│ Sync Log                         > │
└─────────────────────────────────────┘
```

- "Last Fetch" / "Last Upload" show relative time and duration
- "Today" shows conflict and error counts
- "Sync Log" pushes to `CloudSyncActivityView`

#### CloudSyncActivityView (New Screen)

Scrollable list of recent events, newest first, grouped by date.

Each row:
- Leading: icon per category (arrow.down for fetch, arrow.up for upload, exclamationmark.triangle for error, arrow.2.squarepath for conflict, person for account)
- Title: detail text
- Trailing: record count badge (if present) and duration badge (if present)
- Subtitle: timestamp (HH:mm:ss format)
- Color: default for fetch/upload, orange for conflicts, red for errors

Section headers: "Today", "Yesterday", or date string.

### Storage

| Property | Value |
|----------|-------|
| File path | `Library/CloudSync/sync_events.json` |
| Backup exclusion | `isExcludedFromBackup = true` |
| Retention | 500 events max, FIFO pruning |
| Approximate size at capacity | ~50 KB |
| Write strategy | Write after each append; silently drop write failures |

### File Inventory

| File | Location | Purpose |
|------|----------|---------|
| `CloudSyncEvent.swift` | `CarrierWaveData/Sources/CarrierWaveData/CloudSync/` | Event struct and Category enum |
| `CloudSyncEventLog.swift` | `CarrierWaveData/Sources/CarrierWaveData/CloudSync/` | Actor managing event persistence |
| `CloudSyncSummary.swift` | `CarrierWaveData/Sources/CarrierWaveData/CloudSync/` | Summary struct computed from events |
| `CloudSyncEngine.swift` | (existing) | Add timing properties, eventLog reference, counter resets in will* handlers |
| `CloudSyncEngine+Inbound.swift` | (existing) | Add merge/insert/deletion counter increments |
| `CloudSyncEngine+Outbound.swift` | (existing) | Add per-batch upload event logging |
| `CloudSyncEngine+ConflictResolution.swift` | (existing) | Add conflict event logging |
| `CloudSyncEngine+Helpers.swift` | (existing) | Add fetch/upload summary event logging in postSyncNotification/postSendProgress, account change events |
| `CloudSyncService.swift` | (existing) | Add published summary/events, new delegate method |
| `CloudSyncSettingsView.swift` | (existing) | Add activity summary section |
| `CloudSyncActivityView.swift` | `CarrierWave/Views/Settings/` | New timeline view |

### Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| JSON write on every event blocks actor | Events are infrequent (a few per sync cycle); write is <1ms for 50KB |
| Event log grows unbounded | 500-event FIFO cap, ~50KB max |
| Timing inaccuracy from async callbacks | Use `ContinuousClock.Instant` for elapsed time, not wall clock arithmetic |
| Actor isolation for event log | `CloudSyncEventLog` is its own actor; engine calls it directly |
| JSON write failure (disk full) | Silently ignored with logger.warning; events are best-effort |
| recentEvents holds all 500 events in memory | ~50KB of value-type structs on MainActor; acceptable |
| CloudSyncEvent/Summary crossing actor boundaries | Both are pure value types with all Sendable fields |
