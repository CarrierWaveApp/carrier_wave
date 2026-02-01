# Instant QSO Logging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make QSO logging instant by moving all metadata enrichment to background tasks that run after the QSO is saved.

**Architecture:** When a QSO is logged, it saves immediately with only the data entered by the user (plus any pre-fetched callsign info from the lookup card). A new `BackgroundQSOEnricher` actor coordinates background enrichment tasks: QRZ lookup, previous contact counts, and POTA park-to-park detection. The QSO model tracks enrichment state so the UI can show progressive loading.

**Tech Stack:** SwiftUI, SwiftData, Swift Concurrency (actors, task groups).

**Note:** Per project rules, do not run builds or tests yourself. Each "Run tests" step means ask the user to run the command and report results.

---

## Current State Analysis

### Bottlenecks Identified (causing visible lag)

1. **`@Query` fetches ALL QSOs** - The logger view has:
   ```swift
   @Query(filter: #Predicate<QSO> { !$0.isHidden }, sort: \QSO.timestamp, order: .reverse)
   private var allQSOs: [QSO]
   ```
   When `modelContext.save()` is called, SwiftData triggers a full query refresh. With thousands of QSOs, this causes noticeable lag.

2. **`displayQSOs` filters on every access** - The computed property:
   ```swift
   private var displayQSOs: [QSO] {
       return allQSOs.filter { $0.loggingSessionId == sessionId }
   }
   ```
   Filters the entire array on every view body evaluation.

3. **Each `LoggerQSORow` launches callsign lookup** - The `.task { await lookupCallsign() }` on each row causes all 15 visible rows to potentially re-launch lookups when the list re-renders.

4. **Keychain read in `markForUpload`** - `SecItemCopyMatching` call for QRZ key check (minor, ~1-5ms).

5. **Animations on state reset** - Multiple `.animation()` modifiers fire when `lookupResult`, `lookupError`, etc. are reset.

### What's already good:
- Callsign lookup happens during typing (pre-fetch), not at log time
- The lookup result is passed directly to `logQSO`
- No network calls block the log operation

### What needs to be fixed:
- Replace `@Query` for all QSOs with session-scoped query
- Cache service configuration checks to avoid Keychain reads per-QSO
- Prevent `LoggerQSORow` task re-launches on list update
- Background enrichment for fields not pre-fetched

---

## Phase 0: Fix Performance Bottlenecks (Critical)

These changes must come first to eliminate the visible lag.

---

### Task 0.1: Replace broad @Query with session-scoped query

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: Remove the broad @Query and add session-scoped state**

Find and remove (around line 270-275):
```swift
    @Query(
        filter: #Predicate<QSO> { !$0.isHidden },
        sort: \QSO.timestamp,
        order: .reverse
    )
    private var allQSOs: [QSO]
```

Replace with a @State array that we'll populate manually:
```swift
    /// QSOs for the current session (manually managed, not @Query)
    @State private var sessionQSOs: [QSO] = []
```

**Step 2: Update displayQSOs to use sessionQSOs directly**

Find (around line 340-346):
```swift
    private var displayQSOs: [QSO] {
        guard let session = sessionManager?.activeSession else {
            return []
        }
        let sessionId = session.id
        return allQSOs.filter { $0.loggingSessionId == sessionId }
    }
```

Replace with:
```swift
    private var displayQSOs: [QSO] {
        sessionQSOs
    }
```

**Step 3: Add a method to refresh session QSOs**

Add this method (after displayQSOs):
```swift
    /// Refresh the session QSOs from SwiftData
    private func refreshSessionQSOs() {
        guard let session = sessionManager?.activeSession else {
            sessionQSOs = []
            return
        }
        
        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId && !qso.isHidden
        }
        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            sessionQSOs = try modelContext.fetch(descriptor)
        } catch {
            sessionQSOs = []
        }
    }
```

**Step 4: Call refresh on session changes and after logging**

In `.onAppear`, after the session manager is initialized (around line 125), add:
```swift
                refreshSessionQSOs()
```

**Step 5: Update logQSO() to refresh after logging**

In `logQSO()` (around line 1329), after the `sessionManager?.logQSO(...)` call, add:
```swift
        // Refresh the QSO list with the new entry
        refreshSessionQSOs()
```

**Step 6: Add onChange for session changes**

