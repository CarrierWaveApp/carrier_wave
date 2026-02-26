# FT8 Interface Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the FT8 session view with enriched decode rows, progressive disclosure, and operator-focused layout per the [design doc](2026-02-25-ft8-interface-design.md).

**Architecture:** Enrichment runs on the app layer using existing `WorkedBeforeCache`, `DescriptionLookup`, and `MaidenheadConverter`. New `FT8EnrichedDecode` model wraps `FT8DecodeResult` with enrichment data. Views are rebuilt as composable SwiftUI components. Layout restructured to maximize decode list space.

**Tech Stack:** SwiftUI, CarrierWaveCore SPM, Swift Testing (core), XCTest (integration)

---

## Task 1: Add Distance & Bearing to MaidenheadConverter

Adds haversine distance and bearing calculation between two grid squares. Pure math, no dependencies.

**Files:**
- Modify: `CarrierWaveCore/Sources/CarrierWaveCore/MaidenheadConverter.swift`
- Test: `CarrierWaveCore/Tests/CarrierWaveCoreTests/MaidenheadConverterTests.swift`

**Step 1: Write the failing test**

```swift
// In MaidenheadConverterTests.swift — add to existing test suite or create new file

@Suite("MaidenheadConverter Distance Tests")
struct MaidenheadConverterDistanceTests {
    @Test("Distance FN31 to FN42 is approximately 150 km")
    func distanceFN31toFN42() {
        let d = MaidenheadConverter.distanceKm(from: "FN31", to: "FN42")
        #expect(d != nil)
        #expect(d! > 100 && d! < 200)
    }

    @Test("Distance FN31 to PM95 is approximately 10900 km (US to Japan)")
    func distanceFN31toPM95() {
        let d = MaidenheadConverter.distanceKm(from: "FN31", to: "PM95")
        #expect(d != nil)
        #expect(d! > 10_000 && d! < 12_000)
    }

    @Test("Distance with invalid grid returns nil")
    func distanceInvalidGrid() {
        let d = MaidenheadConverter.distanceKm(from: "FN31", to: "ZZ99")
        #expect(d == nil)
    }

    @Test("Bearing FN31 to PM95 is roughly northwest (280-320 degrees)")
    func bearingToJapan() {
        let b = MaidenheadConverter.bearing(from: "FN31", to: "PM95")
        #expect(b != nil)
        #expect(b! > 280 && b! < 340)
    }

    @Test("Distance in miles converts correctly")
    func distanceMiles() {
        let km = MaidenheadConverter.distanceKm(from: "FN31", to: "FN42")
        let mi = MaidenheadConverter.distanceMiles(from: "FN31", to: "FN42")
        #expect(km != nil && mi != nil)
        let ratio = mi! / km!
        #expect(ratio > 0.62 && ratio < 0.63) // 1 km ≈ 0.621 mi
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xc test-core`
Expected: FAIL — `distanceKm`, `distanceMiles`, `bearing` not defined on `MaidenheadConverter`

**Step 3: Write minimal implementation**

Add to `MaidenheadConverter.swift`:

```swift
// MARK: - Distance & Bearing

public extension MaidenheadConverter {
    /// Haversine distance between two grid squares in kilometers.
    static func distanceKm(from grid1: String, to grid2: String) -> Double? {
        guard let c1 = coordinate(from: grid1),
              let c2 = coordinate(from: grid2)
        else { return nil }
        return haversineKm(c1, c2)
    }

    /// Distance between two grid squares in statute miles.
    static func distanceMiles(from grid1: String, to grid2: String) -> Double? {
        guard let km = distanceKm(from: grid1, to: grid2) else { return nil }
        return km * 0.621_371
    }

    /// Initial bearing (degrees, 0-360) from grid1 to grid2.
    static func bearing(from grid1: String, to grid2: String) -> Double? {
        guard let c1 = coordinate(from: grid1),
              let c2 = coordinate(from: grid2)
        else { return nil }
        return initialBearing(c1, c2)
    }

    // MARK: - Private Helpers

    private static func haversineKm(_ c1: Coordinate, _ c2: Coordinate) -> Double {
        let R = 6_371.0 // Earth radius in km
        let dLat = (c2.latitude - c1.latitude) * .pi / 180
        let dLon = (c2.longitude - c1.longitude) * .pi / 180
        let lat1 = c1.latitude * .pi / 180
        let lat2 = c2.latitude * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    private static func initialBearing(_ c1: Coordinate, _ c2: Coordinate) -> Double {
        let lat1 = c1.latitude * .pi / 180
        let lat2 = c2.latitude * .pi / 180
        let dLon = (c2.longitude - c1.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xc test-core`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/MaidenheadConverter.swift
git add CarrierWaveCore/Tests/CarrierWaveCoreTests/MaidenheadConverterTests.swift
git commit -m "feat: add distance and bearing calculation to MaidenheadConverter"
```

---

## Task 2: Create FT8EnrichedDecode Model

Pure data model wrapping `FT8DecodeResult` with enrichment fields. Goes in CarrierWaveCore since it extends the decode pipeline.

**Files:**
- Create: `CarrierWaveCore/Sources/CarrierWaveCore/FT8EnrichedDecode.swift`
- Test: `CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8EnrichedDecodeTests.swift`

**Step 1: Write the failing test**

```swift
@Suite("FT8EnrichedDecode Tests")
struct FT8EnrichedDecodeTests {
    @Test("Section classification: CQ → callingCQ")
    func cqSectionClassification() {
        let decode = FT8DecodeResult(
            message: .cq(call: "W1AW", grid: "FN31", modifier: nil),
            snr: -12, deltaTime: 0.1, frequency: 1500, rawText: "CQ W1AW FN31"
        )
        let enriched = FT8EnrichedDecode(
            decode: decode, dxccEntity: "United States", stateProvince: "Connecticut",
            distanceMiles: 1240, bearing: 45,
            isNewDXCC: true, isNewState: false, isNewGrid: false, isNewBand: false, isDupe: false
        )
        #expect(enriched.section == .callingCQ)
        #expect(enriched.isNewDXCC)
        #expect(enriched.sortPriority == 0) // New DXCC = highest priority
    }

    @Test("Section classification: directed at me → directedAtYou")
    func directedSection() {
        let decode = FT8DecodeResult(
            message: .signalReport(from: "JA1XYZ", to: "K1ABC", dB: -15),
            snr: -15, deltaTime: 0.0, frequency: 800, rawText: "K1ABC JA1XYZ -15"
        )
        let enriched = FT8EnrichedDecode(
            decode: decode, dxccEntity: "Japan", stateProvince: nil,
            distanceMiles: 6800, bearing: 310,
            isNewDXCC: false, isNewState: false, isNewGrid: false, isNewBand: false, isDupe: false,
            isDirectedAtMe: true
        )
        #expect(enriched.section == .directedAtYou)
    }

