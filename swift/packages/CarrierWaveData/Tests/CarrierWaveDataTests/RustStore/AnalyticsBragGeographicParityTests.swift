import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragGeographicParityTests

/// Cross-impl parity for the geographic-reach brag-sheet stats
/// (`BragSheetComputationActor.computeGeoStat`): seed a cw-store from plain objects, assert
/// `RustAnalyticsReadSource.bragGeographic` matches the `AnalyticsAggregator` oracle. All
/// outputs are integer counts (exact). Continents exercise the ported `ContinentMapper`.
@MainActor
final class AnalyticsBragGeographicParityTests: XCTestCase {
    // MARK: Internal

    func testBragGeographicCountsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-geo")
        let rust = RustAnalyticsReadSource(store: store)
        // 291=NA(+VA), 1=NA, 223=EU, 339=AS. 06-21 carries NA+EU+AS; 06-20 only NA.
        let qsos = [
            qso("G1", dxcc: 291, state: "VA", grid: "FN31", on: day(2_026, 6, 21)),
            qso("G2", dxcc: 1, state: nil, grid: "FN20", on: day(2_026, 6, 20)),
            qso("G3", dxcc: 223, state: nil, grid: "IO91", on: day(2_026, 6, 21)),
            qso("G4", dxcc: 339, state: nil, grid: "PM95", on: day(2_026, 6, 21)),
        ]
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragGeographic(over: qsos, allQSOs: qsos)
        let actual = try await rust.bragGeographic(query: "")
        XCTAssertEqual(actual, expected)

        XCTAssertEqual(actual.dxccEntities, 4)
        XCTAssertEqual(actual.statesProvinces, 1)
        XCTAssertEqual(actual.wasStates, 1)
        XCTAssertEqual(actual.gridSquares, 4)
        XCTAssertEqual(actual.continents, 3) // NA, EU, AS
        XCTAssertEqual(actual.mostContinentsDay, 3) // 06-21
        XCTAssertEqual(actual.newDXCCEntities, 4) // empty query → all new
    }

    func testBragNewDXCCParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-geo-new")
        let rust = RustAnalyticsReadSource(store: store)
        // 291 first worked in 2025 (before the period); 1 and 223 first worked in 2026.
        let qsos = [
            qso("P0", dxcc: 291, state: nil, grid: "FN31", on: day(2_025, 12, 1)),
            qso("P1", dxcc: 291, state: nil, grid: "FN31", on: day(2_026, 3, 1)),
            qso("P2", dxcc: 1, state: nil, grid: "FN20", on: day(2_026, 3, 2)),
            qso("P3", dxcc: 223, state: nil, grid: "IO91", on: day(2_026, 4, 1)),
        ]
        try upsert(qsos, into: store)

        let period = qsos.filter { $0.timestamp >= day(2_026, 1, 1) && $0.timestamp < day(2_027, 1, 1) }
        let expected = AnalyticsAggregator.bragGeographic(over: period, allQSOs: qsos)
        let actual = try await rust.bragGeographic(query: "date:2026")
        XCTAssertEqual(actual, expected)

        XCTAssertEqual(actual.dxccEntities, 3) // 291, 1, 223 in 2026
        XCTAssertEqual(actual.newDXCCEntities, 2) // 291 predates the period
    }

    // MARK: Private

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
    }

    private func qso(_ callsign: String, dxcc: Int, state: String?, grid: String, on timestamp: Date) -> QSO {
        let entry = QSO(
            callsign: callsign,
            band: "20m",
            mode: "FT8",
            timestamp: timestamp,
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.dxcc = dxcc
        entry.state = state
        entry.theirGrid = grid
        return entry
    }

    private func upsert(_ qsos: [QSO], into store: FieldStore) throws {
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
    }
}
