import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragRecordsParityTests

/// Cross-impl parity for the volume / records / "fun" brag-sheet stats: seed a cw-store from
/// plain objects, assert `RustAnalyticsReadSource.bragRecords` matches the `AnalyticsAggregator`
/// oracle. All fields are integer/label-exact except `totalDistanceKm` (summed haversine —
/// compared with a tolerance for Rust/Swift trig ULPs).
@MainActor
final class AnalyticsBragRecordsParityTests: XCTestCase {
    // MARK: Internal

    func testBragRecordsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-records")
        let rust = RustAnalyticsReadSource(store: store)
        // 2026-06-19 = Friday: 3 QSOs in one session (W1AW twice). 06-20 = Saturday: 1 QSO.
        let session = UUID()
        let qsos = [
            qso(Spec(call: "W1AW", band: "20m", mode: "FT8", session: session, dxcc: 291, at: ts(19, 8))),
            qso(Spec(call: "K2XX", band: "20m", mode: "CW", session: session, dxcc: 1, at: ts(19, 9))),
            qso(Spec(call: "W1AW", band: "40m", mode: "CW", session: session, dxcc: 291, at: ts(19, 23))),
            qso(Spec(call: "N3ZZ", band: "20m", mode: "SSB", session: nil, dxcc: 223, at: ts(20, 1))),
        ]
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragRecords(over: qsos)
        let actual = try await rust.bragRecords(query: "")

        XCTAssertEqual(actual.mostQSOsDay, expected.mostQSOsDay)
        XCTAssertEqual(actual.mostQSOsSession, expected.mostQSOsSession)
        XCTAssertEqual(actual.mostCountriesDay, expected.mostCountriesDay)
        XCTAssertEqual(actual.mostBandsDay, expected.mostBandsDay)
        XCTAssertEqual(actual.mostActiveWeekday, expected.mostActiveWeekday)
        XCTAssertEqual(actual.busiestBand, expected.busiestBand)
        XCTAssertEqual(actual.busiestMode, expected.busiestMode)
        XCTAssertEqual(actual.repeatCustomer, expected.repeatCustomer)
        XCTAssertEqual(actual.earliestQSO, expected.earliestQSO)
        XCTAssertEqual(actual.latestQSO, expected.latestQSO)
        XCTAssertEqual(actual.activeModes, expected.activeModes)
        assertDistance(actual.totalDistanceKm, expected.totalDistanceKm)

        // Spot-checks against the seeded data.
        XCTAssertEqual(actual.mostQSOsDay, 3)
        XCTAssertEqual(actual.mostQSOsSession, 3)
        XCTAssertEqual(actual.mostActiveWeekday, ItemTallyRow(name: "Fri", count: 3))
        XCTAssertEqual(actual.busiestBand, ItemTallyRow(name: "20m", count: 3))
        XCTAssertEqual(actual.repeatCustomer, ItemTallyRow(name: "W1AW", count: 2))
        XCTAssertEqual(actual.earliestQSO, Int(ts(20, 1).timeIntervalSince1970)) // 01:00 closest to midnight
        XCTAssertEqual(actual.latestQSO, Int(ts(19, 23).timeIntervalSince1970)) // 23:00
    }

    func testBragRecordsEmpty() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-records-empty")
        let rust = RustAnalyticsReadSource(store: store)
        let actual = try await rust.bragRecords(query: "")
        XCTAssertEqual(actual.mostQSOsDay, 0)
        XCTAssertNil(actual.busiestBand)
        XCTAssertNil(actual.repeatCustomer)
        XCTAssertNil(actual.earliestQSO)
        XCTAssertNil(actual.totalDistanceKm)
        XCTAssertEqual(actual.activeModes, 0)
    }

    // MARK: Private

    private struct Spec {
        let call: String
        let band: String
        let mode: String
        let session: UUID?
        let dxcc: Int
        let at: Date
    }

    private func ts(_ dayOfMonth: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2_026, month: 6, day: dayOfMonth, hour: hour))!
    }

    private func qso(_ spec: Spec) -> QSO {
        let entry = QSO(
            callsign: spec.call,
            band: spec.band,
            mode: spec.mode,
            timestamp: spec.at,
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.loggingSessionId = spec.session
        entry.dxcc = spec.dxcc
        entry.myGrid = "FN31"
        entry.theirGrid = "EM12"
        return entry
    }

    private func upsert(_ qsos: [QSO], into store: FieldStore) throws {
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
    }

    private func assertDistance(_ lhs: Double?, _ rhs: Double?, file: StaticString = #filePath, line: UInt = #line) {
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