After the existing `.onChange(of: sessionManager?.activeSession?.mode)` block, add:
```swift
            .onChange(of: sessionManager?.activeSession?.id) { _, _ in
                refreshSessionQSOs()
            }
```

**Step 7: Commit**

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "perf: replace broad @Query with session-scoped fetch for instant logging"
```

---

### Task 0.2: Cache service configuration to avoid Keychain reads

**Files:**
- Modify: `CarrierWave/Services/LoggingSessionManager.swift`

**Step 1: Add cached service configuration properties**

After the `enricher` property (around line 19), add:
```swift
    /// Cached service configuration (checked once at session start)
    private var qrzConfigured = false
    private var lofiConfigured = false
```

**Step 2: Cache the configuration when session starts**

In `startSession()`, after `activeSession = session` (around line 72), add:
```swift
        // Cache service configuration to avoid Keychain reads per-QSO
        qrzConfigured = (try? KeychainHelper.shared.read(for: KeychainHelper.Keys.qrzApiKey)) != nil
        lofiConfigured = UserDefaults.standard.bool(forKey: "lofi.deviceLinked")
```

**Step 3: Update markForUpload to use cached values**

Replace the `markForUpload` method (around line 593-611):
```swift
    /// Mark QSO for upload to configured services
    private func markForUpload(_ qso: QSO) {
        // Use cached service configuration (checked at session start)
        if qrzConfigured {
            qso.markNeedsUpload(to: .qrz, context: modelContext)
        }

        // POTA (only if this is a POTA activation)
        if activeSession?.activationType == .pota,
           UserDefaults.standard.bool(forKey: "pota.authenticated")
        {
            qso.markNeedsUpload(to: .pota, context: modelContext)
        }

        // LoFi
        if lofiConfigured {
            qso.markNeedsUpload(to: .lofi, context: modelContext)
        }
    }
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/LoggingSessionManager.swift
git commit -m "perf: cache service config to avoid Keychain reads per-QSO"
```

---

### Task 0.3: Prevent LoggerQSORow task re-launches

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: Use .task(id:) to prevent re-launches**

Find the LoggerQSORow `.task` (around line 1417):
```swift
        .task {
            await lookupCallsign()
        }
```

Replace with:
```swift
        .task(id: qso.id) {
            await lookupCallsign()
        }
```

This ensures the task only runs once per QSO, not on every re-render.

**Step 2: Skip lookup if data already exists**

Update `lookupCallsign()` (around line 1586):
```swift
    private func lookupCallsign() async {
        // Skip if we already have callsign info from logging or previous lookup
        guard callsignInfo == nil,
              qso.name == nil || qso.theirGrid == nil
        else {
            return
        }
        
        let service = CallsignLookupService(modelContext: modelContext)
        callsignInfo = await service.lookup(qso.callsign)
    }
```

**Step 3: Initialize callsignInfo from QSO data if available**

Add an initializer or use `.onAppear` to pre-populate from QSO:
```swift
        .onAppear {
            // Use QSO's stored data if available
            if qso.name != nil || qso.theirGrid != nil {
                callsignInfo = CallsignInfo(
                    callsign: qso.callsign,
                    name: qso.name,
                    qth: qso.qth,
                    state: qso.state,
                    country: qso.country,
                    grid: qso.theirGrid,
                    licenseClass: qso.theirLicenseClass,
                    source: .qrz
                )
            }
        }
```

**Step 4: Commit**

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "perf: prevent redundant callsign lookups in QSO rows"
```

---

### Task 0.4: Disable animations during form reset

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: Wrap form reset in withTransaction to disable animations**

Update `logQSO()` (around line 1331-1343):
```swift
        // Reset form without animations
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            callsignInput = ""
            lookupResult = nil
            lookupError = nil
            cachedPotaDuplicateStatus = nil
            theirGrid = ""
            theirPark = ""
            notes = ""
            operatorName = ""
            rstSent = defaultRST
            rstReceived = defaultRST
        }
```

