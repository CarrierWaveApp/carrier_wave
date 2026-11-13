import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragStreaksParityTests

/// Cross-impl parity for the streak-shaped brag-sheet stats
/// (`BragSheetComputationActor+Records`): seed a cw-store from plain objects, assert
/// `RustAnalyticsReadSource.bragStreaks` matches the `AnalyticsAggregator` oracle. Streaks are
/// integer day-counts (no float tolerance). Day-bucketing is UTC on both sides.
@MainActor
final class AnalyticsBragStreaksParityTests: XCTestCase {
    // MARK: Internal

    func testBragStreaksOnAirAndModesParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-streaks")
        let rust = RustAnalyticsReadSource(store: store)
        // CW on 06-20, 06-21; FT8 (Digital) on 06-10, 06-19, 06-21.
        let qsos = [
            qso("C1", mode: "CW", park: nil, on: day(2_026, 6, 20)),
            qso("C2", mode: "CW", park: nil, on: day(2_026, 6, 21)),
            qso("F1", mode: "FT8", park: nil, on: day(2_026, 6, 19)),
            qso("F2", mode: "FT8", park: nil, on: day(2_026, 6, 21)),
            qso("F3", mode: "FT8", park: nil, on: day(2_026, 6, 10)),
        ]
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragStreaks(over: qsos, today: day(2_026, 6, 21))
        let actual = try await rust.bragStreaks(query: "", today: "2026-06-21")
        XCTAssertEqual(actual, expected)

        XCTAssertEqual(actual.onAir, StreakValueRow(current: 3, longest: 3)) // 06-19/20/21 run
        XCTAssertNil(actual.activation)
        XCTAssertEqual(actual.modes, [
            ModeStreakRow(mode: "CW", current: 2, longest: 2),
            ModeStreakRow(mode: "Digital", current: 1, longest: 1),
        ])
    }

    func testBragStreaksActivationParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-streaks-act")
        let rust = RustAnalyticsReadSource(store: store)
        // 06-21: 10 unique park QSOs (qualifies). 06-20: only 3 (does not).
        var qsos = (0 ..< 10).map { qso("CALL\($0)", mode: "FT8", park: "US-0001", on: day(2_026, 6, 21)) }
        qsos += (0 ..< 3).map { qso("DX\($0)", mode: "FT8", park: "US-0001", on: day(2_026, 6, 20)) }
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragStreaks(over: qsos, today: day(2_026, 6, 21))
        let actual = try await rust.bragStreaks(query: "", today: "2026-06-21")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.activation, StreakValueRow(current: 1, longest: 1)) // only 06-21
    }

    func testBragStreaksEmpty() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-streaks-empty")
        let rust = RustAnalyticsReadSource(store: store)
        let actual = try await rust.bragStreaks(query: "", today: "2026-06-21")
        XCTAssertEqual(actual.onAir, StreakValueRow(current: 0, longest: 0))
        XCTAssertNil(actual.activation)
        XCTAssertTrue(actual.modes.isEmpty)
    }

    // MARK: Private

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
    }

    private func qso(_ callsign: String, mode: String, park: String?, on timestamp: Date) -> QSO {
        let entry = QSO(
            callsign: callsign,
            band: "20m",
            mode: mode,
            timestamp: timestamp,
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.parkReference = park
        return entry
    }

    private func upsert(_ qsos: [QSO], into store: FieldStore) throws {
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
    }
}