    @Test("Section classification: non-CQ exchange → allActivity")
    func allActivitySection() {
        let decode = FT8DecodeResult(
            message: .signalReport(from: "W3LPL", to: "K1TTT", dB: -5),
            snr: -5, deltaTime: 0.0, frequency: 1200, rawText: "K1TTT W3LPL -05"
        )
        let enriched = FT8EnrichedDecode(
            decode: decode, dxccEntity: nil, stateProvince: nil,
            distanceMiles: nil, bearing: nil,
            isNewDXCC: false, isNewState: false, isNewGrid: false, isNewBand: false, isDupe: false
        )
        #expect(enriched.section == .allActivity)
    }

    @Test("Sort priority: newDXCC < newState < newBand < normal < dupe")
    func sortPriorityOrdering() {
        let base = FT8DecodeResult(
            message: .cq(call: "TEST", grid: "AA00", modifier: nil),
            snr: -10, deltaTime: 0, frequency: 1000, rawText: "CQ TEST AA00"
        )
        let newDXCC = FT8EnrichedDecode(
            decode: base, dxccEntity: nil, stateProvince: nil,
            distanceMiles: nil, bearing: nil,
            isNewDXCC: true, isNewState: false, isNewGrid: false, isNewBand: false, isDupe: false
        )
        let newState = FT8EnrichedDecode(
            decode: base, dxccEntity: nil, stateProvince: nil,
            distanceMiles: nil, bearing: nil,
            isNewDXCC: false, isNewState: true, isNewGrid: false, isNewBand: false, isDupe: false
        )
        let dupe = FT8EnrichedDecode(
            decode: base, dxccEntity: nil, stateProvince: nil,
            distanceMiles: nil, bearing: nil,
            isNewDXCC: false, isNewState: false, isNewGrid: false, isNewBand: false, isDupe: true
        )
        #expect(newDXCC.sortPriority < newState.sortPriority)
        #expect(newState.sortPriority < dupe.sortPriority)
    }