**Step 2: Commit**

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "perf: disable animations during form reset after logging"
```

---

## Phase 1: QSO Enrichment State Tracking

Add fields to track enrichment progress so the UI can show loading states.

---

### Task 1.1: Add enrichment state enum to QSO model

**Files:**
- Modify: `CarrierWave/Models/QSO.swift`

**Step 1: Add enrichment state enum at the top of the file (after imports)**

```swift
/// State of background metadata enrichment for a QSO
enum QSOEnrichmentState: String, Codable {
    /// Not yet enriched, waiting in queue
    case pending
    /// Currently being enriched
    case inProgress
    /// Enrichment completed successfully
    case completed
    /// Enrichment failed (will retry)
    case failed
    /// Skipped (already had all data at log time)
    case skipped
}
```

**Step 2: Add enrichment tracking properties to the QSO class (after `theirLicenseClass`)**

```swift
    /// Background enrichment state
    var enrichmentState: QSOEnrichmentState = .pending

    /// Previous contact count with this callsign (from enrichment)
    var previousContactCount: Int?

    /// Whether this is a park-to-park contact (POTA - from active spots check)
    var isParkToPark: Bool = false

    /// The other station's park reference if park-to-park (detected from spots)
    var detectedTheirParkReference: String?
```

**Step 3: Commit**

```bash
git add CarrierWave/Models/QSO.swift
git commit -m "feat: add enrichment state tracking to QSO model"
```

---

### Task 1.2: Update FILE_INDEX.md with new files

**Files:**
- Modify: `docs/FILE_INDEX.md`

**Step 1: Add BackgroundQSOEnricher to Services section**

In the Services table, add:

```markdown
| `BackgroundQSOEnricher.swift` | Background QSO metadata enrichment (QRZ, contact counts, P2P) |
```

**Step 2: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: add BackgroundQSOEnricher to file index"
```

---

## Phase 2: Background QSO Enricher Service

Create the actor that coordinates background enrichment.

---

### Task 2.1: Create BackgroundQSOEnricher actor

**Files:**
- Create: `CarrierWave/Services/BackgroundQSOEnricher.swift`

**Step 1: Create the enricher actor**

