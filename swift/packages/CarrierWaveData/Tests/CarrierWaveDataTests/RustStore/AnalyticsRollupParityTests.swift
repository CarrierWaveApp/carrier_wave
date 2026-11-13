import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsRollupParityTests

/// Cross-impl parity for the park / state / equipment / brag analytics surfaces (split
/// from `AnalyticsReadSourceTests` for type-body length). Same harness: seed a cw-store
/// from plain objects, assert `RustAnalyticsReadSource` matches the `AnalyticsAggregator`
/// oracle. Empty query → both compute over all visible QSOs.
@MainActor
final class AnalyticsRollupParityTests: XCTestCase {
    // MARK: Internal

    func testParkRollupParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-parks")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []
        func add(_ qso: QSO) throws {
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }

        let day1: TimeInterval = 1_700_000_000
        let day2: TimeInterval = 1_700_100_000 // different UTC day
        func parked(_ id: String, ref: String, at timestamp: TimeInterval) throws {
            let qso = makeQSO(id, band: "20m", mode: "FT8", timestamp: timestamp)
            qso.parkReference = ref
            try add(qso)
        }
        func hunted(_ id: String, ref: String, at timestamp: TimeInterval) throws {
            let qso = makeQSO(id, band: "20m", mode: "FT8", timestamp: timestamp)
            qso.theirParkReference = ref
            try add(qso)
        }
        try parked("pa1", ref: "K-1", at: day1)
        try parked("pa2", ref: "K-1", at: day1) // same-day dup
        try parked("pa3", ref: "K-1", at: day2)
        try parked("pa4", ref: "K-1, K-2", at: day1) // combined
        try hunted("h1", ref: "K-9", at: day1)
        try hunted("h2", ref: "K-9", at: day1)
        try hunted("h3", ref: "K-1", at: 1_700_200_000) // latest overall

        let expected = AnalyticsAggregator.parkRollup(over: qsos)
        let actual = try await rust.parkRollup(query: "")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.first { $0.park == "K-1" }?.activationDays, 2)
        XCTAssertEqual(actual.first { $0.park == "K-1" }?.huntQSOs, 1)
        XCTAssertEqual(actual.first { $0.park == "K-1" }?.lastWorked, 1_700_200_000)
        XCTAssertEqual(actual.first { $0.park == "K-2" }?.activationDays, 1)
        XCTAssertEqual(actual.first { $0.park == "K-9" }?.huntQSOs, 2)
    }

    func testStateCountsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-states")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []
        func add(_ id: String, state: String?, ts: TimeInterval) throws {
            let qso = makeQSO(id, band: "20m", mode: "FT8", timestamp: ts)
            qso.state = state
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }
        try add("a", state: "VA", ts: 1_700_000_000)
        try add("b", state: "va", ts: 1_700_000_100) // normalizes to VA
        try add("c", state: "tx // Texas", ts: 1_700_000_200) // LoFi suffix
        try add("d", state: "ZZ", ts: 1_700_000_300) // invalid
        try add("e", state: nil, ts: 1_700_000_400)

        let expected = AnalyticsAggregator.stateCounts(over: qsos)
        let actual = try await rust.stateCounts(query: "")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.map(\.state), ["VA", "TX"]) // count desc
        XCTAssertEqual(actual.first?.count, 2)
    }

    func testEquipmentAndComboRollupParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-equipment")
        let rust = RustAnalyticsReadSource(store: store)
        var inputs: [SessionInput] = []
        func addSession(rig: String?, antenna: String?, key: String?, qsoCount: Int, at started: TimeInterval) throws {
            let session = LoggingSession(
                myCallsign: "W6JY",
                startedAt: Date(timeIntervalSince1970: started),
                myRig: rig,
                myAntenna: antenna,
                myKey: key
            )
            session.qsoCount = qsoCount
            try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))
            inputs.append(SessionInput(
                myRig: rig, myAntenna: antenna, myKey: key, myMic: nil,
                qsoCount: qsoCount, startedAt: Int(started)
            ))
        }
        try addSession(rig: "IC-7300", antenna: "EFHW", key: nil, qsoCount: 10, at: 100)
        try addSession(rig: "IC-7300", antenna: "EFHW", key: nil, qsoCount: 5, at: 200)
        try addSession(rig: "KX2", antenna: nil, key: "Begali", qsoCount: 3, at: 300)
        try addSession(rig: "IC-7300", antenna: "Dipole", key: nil, qsoCount: 0, at: 400) // excluded

        let actualEquip = try await rust.sessionEquipmentRollup()
        XCTAssertEqual(actualEquip, AnalyticsAggregator.sessionEquipmentRollup(over: inputs))
        let radio = actualEquip.first { $0.kind == "radio" && $0.name == "IC-7300" }
        XCTAssertEqual(radio?.sessionCount, 2)
        XCTAssertEqual(radio?.totalQSOs, 15)
        XCTAssertFalse(actualEquip.contains { $0.name == "Dipole" })

        let actualCombo = try await rust.sessionComboRollup()
        XCTAssertEqual(actualCombo, AnalyticsAggregator.sessionComboRollup(over: inputs))
        XCTAssertEqual(actualCombo.count, 1)
        XCTAssertEqual(actualCombo.first?.rig, "IC-7300")
        XCTAssertEqual(actualCombo.first?.totalQSOs, 15)
    }

    func testBragPeriodMetricsParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-brag")
        let rust = RustAnalyticsReadSource(store: store)
        var qsos: [QSO] = []
        func add(_ qso: QSO) throws {
            qsos.append(qso)
            try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        }
        let q1 = makeQSO("W1AW", band: "20m", mode: "FT8", timestamp: 1_700_000_000)
        q1.dxcc = 291; q1.power = 5; q1.rstReceived = "599"
        q1.parkReference = "K-1"; q1.theirParkReference = "K-2"
        try add(q1)
        let q2 = makeQSO("K2XX", band: "40m", mode: "CW", timestamp: 1_700_100_000)
        q2.dxcc = 1; q2.power = 0; q2.rstReceived = "59"
        try add(q2)
        let q3 = makeQSO("W1AW", band: "20m", mode: "SSB", timestamp: 1_700_000_500)
        q3.dxcc = 291; q3.theirParkReference = "K-2"
        try add(q3)
        let hidden = makeQSO("HID", band: "20m", mode: "FT8", timestamp: 1_700_000_000)
        hidden.isHidden = true
        try add(hidden)
        try add(makeQSO("META", band: "20m", mode: "WEATHER", timestamp: 1_700_000_000))

        let expected = AnalyticsAggregator.bragPeriodMetrics(over: qsos)
        let actual = try await rust.bragPeriodMetrics(query: "")
        XCTAssertEqual(actual, expected)
        XCTAssertEqual(actual.totalQSOs, 3)
        XCTAssertEqual(actual.cwQSOs, 1)
        XCTAssertEqual(actual.operatingDays, 2)
        XCTAssertEqual(actual.qrpQSOs, 2) // q1 (5) + q2 (0)
        XCTAssertEqual(actual.milliwattQSOs, 1) // q2 (0)
        XCTAssertEqual(actual.parksHunted, 1) // K-2
        XCTAssertEqual(actual.parkToPark, 1) // q1
        XCTAssertEqual(actual.perfectReports, 2) // 599, 59
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
