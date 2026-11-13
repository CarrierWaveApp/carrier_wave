import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragSignalParityTests

/// Cross-impl parity for the brag-sheet signal-quality average (`computeAverageRST`) and the
/// club-membership worked set (`computeClubMembersWorked` / `computeClubsRepresented` source):
/// seed a cw-store from plain objects, assert `RustAnalyticsReadSource` matches the
/// `AnalyticsAggregator` oracle. averageRST is compared with a tolerance (`AVG` floating math);
/// the worked-member list is compared exactly.
@MainActor
final class AnalyticsBragSignalParityTests: XCTestCase {
    // MARK: Internal

    func testAverageRSTParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-signal-rst")
        let rust = RustAnalyticsReadSource(store: store)
        // "599"→9, "59"→9, "579"→7, "5"→skipped (< 2 chars), "5N"→skipped (one digit), nil→skipped.
        let qsos = [
            qso(call: "W1AW", rst: "599"),
            qso(call: "K2XX", rst: "59"),
            qso(call: "N3ZZ", rst: "579"),
            qso(call: "AA1A", rst: "5"),
            qso(call: "BB2B", rst: "5N"),
            qso(call: "CC3C", rst: nil),
        ]
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragAverageRST(over: qsos)
        let actual = try await rust.bragAverageRST(query: "")
        assertAverage(actual, expected)

        // Spot-check: (9 + 9 + 7) / 3 = 8.333…
        let value = try XCTUnwrap(actual)
        XCTAssertEqual(value, 25.0 / 3.0, accuracy: 1e-6)
    }

    func testAverageRSTEmpty() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-signal-rst-empty")
        let rust = RustAnalyticsReadSource(store: store)
        // Seed only non-qualifying QSOs; both paths return nil.
        try upsert([qso(call: "W1AW", rst: "5"), qso(call: "K2XX", rst: nil)], into: store)

        let expected = AnalyticsAggregator.bragAverageRST(over: [
            qso(call: "W1AW", rst: "5"),
            qso(call: "K2XX", rst: nil),
        ])
        let actual = try await rust.bragAverageRST(query: "")
        assertAverage(actual, expected)
        XCTAssertNil(actual)
    }

    func testWorkedMemberCallsignsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-signal-club")
        let rust = RustAnalyticsReadSource(store: store)
        // W1AW worked twice (proves DISTINCT); casing varied (proves uppercasing). N3ZZ is worked
        // but not a member → excluded. DX0NE is a member but not worked → excluded.
        let qsos = [
            qso(call: "w1aw", rst: "599"),
            qso(call: "W1AW", rst: "59"),
            qso(call: "K2XX", rst: "599"),
            qso(call: "N3ZZ", rst: "599"),
        ]
        try upsert(qsos, into: store)

        let members = ["w1aw", "k2xx", "DX0NE"]
        let expected = AnalyticsAggregator.workedMemberCallsigns(over: qsos, members: Set(members))
        let actual = try await rust.workedMemberCallsigns(query: "", members: members)
        XCTAssertEqual(actual, expected)
        // Spot-check: distinct, uppercased, sorted ascending.
        XCTAssertEqual(actual, ["K2XX", "W1AW"])

        // Empty members → empty list on both paths.
        let none = try await rust.workedMemberCallsigns(query: "", members: [])
        XCTAssertEqual(none, AnalyticsAggregator.workedMemberCallsigns(over: qsos, members: []))
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: Private

    private func qso(call: String, rst: String?) -> QSO {
        let entry = QSO(
            callsign: call,
            band: "20m",
            mode: "FT8",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.rstReceived = rst
        return entry
    }

    private func upsert(_ qsos: [QSO], into store: FieldStore) throws {
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
    }

    private func assertAverage(_ lhs: Double?, _ rhs: Double?, file: StaticString = #filePath, line: UInt = #line) {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            XCTAssertEqual(lhs, rhs, accuracy: 1e-6, file: file, line: line)
        case (nil, nil):
            break
        default:
            XCTFail("averageRST nil mismatch", file: file, line: line)
        }
    }
}