    @Test("SNR tier classification")
    func snrTier() {
        let strong = FT8EnrichedDecode.snrTier(forSNR: -3)
        let medium = FT8EnrichedDecode.snrTier(forSNR: -10)
        let weak = FT8EnrichedDecode.snrTier(forSNR: -18)
        #expect(strong == .strong)
        #expect(medium == .medium)
        #expect(weak == .weak)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xc test-core`
Expected: FAIL — `FT8EnrichedDecode` not defined

**Step 3: Write minimal implementation**

```swift
//
//  FT8EnrichedDecode.swift
//  CarrierWaveCore
//

import Foundation

// MARK: - FT8EnrichedDecode

/// FT8 decode result enriched with DXCC, distance, worked-before, and section data.
public struct FT8EnrichedDecode: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        decode: FT8DecodeResult,
        dxccEntity: String?,
        stateProvince: String?,
        distanceMiles: Int?,
        bearing: Int?,
        isNewDXCC: Bool,
        isNewState: Bool,
        isNewGrid: Bool,
        isNewBand: Bool,
        isDupe: Bool,
        isDirectedAtMe: Bool = false
    ) {
        self.decode = decode
        self.dxccEntity = dxccEntity
        self.stateProvince = stateProvince
        self.distanceMiles = distanceMiles
        self.bearing = bearing
        self.isNewDXCC = isNewDXCC
        self.isNewState = isNewState
        self.isNewGrid = isNewGrid
        self.isNewBand = isNewBand
        self.isDupe = isDupe
        self.isDirectedAtMe = isDirectedAtMe
    }

    // MARK: Public

    public let decode: FT8DecodeResult
    public let dxccEntity: String?
    public let stateProvince: String?
    public let distanceMiles: Int?
    public let bearing: Int?
    public let isNewDXCC: Bool
    public let isNewState: Bool
    public let isNewGrid: Bool
    public let isNewBand: Bool
    public let isDupe: Bool
    public let isDirectedAtMe: Bool

    public var id: UUID { decode.id }

    // MARK: - Section Classification

    public enum Section: Int, Sendable, Comparable {
        case directedAtYou = 0
        case callingCQ = 1
        case allActivity = 2

        public static func < (lhs: Section, rhs: Section) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var section: Section {
        if isDirectedAtMe { return .directedAtYou }
        if decode.message.isCallable { return .callingCQ }
        return .allActivity
    }

    /// Sort priority within a section (lower = more interesting).
    /// New DXCC (0) > New State/Grid (1) > New Band (2) > Normal (3) > Dupe (4)
    public var sortPriority: Int {
        if isNewDXCC { return 0 }
        if isNewState || isNewGrid { return 1 }
        if isNewBand { return 2 }
        if isDupe { return 4 }
        return 3
    }

    // MARK: - SNR Tier

    public enum SNRTier: Sendable {
        case strong  // > -5 dB
        case medium  // -5 to -15 dB
        case weak    // < -15 dB
    }

    public static func snrTier(forSNR snr: Int) -> SNRTier {
        if snr > -5 { return .strong }
        if snr >= -15 { return .medium }
        return .weak
    }
}
```

**Step 4: Run test to verify it passes**

Run: `xc test-core`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWaveCore/Sources/CarrierWaveCore/FT8EnrichedDecode.swift
git add CarrierWaveCore/Tests/CarrierWaveCoreTests/FT8EnrichedDecodeTests.swift
git commit -m "feat: add FT8EnrichedDecode model with section classification and sort priority"
```

---

## Task 3: Create FT8DecodeEnricher Service

App-layer service that enriches raw `FT8DecodeResult` arrays into `FT8EnrichedDecode` arrays using existing `WorkedBeforeCache`, `DescriptionLookup`, and `MaidenheadConverter`.

**Files:**
- Create: `CarrierWave/Services/FT8DecodeEnricher.swift`
- Test: `CarrierWaveTests/FT8DecodeEnricherTests.swift`

**Step 1: Write the failing test**

```swift
import CarrierWaveCore
@testable import CarrierWave
import XCTest

final class FT8DecodeEnricherTests: XCTestCase {
    @MainActor
    func testEnrichCQDecode_PopulatesEntityAndDistance() throws {
        let enricher = FT8DecodeEnricher(myCallsign: "K1ABC", myGrid: "FN31", currentBand: "20m")

        let decode = FT8DecodeResult(
            message: .cq(call: "W1AW", grid: "FN31", modifier: nil),
            snr: -12, deltaTime: 0.1, frequency: 1500, rawText: "CQ W1AW FN31"
        )
        let results = enricher.enrich([decode])

        XCTAssertEqual(results.count, 1)
        let enriched = results[0]
        XCTAssertEqual(enriched.section, .callingCQ)
        // W1AW is a US callsign — entity should resolve
        XCTAssertNotNil(enriched.dxccEntity)
        // FN31 to FN31 distance should be ~0
        XCTAssertNotNil(enriched.distanceMiles)
    }

    @MainActor
    func testEnrichDirectedMessage_MarksDirectedAtMe() throws {
        let enricher = FT8DecodeEnricher(myCallsign: "K1ABC", myGrid: "FN31", currentBand: "20m")

        let decode = FT8DecodeResult(
            message: .signalReport(from: "JA1XYZ", to: "K1ABC", dB: -15),
            snr: -15, deltaTime: 0.0, frequency: 800, rawText: "K1ABC JA1XYZ -15"
        )
        let results = enricher.enrich([decode])

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isDirectedAtMe)
        XCTAssertEqual(results[0].section, .directedAtYou)
    }

    @MainActor
    func testEnrichDupe_MarksDuplicateSession() throws {
        let enricher = FT8DecodeEnricher(myCallsign: "K1ABC", myGrid: "FN31", currentBand: "20m")
        enricher.markWorkedThisSession("W1AW")

        let decode = FT8DecodeResult(
            message: .cq(call: "W1AW", grid: "FN31", modifier: nil),
            snr: -12, deltaTime: 0.1, frequency: 1500, rawText: "CQ W1AW FN31"
        )
        let results = enricher.enrich([decode])

        XCTAssertTrue(results[0].isDupe)
    }

    @MainActor
    func testEnrichNonCQExchange_ClassifiesAsAllActivity() throws {
        let enricher = FT8DecodeEnricher(myCallsign: "K1ABC", myGrid: "FN31", currentBand: "20m")

        let decode = FT8DecodeResult(
            message: .rogerReport(from: "W3LPL", to: "K1TTT", dB: -5),
            snr: -5, deltaTime: 0.0, frequency: 1200, rawText: "K1TTT W3LPL R-05"
        )
        let results = enricher.enrich([decode])

        XCTAssertEqual(results[0].section, .allActivity)
        XCTAssertFalse(results[0].isDirectedAtMe)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xc test-unit`
Expected: FAIL — `FT8DecodeEnricher` not defined

**Step 3: Write minimal implementation**

```swift
//
//  FT8DecodeEnricher.swift
//  CarrierWave
//

import CarrierWaveCore
import Foundation

/// Enriches raw FT8 decode results with DXCC, distance, and worked-before data.
/// Runs synchronously on the calling thread — all lookups are in-memory O(1).
@MainActor
final class FT8DecodeEnricher {
    // MARK: Lifecycle

    init(myCallsign: String, myGrid: String, currentBand: String) {
        self.myCallsign = myCallsign.uppercased()
        self.myGrid = myGrid
        self.currentBand = currentBand
    }

    // MARK: Internal

    /// Enrich a batch of decode results. Call on each decode cycle.
    func enrich(_ decodes: [FT8DecodeResult]) -> [FT8EnrichedDecode] {
        decodes.map { enrichSingle($0) }
    }

    /// Track a callsign worked during this session (for dupe detection).
    func markWorkedThisSession(_ callsign: String) {
        sessionWorkedCallsigns.insert(callsign.uppercased())
    }

    /// Update preloaded worked-before sets from QSO history.
    func loadWorkedHistory(
        dxccEntities: Set<String>,
        states: Set<String>,
        grids: Set<String>,
        callBandCombos: Set<String>
    ) {
        workedDXCCEntities = dxccEntities
        workedStates = states
        workedGrids = grids
        workedCallBandCombos = callBandCombos
    }

    // MARK: Private

    private let myCallsign: String
    private let myGrid: String
    private let currentBand: String
    private var sessionWorkedCallsigns = Set<String>()
    private var workedDXCCEntities = Set<String>()
    private var workedStates = Set<String>()
    private var workedGrids = Set<String>()
    private var workedCallBandCombos = Set<String>()

    private func enrichSingle(_ decode: FT8DecodeResult) -> FT8EnrichedDecode {
        let callsign = decode.message.callerCallsign?.uppercased()
        let grid = decode.message.grid
        let isDirected = decode.message.isDirectedTo(myCallsign)

        // DXCC lookup
        let entity = callsign.flatMap { DescriptionLookup.entityDescription(for: $0) }
        let entityName = entity?.name
        let stateProvince = entity?.subdivision

        // Distance
        var distanceMiles: Int?
        var bearing: Int?
        if let grid, !grid.isEmpty {
            if let mi = MaidenheadConverter.distanceMiles(from: myGrid, to: grid) {
                distanceMiles = Int(mi)
            }
            if let b = MaidenheadConverter.bearing(from: myGrid, to: grid) {
                bearing = Int(b)
            }
        }

        // Worked-before checks
        let isNewDXCC = entityName != nil && !workedDXCCEntities.contains(entityName!)
        let isNewState = stateProvince != nil && !workedStates.contains(stateProvince!)
        let isNewGrid = grid != nil && !workedGrids.contains(grid!)
        let callBandKey = callsign.map { "\($0)-\(currentBand)" } ?? ""
        let isNewBand = callsign != nil
            && workedCallBandCombos.contains(callsign!) == false
            && !isNewDXCC // Only show NEW BAND if we've worked them on another band
        let isDupe = callsign != nil && sessionWorkedCallsigns.contains(callsign!)

        return FT8EnrichedDecode(
            decode: decode,
            dxccEntity: entityName,
            stateProvince: stateProvince,
            distanceMiles: distanceMiles,
            bearing: bearing,
            isNewDXCC: isNewDXCC,
            isNewState: isNewState,
            isNewGrid: isNewGrid,
            isNewBand: isNewBand,
            isDupe: isDupe,
            isDirectedAtMe: isDirected
        )
    }
}
```

> **Note:** The `DescriptionLookup.entityDescription(for:)` call returns a `DXCCEntity` with `name` and optionally `subdivision`. If the existing API doesn't have a `subdivision` field, you'll need to check the actual `DescriptionLookup` API and adapt — state/province may need to be derived from the callsign prefix or grid. Set `stateProvince` to `nil` initially if the API doesn't support it, and add it in a follow-up.

**Step 4: Run test to verify it passes**

Run: `xc test-unit`
Expected: PASS (some enrichment fields may be nil depending on DescriptionLookup API — adjust tests if needed)

**Step 5: Commit**

```bash
git add CarrierWave/Services/FT8DecodeEnricher.swift
git add CarrierWaveTests/FT8DecodeEnricherTests.swift
git commit -m "feat: add FT8DecodeEnricher service for decode enrichment"
```

---

## Task 4: Wire Enrichment into FT8SessionManager

Add the enricher to `FT8SessionManager`, enrich decodes as they arrive, and expose enriched results to views.

**Files:**
- Modify: `CarrierWave/Services/FT8SessionManager.swift`

**Step 1: Add enricher property and enriched results**

In `FT8SessionManager.swift`, add:

```swift
// New published state (add near line 43)
private(set) var enrichedDecodes: [FT8EnrichedDecode] = []
private(set) var currentCycleEnriched: [FT8EnrichedDecode] = []

// New private property (add near line 146)
private lazy var decodeEnricher = FT8DecodeEnricher(
    myCallsign: qsoStateMachine.myCallsign,
    myGrid: qsoStateMachine.myGrid,
    currentBand: selectedBand
)
```

**Step 2: Enrich decodes in handleDecodedSlot**

In `handleDecodedSlot(_ samples:)` (around line 157), after `currentCycleDecodes = results`, add:

```swift
currentCycleEnriched = decodeEnricher.enrich(results)
enrichedDecodes.append(contentsOf: currentCycleEnriched)

// Trim enriched decodes in sync with raw decodes
if enrichedDecodes.count > Self.maxDecodeResults {
    enrichedDecodes.removeFirst(enrichedDecodes.count - Self.maxDecodeResults)
}
```

**Step 3: Mark worked on QSO completion**

In `logCompletedQSO` (around line 285), after `qsoCount += 1`, add:

```swift
decodeEnricher.markWorkedThisSession(completed.theirCallsign)
```

**Step 4: Update band on band change**

Add a `didSet` to `selectedBand` (line 54):

```swift
var selectedBand: String = "20m" {
    didSet {
        decodeEnricher = FT8DecodeEnricher(
            myCallsign: qsoStateMachine.myCallsign,
            myGrid: qsoStateMachine.myGrid,
            currentBand: selectedBand
        )
    }
}
```

**Step 5: Build and verify**

Run: `xc build`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add CarrierWave/Services/FT8SessionManager.swift
git commit -m "feat: wire FT8DecodeEnricher into FT8SessionManager"
```

---

## Task 5: FT8StatusPillView (Collapsed Debug Panel)

Replace the always-visible debug panel with a compact status pill in the band selector line. Tapping expands the full debug panel.

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8StatusPillView.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift` (wire in later in Task 11)

**Step 1: Create the status pill view**

```swift
//
//  FT8StatusPillView.swift
//  CarrierWave
//

import SwiftUI

/// Compact status indicator showing audio health and decode count.
/// Tapping expands the full debug panel.
struct FT8StatusPillView: View {
    // MARK: Internal

    let audioLevel: Float
    let decodeCount: Int
    let cyclesSinceLastDecode: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text("\(decodeCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private var statusColor: Color {
        if cyclesSinceLastDecode >= 4 || audioLevel < 0.001 {
            return .red
        }
        if audioLevel < 0.01 || audioLevel > 0.8 {
            return .orange
        }
        return .green
    }

    private var statusLabel: String {
        if cyclesSinceLastDecode >= 4 || audioLevel < 0.001 {
            return "No Signal"
        }
        if audioLevel < 0.01 {
            return "Low"
        }
        if audioLevel > 0.8 {
            return "Hot"
        }
        return "OK"
    }
}
```

**Step 2: Build and verify**

Run: `xc build`
Expected: PASS

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8StatusPillView.swift
git commit -m "feat: add FT8StatusPillView for collapsed debug panel"
```

---

## Task 6: Achievement Badge & SNR Badge Components

Small reusable badge views for NEW DXCC, NEW STATE, NEW GRID, NEW BAND, DUPE, and SNR strength.

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8BadgeViews.swift`

**Step 1: Write badge components**

```swift
//
//  FT8BadgeViews.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

// MARK: - FT8AchievementBadge

/// Achievement badge for worked-before status (NEW DXCC, NEW BAND, DUPE, etc.)
struct FT8AchievementBadge: View {
    let label: String
    let foregroundColor: Color
    let backgroundColor: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Preset Badges

extension FT8AchievementBadge {
    static var newDXCC: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW DXCC",
            foregroundColor: .yellow,
            backgroundColor: Color.yellow.opacity(0.3)
        )
    }

    static var newState: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW STATE",
            foregroundColor: .blue,
            backgroundColor: Color.blue.opacity(0.15)
        )
    }

