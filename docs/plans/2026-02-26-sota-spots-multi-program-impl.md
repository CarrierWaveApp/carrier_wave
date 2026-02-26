# SOTA Spots + Multi-Program Sessions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add SOTA spots from SOTAwatch API, support dual POTA+SOTA sessions, and rename the POTA command to HUNT for unified spot browsing.

**Architecture:** Extend existing `ActivityProgram` system (server-driven program registry) to support multi-program sessions. Store program set as JSON array on `LoggingSession`. Integrate SOTAwatch spots API via new `SOTAClient` actor alongside existing `POTAClient`. Unified spot display uses badge-based differentiation in a single chronological list.

**Tech Stack:** SwiftUI, SwiftData, async/await actors, SOTAwatch REST API

**Design doc:** `docs/plans/2026-02-26-sota-spots-multi-program-design.md`

---

## Task 1: SOTAwatch API Client + Spot Model

Build the SOTA spots data pipeline — the foundation everything else depends on.

**Files:**
- Create: `CarrierWave/Models/SOTASpot.swift`
- Create: `CarrierWave/Services/SOTA/SOTAClient+Spots.swift`
- Test: `CarrierWaveTests/SOTAClientTests.swift`

**Step 1: Create `SOTASpot` model**

Create `CarrierWave/Models/SOTASpot.swift`:

```swift
import Foundation

// MARK: - SOTASpot

/// A spot from the SOTAwatch API representing an active SOTA activator.
struct SOTASpot: Codable, Sendable, Identifiable {
    let id: Int
    let activatorCallsign: String
    let associationCode: String   // "W4C"
    let summitCode: String        // "W4C/CM-001"
    let summitDetails: String     // "Mount Mitchell"
    let frequency: String         // "14.062" — string from API
    let mode: String              // "CW", "SSB", "FM"
    let comments: String?
    let highlightColor: String?
    let points: Int
    let timeStamp: String         // ISO-8601 date

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case activatorCallsign
        case associationCode
        case summitCode
        case summitDetails
        case frequency
        case mode
        case comments
        case highlightColor
        case points
        case timeStamp
    }

    // MARK: - Computed

    /// Frequency in MHz, parsed from the API string (which is in MHz)
    var frequencyMHz: Double? {
        Double(frequency)
    }

    /// Frequency in kHz for band derivation
    var frequencyKHz: Double? {
        guard let mhz = frequencyMHz else { return nil }
        return mhz * 1_000
    }

    /// Parsed timestamp from the ISO-8601 string
    var parsedTimestamp: Date? {
        SOTASpot.dateFormatter.date(from: timeStamp)
    }

    // MARK: Private

    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
```

**Step 2: Create `SOTAClient+Spots.swift`**

Create `CarrierWave/Services/SOTA/SOTAClient+Spots.swift`. The existing SOTA directory already has `SOTASummitsCache.swift` and `SOTASummitsCache+Parsing.swift`.

```swift
import Foundation

// MARK: - SOTAClient

/// Client for the SOTAwatch API (api2.sota.org.uk).
/// Fetches active spots for SOTA activators.
actor SOTAClient {
    // MARK: Internal

    /// Fetch the most recent SOTA spots.
    /// - Parameters:
    ///   - count: Maximum number of spots to return (default 50)
    ///   - association: Optional association filter (e.g., "W4C"). Nil = all.
    /// - Returns: Array of SOTA spots, most recent first.
    func fetchSpots(count: Int = 50, association: String? = nil) async throws -> [SOTASpot] {
        let filter = association ?? "all"
        let url = URL(string: "\(baseURL)/spots/\(count)/\(filter)")!

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw SOTAError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw SOTAError.httpError(http.statusCode)
        }

        return try JSONDecoder().decode([SOTASpot].self, from: data)
    }

    // MARK: Private

    private let baseURL = "https://api2.sota.org.uk/api"
}

// MARK: - SOTAError

enum SOTAError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from SOTA API"
        case let .httpError(code):
            "SOTA API returned HTTP \(code)"
        }
    }
}
```

**Step 3: Write unit test**

Create `CarrierWaveTests/SOTAClientTests.swift` to verify JSON decoding:

