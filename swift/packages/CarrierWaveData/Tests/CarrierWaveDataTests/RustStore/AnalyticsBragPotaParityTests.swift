import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsBragPotaParityTests

/// Cross-impl parity for the POTA-category brag-sheet stats (`BragSheetComputationActor+POTA`):
/// seed a cw-store from plain objects, assert `RustAnalyticsReadSource.bragPota` matches the
/// `AnalyticsAggregator` oracle. All outputs are integer counts / exact strings.
@MainActor
final class AnalyticsBragPotaParityTests: XCTestCase {
    // MARK: Internal

    func testBragPotaAggregatesParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-pota")
        let rust = RustAnalyticsReadSource(store: store)
        // US-0001 on 06-21: 10 unique QSOs (activates) + 1 P2P. US-0002 on 06-20: 3 (does not).
        // One hunt-only QSO (their park, no own park).
        var qsos: [QSO] = []
        for idx in 0 ..< 10 {
            qsos.append(qso(Spec("CALL\(idx)", park: "US-0001", on: day(2_026, 6, 21))))
        }
        for idx in 0 ..< 3 {
            qsos.append(qso(Spec("DX\(idx)", park: "US-0002", on: day(2_026, 6, 20))))
        }
        qsos.append(qso(Spec("P2PCALL", park: "US-0001", theirPark: "US-9000", on: day(2_026, 6, 21))))
        qsos.append(qso(Spec("HUNTCALL", theirPark: "US-9001", on: day(2_026, 6, 21))))
        try upsert(qsos, into: store)

        let expected = AnalyticsAggregator.bragPota(over: qsos, allQSOs: qsos)
        let actual = try await rust.bragPota(query: "")
        XCTAssertEqual(actual, expected)

        XCTAssertEqual(actual.parksActivated, 1) // US-0001 (11 unique); US-0002 only 3
        XCTAssertEqual(actual.parksHunted, 2) // US-9000, US-9001
        XCTAssertEqual(actual.parkToPark, 1) // only the P2P QSO
        XCTAssertEqual(actual.bestActivation?.park, "US-0001")
        XCTAssertEqual(actual.bestActivation?.day, "2026-06-21")
        XCTAssertEqual(actual.bestActivation?.count, 11)
    }

    func testBragNewParksParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag-pota-new")
        let rust = RustAnalyticsReadSource(store: store)
        // US-0001 first activated in 2025 (before period); US-0002 first worked in 2026.
        // US-9000 first hunted in 2025 (before); US-9001 first hunted in 2026.
        let qsos = [
            qso(Spec("K0", park: "US-0001", on: day(2_025, 12, 1))),
            qso(Spec("K1", park: "US-0001", on: day(2_026, 3, 1))),
            qso(Spec("K2", park: "US-0002", on: day(2_026, 3, 2))),
            qso(Spec("H0", theirPark: "US-9000", on: day(2_025, 11, 1))),
            qso(Spec("H1", theirPark: "US-9000", on: day(2_026, 4, 1))),
            qso(Spec("H2", theirPark: "US-9001", on: day(2_026, 4, 2))),
        ]
        try upsert(qsos, into: store)

        let period = qsos.filter { $0.timestamp >= day(2_026, 1, 1) && $0.timestamp < day(2_027, 1, 1) }
        let expected = AnalyticsAggregator.bragPota(over: period, allQSOs: qsos)
        let actual = try await rust.bragPota(query: "date:2026")
        XCTAssertEqual(actual, expected)

        XCTAssertEqual(actual.newParks, 2) // US-0002 + US-9001 (US-0001 & US-9000 predate the period)
    }

    // MARK: Private

    private struct Spec {
        // MARK: Lifecycle

        init(_ callsign: String, park: String? = nil, theirPark: String? = nil, on timestamp: Date) {
            self.callsign = callsign
            self.park = park
            self.theirPark = theirPark
            self.timestamp = timestamp
        }

        // MARK: Internal

        let callsign: String
        let park: String?
        let theirPark: String?
        let timestamp: Date
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12))!
    }

    private func qso(_ spec: Spec) -> QSO {
        let entry = QSO(
            callsign: spec.callsign,
            band: "20m",
            mode: "FT8",
            timestamp: spec.timestamp,
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.parkReference = spec.park
        entry.theirParkReference = spec.theirPark
        return entry
    }

    private func upsert(_ qsos: [QSO], into store: FieldStore) throws {
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }
    }
}
