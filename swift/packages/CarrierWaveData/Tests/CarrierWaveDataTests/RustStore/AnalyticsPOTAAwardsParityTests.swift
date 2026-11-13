import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsPOTAAwardsParityTests

/// Cross-impl parity for the POTA activator awards + America 250 WAS aggregates.
/// Same harness as the other analytics parity tests: seed a cw-store from plain
/// objects, assert `RustAnalyticsReadSource` matches the `AnalyticsAggregator` oracle.
/// `statesActivated` uses the `pota_park` cache path on both sides (US parks are seeded
/// with a `location_desc`); the grid fallback is covered by cw-domain's `us_grid_state`
/// unit tests.
@MainActor
final class AnalyticsPOTAAwardsParityTests: XCTestCase {
    // MARK: Internal

    func testPOTAAwardsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-pota-awards")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []

        func add(_ qso: QSO) throws {
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        /// A valid activation: `count` distinct callsigns at one park/op/day.
        func activation(_ tag: String, park: String, day: TimeInterval, count: Int, band: String) throws {
            for idx in 0 ..< count {
                let qso = makeQSO("W\(tag)\(idx)", band: band, mode: "CW", timestamp: day + TimeInterval(idx))
                qso.parkReference = park
                qso.dxcc = 291
                try add(qso)
            }
        }

        let day1: TimeInterval = 1_700_000_000
        let day2: TimeInterval = 1_700_100_000 // different UTC day
        try activation("a", park: "US-0001", day: day1, count: 10, band: "20m") // valid, WY
        try activation("b", park: "US-0002", day: day1, count: 10, band: "40m") // valid, CA, rover day1=2
        try activation("c", park: "US-0003, US-0004", day: day2, count: 10, band: "20m") // two-fer
        try activation("d", park: "US-0001", day: day2, count: 9, band: "20m") // below threshold

        // Metadata at a park: counted in raw totals, excluded from activations.
        let meta = makeQSO("META", band: "20m", mode: "WEATHER", timestamp: day1)
        meta.parkReference = "US-0001"
        try add(meta)
        // Park-to-park hunt.
        let p2p = makeQSO("P2P", band: "20m", mode: "CW", timestamp: day1)
        p2p.parkReference = "US-0001"
        p2p.theirParkReference = "US-9999"
        try add(p2p)

        // pota_park reference rows (US parks → location_desc states).
        let parks = [
            ffiPark("US-0001", "US-WY"),
            ffiPark("US-0002", "US-CA"),
            ffiPark("US-0003", "US-TX"),
            ffiPark("US-0004", "US-NY"),
        ]
        try store.upsertPotaParks(parks: parks)
        let locationDescs = Dictionary(uniqueKeysWithValues: parks.map { ($0.reference, $0.locationDesc) })

        let expected = AnalyticsAggregator.potaAwards(over: qsos, parkLocationDescs: locationDescs)
        let actual = try await rust.potaAwards(query: "")
        XCTAssertEqual(actual, expected)

        // Spot-checks on the oracle/rust agreement.
        XCTAssertEqual(actual.uniqueParksCount, 4) // 0001, 0002, 0003, 0004
        XCTAssertEqual(actual.validActivationGroups, 3) // a, b, c (not d — only 9 unique)
        XCTAssertEqual(actual.statesActivated, ["CA", "NY", "TX", "WY"])
        XCTAssertEqual(actual.roverMaxParks, 2) // day1: US-0001 + US-0002
        XCTAssertEqual(actual.dxEntitiesCount, 1) // all 291
        XCTAssertEqual(actual.parkToParkCount, 1) // p2p
        XCTAssertEqual(actual.metadataExcluded, 1) // meta
    }

    func testWAS250Parity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-was250")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []
        func add(_ id: String, mode: String, state: String?, ts: TimeInterval) throws {
            let qso = makeQSO(id, band: "20m", mode: mode, timestamp: ts)
            qso.state = state
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        let in2026: TimeInterval = 1_767_300_000
        try add("a", mode: "FT8", state: "VA", ts: in2026) // Digital, valid
        try add("b", mode: "CW", state: "va", ts: in2026 + 1) // CW, normalizes to VA
        try add("c", mode: "SSB", state: "tx // TX", ts: in2026 + 2) // Phone, valid
        try add("d", mode: "FT8", state: "ZZ", ts: in2026 + 3) // invalid state
        try add("e", mode: "WEATHER", state: "CA", ts: in2026 + 4) // metadata
        try add("f", mode: "FT8", state: "NY", ts: 1_700_000_000) // 2023, out of window

        let expected = AnalyticsAggregator.was250(over: qsos)
        let actual = try await rust.was250(query: "")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.statesWorked, ["TX", "VA"])
        XCTAssertEqual(actual.cwStates, ["VA"])
        XCTAssertEqual(actual.digitalStates, ["VA"])
        XCTAssertEqual(actual.phoneStates, ["TX"])
        XCTAssertEqual(actual.totalQSOs, 5) // a–e (not f, out of window)
        XCTAssertEqual(actual.metadataExcluded, 1) // e
        XCTAssertEqual(actual.withValidState, 3) // VA, VA, TX
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

    private func ffiPark(_ reference: String, _ locationDesc: String) -> FfiPotaPark {
        FfiPotaPark(
            reference: reference,
            name: "\(reference) Park",
            locationDesc: locationDesc,
            latitude: nil,
            longitude: nil,
            grid: nil,
            entityId: 291,
            isActive: true
        )
    }
}