```swift
import XCTest
@testable import CarrierWave

final class SOTASpotTests: XCTestCase {
    func testDecodeSOTASpot() throws {
        let json = """
        {
            "id": 12345,
            "activatorCallsign": "W4DOG",
            "associationCode": "W4C",
            "summitCode": "W4C/CM-001",
            "summitDetails": "Mount Mitchell",
            "frequency": "14.062",
            "mode": "CW",
            "comments": "Looking for S2S",
            "highlightColor": null,
            "points": 8,
            "timeStamp": "2026-02-26T15:30:00Z"
        }
        """.data(using: .utf8)!

        let spot = try JSONDecoder().decode(SOTASpot.self, from: json)
        XCTAssertEqual(spot.id, 12345)
        XCTAssertEqual(spot.activatorCallsign, "W4DOG")
        XCTAssertEqual(spot.summitCode, "W4C/CM-001")
        XCTAssertEqual(spot.frequencyMHz, 14.062)
        XCTAssertEqual(spot.points, 8)
        XCTAssertNotNil(spot.parsedTimestamp)
    }

    func testDecodeSOTASpotArray() throws {
        let json = """
        [
            {
                "id": 1,
                "activatorCallsign": "N5RZ",
                "associationCode": "W5",
                "summitCode": "W5O/OU-001",
                "summitDetails": "Black Mesa",
                "frequency": "7.030",
                "mode": "CW",
                "comments": null,
                "highlightColor": null,
                "points": 6,
                "timeStamp": "2026-02-26T14:00:00Z"
            }
        ]
        """.data(using: .utf8)!

        let spots = try JSONDecoder().decode([SOTASpot].self, from: json)
        XCTAssertEqual(spots.count, 1)
        XCTAssertEqual(spots[0].summitCode, "W5O/OU-001")
    }
}
```

**Step 4: Run tests**

Run: `xc test-unit` (or `make test-unit` depending on environment).
Expected: SOTASpot decoding tests pass.

**Step 5: Commit**

```
feat: add SOTAwatch API client and SOTASpot model

Adds SOTAClient actor for fetching spots from api2.sota.org.uk
and SOTASpot Codable model with frequency/timestamp parsing.
```

**Step 6: Update FILE_INDEX.md**

Add entries for the two new files.

---

## Task 2: Extend ActiveStation for SOTA Source

Add SOTA as a spot source type so the unified spot list can display SOTA spots.

**Files:**
- Modify: `CarrierWave/Models/ActiveStation.swift:8-11` (Source enum)
- Modify: `CarrierWave/Models/ActiveStation.swift` (add `fromSOTA` factory)

**Step 1: Add `.sota` case to `Source` enum**

In `ActiveStation.swift`, line 8-11, change `Source` from:

```swift
enum Source: Sendable {
    case pota(park: String)
    case rbn(snr: Int)
}
```

to:

```swift
enum Source: Sendable {
    case pota(park: String)
    case sota(summit: String, points: Int)
    case rbn(snr: Int)
}
```

**Step 2: Update `sourceLabel` computed property**

At line 49-53, add the SOTA case:

```swift
var sourceLabel: String {
    switch source {
    case let .pota(park): park
    case let .sota(summit, _): summit
    case let .rbn(snr): "\(snr) dB"
    }
}
```

**Step 3: Add `fromSOTA` factory method**

After the `fromRBN` method (line 79), add:

```swift
static func fromSOTA(_ spot: SOTASpot) -> ActiveStation? {
    guard let mhz = spot.frequencyMHz else {
        return nil
    }
    return ActiveStation(
        id: "sota-\(spot.id)",
        callsign: spot.activatorCallsign,
        frequencyMHz: mhz,
        mode: spot.mode.uppercased(),
        timestamp: spot.parsedTimestamp ?? Date(),
        source: .sota(summit: spot.summitCode, points: spot.points)
    )
}
```

**Step 4: Fix any switch exhaustiveness errors**

Search for `switch.*source` and `case .pota` in ActiveStation-related views to ensure all switches handle the new `.sota` case. Key files to check:
- Any view that pattern-matches on `ActiveStation.Source`

**Step 5: Build**

Run: `xc build`
Expected: Clean build with no exhaustive switch errors.

**Step 6: Commit**

