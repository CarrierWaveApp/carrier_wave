import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragDistanceParityTests

/// Cross-impl parity for the distance-shaped brag-sheet stats
/// (`BragSheetComputationActor+Distance`/`+Records`): seed a cw-store from plain objects,
/// assert `RustAnalyticsReadSource.bragDistanceStats` matches the `AnalyticsAggregator`
/// oracle. Distances are compared with a tolerance (Rust UDF vs Swift `MaidenheadConverter`
/// use independent trig of the same haversine); callsign/band are exact.
@MainActor
final class AnalyticsBragDistanceParityTests: XCTestCase {
    // MARK: Internal

    func testBragDistanceStatsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-distance")
        let rust = RustAnalyticsReadSource(store: store)
        let qsos = try seed(into: store)

        let expected = AnalyticsAggregator.bragDistanceStats(over: qsos)
        let actual = try await rust.bragDistanceStats(query: "")

        assertContact(actual.furthest, expected.furthest)
        assertContact(actual.furthestQRP, expected.furthestQRP)
        assertContact(actual.furthestCW, expected.furthestCW)
        assertContact(actual.furthestCWQRP, expected.furthestCWQRP)
        assertContact(actual.furthestPerfectRST, expected.furthestPerfectRST)
        assertDistance(actual.averageKm, expected.averageKm)

        XCTAssertEqual(actual.furthestPerBand.map(\.band), expected.furthestPerBand.map(\.band))
        XCTAssertEqual(actual.furthestPerBand.map(\.callsign), expected.furthestPerBand.map(\.callsign))
        XCTAssertEqual(actual.lowestPower?.watts, expected.lowestPower?.watts)
        XCTAssertEqual(actual.lowestPower?.callsign, expected.lowestPower?.callsign)
        XCTAssertEqual(actual.bestWattsPerMile?.callsign, expected.bestWattsPerMile?.callsign)

        // Spot-check the selections against the seeded data.
        XCTAssertEqual(actual.furthest?.callsign, "A1") // DM12, farthest
        XCTAssertEqual(actual.furthestQRP?.callsign, "B1") // power 5, EM12
        XCTAssertEqual(actual.furthestPerfectRST?.callsign, "C1") // only 599
        XCTAssertEqual(actual.furthestPerBand.first?.band, "20m") // A1 ahead of 40m C1
        XCTAssertEqual(actual.lowestPower?.watts, 1) // D1
        XCTAssertEqual(actual.bestWattsPerMile?.callsign, "B1")
    }

    func testBragDistanceStatsEmpty() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-distance-empty")
        let rust = RustAnalyticsReadSource(store: store)
        let actual = try await rust.bragDistanceStats(query: "")
        XCTAssertNil(actual.furthest)
        XCTAssertNil(actual.furthestQRP)
        XCTAssertNil(actual.averageKm)
        XCTAssertTrue(actual.furthestPerBand.isEmpty)
        XCTAssertNil(actual.lowestPower)
        XCTAssertNil(actual.bestWattsPerMile)
    }

    // MARK: Private

    private struct Spec {
        let call: String
        let band: String
        let mode: String
        let theirGrid: String
        let power: Int?
        let rst: String?
        let hidden: Bool
    }

    private func seed(into store: FieldStore) throws -> [QSO] {
        let specs = [
            Spec(call: "A1", band: "20m", mode: "FT8", theirGrid: "DM12", power: 100, rst: nil, hidden: false),
            Spec(call: "B1", band: "20m", mode: "CW", theirGrid: "EM12", power: 5, rst: nil, hidden: false),
            Spec(call: "C1", band: "40m", mode: "CW", theirGrid: "FN30", power: 5, rst: "599", hidden: false),
            Spec(call: "D1", band: "20m", mode: "FT8", theirGrid: "FN31", power: 1, rst: nil, hidden: false),
            Spec(call: "HID", band: "20m", mode: "FT8", theirGrid: "DM12", power: 100, rst: nil, hidden: true),
            Spec(call: "MET", band: "20m", mode: "WEATHER", theirGrid: "DM12", power: 100, rst: nil, hidden: false),
        ]
        let qsos = specs.map(qso(from:))
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
        return qsos
    }

    private func qso(from spec: Spec) -> QSO {
        let entry = QSO(
            callsign: spec.call,
            band: spec.band,
            mode: spec.mode,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.myGrid = "FN31"
        entry.theirGrid = spec.theirGrid
        entry.power = spec.power
        entry.rstReceived = spec.rst
        entry.isHidden = spec.hidden
        return entry
    }

    private func assertContact(
        _ lhs: BragContactRow?,
        _ rhs: BragContactRow?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs?.callsign, rhs?.callsign, file: file, line: line)
        XCTAssertEqual(lhs?.band, rhs?.band, file: file, line: line)
        assertDistance(lhs?.distanceKm, rhs?.distanceKm, file: file, line: line)
    }

    private func assertDistance(
        _ lhs: Double?,
        _ rhs: Double?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            XCTAssertEqual(lhs, rhs, accuracy: 1e-6, file: file, line: line)
        case (nil, nil):
            break
        default:
            XCTFail("distance nil mismatch", file: file, line: line)
        }
    }
}
