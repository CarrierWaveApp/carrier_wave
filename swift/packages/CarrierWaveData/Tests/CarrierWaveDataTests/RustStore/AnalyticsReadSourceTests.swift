import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsReadSourceTests

/// Cross-impl parity for the analytics surface: build identical QSOs, seed a
/// cw-store from them, then assert `RustAnalyticsReadSource` (SQL GROUP BY) matches
/// the `AnalyticsAggregator` pure-Swift oracle.
/// Runs in the package loop — no device, and no `ModelContainer` (the heavy QSO
/// `@Model` can crash materializing via `context.fetch` in-memory). Empty query →
/// both backends compute over all visible QSOs.
@MainActor
final class AnalyticsReadSourceTests: XCTestCase {
    // MARK: Internal

    func testDistinctCountsParity() async throws {
        let (qsos, store) = try seed()
        let rust = RustAnalyticsReadSource(store: store)

        let expected = AnalyticsAggregator.distinctCounts(over: qsos)
        let actual = try await rust.distinctCounts(query: "")

        XCTAssertEqual(actual, expected)
        // a, b, c are visible; the hidden + WEATHER rows are excluded.
        XCTAssertEqual(actual.qsos, 3)
        XCTAssertEqual(actual.bands, 2) // 20m, 40m
        XCTAssertEqual(actual.entities, 2) // 291, 1
        XCTAssertEqual(actual.parks, 1) // US-0001
        XCTAssertEqual(actual.confirmed, 1) // a
        XCTAssertEqual(actual.qrzConfirmed, 1) // a
        XCTAssertEqual(actual.lotwConfirmed, 0)
        XCTAssertEqual(actual.withGrid, 3) // a, b, c
        XCTAssertEqual(actual.withPark, 1) // b
        XCTAssertEqual(actual.withDXCC, 3) // a, b → 291; c → 1
        XCTAssertEqual(actual.uniqueCallsigns, 2) // W1AW, K2XX
    }

    func testCountByParityForLabelMatchedDimensions() async throws {
        let (qsos, store) = try seed()
        let rust = RustAnalyticsReadSource(store: store)

        for dimension in [AnalyticsDimension.band, .modeFamily, .month] {
            let expected = AnalyticsAggregator.countBy(over: qsos, dimension: dimension)
            let actual = try await rust.countBy(query: "", dimension: dimension)
            XCTAssertEqual(actual, expected, "parity mismatch for \(dimension)")
        }
    }

    func testCountByDxccParityAndCountryLabel() async throws {
        let (qsos, store) = try seed()
        let rust = RustAnalyticsReadSource(store: store)

        let expected = AnalyticsAggregator.countBy(over: qsos, dimension: .dxcc)
        let actual = try await rust.countBy(query: "", dimension: .dxcc)

        // key / count / distinctCalls must match; the country label is cw-domain's.
        XCTAssertEqual(actual.map(\.key), expected.map(\.key))
        XCTAssertEqual(actual.map(\.count), expected.map(\.count))
        XCTAssertEqual(actual.map(\.distinctCalls), expected.map(\.distinctCalls))
        XCTAssertEqual(actual.first { $0.key == "291" }?.label, "United States")
        XCTAssertEqual(actual.first { $0.key == "1" }?.label, "Canada")
    }