```
feat: add SOTA source to ActiveStation

Extends ActiveStation.Source enum with .sota(summit:points:) case
and adds fromSOTA(_:) factory method for SOTAwatch spots.
```

---

## Task 3: Integrate SOTA Spots into SpotMonitoringService

Wire up SOTA spot fetching alongside existing POTA + RBN polling.

**Files:**
- Modify: `CarrierWave/Services/SpotMonitoringService.swift` (add SOTA polling)
- Modify: `CarrierWave/Services/SpotsService.swift:1-17` (add `.sota` to `SpotSource`)

**Step 1: Add `.sota` to `SpotSource` enum**

In `SpotsService.swift` line 6-8 (the `SpotSource` enum), add:

```swift
enum SpotSource: String, Sendable {
    case rbn
    case pota
    case sota
}
```

**Step 2: Add `UnifiedSpot` SOTA fields**

In `SpotsService.swift`, the `UnifiedSpot` struct (lines 22-119) has POTA-specific optional fields (`parkRef`, `parkName`, etc.). Add SOTA fields:

```swift
/// SOTA-specific fields
var summitCode: String?
var summitName: String?
var summitPoints: Int?
```

**Step 3: Add SOTAClient to SpotMonitoringService**

In `SpotMonitoringService.swift`, add a `sotaClient` property alongside the existing `potaClient`:

```swift
private var sotaClient: SOTAClient?
```

**Step 4: Extend `fetchHunterPOTASpots` to also fetch SOTA**

Rename or extend the existing `fetchHunterPOTASpots(since:)` method (lines 244-274) to also fetch SOTA spots concurrently. The pattern: use `async let` to fetch both in parallel, then merge results. Convert SOTA spots to the same unified format used for display.

Add a new `fetchHunterSOTASpots` method:

```swift
private func fetchHunterSOTASpots() async throws -> [SOTASpot] {
    if sotaClient == nil {
        sotaClient = SOTAClient()
    }
    return try await sotaClient!.fetchSpots(count: 50)
}
```

Then in the hunter poll loop, fetch SOTA spots alongside POTA and merge into `hunterSpots`.

**Step 5: Build and verify**

Run: `xc build`
Expected: Clean build. SOTA spots will now be fetched during hunter monitoring.

**Step 6: Commit**

```
feat: integrate SOTA spots into SpotMonitoringService

Fetches SOTAwatch spots alongside POTA in the hunter poll loop.
SOTA spots appear as ActiveStation with .sota source.
```

---

## Task 4: Rename `.pota` Command to `.hunt`

Rename the logger command and update all references. Keep `POTA` as a parsing alias.

**Files:**
- Modify: `CarrierWave/Models/LoggerCommand.swift` (rename case + parsing)
- Modify: `CarrierWave/Models/LoggerCommand+Suggestions.swift` (update suggestion)
- Modify: `CarrierWave/Views/Logger/LoggerView+Commands.swift:26` (handle `.hunt`)
- Modify: `CarrierWave/Views/Logger/SpotSelection.swift:7,48` (rename tab + action)
- Modify: `CarrierWave/Views/Logger/LoggerSpotsSidebarView.swift:36-39` (tab reference)
- Modify: `CarrierWave/Views/Settings/CommandRowSettingsView.swift:22,36,50,64,78` (rename item)
- Modify: `CarrierWave/Views/Logger/iPadCommandStrip.swift:43` (default commands string)
- Modify: All files referencing `.pota` on `LoggerCommand`, `SidebarTab`, `SpotCommandAction`, or `CommandRowItem`

**Step 1: Rename `LoggerCommand.pota` to `.hunt`**

In `LoggerCommand.swift`:
- Line 21: `case pota` → `case hunt`
- Line 77: Help text: `POTA` line → `HUNT - Show activator spots (POTA + SOTA)` with `(or POTA, SPOTS)` alias note
- Line 114-115: description `case .pota: "Show POTA spots"` → `case .hunt: "Show activator spots"`
- Line 154-155: icon `case .pota: "tree.fill"` → `case .hunt: "binoculars"`
- Lines 202-204: rename `parsePOTA` call to `parseHunt`
- Lines 295-300: rename method and update:

```swift
private static func parseHunt(upper: String) -> LoggerCommand? {
    if upper == "HUNT" || upper == "POTA" || upper == "SPOTS" {
        return .hunt
    }
    return nil
}
```