    static var newGrid: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW GRID",
            foregroundColor: .cyan,
            backgroundColor: Color.cyan.opacity(0.15)
        )
    }

    static var newBand: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "NEW BAND",
            foregroundColor: .white,
            backgroundColor: .blue
        )
    }

    static var dupe: FT8AchievementBadge {
        FT8AchievementBadge(
            label: "DUPE",
            foregroundColor: .orange,
            backgroundColor: Color.orange.opacity(0.2)
        )
    }
}

// MARK: - FT8SNRBadge

/// Colored SNR badge indicating signal strength tier.
struct FT8SNRBadge: View {
    let snr: Int

    var body: some View {
        Text("\(snr)")
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: Private

    private var tier: FT8EnrichedDecode.SNRTier {
        FT8EnrichedDecode.snrTier(forSNR: snr)
    }

    private var foregroundColor: Color {
        switch tier {
        case .strong: .green
        case .medium: .yellow
        case .weak: .orange
        }
    }

    private var backgroundColor: Color {
        switch tier {
        case .strong: Color.green.opacity(0.2)
        case .medium: Color.yellow.opacity(0.2)
        case .weak: Color.orange.opacity(0.2)
        }
    }
}
```

**Step 2: Build and verify**

Run: `xc build`
Expected: PASS

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8BadgeViews.swift
git commit -m "feat: add FT8 achievement badge and SNR badge components"
```

---

## Task 7: Enriched Decode Row View

The primary UI component — a multi-line enriched decode row replacing the current raw text row.

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8EnrichedDecodeRow.swift`

**Step 1: Write the enriched row view**

```swift
//
//  FT8EnrichedDecodeRow.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

/// Enriched decode row with callsign, SNR badge, grid, entity, distance, and achievement badges.
struct FT8EnrichedDecodeRow: View {
    // MARK: Internal

