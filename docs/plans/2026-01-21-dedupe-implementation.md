# QSO Deduplication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Settings button that finds and auto-merges duplicate QSOs using time-delta matching with configurable window.

**Architecture:** New `DeduplicationService` actor handles matching/merging. Settings UI adds a "Deduplication" section with time window stepper and action button. Duplicates are detected by comparing callsign/band/mode and checking if timestamps are within N minutes.

**Tech Stack:** SwiftUI, SwiftData, UserDefaults for config

---

### Task 1: Add fieldRichnessScore to QSO model

**Files:**
- Modify: `FullDuplex/Models/QSO.swift:100` (after `isUSStation`)

**Step 1: Write the property**

Add this computed property to QSO.swift after the `isUSStation` property (around line 106):

```swift
/// Count of populated optional fields (for deduplication tiebreaker)
var fieldRichnessScore: Int {
    var score = 0
    if rstSent != nil { score += 1 }
    if rstReceived != nil { score += 1 }
    if myGrid != nil { score += 1 }
    if theirGrid != nil { score += 1 }
    if parkReference != nil { score += 1 }
    if notes != nil { score += 1 }
    if qrzLogId != nil { score += 1 }
    if rawADIF != nil { score += 1 }
    if frequency != nil { score += 1 }
    return score
}
```

**Step 2: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Models/QSO.swift
git commit -m "feat(qso): add fieldRichnessScore for deduplication tiebreaker

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Add syncedServicesCount helper to QSO

**Files:**
- Modify: `FullDuplex/Models/QSO.swift` (after fieldRichnessScore)

**Step 1: Write the property**

Add this computed property after `fieldRichnessScore`:

```swift
/// Count of services where this QSO is confirmed present
var syncedServicesCount: Int {
    servicePresence.filter { $0.isPresent }.count
}
```

**Step 2: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add FullDuplex/Models/QSO.swift
git commit -m "feat(qso): add syncedServicesCount for deduplication priority

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Create DeduplicationService with result type

**Files:**
- Create: `FullDuplex/Services/DeduplicationService.swift`

**Step 1: Write the service skeleton**