**Step 2: Rename `SidebarTab.pota` to `.hunt`**

In `SpotSelection.swift`:
- Line 7: `case pota = "POTA"` → `case hunt = "Hunt"`
- Line 48: `case showPOTA` → `case showHunt`

**Step 3: Rename `CommandRowItem.pota` to `.hunt`**

In `CommandRowSettingsView.swift`:
- Line 22: `case pota` → `case hunt`
- Line 36: `case .pota: "POTA"` → `case .hunt: "HUNT"`
- Line 50: `case .pota: "tree.fill"` → `case .hunt: "binoculars"`
- Line 64: `case .pota: "Show POTA activator spots"` → `case .hunt: "Show activator spots"`
- Line 78: `case .pota: .pota` → `case .hunt: .hunt`

**Step 4: Update default commands string**

In `iPadCommandStrip.swift` line 43:
- `"rbn,solar,weather,spot,pota,p2p"` → `"rbn,solar,weather,spot,hunt,p2p"`

**Note:** Users who already have customized their command row will have `"pota"` saved in `@AppStorage`. Need to handle migration: when parsing the stored string, treat `"pota"` as `"hunt"`. Add a fallback in `CommandRowItem(rawValue:)` or in the parsing code.

**Step 5: Update LoggerView+Commands.swift**

Line 26: `case .pota:` → `case .hunt:`
Line 30: `onSpotCommand(.showPOTA)` → `onSpotCommand(.showHunt)`
Line 32: `showPOTAPanel = true` → rename the state variable or update it

**Step 6: Update LoggerSpotsSidebarView.swift**

Line 36-39: `SidebarTab.allCases` includes `.hunt` now (was `.pota`). Non-POTA sessions show `[.hunt, .mySpots, .map]` (was `[.pota, .mySpots, .map]`).

**Step 7: Search and replace all remaining `.pota` references on these types**

Grep for `\.pota` in context of `LoggerCommand`, `SidebarTab`, `SpotCommandAction`, `CommandRowItem` and update each one to `.hunt` / `.showHunt`.

**Step 8: Build**

Run: `xc build`
Expected: Clean build. All exhaustive switch statements updated.

**Step 9: Commit**

```
refactor: rename POTA command to HUNT for unified spots

Renames LoggerCommand.pota → .hunt, SidebarTab.pota → .hunt,
CommandRowItem.pota → .hunt, SpotCommandAction.showPOTA → .showHunt.
Keeps "POTA" and "SPOTS" as parsing aliases for backward compat.
Icon changes from tree.fill to binoculars.
```

---

## Task 5: Multi-Program Session Data Model

Change `LoggingSession` from single `activationType` to a set of programs.

**Files:**
- Modify: `CarrierWave/Models/LoggingSession.swift` (add `programsRawValue`, computed properties)
- Modify: `CarrierWave/Services/LoggingSessionManager.swift` (update `startSession` signature)
- Test: `CarrierWaveTests/LoggingSessionTests.swift` (add multi-program tests)

**Step 1: Add `programsRawValue` field to LoggingSession**

In `LoggingSession.swift`, after line 100 (`activationTypeRawValue`), add:

```swift
/// Programs active in this session, stored as JSON array of slugs (e.g., ["pota","sota"]).
/// Empty array = casual. Replaces activationTypeRawValue as source of truth.
var programsRawValue: String = ""
```

**Step 2: Add computed properties**

After the existing `activationType` computed property (lines 197-200), add:

```swift
/// The set of active programs for this session
var programs: Set<String> {
    get {
        guard !programsRawValue.isEmpty,
              let data = programsRawValue.data(using: .utf8),
              let slugs = try? JSONDecoder().decode([String].self, from: data)
        else {
            // Migration: derive from old activationTypeRawValue
            if activationTypeRawValue == "casual" || activationTypeRawValue.isEmpty {
                return []
            }
            return [activationTypeRawValue]
        }
        return Set(slugs)
    }
    set {
        let sorted = newValue.sorted()
        if let data = try? JSONEncoder().encode(sorted) {
            programsRawValue = String(data: data, encoding: .utf8) ?? ""
        }
        // Keep activationTypeRawValue in sync for backward compat
        if newValue.isEmpty {
            activationTypeRawValue = "casual"
        } else if newValue.count == 1, let first = newValue.first {
            activationTypeRawValue = first
        } else {
            // For multi-program, pick the first alphabetically for legacy compat
            activationTypeRawValue = sorted.first ?? "casual"
        }
    }
}

/// Whether this is a POTA activation
var isPOTA: Bool { programs.contains("pota") }

/// Whether this is a SOTA activation
var isSOTA: Bool { programs.contains("sota") }

/// Whether this is a casual (no-program) session
var isCasual: Bool { programs.isEmpty }
```