    func testActivationRollupParity() async throws {
        let (qsos, store) = try seed()
        let rust = RustAnalyticsReadSource(store: store)

        // b is the only parked QSO (US-0001) in the shared fixture; add a second op /
        // a dup to exercise dedup + grouping.
        let dup = makeQSO("K2XX", band: "40m", mode: "CW", timestamp: 1_700_100_500)
        dup.parkReference = "us-0001" // lowercase → same activation after UPPER()
        try store.upsertQso(qso: SwiftDataStoreImporter.project(dup))
        let all = qsos + [dup]

        let expected = AnalyticsAggregator.activationRollup(over: all, minQSOs: 1)
        let actual = try await rust.activationRollup(query: "", minQSOs: 1)
        XCTAssertEqual(actual, expected)
        // One activation (park US-0001, op W6JY, one UTC day); K2XX/40m/CW deduped to 1.
        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual.first?.park, "US-0001")
        XCTAssertEqual(actual.first?.totalQSOs, 2)
        XCTAssertEqual(actual.first?.uniqueQSOs, 1)
        XCTAssertEqual(actual.first?.successful, true)
    }

    func testGridTilesParity() async throws {
        let (qsos, store) = try seed()
        let rust = RustAnalyticsReadSource(store: store)

        for precision in [4, 2] {
            let expected = AnalyticsAggregator.gridTiles(over: qsos, precision: precision)
            let actual = try await rust.gridTiles(query: "", precision: precision)
            XCTAssertEqual(actual, expected, "grid tile parity mismatch at precision \(precision)")
        }
        // a + c are EM12, b is DM79 → two 4-char tiles, EM12 first (count 2).
        let tiles = try await rust.gridTiles(query: "", precision: 4)
        XCTAssertEqual(tiles.first?.tile, "EM12")
        XCTAssertEqual(tiles.first?.count, 2)
        XCTAssertEqual(tiles.first?.confirmed, 1) // a
        // EM12 = a (W1AW/20m/FT8) + c (W1AW/20m/SSB): distinct, sorted detail.
        XCTAssertEqual(tiles.first?.callsigns, ["W1AW"])
        XCTAssertEqual(tiles.first?.bands, ["20m"])
        XCTAssertEqual(tiles.first?.modes, ["FT8", "SSB"])
    }

    func testDxccWorkedParityAndLocation() async throws {
        let (qsos, store) = try seed()
        let rust = RustAnalyticsReadSource(store: store)

        let expected = AnalyticsAggregator.dxccWorked(over: qsos)
        let actual = try await rust.dxccWorked(query: "")

        // id + count + bands + ordering must match; name/lat/lon are cw-domain's.
        XCTAssertEqual(actual.map(\.dxccID), expected.map(\.dxccID))
        XCTAssertEqual(actual.map(\.count), expected.map(\.count))
        XCTAssertEqual(actual.map(\.bands), expected.map(\.bands))
        // 291 (US) worked twice (a, b) → first; Canada (1) once.
        XCTAssertEqual(actual.first?.dxccID, 291)
        XCTAssertEqual(actual.first?.count, 2)
        XCTAssertEqual(actual.first?.bands, ["20m", "40m"]) // a@20m + b@40m
        XCTAssertEqual(actual.first { $0.dxccID == 1 }?.bands, ["20m"]) // c@20m
        XCTAssertEqual(actual.first?.name, "United States")
        XCTAssertEqual(actual.first { $0.dxccID == 1 }?.name, "Canada")
    }

    func testWasSummaryParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-was")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []

        func add(_ qso: QSO) throws {
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        let va1 = makeQSO("W1AW", band: "20m", mode: "FT8", timestamp: 1_700_000_000)
        va1.state = "VA"
        try add(va1)
        let va2 = makeQSO("K2XX", band: "40m", mode: "CW", timestamp: 1_700_100_000)
        va2.state = "va" // normalizes to VA
        try add(va2)
        let txQSO = makeQSO("N5XX", band: "20m", mode: "SSB", timestamp: 1_700_200_000)
        txQSO.state = "tx // Texas" // LoFi comment suffix
        try add(txQSO)
        let invalid = makeQSO("DX1", band: "20m", mode: "FT8", timestamp: 1_700_300_000)
        invalid.state = "ZZ" // not a real state
        try add(invalid)

        let expected = AnalyticsAggregator.wasSummary(over: qsos)
        let actual = try await rust.wasSummary(query: "")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.allStates, ["TX", "VA"])
        XCTAssertEqual(actual.perMode.first { $0.modeFamily == "Phone" }?.states, ["TX"])
        XCTAssertEqual(actual.perMode.first { $0.modeFamily == "CW" }?.states, ["VA"])
        XCTAssertEqual(actual.perMode.first { $0.modeFamily == "Digital" }?.states, ["VA"])
    }

    func testServicePresenceCountsParity() async throws {
        let (store, inputs) = try seedPresence()
        let rust = RustAnalyticsReadSource(store: store)
        let configured = ["qrz"]

        let expected = AnalyticsAggregator.servicePresenceCounts(
            over: inputs, primaryCallsign: "W6JY", configuredServices: Set(configured)
        )
        let actual = try await rust.servicePresenceCounts(
            query: "", primaryCallsign: "W6JY", configuredServices: configured
        )
        XCTAssertEqual(actual, expected)
        // pota only on hidden QSO → excluded; lotw < qrz.
        XCTAssertEqual(actual.map(\.service), ["lotw", "qrz"])
        XCTAssertEqual(actual.first { $0.service == "qrz" }?.uploaded, 1) // q1 (dup collapses)
        XCTAssertEqual(actual.first { $0.service == "qrz" }?.pending, 1) // q2 filtered by primary
        XCTAssertEqual(actual.first { $0.service == "lotw" }?.pending, 0) // not configured

        // No primary filter → both q1 and q2 pending for qrz.
        let noPrimary = try await rust.servicePresenceCounts(
            query: "", primaryCallsign: nil, configuredServices: configured
        )
        XCTAssertEqual(noPrimary.first { $0.service == "qrz" }?.pending, 2)
    }

    // MARK: Private

    /// Seed three QSOs (q1 W6JY, q2 K9ZZ, qh W6JY+hidden) and six presence rows into a
    /// cw-store, returning the store and the matching `PresenceInput` oracle list.
    private func seedPresence() throws -> (FieldStore, [PresenceInput]) {
        let store = try FieldStore.openInMemory(key: "analytics-presence")
        let q1 = makeQSO("W1AW", band: "20m", mode: "FT8", timestamp: 1_700_000_000)
        let q2 = makeQSO("K2XX", band: "40m", mode: "CW", timestamp: 1_700_100_000)
        q2.myCallsign = "K9ZZ"
        let qh = makeQSO("HID", band: "20m", mode: "FT8", timestamp: 1_700_200_000)
        qh.isHidden = true
        for qso in [q1, q2, qh] {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        // qrz: present q1 (x2 dup) + needs_upload q1/q2; lotw: present q1;
        // pota: needs_upload on hidden qh (excluded entirely).
        var inputs: [PresenceInput] = []
        func addPresence(_ id: String, _ service: String, _ qso: QSO, present: Bool, needs: Bool) throws {
            try store.upsertServicePresence(item: FfiServicePresence(
                id: id,
                serviceTypeRawValue: service,
                isPresent: present,
                needsUpload: needs,
                uploadRejected: false,
                rejectedAtBuild: nil,
                isSubmitted: false,
                lastConfirmedAt: nil,
                parkReference: nil,
                cloudDirtyFlag: false,
                qsoId: SwiftDataStoreImporter.uuid(qso.id)
            ))
            inputs.append(PresenceInput(
                service: service,
                isPresent: present,
                needsUpload: needs,
                qsoID: SwiftDataStoreImporter.uuid(qso.id),
                qsoMyCallsign: qso.myCallsign,
                qsoIsHidden: qso.isHidden
            ))
        }
        try addPresence("p1", "qrz", q1, present: true, needs: false)
        try addPresence("p2", "qrz", q1, present: true, needs: false)
        try addPresence("p3", "qrz", q2, present: false, needs: true)
        try addPresence("p4", "qrz", q1, present: false, needs: true)
        try addPresence("p5", "lotw", q1, present: true, needs: false)
        try addPresence("p6", "pota", qh, present: false, needs: true)
        return (store, inputs)
    }

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

    /// Build the QSO fixtures and seed a cw-store from them (via the importer). The
    /// QSOs are plain (un-inserted) `@Model` objects — read directly, never fetched.
    private func seed() throws -> ([QSO], FieldStore) {
        let store = try FieldStore.openInMemory(key: "analytics-parity")
        var qsos: [QSO] = []

        func add(_ qso: QSO) throws {
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        let qsoA = makeQSO("W1AW", band: "20m", mode: "FT8", timestamp: 1_700_000_000)
        qsoA.theirGrid = "EM12"
        qsoA.dxcc = 291
        qsoA.qrzConfirmed = true
        try add(qsoA)

        let qsoB = makeQSO("K2XX", band: "40m", mode: "CW", timestamp: 1_700_100_000)
        qsoB.theirGrid = "DM79"
        qsoB.dxcc = 291
        qsoB.parkReference = "US-0001"
        try add(qsoB)

        let qsoC = makeQSO("W1AW", band: "20m", mode: "SSB", timestamp: 1_705_000_000)
        qsoC.theirGrid = "EM12"
        qsoC.dxcc = 1
        try add(qsoC)

        let hidden = makeQSO("HIDDEN", band: "20m", mode: "FT8", timestamp: 1_700_000_000)
        hidden.isHidden = true
        try add(hidden)

        let metadata = makeQSO("META", band: "20m", mode: "WEATHER", timestamp: 1_700_000_000)
        try add(metadata)

        return (qsos, store)
    }
}