```swift
import Foundation
import SwiftData

struct DeduplicationResult {
    let duplicateGroupsFound: Int
    let qsosMerged: Int
    let qsosRemoved: Int
}

actor DeduplicationService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Find and merge duplicate QSOs within the given time window
    func findAndMergeDuplicates(timeWindowMinutes: Int = 5) async throws -> DeduplicationResult {
        // Fetch all QSOs sorted by timestamp
        var descriptor = FetchDescriptor<QSO>(sortBy: [SortDescriptor(\.timestamp)])
        let allQSOs = try modelContext.fetch(descriptor)

        if allQSOs.isEmpty {
            return DeduplicationResult(duplicateGroupsFound: 0, qsosMerged: 0, qsosRemoved: 0)
        }

        let timeWindow = TimeInterval(timeWindowMinutes * 60)
        var duplicateGroups: [[QSO]] = []
        var processed = Set<UUID>()

        // Find duplicate groups
        for i in 0..<allQSOs.count {
            let qso = allQSOs[i]
            if processed.contains(qso.id) { continue }

            var group = [qso]
            processed.insert(qso.id)

            // Check subsequent QSOs within time window
            for j in (i + 1)..<allQSOs.count {
                let candidate = allQSOs[j]
                if processed.contains(candidate.id) { continue }

                // Stop if beyond time window
                let timeDelta = candidate.timestamp.timeIntervalSince(qso.timestamp)
                if timeDelta > timeWindow { break }

                // Check if duplicate (same call/band/mode within window)
                if isDuplicate(qso, candidate) {
                    group.append(candidate)
                    processed.insert(candidate.id)
                }
            }

            if group.count > 1 {
                duplicateGroups.append(group)
            }
        }

        // Merge each group
        var totalMerged = 0
        var totalRemoved = 0

        for group in duplicateGroups {
            let (merged, removed) = mergeGroup(group)
            totalMerged += merged
            totalRemoved += removed
        }

        try modelContext.save()

        return DeduplicationResult(
            duplicateGroupsFound: duplicateGroups.count,
            qsosMerged: totalMerged,
            qsosRemoved: totalRemoved
        )
    }

    /// Check if two QSOs are duplicates (same callsign, band, mode)
    private func isDuplicate(_ a: QSO, _ b: QSO) -> Bool {
        return a.callsign.uppercased() == b.callsign.uppercased() &&
               a.band.uppercased() == b.band.uppercased() &&
               a.mode.uppercased() == b.mode.uppercased()
    }

    /// Merge a group of duplicates, keeping the best one
    /// Returns (merged count, removed count)
    private func mergeGroup(_ group: [QSO]) -> (Int, Int) {
        guard group.count > 1 else { return (0, 0) }

        // Sort to find winner:
        // 1. Most synced services
        // 2. Highest field richness score
        let sorted = group.sorted { a, b in
            if a.syncedServicesCount != b.syncedServicesCount {
                return a.syncedServicesCount > b.syncedServicesCount
            }
            return a.fieldRichnessScore > b.fieldRichnessScore
        }

        let winner = sorted[0]
        let losers = Array(sorted.dropFirst())

        // Absorb data from losers into winner
        for loser in losers {
            absorbFields(from: loser, into: winner)
            absorbServicePresence(from: loser, into: winner)
            modelContext.delete(loser)
        }

        return (1, losers.count)
    }

    /// Fill nil fields in winner from loser
    private func absorbFields(from loser: QSO, into winner: QSO) {
        if winner.rstSent == nil { winner.rstSent = loser.rstSent }
        if winner.rstReceived == nil { winner.rstReceived = loser.rstReceived }
        if winner.myGrid == nil { winner.myGrid = loser.myGrid }
        if winner.theirGrid == nil { winner.theirGrid = loser.theirGrid }
        if winner.parkReference == nil { winner.parkReference = loser.parkReference }
        if winner.notes == nil { winner.notes = loser.notes }
        if winner.qrzLogId == nil { winner.qrzLogId = loser.qrzLogId }
        if winner.rawADIF == nil { winner.rawADIF = loser.rawADIF }
        if winner.frequency == nil { winner.frequency = loser.frequency }
    }

    /// Transfer service presence records from loser to winner
    private func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence {
            // Check if winner already has this service
            if let existing = winner.presence(for: presence.serviceType) {
                // Update if loser's is "better" (present beats not present)
                if presence.isPresent && !existing.isPresent {
                    existing.isPresent = true
                    existing.needsUpload = false
                    existing.lastConfirmedAt = presence.lastConfirmedAt
                }
            } else {
                // Transfer the presence record to winner
                presence.qso = winner
                winner.servicePresence.append(presence)
            }
        }
    }
}
```

**Step 2: Add file to Xcode project**

The file will be automatically picked up by Xcode since the project uses folder references.

**Step 3: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add FullDuplex/Services/DeduplicationService.swift
git commit -m "feat(dedupe): add DeduplicationService with time-delta matching

Finds duplicate QSOs by comparing callsign/band/mode within a
configurable time window. Merges by preferring QSOs already synced
to services, then by field richness.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Add deduplication UI to SettingsView

**Files:**
- Modify: `FullDuplex/Views/Settings/SettingsView.swift`

**Step 1: Add state variables**

Add these after the existing `@State` variables (around line 15):

```swift
@State private var dedupeTimeWindow = 5
@State private var isDeduplicating = false
@State private var showingDedupeResult = false
@State private var dedupeResultMessage = ""
```

**Step 2: Add the Deduplication section**

Add this new section after the "Import Sources" section (after line 106, before the "Data" section):