**Step 3: Update init to accept programs**

Update the init (lines 48-84) to accept `programs: Set<String> = []` instead of `activationType: ActivationType = .casual`. Keep the old parameter for backward compat with tests:

```swift
init(
    id: UUID = UUID(),
    myCallsign: String,
    startedAt: Date = Date(),
    frequency: Double? = nil,
    mode: String = "CW",
    programs: Set<String> = [],
    activationType: ActivationType = .casual,  // deprecated, for test compat
    parkReference: String? = nil,
    sotaReference: String? = nil,
    // ... rest unchanged
) {
    // ...
    if !programs.isEmpty {
        self.programs = programs
    } else if activationType != .casual {
        self.programs = [activationType.rawValue]
    }
    // ...
}
```

**Step 4: Write tests for multi-program sessions**

Add to `CarrierWaveTests/LoggingSessionTests.swift`:

```swift
func testMultiProgramSession() {
    let session = LoggingSession(
        myCallsign: "W6JSV",
        programs: ["pota", "sota"],
        parkReference: "K-1234",
        sotaReference: "W4C/CM-001"
    )
    XCTAssertTrue(session.isPOTA)
    XCTAssertTrue(session.isSOTA)
    XCTAssertFalse(session.isCasual)
    XCTAssertEqual(session.programs, ["pota", "sota"])
}

func testCasualSessionFromEmptyPrograms() {
    let session = LoggingSession(myCallsign: "W6JSV")
    XCTAssertTrue(session.isCasual)
    XCTAssertFalse(session.isPOTA)
    XCTAssertFalse(session.isSOTA)
    XCTAssertTrue(session.programs.isEmpty)
}

func testMigrationFromOldActivationType() {
    let session = LoggingSession(myCallsign: "W6JSV")
    session.activationTypeRawValue = "pota"
    session.programsRawValue = ""  // Simulate old data with no programs field
    XCTAssertTrue(session.isPOTA)
    XCTAssertEqual(session.programs, ["pota"])
}
```

**Step 5: Run tests**

Run: `xc test-unit`
Expected: All tests pass including new multi-program tests.

**Step 6: Commit**

```
feat: add multi-program support to LoggingSession

Adds programsRawValue field storing JSON array of program slugs.
Sessions can now be POTA+SOTA simultaneously. Old activationTypeRawValue
migrates transparently on read. Adds isPOTA, isSOTA, isCasual helpers.
```

---

## Task 6: Migrate `activationType` References

Convert all `activationType == .pota` checks to use the new `isPOTA`/`isSOTA`/`isCasual` properties. This is a large but mechanical find-and-replace task.

**Files:** ~30 files (see full list from exploration). Group by subsystem.

**Strategy:** For each file, replace:
- `session.activationType == .pota` → `session.isPOTA`
- `session.activationType == .sota` → `session.isSOTA`
- `session.activationType == .casual` → `session.isCasual`
- `activationType: .pota` (in init calls) → `programs: ["pota"]`
- `activationType: .sota` → `programs: ["sota"]`
- `activationType: .casual` → `programs: []` or just omit

**Key subsystems to update (do these in separate sub-commits):**

**6a: LoggingSessionManager and extensions**
- `LoggingSessionManager.swift:94,117,131`
- `LoggingSessionManager+SessionManagement.swift:35`
- `LoggingSessionManager+Conditions.swift:27`
- `LoggingSessionManager+Spotting.swift:46,77,177,249,339`
- `LoggingSessionManager+FrequencyAndMode.swift:36,57,94,108`
- `LoggingSessionManager+Helpers.swift:59,72,143`
- `LoggingSessionManager+SessionActivity.swift:104`
- `LoggingSessionManager+QSOManagement.swift:56`
- `LoggingSessionManager+LiveActivity.swift:14`
- `LoggingSessionManager+POTASplit.swift:19,135`

