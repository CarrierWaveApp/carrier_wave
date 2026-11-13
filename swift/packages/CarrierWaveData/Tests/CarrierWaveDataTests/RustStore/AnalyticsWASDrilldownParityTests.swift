import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsWASDrilldownParityTests

/// Cross-impl parity for the WAS drilldown aggregate (`StatsComputationActor.wasData`):
/// seed a cw-store from plain objects, assert `RustAnalyticsReadSource` matches the
/// `AnalyticsAggregator` oracle. Empty query → both compute over all visible QSOs.
@MainActor
final class AnalyticsWASDrilldownParityTests: XCTestCase {
    // MARK: Internal

    func testWASDrilldownParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-was-drilldown")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []

        func add(_ id: String, mode: String, state: String?, park: String?, ts: TimeInterval) throws {
            let qso = makeQSO(id, band: "20m", mode: mode, timestamp: ts)
            qso.state = state
            qso.parkReference = park
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        try add("K1AA", mode: "FT8", state: "VA", park: nil, ts: 1_700_000_000) // QTH, Digital
        try add("K2BB", mode: "CW", state: "va", park: "US-0001", ts: 1_700_000_100) // park, CW
        try add("K3CC", mode: "FT8", state: "tx // Texas", park: nil, ts: 1_700_000_200) // QTH
        try add("K4DD", mode: "FT8", state: "VA", park: nil, ts: 1_700_000_300) // QTH, same state
        // Excluded: invalid state, nil state, metadata, hidden.
        try add("K5EE", mode: "FT8", state: "ZZ", park: nil, ts: 1_700_000_400)
        try add("K6FF", mode: "FT8", state: nil, park: nil, ts: 1_700_000_500)
        try add("K7GG", mode: "WEATHER", state: "CA", park: nil, ts: 1_700_000_600)
        let hidden = makeQSO("K8HH", band: "20m", mode: "FT8", timestamp: 1_700_000_700)
        hidden.state = "NY"
        hidden.isHidden = true
        qsos.append(hidden)
        try store.upsertQso(qso: SwiftDataStoreImporter.project(hidden))

        let expected = AnalyticsAggregator.wasDrilldown(over: qsos)
        let actual = try await rust.wasDrilldown(query: "")
        XCTAssertEqual(actual, expected)

        func row(_ source: String, _ mode: String?, _ state: String) -> WASDrilldownRow? {
            actual.first { $0.source == source && $0.mode == mode && $0.state == state }
        }
        // all/any/VA: K1AA + K4DD (QTH FT8) + K2BB (park CW) = 3.
        XCTAssertEqual(row("all", nil, "VA")?.count, 3)
        XCTAssertEqual(row("all", nil, "VA")?.callsigns, ["K1AA", "K2BB", "K4DD"])
        XCTAssertEqual(row("all", "FT8", "VA")?.count, 2)
        XCTAssertEqual(row("all", "CW", "VA")?.count, 1)
        // qth/any/VA: only the two QTH FT8 QSOs (the CW one was at a park).
        XCTAssertEqual(row("qth", nil, "VA")?.count, 2)
        XCTAssertEqual(row("qth", nil, "VA")?.callsigns, ["K1AA", "K4DD"])
        XCTAssertNil(row("qth", "CW", "VA"))
        // No leakage from invalid / nil / metadata / hidden rows.
        XCTAssertNil(row("all", nil, "CA"))
        XCTAssertNil(row("all", nil, "ZZ"))
        XCTAssertNil(row("all", nil, "NY"))
    }

    // MARK: Private

    private func makeQSO(_ callsign: String, band: String, mode: String, timestamp: TimeInterval) -> QSO {
        QSO(
            callsign: callsign,
            band: band,
            mode: mode,
            timestamp: Date(timeIntervalSince1970: timestamp),
            myCallsign: "W6JY",
            importSource: .logger
        )
    }
}