    let enriched: FT8EnrichedDecode
    let isCurrentCycle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            essentialsLine
            if hasContextLine {
                contextLine
            }
            if hasBadges {
                badgeLine
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .opacity(enriched.isDupe ? 0.5 : 1.0)
        .contentShape(Rectangle())
    }

    // MARK: Private

    private var callsign: String {
        enriched.decode.message.callerCallsign ?? enriched.decode.rawText
    }

    private var hasContextLine: Bool {
        enriched.dxccEntity != nil || enriched.distanceMiles != nil
    }

    private var hasBadges: Bool {
        enriched.isNewDXCC || enriched.isNewState || enriched.isNewGrid
            || enriched.isNewBand || enriched.isDupe
    }

    // MARK: Line 1 — Essentials

    private var essentialsLine: some View {
        HStack(spacing: 8) {
            Text(callsign)
                .font(.headline.monospaced().weight(.semibold))
                .fontWeight(isCurrentCycle ? .bold : .semibold)

            FT8SNRBadge(snr: enriched.decode.snr)

            if let grid = enriched.decode.message.grid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if enriched.decode.message.isCallable {
                cqIndicator
            }

            if enriched.decode.message.isCallable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var cqIndicator: some View {
        Group {
            if let modifier = enriched.decode.message.cqModifier {
                Text("CQ \(modifier)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            } else {
                Text("CQ")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: Line 2 — Context

    private var contextLine: some View {
        HStack(spacing: 4) {
            if let entity = enriched.dxccEntity {
                Text(entity)
            }
            if let state = enriched.stateProvince {
                Text("·")
                Text(state)
            }
            if let miles = enriched.distanceMiles {
                Text("·")
                Text("\(miles.formatted()) mi")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Line 3 — Badges

    private var badgeLine: some View {
        HStack(spacing: 4) {
            if enriched.isNewDXCC { FT8AchievementBadge.newDXCC }
            if enriched.isNewState { FT8AchievementBadge.newState }
            if enriched.isNewGrid { FT8AchievementBadge.newGrid }
            if enriched.isNewBand { FT8AchievementBadge.newBand }
            if enriched.isDupe { FT8AchievementBadge.dupe }
        }
    }
}

// MARK: - Directed Row Variant

/// Row variant for "Directed at You" section with orange left border.
struct FT8DirectedDecodeRow: View {
    let enriched: FT8EnrichedDecode

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 4)

            FT8EnrichedDecodeRow(enriched: enriched, isCurrentCycle: true)
        }
    }
}
```

**Step 2: Build and verify**

Run: `xc build`
Expected: PASS

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8EnrichedDecodeRow.swift
git commit -m "feat: add FT8EnrichedDecodeRow with context and achievement badges"
```

---

## Task 8: Rewrite Segmented Decode List

Replace `FT8DecodeListView` with a segmented version: "Directed at You" (pinned), "Calling CQ" (primary), "All Activity" (collapsed).

**Files:**
- Rewrite: `CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift`

**Step 1: Rewrite the decode list**

Replace the entire contents of `FT8DecodeListView.swift`:

```swift
//
//  FT8DecodeListView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8DecodeListView: View {
    // MARK: Internal

    let enrichedDecodes: [FT8EnrichedDecode]
    let currentCycleIDs: Set<UUID>
    let onCallStation: (FT8DecodeResult) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    directedSection
                    callingCQSection
                    allActivitySection
                }
            }
            .onChange(of: directedDecodes.count) { oldCount, newCount in
                if newCount > oldCount, let first = directedDecodes.first {
                    withAnimation {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var isAllActivityExpanded = false

    private var directedDecodes: [FT8EnrichedDecode] {
        enrichedDecodes
            .filter { $0.section == .directedAtYou }
    }

    private var cqDecodes: [FT8EnrichedDecode] {
        enrichedDecodes
            .filter { $0.section == .callingCQ }
            .sorted { lhs, rhs in
                if lhs.sortPriority != rhs.sortPriority {
                    return lhs.sortPriority < rhs.sortPriority
                }
                return lhs.decode.snr > rhs.decode.snr
            }
    }

    private var activityDecodes: [FT8EnrichedDecode] {
        enrichedDecodes.filter { $0.section == .allActivity }
    }

    // MARK: - Directed Section

    @ViewBuilder
    private var directedSection: some View {
        if !directedDecodes.isEmpty {
            sectionHeader("DIRECTED AT YOU", count: directedDecodes.count, accent: .orange)

            ForEach(directedDecodes) { enriched in
                FT8DirectedDecodeRow(enriched: enriched)
                    .id(enriched.id)
                    .onTapGesture { onCallStation(enriched.decode) }
            }
        }
    }

    // MARK: - CQ Section

    private var callingCQSection: some View {
        Group {
            sectionHeader("CALLING CQ", count: cqDecodes.count, accent: .blue)

            ForEach(cqDecodes) { enriched in
                FT8EnrichedDecodeRow(
                    enriched: enriched,
                    isCurrentCycle: currentCycleIDs.contains(enriched.id)
                )
                .id(enriched.id)
                .onTapGesture { onCallStation(enriched.decode) }
            }
        }
    }

    // MARK: - All Activity Section

    @ViewBuilder
    private var allActivitySection: some View {
        if !activityDecodes.isEmpty {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.0)) {
                    isAllActivityExpanded.toggle()
                }
            } label: {
                sectionHeader(
                    "ALL ACTIVITY",
                    count: activityDecodes.count,
                    accent: .secondary,
                    chevron: isAllActivityExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.plain)

            if isAllActivityExpanded {
                ForEach(activityDecodes) { enriched in
                    compactActivityRow(enriched)
                        .id(enriched.id)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(
        _ title: String,
        count: Int,
        accent: Color,
        chevron: String? = nil
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(accent)

            Text("(\(count))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            if let chevron {
                Image(systemName: chevron)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func compactActivityRow(_ enriched: FT8EnrichedDecode) -> some View {
        HStack(spacing: 6) {
            if let from = enriched.decode.message.callerCallsign {
                Text(from)
                    .font(.caption.monospaced())
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(enriched.decode.rawText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(enriched.decode.snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
```

**Step 2: Build and verify**

Run: `xc build`
Expected: Build will fail because `FT8SessionView` still passes old parameters. That's fine — we'll fix in Task 11.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift
git commit -m "feat: rewrite FT8DecodeListView with segmented sections and enriched rows"
```

---

## Task 9: Redesign Active QSO Card

Replace the current card with the step-indicator design from the design doc.

**Files:**
- Rewrite: `CarrierWave/Views/Logger/FT8/FT8ActiveQSOCard.swift`

**Step 1: Rewrite the QSO card**

```swift
//
//  FT8ActiveQSOCard.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8ActiveQSOCard: View {
    // MARK: Internal

    let stateMachine: FT8QSOStateMachine
    let distanceMiles: Int?
    let dxccEntity: String?
    let onAbort: () -> Void

    var body: some View {
        if let call = stateMachine.theirCallsign,
           stateMachine.state != .idle,
           stateMachine.state != .complete
        {
            VStack(alignment: .leading, spacing: 6) {
                headerLine(call)
                stepIndicator
                HStack {
                    Spacer()
                    Button("Abort", action: onAbort)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: Private

    private func headerLine(_ call: String) -> some View {
        HStack {
            Text(call)
                .font(.title3.bold().monospaced())

            if let grid = stateMachine.theirGrid {
                Text(grid)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let report = stateMachine.theirReport {
                Text("\(report) dB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let miles = distanceMiles {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(miles.formatted()) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            stepDot(label: "Call", filled: stepIndex >= 1)
            stepConnector
            stepDot(label: "Rpt", filled: stepIndex >= 2)
            stepConnector
            stepDot(label: "73", filled: stepIndex >= 3)
        }
    }

    private var stepIndex: Int {
        switch stateMachine.state {
        case .idle: 0
        case .calling: 1
        case .reportSent: 2
        case .reportReceived: 3
        case .complete: 3
        }
    }

    private func stepDot(label: String, filled: Bool) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? Color.orange : Color(.systemGray4))
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(filled ? .primary : .tertiary)
        }
    }

    private var stepConnector: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .frame(height: 1)
            .frame(maxWidth: 20)
            .padding(.bottom, 12) // Align with dot center
    }

    private var stateLabel: String {
        switch stateMachine.state {
        case .idle: "Idle"
        case .calling: "Calling..."
        case .reportSent: "Report Sent"
        case .reportReceived: "Confirming..."
        case .complete: "Complete!"
        }
    }
}
```

**Step 2: Build**

Run: `xc build`
Expected: Build will fail — caller in `FT8SessionView` uses old signature. Fix in Task 11.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8ActiveQSOCard.swift
git commit -m "feat: redesign FT8ActiveQSOCard with step indicator and abort button"
```

---

## Task 10: Update Control Bar with POTA Counter

Add the POTA activation counter and simplify the layout.

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8ControlBar.swift`

**Step 1: Add POTA counter**

Replace the bottom `HStack` (the QSO count / park reference section, lines 48–62) with a POTA-aware counter:

```swift
HStack {
    if let park = parkReference {
        potaCounter
    } else {
        Label("\(qsoCount) QSOs", systemImage: "list.bullet")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
}
.padding(.horizontal)
```

Add the POTA counter computed view:

```swift
@ViewBuilder
private var potaCounter: some View {
    let isValid = qsoCount >= 10
    HStack(spacing: 4) {
        if isValid {
            Text("\(qsoCount)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.green)
            Image(systemName: "tree.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Text("\(qsoCount)/10")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "tree.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

**Step 2: Build**

Run: `xc build`
Expected: PASS (control bar is standalone)

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8ControlBar.swift
git commit -m "feat: add POTA activation counter to FT8 control bar"
```

---

## Task 11: Restructure FT8SessionView Layout

Wire everything together: status pill in band row, compact waterfall, conditional QSO card, segmented decode list.

**Files:**
- Rewrite: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8DebugPanel.swift` (no structural changes, just used conditionally)

**Step 1: Rewrite FT8SessionView**

```swift
//
//  FT8SessionView.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

struct FT8SessionView: View {
    // MARK: Internal

    let ft8Manager: FT8SessionManager
    let parkReference: String?

    var body: some View {
        VStack(spacing: 0) {
            bandAndStatusRow

            if isDebugExpanded {
                FT8DebugPanel(ft8Manager: ft8Manager)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            FT8WaterfallView(
                data: ft8Manager.waterfallData,
                currentDecodes: ft8Manager.currentCycleDecodes
            )
            .frame(height: 48)

            FT8CycleIndicatorView(
                isTransmitting: ft8Manager.isTransmitting,
                timeRemaining: ft8Manager.cycleTimeRemaining
            )

            Divider()

            activeQSOCard

            FT8DecodeListView(
                enrichedDecodes: ft8Manager.enrichedDecodes,
                currentCycleIDs: Set(ft8Manager.currentCycleEnriched.map(\.id)),
                onCallStation: { ft8Manager.callStation($0) }
            )
            .frame(minHeight: 120)

            Divider()

            FT8ControlBar(
                isReceiving: ft8Manager.isReceiving,
                operatingMode: Binding(
                    get: { ft8Manager.operatingMode },
                    set: { ft8Manager.setMode($0) }
                ),
                qsoCount: ft8Manager.qsoCount,
                parkReference: parkReference,
                onStart: {
                    Task { try? await ft8Manager.start() }
                },
                onStop: {
                    Task { await ft8Manager.stop() }
                }
            )
        }
        .animation(.spring(duration: 0.3, bounce: 0.0), value: isDebugExpanded)
        .task {
            try? await ft8Manager.start()
        }
    }

    // MARK: Private

    @State private var isDebugExpanded = false

    private var bandAndStatusRow: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(FT8Constants.supportedBands, id: \.self) { band in
                    Button(band) {
                        ft8Manager.selectedBand = band
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(ft8Manager.selectedBand)
                        .font(.body.bold())
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.primary)
            }

            Text("\u{00B7}")
                .foregroundStyle(.secondary)

            Text("\(ft8Manager.selectedFrequency, specifier: "%.3f") MHz")
                .font(.body.monospacedDigit())

            Text("\u{00B7}")
                .foregroundStyle(.secondary)

            Text("FT8")
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .clipShape(Capsule())

            Spacer()

            Button {
                isDebugExpanded.toggle()
            } label: {
                FT8StatusPillView(
                    audioLevel: ft8Manager.audioLevel,
                    decodeCount: ft8Manager.currentCycleDecodes.count,
                    cyclesSinceLastDecode: ft8Manager.cyclesSinceLastDecode
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var activeQSOCard: some View {
        FT8ActiveQSOCard(
            stateMachine: ft8Manager.qsoStateMachine,
            distanceMiles: currentQSODistanceMiles,
            dxccEntity: currentQSOEntity,
            onAbort: {
                ft8Manager.setMode(.listen)
            }
        )
    }

    private var currentQSODistanceMiles: Int? {
        guard let theirGrid = ft8Manager.qsoStateMachine.theirGrid else { return nil }
        return MaidenheadConverter.distanceMiles(
            from: ft8Manager.qsoStateMachine.myGrid,
            to: theirGrid
        ).map(Int.init)
    }

    private var currentQSOEntity: String? {
        guard let call = ft8Manager.qsoStateMachine.theirCallsign else { return nil }
        return DescriptionLookup.entityDescription(for: call)?.name
    }
}
```

> **Note:** This references `ft8Manager.cyclesSinceLastDecode` which doesn't exist yet. Add it to `FT8SessionManager` as a simple counter that increments when `currentCycleDecodes` is empty and resets to 0 when decodes arrive:
>
> ```swift
> // In FT8SessionManager.swift, add property:
> private(set) var cyclesSinceLastDecode = 0
>
> // In handleDecodedSlot, update:
> if results.isEmpty {
>     cyclesSinceLastDecode += 1
> } else {
>     cyclesSinceLastDecode = 0
> }
> ```

**Step 2: Build and fix**

Run: `xc build`

Expected issues:
1. `cyclesSinceLastDecode` not on `FT8SessionManager` — add it per note above
2. `DescriptionLookup.entityDescription(for:)` API may differ — adapt to actual API
3. `MaidenheadConverter.distanceMiles` may not be available yet if Task 1 isn't done — ensure Task 1 completes first

Fix any remaining issues, then rebuild.

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8SessionView.swift
git add CarrierWave/Services/FT8SessionManager.swift
git commit -m "feat: restructure FT8SessionView with status pill, compact waterfall, and enriched decode list"
```

---

## Task 12: Haptic Feedback Integration

Add haptic feedback for key events per the design doc.

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift`

**Step 1: Add haptics to decode list**

In `FT8DecodeListView`, add haptic feedback when "Directed at You" section first appears. In the `directedSection` view builder, add an `.onChange` modifier:

```swift
// After the directedSection ForEach, add to the parent:
.onChange(of: directedDecodes.count) { oldCount, newCount in
    if newCount > oldCount {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
```

In `FT8EnrichedDecodeRow`, add tap haptic:

```swift
// Wrap the onTapGesture in callingCQSection with haptic:
.onTapGesture {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    onCallStation(enriched.decode)
}
```

**Step 2: Add QSO completion haptic**

In `FT8SessionManager.logCompletedQSO`, add:

```swift
UINotificationFeedbackGenerator().notificationOccurred(.success)
```

> Import UIKit at the top of `FT8SessionManager.swift`.

**Step 3: Add POTA milestone haptic**

In `logCompletedQSO`, after incrementing `qsoCount`:

```swift
if qsoCount == 10 {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}
```

**Step 4: Build and verify**

Run: `xc build`
Expected: PASS

**Step 5: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift
git add CarrierWave/Views/Logger/FT8/FT8SessionView.swift
git add CarrierWave/Services/FT8SessionManager.swift
git commit -m "feat: add haptic feedback for FT8 decode events and QSO completion"
```

---

## Task 13: Session Summary Toast

Show a summary toast when the FT8 session stops.

**Files:**
- Create: `CarrierWave/Views/Logger/FT8/FT8SessionSummaryToast.swift`
- Modify: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift`

**Step 1: Create the toast view**

```swift
//
//  FT8SessionSummaryToast.swift
//  CarrierWave
//

import SwiftUI

struct FT8SessionSummaryToast: View {
    let band: String
    let qsoCount: Int
    let duration: TimeInterval
    let newGrids: Int
    let newDXCC: [String] // Entity names

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("FT8 Session Complete")
                    .font(.subheadline.bold())
            }

            Text("\(formattedDuration) on \(band) · \(qsoCount) QSOs")
                .font(.caption)
                .foregroundStyle(.secondary)

            if newGrids > 0 || !newDXCC.isEmpty {
                HStack(spacing: 8) {
                    if newGrids > 0 {
                        Text("\(newGrids) new grids")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let first = newDXCC.first {
                        Text("\(newDXCC.count) new DXCC (\(first))")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.horizontal)
    }

    // MARK: Private

    private var formattedDuration: String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return "\(hours)h \(remaining)m"
    }
}
```

**Step 2: Wire into session view**

Add state and overlay to `FT8SessionView`:

```swift
@State private var showSessionSummary = false
@State private var sessionSummary: FT8SessionSummaryToast?
```

Add `.overlay` after the main VStack:

```swift
.overlay(alignment: .top) {
    if showSessionSummary, let summary = sessionSummary {
        summary
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { showSessionSummary = false }
                }
            }
    }
}
```

> The session summary data collection (tracking new grids/DXCC during session) requires adding counters to `FT8DecodeEnricher` or `FT8SessionManager`. Add `newDXCCThisSession: [String]` and `newGridsThisSession: Int` properties that increment as QSOs are logged. Wire the stop action to show the toast.

**Step 3: Build and verify**

Run: `xc build`
Expected: PASS

**Step 4: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8SessionSummaryToast.swift
git add CarrierWave/Views/Logger/FT8/FT8SessionView.swift
git commit -m "feat: add FT8 session summary toast on stop"
```

---

## Task 14: Compact Mode Toggle

Add a compact single-line display mode toggled from the section header or settings.

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift`
- Create: `CarrierWave/Views/Logger/FT8/FT8CompactDecodeRow.swift`

**Step 1: Create compact row**

```swift
//
//  FT8CompactDecodeRow.swift
//  CarrierWave
//

import CarrierWaveCore
import SwiftUI

/// Single-line compact decode row for space-constrained or preference-based display.
struct FT8CompactDecodeRow: View {
    let enriched: FT8EnrichedDecode

    var body: some View {
        HStack(spacing: 6) {
            Text(enriched.decode.message.callerCallsign ?? "???")
                .font(.caption.monospaced().weight(.medium))
                .frame(width: 72, alignment: .leading)

            Text("\(enriched.decode.snr)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            if let grid = enriched.decode.message.grid {
                Text(grid)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
            }

            if enriched.decode.message.isCallable {
                Text("CQ")
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
            }

            if let entity = enriched.dxccEntity {
                Text(entity)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if enriched.isNewDXCC {
                Text("NEW DXCC")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.yellow)
            } else if enriched.isNewGrid {
                Text("NEW GRID")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.cyan)
            } else if enriched.isDupe {
                Text("DUPE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .opacity(enriched.isDupe ? 0.5 : 1.0)
        .contentShape(Rectangle())
    }
}
```

**Step 2: Add compact mode toggle to decode list**

In `FT8DecodeListView`, add an `@AppStorage` property:

```swift
@AppStorage("ft8CompactMode") private var isCompactMode = false
```

Add a context menu on the "CALLING CQ" section header:

```swift
.contextMenu {
    Button {
        isCompactMode.toggle()
    } label: {
        Label(
            isCompactMode ? "Expanded View" : "Compact View",
            systemImage: isCompactMode ? "list.bullet" : "list.dash"
        )
    }
}
```

In the CQ section ForEach, switch on `isCompactMode`:

```swift
ForEach(cqDecodes) { enriched in
    Group {
        if isCompactMode {
            FT8CompactDecodeRow(enriched: enriched)
        } else {
            FT8EnrichedDecodeRow(
                enriched: enriched,
                isCurrentCycle: currentCycleIDs.contains(enriched.id)
            )
        }
    }
    .id(enriched.id)
    .onTapGesture {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onCallStation(enriched.decode)
    }
}
```

**Step 3: Build and verify**

Run: `xc build`
Expected: PASS

**Step 4: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8CompactDecodeRow.swift
git add CarrierWave/Views/Logger/FT8/FT8DecodeListView.swift
git commit -m "feat: add compact mode toggle for FT8 decode list"
```

---

## Task 15: Landscape Two-Column Layout

Add landscape-responsive layout using `verticalSizeClass`.

**Files:**
- Modify: `CarrierWave/Views/Logger/FT8/FT8SessionView.swift`

**Step 1: Add environment and conditional layout**

In `FT8SessionView`, add:

```swift
@Environment(\.verticalSizeClass) private var verticalSizeClass
```

Replace the main `body` with a layout switch:

```swift
var body: some View {
    Group {
        if verticalSizeClass == .compact {
            landscapeLayout
        } else {
            portraitLayout
        }
    }
    .animation(.spring(duration: 0.3, bounce: 0.0), value: isDebugExpanded)
    .task {
        try? await ft8Manager.start()
    }
}
```

Extract the current body into `portraitLayout` and add `landscapeLayout`:

```swift
private var landscapeLayout: some View {
    VStack(spacing: 0) {
        bandAndStatusRow
        HStack(spacing: 0) {
            // Left column: waterfall, QSO card, controls
            VStack(spacing: 0) {
                FT8WaterfallView(
                    data: ft8Manager.waterfallData,
                    currentDecodes: ft8Manager.currentCycleDecodes
                )
                .frame(height: 140)

                activeQSOCard

                Spacer()

                FT8ControlBar(
                    isReceiving: ft8Manager.isReceiving,
                    operatingMode: Binding(
                        get: { ft8Manager.operatingMode },
                        set: { ft8Manager.setMode($0) }
                    ),
                    qsoCount: ft8Manager.qsoCount,
                    parkReference: parkReference,
                    onStart: {
                        Task { try? await ft8Manager.start() }
                    },
                    onStop: {
                        Task { await ft8Manager.stop() }
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right column: decode list
            VStack(spacing: 0) {
                FT8CycleIndicatorView(
                    isTransmitting: ft8Manager.isTransmitting,
                    timeRemaining: ft8Manager.cycleTimeRemaining
                )

                FT8DecodeListView(
                    enrichedDecodes: ft8Manager.enrichedDecodes,
                    currentCycleIDs: Set(ft8Manager.currentCycleEnriched.map(\.id)),
                    onCallStation: { ft8Manager.callStation($0) }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

**Step 2: Build and verify**

Run: `xc build`
Expected: PASS

**Step 3: Commit**

```bash
git add CarrierWave/Views/Logger/FT8/FT8SessionView.swift
git commit -m "feat: add landscape two-column layout for FT8 session view"
```

---

## Task 16: Update FILE_INDEX.md

Add all new files to the file index.

**Files:**
- Modify: `docs/FILE_INDEX.md`

**Step 1: Add entries**

Add under the appropriate sections:

```markdown
## CarrierWaveCore
- `FT8EnrichedDecode.swift` — Enriched decode model with section classification, sort priority, and SNR tiers

## Services
- `FT8DecodeEnricher.swift` — Enriches raw FT8 decodes with DXCC, distance, and worked-before data

## Views/Logger/FT8
- `FT8StatusPillView.swift` — Compact audio health and decode count status pill
- `FT8BadgeViews.swift` — Achievement badges (NEW DXCC, NEW BAND, etc.) and SNR strength badges
- `FT8EnrichedDecodeRow.swift` — Multi-line enriched decode row with context and badges
- `FT8CompactDecodeRow.swift` — Single-line compact decode row
- `FT8SessionSummaryToast.swift` — Session completion summary toast
```

**Step 2: Commit**

```bash
git add docs/FILE_INDEX.md
git commit -m "docs: update FILE_INDEX.md with new FT8 interface files"
```

---

## Task 17: Update CHANGELOG.md

**Step 1: Add entry under [Unreleased]**

```markdown
### Added
- FT8: Enriched decode list with DXCC entity, state, distance, and worked-before badges
- FT8: Segmented decode sections (Directed at You, Calling CQ, All Activity)
- FT8: Collapsed debug panel with expandable status pill
- FT8: Redesigned Active QSO card with step indicator
- FT8: POTA activation counter in control bar
- FT8: Compact mode toggle for decode list
- FT8: Landscape two-column layout
- FT8: Session summary toast on stop
- FT8: Haptic feedback for new decodes, QSO completion, and POTA milestones
- Core: Distance and bearing calculation between Maidenhead grid squares
```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: update changelog with FT8 interface redesign"
```

---

## Dependency Graph

```
Task 1 (Distance/Bearing) ──┐
                             ├── Task 3 (Enricher) ── Task 4 (Wire into Manager)
Task 2 (EnrichedDecode)  ───┘            │
                                         │
Task 5 (Status Pill) ───────────────────┐│
Task 6 (Badges) ────── Task 7 (Row) ───┤│
                                        ├── Task 11 (Session View) ── Task 15 (Landscape)
Task 8 (Decode List) ──────────────────┤│
Task 9 (QSO Card) ────────────────────┤│
Task 10 (Control Bar) ─────────────────┘│
                                         │
Task 12 (Haptics) ──────────────────────┘
Task 13 (Summary Toast) ── after Task 11
Task 14 (Compact Mode) ── after Task 8
Task 16 (FILE_INDEX) ── after all files created
Task 17 (CHANGELOG) ── last
```

**Critical path:** Tasks 1 → 2 → 3 → 4 → 11 (enrichment pipeline must exist before views can consume it)

**Parallelizable:** Tasks 5, 6, 7, 8, 9, 10 can all be built in parallel once Task 2 exists (they only need the `FT8EnrichedDecode` type). Task 11 wires them all together.