**6b: Logger views**
- `LoggerView+Commands.swift:106,174`
- `LoggerView+Landscape.swift:152`
- `LoggerView+Data.swift:39,133`
- `LoggerView+FormFields.swift:239`
- `LoggerView+QSOLogging.swift:270`
- `LoggerView+SessionHeader.swift:143,147,241`
- `LoggerContainerView.swift:166`

**6c: Session views**
- `SessionsTabView.swift:62,67`
- `SessionDetailView+Components.swift:182`
- `SessionMetadataEditSheet.swift:41`
- `SessionRow.swift:70,118`
- `SessionsView+Actions.swift:34`

**6d: Cloud sync (handle carefully — affects iCloud data)**
- `CKRecordMapper+SessionMapping.swift:24,85-86` — keep `activationTypeRawValue` in CK records for cross-device compat
- `CloudSyncEngine+InboundSession.swift:57` — on inbound, set both old and new fields
- `CloudSyncEngine+FieldExtraction.swift:75` — extract both fields
- `CloudSyncEngine+FieldApplication.swift:53` — apply both fields
- `CloudSyncConflictResolver.swift:110` — keep both in sync

**6e: Other services**
- `POTASplitRepairService.swift:15,106` — keep using `activationTypeRawValue` for predicate (SwiftData predicates can't use computed properties)
- `ActivityProgramStore.swift:44-45` — keep bridge method
- `ActivityProgram.swift:127-137` — keep bridge for now

**6f: Watch app**
- `WatchSessionDelegate.swift:31,47`
- `SharedDataReader.swift:62`
- `ActiveSessionView.swift:74`
- `QuickStartView.swift:28,31,139,149,155`

**6g: Test files**
- All test files using `activationType:` parameter — update to `programs:` where appropriate

**Important:** For SwiftData `#Predicate` expressions that filter on `activationTypeRawValue` (e.g., `POTASplitRepairService.swift:15`), keep using the raw value field since predicates can't call computed properties. The `activationTypeRawValue` stays in sync via the `programs` setter.

**Step: Build after each subsystem**

After each sub-commit (6a through 6g), run `xc build` to verify clean compilation.

**Commit pattern:**

```
refactor(sessions): migrate activationType to programs in session manager
refactor(logger): migrate activationType to programs in logger views
refactor(sessions): migrate activationType to programs in session views
refactor(cloud): handle programs field in iCloud sync
refactor(services): migrate activationType in repair services
refactor(watch): migrate activationType in Watch app
refactor(tests): update tests for multi-program sessions
```

---

## Task 7: Session Start UI — Toggle Chips

Replace the segmented picker with toggle chips for POTA/SOTA selection.

**Files:**
- Modify: `CarrierWave/Views/Logger/SessionStartHelperViews.swift:51-105` (ActivationSectionView)
- Modify: `CarrierWave/Views/Logger/SessionStartSheet.swift:18,124-129,198-199,284-286,343-345,375-379`
- Modify: `CarrierWave/Views/Logger/SessionStartSheet+Sections.swift:128-137`

**Step 1: Redesign ActivationSectionView**

In `SessionStartHelperViews.swift`, replace the `ActivationSectionView` (lines 51-105) with a toggle-chip approach:

```swift
struct ActivationSectionView: View {
    @Binding var selectedPrograms: Set<String>
    @Binding var parkReference: String
    @Binding var sotaReference: String
    @Binding var isRove: Bool

    var userGrid: String?
    var defaultCountry: String = "US"

    var body: some View {
        Section {
            programChips
            if selectedPrograms.contains("pota") {
                potaFields
            }
            if selectedPrograms.contains("sota") {
                sotaFields
            }
        } header: {
            Text("Programs")
        } footer: {
            if selectedPrograms.isEmpty {
                Text("No program selected — casual session")
            }
        }
    }

    private var programChips: some View {
        HStack(spacing: 12) {
            ProgramChip(
                label: "POTA",
                icon: "tree",
                isSelected: selectedPrograms.contains("pota"),
                onToggle: { toggleProgram("pota") }
            )
            ProgramChip(
                label: "SOTA",
                icon: "mountain.2",
                isSelected: selectedPrograms.contains("sota"),
                onToggle: { toggleProgram("sota") }
            )
            Spacer()
        }
    }

    private func toggleProgram(_ slug: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedPrograms.contains(slug) {
                selectedPrograms.remove(slug)
            } else {
                selectedPrograms.insert(slug)
            }
        }
    }

    @ViewBuilder
    private var potaFields: some View {
        ParkEntryField(
            parkReference: $parkReference,
            label: "Parks",
            placeholder: "1234 or US-1234",
            userGrid: userGrid,
            defaultCountry: defaultCountry
        )
        Toggle(isOn: $isRove) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This is a rove")
                    .font(.subheadline.weight(.medium))
                Text("Visit multiple parks in one session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sotaFields: some View {
        SummitEntryField(
            sotaReference: $sotaReference,
            userGrid: userGrid
        )
    }
}
```

**Step 2: Create ProgramChip view**

Add a `ProgramChip` component (can be in the same file or a new helper):

```swift
struct ProgramChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark" : icon)
                    .font(.caption.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
            .foregroundStyle(isSelected ? .accentColor : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

**Step 3: Update SessionStartSheet state**

In `SessionStartSheet.swift`:
- Line 18: Replace `@State var activationType: ActivationType = .casual` with `@State var selectedPrograms: Set<String> = []`
- Update `@AppStorage("loggerDefaultActivationType")` to `@AppStorage("loggerDefaultPrograms")` storing JSON
- Update `startSession()` to pass `programs: selectedPrograms`
- Update `saveDefaults()` to persist the program set
- Update `canStart` / `startDisabledReason` to use program set

**Step 4: Update SessionStartValidation**

In `SessionStartHelperViews.swift`, update validation:

```swift
enum SessionStartValidation {
    static func canStart(
        callsign: String,
        programs: Set<String>,
        parkReference: String,
        sotaReference: String,
        frequency: Double?
    ) -> Bool {
        guard !callsign.isEmpty, callsign.count >= 3 else { return false }
        if programs.contains("pota") {
            guard !parkReference.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        }
        if programs.contains("sota") {
            guard !sotaReference.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        }
        return true
    }

    static func disabledReason(
        callsign: String,
        programs: Set<String>,
        parkReference: String,
        sotaReference: String,
        frequency: Double?
    ) -> String? {
        if callsign.isEmpty || callsign.count < 3 {
            return "Set your callsign in Settings → About Me"
        }
        if programs.contains("pota"),
           parkReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return "POTA requires park reference"
        }
        if programs.contains("sota"),
           sotaReference.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return "SOTA requires summit reference"
        }
        return nil
    }
}
```

**Step 5: Build and test**

Run: `xc build`
Expected: Clean build. The session start sheet now shows toggle chips.

**Step 6: Commit**

```
feat: replace activation type picker with program toggle chips