```swift
Section {
    Stepper("Time window: \(dedupeTimeWindow) min", value: $dedupeTimeWindow, in: 1...15)

    Button {
        Task { await runDeduplication() }
    } label: {
        if isDeduplicating {
            HStack {
                ProgressView()
                    .padding(.trailing, 4)
                Text("Scanning...")
            }
        } else {
            Text("Find & Merge Duplicates")
        }
    }
    .disabled(isDeduplicating)
} header: {
    Text("Deduplication")
} footer: {
    Text("Find QSOs with same callsign, band, and mode within \(dedupeTimeWindow) minutes and merge them.")
}
```

**Step 3: Add the alert modifier**

Add this after the existing `.alert("Clear All QSOs?"...)` modifier (around line 154):

```swift
.alert("Deduplication Complete", isPresented: $showingDedupeResult) {
    Button("OK") { }
} message: {
    Text(dedupeResultMessage)
}
```

**Step 4: Add the runDeduplication function**

Add this function after `clearAllQSOs()` (around line 202):

```swift
private func runDeduplication() async {
    isDeduplicating = true
    defer { isDeduplicating = false }

    do {
        let service = DeduplicationService(modelContext: modelContext)
        let result = await try service.findAndMergeDuplicates(timeWindowMinutes: dedupeTimeWindow)

        if result.duplicateGroupsFound == 0 {
            dedupeResultMessage = "No duplicates found."
        } else {
            dedupeResultMessage = "Found \(result.duplicateGroupsFound) duplicate groups.\nMerged \(result.qsosMerged) QSOs, removed \(result.qsosRemoved) duplicates."
        }
        showingDedupeResult = true
    } catch {
        errorMessage = "Deduplication failed: \(error.localizedDescription)"
        showingError = true
    }
}
```

**Step 5: Build to verify**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add FullDuplex/Views/Settings/SettingsView.swift
git commit -m "feat(settings): add deduplication UI with configurable time window

Adds Deduplication section with:
- Stepper for time window (1-15 minutes, default 5)
- Find & Merge Duplicates button with progress indicator
- Result alert showing merge statistics

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Write tests for DeduplicationService

**Files:**
- Create: `FullDuplexTests/DeduplicationServiceTests.swift`

**Step 1: Write the test file**