```swift
import Foundation
import SwiftData

// MARK: - BackgroundQSOEnricher

/// Coordinates background enrichment of QSO metadata
/// Runs after QSO is logged to populate:
/// - Callsign info from QRZ (if not pre-fetched)
/// - Previous contact count
/// - Park-to-park detection for POTA activations
actor BackgroundQSOEnricher {
    // MARK: Lifecycle

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: Internal

    /// Enqueue a QSO for background enrichment
    /// - Parameters:
    ///   - qsoId: The QSO's UUID
    ///   - callsign: The callsign to enrich
    ///   - needsCallsignLookup: Whether callsign lookup is needed (wasn't pre-fetched)
    ///   - isPOTASession: Whether this is a POTA activation (for P2P detection)
    ///   - myCallsign: The operator's callsign (for previous contact lookup)
    func enqueue(
        qsoId: UUID,
        callsign: String,
        needsCallsignLookup: Bool,
        isPOTASession: Bool,
        myCallsign: String
    ) {
        let item = EnrichmentItem(
            qsoId: qsoId,
            callsign: callsign,
            needsCallsignLookup: needsCallsignLookup,
            isPOTASession: isPOTASession,
            myCallsign: myCallsign
        )
        queue.append(item)
        startProcessingIfNeeded()
    }

    // MARK: Private

    private struct EnrichmentItem {
        let qsoId: UUID
        let callsign: String
        let needsCallsignLookup: Bool
        let isPOTASession: Bool
        let myCallsign: String
    }

    private let modelContainer: ModelContainer
    private var queue: [EnrichmentItem] = []
    private var isProcessing = false

    private func startProcessingIfNeeded() {
        guard !isProcessing, !queue.isEmpty else {
            return
        }
        isProcessing = true
        Task {
            await processQueue()
        }
    }

    private func processQueue() async {
        while !queue.isEmpty {
            let item = queue.removeFirst()
            await enrichQSO(item)
        }
        isProcessing = false
    }

    private func enrichQSO(_ item: EnrichmentItem) async {
        let context = ModelContext(modelContainer)

        // Fetch the QSO
        let qsoId = item.qsoId
        let predicate = #Predicate<QSO> { qso in
            qso.id == qsoId
        }
        let descriptor = FetchDescriptor<QSO>(predicate: predicate)

        guard let qso = try? context.fetch(descriptor).first else {
            return
        }

        // Mark as in progress
        qso.enrichmentState = .inProgress
        try? context.save()

        // Run enrichment tasks concurrently
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Callsign lookup (if needed)
            if item.needsCallsignLookup {
                group.addTask {
                    await self.enrichCallsignInfo(qso: qso, callsign: item.callsign, context: context)
                }
            }

            // Task 2: Previous contact count
            group.addTask {
                await self.enrichPreviousContactCount(
                    qso: qso,
                    callsign: item.callsign,
                    myCallsign: item.myCallsign,
                    context: context
                )
            }

            // Task 3: Park-to-park detection (POTA only)
            if item.isPOTASession {
                group.addTask {
                    await self.enrichParkToPark(qso: qso, callsign: item.callsign, context: context)
                }
            }
        }

        // Mark as completed
        qso.enrichmentState = .completed
        try? context.save()
    }

    private func enrichCallsignInfo(qso: QSO, callsign: String, context: ModelContext) async {
        let service = CallsignLookupService(modelContext: context)
        guard let info = await service.lookup(callsign) else {
            return
        }

        // Only update fields that aren't already set
        if qso.name == nil {
            qso.name = info.name
        }
        if qso.theirGrid == nil {
            qso.theirGrid = info.grid
        }
        if qso.state == nil {
            qso.state = info.state
        }
        if qso.country == nil {
            qso.country = info.country
        }
        if qso.qth == nil {
            qso.qth = info.qth
        }
        if qso.theirLicenseClass == nil {
            qso.theirLicenseClass = info.licenseClass
        }

        try? context.save()
    }

    private func enrichPreviousContactCount(
        qso: QSO,
        callsign: String,
        myCallsign: String,
        context: ModelContext
    ) async {
        let upperCallsign = callsign.uppercased()
        let upperMyCallsign = myCallsign.uppercased()
        let qsoTimestamp = qso.timestamp

        // Count previous QSOs with this callsign (before this QSO's timestamp)
        let predicate = #Predicate<QSO> { q in
            q.callsign == upperCallsign &&
            q.myCallsign == upperMyCallsign &&
            q.timestamp < qsoTimestamp &&
            !q.isHidden
        }
        let descriptor = FetchDescriptor<QSO>(predicate: predicate)

        do {
            let count = try context.fetchCount(descriptor)
            qso.previousContactCount = count
            try context.save()
        } catch {
            // Ignore errors - this is non-critical
        }
    }

    private func enrichParkToPark(qso: QSO, callsign: String, context: ModelContext) async {
        // Check POTA active spots to see if this callsign is also activating
        let potaClient = POTAClient(authService: POTAAuthService())

        do {
            let spots = try await potaClient.fetchSpots(for: callsign)

            // Find the most recent spot for this callsign
            if let spot = spots.first {
                qso.isParkToPark = true
                qso.detectedTheirParkReference = spot.reference

                // If theirParkReference wasn't manually entered, use detected value
                if qso.theirParkReference == nil {
                    qso.theirParkReference = spot.reference
                }

                try context.save()
            }
        } catch {
            // Ignore errors - P2P detection is best-effort
        }
    }
}
```

**Step 2: Commit**

```bash
git add CarrierWave/Services/BackgroundQSOEnricher.swift
git commit -m "feat: add BackgroundQSOEnricher for async metadata population"
```

---

## Phase 3: Integrate Enricher into Logging Flow

Wire up the enricher to be called after QSO logging.

---

### Task 3.1: Add enricher to LoggingSessionManager

**Files:**
- Modify: `CarrierWave/Services/LoggingSessionManager.swift`

**Step 1: Add enricher property after modelContext declaration (~line 18)**

```swift
    private let modelContext: ModelContext
    private var enricher: BackgroundQSOEnricher?
```

**Step 2: Initialize enricher in init (after loadActiveSession call, ~line 25)**

```swift
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadActiveSession()
        
        // Initialize background enricher
        if let container = modelContext.container {
            self.enricher = BackgroundQSOEnricher(modelContainer: container)
        }
    }
```

**Step 3: Update logQSO to set enrichment state and enqueue enrichment**

After the line `try? modelContext.save()` at the end of logQSO (~line 257), add:

```swift
        // Determine if callsign lookup is needed (pre-fetched data wasn't available)
        let needsCallsignLookup = name == nil && theirGrid == nil

        // Set initial enrichment state
        if needsCallsignLookup || activeSession?.activationType == .pota {
            qso.enrichmentState = .pending
        } else {
            qso.enrichmentState = .skipped
        }

        try? modelContext.save()

        // Enqueue background enrichment
        if let enricher, qso.enrichmentState == .pending {
            Task {
                await enricher.enqueue(
                    qsoId: qso.id,
                    callsign: callsign,
                    needsCallsignLookup: needsCallsignLookup,
                    isPOTASession: activeSession?.activationType == .pota,
                    myCallsign: session.myCallsign
                )
            }
        }
```

**Step 4: Commit**

```bash
git add CarrierWave/Services/LoggingSessionManager.swift
git commit -m "feat: integrate BackgroundQSOEnricher into logging flow"
```

---

## Phase 4: UI Updates for Progressive Loading

Update the QSO row to show enrichment state and progressive data loading.

---

### Task 4.1: Update LoggerQSORow to show enrichment state

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: Add enrichment indicator to LoggerQSORow (after the callsign text, ~line 1475)**

Find the HStack containing the callsign text and add an enrichment indicator:

```swift
                // Show enrichment state indicator
                if qso.enrichmentState == .pending || qso.enrichmentState == .inProgress {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
```

**Step 2: Add previous contact count badge (after POTA status badges)**

```swift
                // Show previous contact count if available
                if let count = qso.previousContactCount, count > 0 {
                    Text("\(count)×")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.purple.opacity(0.2))
                        .foregroundStyle(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .help("Worked \(count) time\(count == 1 ? "" : "s") before")
                }

                // Show park-to-park badge
                if qso.isParkToPark {
                    Text("P2P")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .help(qso.detectedTheirParkReference ?? "Park to park")
                }
```

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/LoggerView.swift
git commit -m "feat: show enrichment state and metadata badges in QSO row"
```

---

### Task 4.2: Add refresh trigger for enrichment updates

**Files:**
- Modify: `CarrierWave/Views/Logger/LoggerView.swift`

**Step 1: The @Query already observes QSO changes, so enrichment updates will trigger UI refresh automatically.**

No code changes needed - SwiftData's @Query automatically observes model changes.

**Step 2: Verify the observation works by checking that displayQSOs is derived from allQSOs**

The existing code at ~line 235 already does this:
```swift
private var displayQSOs: [QSO] {
    guard let session = sessionManager?.activeSession else {
        return []
    }
    let sessionId = session.id
    return allQSOs.filter { $0.loggingSessionId == sessionId }
}
```

**Step 3: Commit (documentation only)**

```bash
git commit --allow-empty -m "docs: SwiftData @Query auto-observes enrichment updates"
```

---

## Phase 5: Testing

---

### Task 5.1: Manual testing checklist

**Test the following scenarios:**

1. **Instant logging without pre-fetch:**
   - Start a session
   - Type a callsign quickly and tap Log before lookup completes
   - Verify: QSO appears immediately in list with loading spinner
   - Verify: After a few seconds, name/grid/location populate

2. **Logging with pre-fetched data:**
   - Start a session
   - Type a callsign and wait for the lookup card to appear
   - Tap Log
   - Verify: QSO appears with all data immediately, no spinner

3. **Previous contact count:**
   - Log a contact with a callsign you've worked before
   - Verify: After enrichment, the "×" badge shows previous contact count

4. **Park-to-park detection (POTA):**
   - Start a POTA session
   - Log a contact with an activator who is currently spotted on POTA
   - Verify: "P2P" badge appears after enrichment
   - Verify: Their park reference is auto-filled if not manually entered

5. **Rapid logging:**
   - Log 5 QSOs quickly in succession
   - Verify: All QSOs appear instantly
   - Verify: Enrichment completes for all within a few seconds

---

## Summary

This implementation ensures:

1. **Instant QSO logging** - The QSO is saved to SwiftData immediately with only user-entered data
2. **Background enrichment** - Metadata is populated asynchronously after logging
3. **Pre-fetch optimization** - If callsign was already looked up while typing, that data is used immediately
4. **Progressive UI** - Loading spinners show while enrichment is pending, badges appear when complete
5. **POTA P2P detection** - Checks active spots to detect park-to-park contacts automatically

The architecture uses Swift actors for thread-safe background processing and leverages SwiftData's automatic observation for UI updates.
