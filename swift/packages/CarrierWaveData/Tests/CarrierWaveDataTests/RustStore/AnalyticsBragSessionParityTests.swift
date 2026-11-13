import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragSessionParityTests

/// Cross-impl parity for the session-/sequence-based brag-sheet stats: seed a cw-store from
/// plain objects, assert `RustAnalyticsReadSource.bragSessionStats` matches the
/// `AnalyticsAggregator` oracle. Counts are exact; durations / rate are compared with a
/// tolerance (Rust i64→f64 vs Swift Double arithmetic).
@MainActor
final class AnalyticsBragSessionParityTests: XCTestCase {
    // MARK: Internal

    func testBragSessionStatsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-session")
        let rust = RustAnalyticsReadSource(store: store)
        let session = UUID()
        var qsos: [QSO] = []
        // 10 QSOs 1 min apart at US-0001 in one session, + an 11th at US-0002 (Nfer 2) at +14m.
        for idx in 0 ..< 10 {
            qsos.append(qso(
                "C\(idx)",
                session: session,
                park: "US-0001",
                at: base().addingTimeInterval(Double(idx) * 60)
            ))
        }
        qsos.append(qso("P2", session: session, park: "US-0002", at: base().addingTimeInterval(14 * 60)))
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragSessionStats(over: qsos)
        let actual = try await rust.bragSessionStats(query: "")

        XCTAssertEqual(actual.peak15MinCount, expected.peak15MinCount)
        XCTAssertEqual(actual.largestNfer, expected.largestNfer)
        assertSeconds(actual.operatingSeconds, expected.operatingSeconds)
        assertSeconds(actual.fastestTenSeconds, expected.fastestTenSeconds)
        assertSeconds(actual.fastestActivationSeconds, expected.fastestActivationSeconds)
        assertSeconds(actual.longestSessionSeconds, expected.longestSessionSeconds)
        assertSeconds(actual.bestSessionRate, expected.bestSessionRate)

        // Spot-checks.
        XCTAssertEqual(actual.largestNfer, 2)
        XCTAssertEqual(actual.peak15MinCount, 11)
        assertSeconds(actual.fastestTenSeconds, 540) // 9 minutes
        assertSeconds(actual.longestSessionSeconds, 840) // 14 minutes
    }

    func testBragSessionStatsEmpty() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-session-empty")
        let rust = RustAnalyticsReadSource(store: store)
        let actual = try await rust.bragSessionStats(query: "")
        XCTAssertNil(actual.operatingSeconds)
        XCTAssertNil(actual.fastestTenSeconds)
        XCTAssertNil(actual.bestSessionRate)
        XCTAssertNil(actual.fastestActivationSeconds)
        XCTAssertNil(actual.longestSessionSeconds)
        XCTAssertEqual(actual.peak15MinCount, 0)
        XCTAssertEqual(actual.largestNfer, 0)
    }

    // MARK: Private

    private func base() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2_026, month: 6, day: 19, hour: 12))!
    }

    private func qso(_ call: String, session: UUID, park: String, at timestamp: Date) -> QSO {
        let entry = QSO(
            callsign: call,
            band: "20m",
            mode: "CW",
            timestamp: timestamp,
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.loggingSessionId = session
        entry.parkReference = park
        return entry
    }

    private func upsert(_ qsos: [QSO], into store: FieldStore) throws {
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
    }

    private func assertSeconds(_ lhs: Double?, _ rhs: Double?, file: StaticString = #filePath, line: UInt = #line) {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            XCTAssertEqual(lhs, rhs, accuracy: 1e-6, file: file, line: line)
        case (nil, nil):
            break
        default:
            XCTFail(
                "seconds nil mismatch: \(String(describing: lhs)) vs \(String(describing: rhs))",
                file: file,
                line: line
            )
        }
    }
}