Session start now uses independent POTA/SOTA toggle chips instead
of a segmented picker. Neither selected = casual. Both = dual session.
Park and summit entry fields appear conditionally when toggled on.
```

---

## Task 8: Unified Spots Panel (HUNT view)

Update the POTA spots views to show SOTA spots in a unified list with program badges.

**Files:**
- Modify: `CarrierWave/Views/Logger/POTASpotsView.swift` (extend for SOTA, or rename to `HuntSpotsView`)
- Modify: `CarrierWave/Views/Logger/POTASpotRow.swift` (add SOTA badge support)
- Modify: `CarrierWave/Views/Logger/SidebarPOTASpotsView.swift` (extend for SOTA)
- Modify: `CarrierWave/Views/Logger/SpotFilters.swift` (add source filter enum)
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogSpotRow.swift` (add SOTA badge)
- Modify: `CarrierWave/Views/ActivityLog/ActivityLogSpotsList.swift` (include SOTA)

**Step 1: Add source filter to SpotFilters**

In `SpotFilters.swift`, add a `SourceFilter` enum:

```swift
enum SourceFilter: String, CaseIterable {
    case all = "All"
    case pota = "POTA"
    case sota = "SOTA"
    case rbn = "RBN"

    func matches(_ source: SpotSource) -> Bool {
        switch self {
        case .all: true
        case .pota: source == .pota
        case .sota: source == .sota
        case .rbn: source == .rbn
        }
    }
}
```