```swift
import XCTest
import SwiftData
@testable import FullDuplex

final class DeduplicationServiceTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    @MainActor
    override func setUp() async throws {
        let schema = Schema([QSO.self, ServicePresence.self, UploadDestination.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = modelContainer.mainContext
    }

    @MainActor
    func testNoDuplicates() async throws {
        // Create two different QSOs
        let qso1 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: Date(), myCallsign: "N0CALL", importSource: .adifFile)
        let qso2 = QSO(callsign: "K3LR", band: "40m", mode: "SSB",
                       timestamp: Date(), myCallsign: "N0CALL", importSource: .adifFile)
        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 0)
        XCTAssertEqual(result.qsosRemoved, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 2)
    }

    @MainActor
    func testExactDuplicatesWithinWindow() async throws {
        let baseTime = Date()

        // Create two identical QSOs 2 minutes apart
        let qso1 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile)
        let qso2 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime.addingTimeInterval(120), myCallsign: "N0CALL", importSource: .adifFile)
        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 1)
        XCTAssertEqual(result.qsosRemoved, 1)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
    }

    @MainActor
    func testDuplicatesOutsideWindow() async throws {
        let baseTime = Date()

        // Create two identical QSOs 10 minutes apart (outside 5-min window)
        let qso1 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile)
        let qso2 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime.addingTimeInterval(600), myCallsign: "N0CALL", importSource: .adifFile)
        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 0)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 2)
    }

    @MainActor
    func testPrefersSyncedQSO() async throws {
        let baseTime = Date()

        // Create two duplicates, one with sync status
        let qso1 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile)
        let qso2 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime.addingTimeInterval(60), myCallsign: "N0CALL", importSource: .adifFile,
                       qrzLogId: "12345")

        modelContext.insert(qso1)
        modelContext.insert(qso2)

        // Mark qso2 as present in QRZ
        let presence = ServicePresence.downloaded(from: .qrz, qso: qso2)
        modelContext.insert(presence)
        qso2.servicePresence.append(presence)

        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        _ = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].qrzLogId, "12345") // The synced one should survive
    }

    @MainActor
    func testPrefersRicherQSO() async throws {
        let baseTime = Date()

        // Create two duplicates, one with more fields
        let qso1 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile)
        let qso2 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime.addingTimeInterval(60), myCallsign: "N0CALL",
                       rstSent: "599", rstReceived: "599", theirGrid: "FN31",
                       importSource: .adifFile)

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        _ = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos[0].rstSent, "599") // The richer one should survive
        XCTAssertEqual(qsos[0].theirGrid, "FN31")
    }

    @MainActor
    func testCaseInsensitiveMatching() async throws {
        let baseTime = Date()

        // Create duplicates with different cases
        let qso1 = QSO(callsign: "w1aw", band: "20M", mode: "cw",
                       timestamp: baseTime, myCallsign: "N0CALL", importSource: .adifFile)
        let qso2 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime.addingTimeInterval(60), myCallsign: "N0CALL", importSource: .adifFile)

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        let result = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        XCTAssertEqual(result.duplicateGroupsFound, 1)
        XCTAssertEqual(result.qsosRemoved, 1)
    }

    @MainActor
    func testFieldAbsorption() async throws {
        let baseTime = Date()

        // Create duplicates with complementary fields
        let qso1 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime, myCallsign: "N0CALL",
                       rstSent: "599", importSource: .adifFile)
        let qso2 = QSO(callsign: "W1AW", band: "20m", mode: "CW",
                       timestamp: baseTime.addingTimeInterval(60), myCallsign: "N0CALL",
                       rstReceived: "579", theirGrid: "FN31", importSource: .adifFile)

        modelContext.insert(qso1)
        modelContext.insert(qso2)
        try modelContext.save()

        let service = DeduplicationService(modelContext: modelContext)
        _ = try await service.findAndMergeDuplicates(timeWindowMinutes: 5)

        let qsos = try modelContext.fetch(FetchDescriptor<QSO>())
        XCTAssertEqual(qsos.count, 1)
        // Winner should have absorbed fields from loser
        XCTAssertNotNil(qsos[0].rstSent)
        XCTAssertNotNil(qsos[0].rstReceived)
        XCTAssertNotNil(qsos[0].theirGrid)
    }
}
```

**Step 2: Run tests**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E '(Test Case|passed|failed|error:)'`
Expected: All tests pass

**Step 3: Commit**

```bash
git add FullDuplexTests/DeduplicationServiceTests.swift
git commit -m "test(dedupe): add comprehensive tests for DeduplicationService

Tests cover:
- No duplicates case
- Exact duplicates within window
- Duplicates outside window (not merged)
- Prefers synced QSOs
- Prefers richer QSOs when neither synced
- Case-insensitive matching
- Field absorption from loser to winner

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Final build and manual test

**Step 1: Run full test suite**

Run: `xcodebuild -project FullDuplex.xcodeproj -scheme FullDuplex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E '(Test Case|passed|failed|BUILD)'`
Expected: All tests pass, BUILD SUCCEEDED

**Step 2: Manual verification checklist**

- [ ] Build and run on simulator
- [ ] Navigate to Settings
- [ ] Verify "Deduplication" section appears between "Import Sources" and "Data"
- [ ] Verify stepper shows "Time window: 5 min" by default
- [ ] Verify stepper can be adjusted from 1-15 minutes
- [ ] Tap "Find & Merge Duplicates" and verify progress indicator shows
- [ ] Verify result alert appears with appropriate message