**Step 2: Add program badge to spot rows**

In `POTASpotRow.swift` (or a new shared component), add a small icon badge:

```swift
@ViewBuilder
var programBadge: some View {
    switch source {
    case .pota:
        Image(systemName: "tree.fill")
            .foregroundStyle(.green)
    case .sota:
        Image(systemName: "mountain.2.fill")
            .foregroundStyle(.brown)
    case .rbn:
        Image(systemName: "dot.radiowaves.up.forward")
            .foregroundStyle(.blue)
    }
}
```

**Step 3: Extend POTASpotsView to include SOTA**

The existing `POTASpotsView` fetches spots from `POTAClient`. Extend it to also use `SOTAClient` and merge results. Add a source filter chip row at the top. Rename if appropriate (the file can keep its name for git history, but the struct could become `HuntSpotsView` with a typealias for backward compat).

**Step 4: Similarly update ActivityLogSpotsList**

The activity log spots list already uses `SpotMonitoringService.hunterSpots`. Since Task 3 already wired SOTA into that service, the spots should flow through automatically. Just update the row views to show the program badge.

**Step 5: Build**

Run: `xc build`
Expected: Clean build. Spots panel now shows POTA and SOTA spots with badges.

**Step 6: Commit**

```
feat: unified HUNT spots panel with POTA + SOTA badges

Shows POTA and SOTA spots in a single chronological list with
program badges (tree for POTA, mountain for SOTA). Adds source
filter chips (All/POTA/SOTA/RBN) at the top of the spots panel.
```

---

## Task 9: Update SOTA Capabilities + ActivityProgramStore

Enable `.browseSpots` capability for SOTA in the bundled program definitions.

**Files:**
- Modify: `CarrierWave/Services/ActivityProgramStore.swift:141` (SOTA capabilities)

**Step 1: Add `.browseSpots` to SOTA**

In `ActivityProgramStore.swift` line 141, change SOTA capabilities from:

```swift
capabilities: [.referenceField, .adifUpload],
```

to:

```swift
capabilities: [.referenceField, .adifUpload, .browseSpots],
```

**Step 2: Commit**

```
feat: enable SOTA spot browsing capability

Adds .browseSpots to SOTA program capabilities in bundled definitions.
```

---

## Task 10: Update CHANGELOG and FILE_INDEX

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/FILE_INDEX.md`

**Step 1: Update CHANGELOG**

Add under `[Unreleased]`:

```markdown
### Added
- SOTA spots from SOTAwatch API in unified HUNT spots panel
- Multi-program sessions: activate POTA and SOTA simultaneously
- HUNT logger command replacing POTA (POTA kept as alias)
- Program toggle chips in session start sheet
- Source filter (All/POTA/SOTA/RBN) in spots panel

### Changed
- POTA spots command renamed to HUNT with binoculars icon
- Session start uses toggle chips instead of segmented picker
- Spots panel shows unified list with program badges
```

**Step 2: Update FILE_INDEX**

Add entries for all new files:
- `Models/SOTASpot.swift`
- `Services/SOTA/SOTAClient+Spots.swift`

**Step 3: Commit**

```
docs: update CHANGELOG and FILE_INDEX for SOTA spots feature
```

---

## Task 11: End-to-End Smoke Test

Verify the complete flow works together.

**Checklist:**
1. Start a casual session (no programs selected) — verify it works as before
2. Start a POTA-only session — verify park reference required, spots show
3. Start a SOTA-only session — verify summit reference required
4. Start a POTA+SOTA dual session — verify both references required
5. Type `HUNT` command — verify unified spots panel opens
6. Type `POTA` command — verify it still works (alias)
7. Verify SOTA spots appear in the spots panel
8. Tap a SOTA spot — verify it fills the logger fields
9. Verify iPad sidebar shows "Hunt" tab with unified spots
10. Verify hunter activity log shows SOTA spots
11. Verify old sessions with `activationTypeRawValue` display correctly

**Step 1: Deploy to device**

Run: `xc deploy` (or `make deploy`)

**Step 2: Manual testing of each checklist item**

**Step 3: Fix any issues found, commit fixes**
