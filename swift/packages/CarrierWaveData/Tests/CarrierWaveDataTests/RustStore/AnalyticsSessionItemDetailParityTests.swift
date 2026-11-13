import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - AnalyticsSessionItemDetailParityTests

/// Cross-impl parity for the per-equipment-item QSO breakdown
/// (`EquipmentItemDetailActor.computeQSOStats`): seed a cw-store with sessions + QSOs from
/// plain objects, assert `RustAnalyticsReadSource.sessionItemDetail` matches the
/// `AnalyticsAggregator` oracle. Distance fields are compared with a tolerance because the
/// Rust UDF (`cw_grid_distance_km`) and the Swift oracle (`MaidenheadConverter.distanceKm`)
/// use independent trig implementations of the same haversine.
@MainActor
final class AnalyticsSessionItemDetailParityTests: XCTestCase {
    // MARK: Internal

    func testSessionItemDetailParity() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-item-detail")
        let rust = RustAnalyticsReadSource(store: store)

        let rig = makeSession(myRig: "IC-7300", myAntenna: "EFHW", myKey: nil, qsoCount: 4)
        let keyer = makeSession(myRig: "KX2", myAntenna: nil, myKey: "Begali", qsoCount: 1)
        for session in [rig, keyer] {
            try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))
        }
        let sessions = [rig, keyer].map(input(for:))

        // IC-7300: far, same-grid (0 km), nearer, and a metadata pseudo-mode. Begali: one QSO.
        let qsos = [
            qso(Spec(call: "Q1", band: "20m", mode: "FT8", theirGrid: "DM12", dxcc: 291), session: rig.id),
            qso(Spec(call: "Q2", band: "20m", mode: "CW", theirGrid: "FN31", dxcc: 291), session: rig.id),
            qso(Spec(call: "Q3", band: "40m", mode: "CW", theirGrid: "EM12", dxcc: 6), session: rig.id),
            qso(Spec(call: "Q4", band: "20m", mode: "WEATHER", theirGrid: "DM12", dxcc: 291), session: rig.id),
            qso(Spec(call: "Q5", band: "20m", mode: "SSB", theirGrid: "DM12", dxcc: 100), session: keyer.id),
        ]
        for entry in qsos {
            try store.upsertQso(qso: SwiftDataStoreImporter.project(entry))
        }

        let expected = AnalyticsAggregator.sessionItemDetail(name: "IC-7300", over: qsos, sessions: sessions)
        let actual = try await rust.sessionItemDetail(name: "IC-7300")

        XCTAssertEqual(actual.totalQSOs, expected.totalQSOs)
        XCTAssertEqual(actual.totalQSOs, 3) // Q1, Q2, Q3 (Q4 metadata, Q5 is Begali)
        XCTAssertEqual(actual.uniqueEntities, expected.uniqueEntities)
        XCTAssertEqual(actual.uniqueEntities, 2) // 291, 6
        XCTAssertEqual(actual.bandBreakdown, expected.bandBreakdown)
        XCTAssertEqual(actual.bandBreakdown, [bandRow("20m", 2), bandRow("40m", 1)])
        XCTAssertEqual(actual.modeBreakdown, expected.modeBreakdown)
        XCTAssertEqual(actual.modeBreakdown, [bandRow("CW", 2), bandRow("FT8", 1)])
        assertDistance(actual.farthestKm, expected.farthestKm)
        assertDistance(actual.shortestKm, expected.shortestKm)
        assertDistance(actual.averageKm, expected.averageKm)
        // Q2 (0 km) excluded; two distances remain → average is their mean.
        let farthest = try XCTUnwrap(actual.farthestKm)
        let shortest = try XCTUnwrap(actual.shortestKm)
        XCTAssertEqual(try XCTUnwrap(actual.averageKm), (farthest + shortest) / 2, accuracy: 1e-6)
    }

    func testSessionItemDetailEmptyResult() async throws {
        let store = try FieldStore.openInMemory(key: "analytics-item-detail-empty")
        let rust = RustAnalyticsReadSource(store: store)

        let none = try await rust.sessionItemDetail(name: "Nonexistent")
        XCTAssertEqual(none.totalQSOs, 0)
        XCTAssertEqual(none.uniqueEntities, 0)
        XCTAssertNil(none.farthestKm)
        XCTAssertNil(none.shortestKm)
        XCTAssertNil(none.averageKm)
        XCTAssertTrue(none.bandBreakdown.isEmpty)
        XCTAssertTrue(none.modeBreakdown.isEmpty)
    }

    // MARK: Private

    private struct Spec {
        let call: String
        let band: String
        let mode: String
        let theirGrid: String
        let dxcc: Int
    }

    private func makeSession(myRig: String?, myAntenna: String?, myKey: String?, qsoCount: Int) -> LoggingSession {
        let session = LoggingSession(
            myCallsign: "W6JY",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            myRig: myRig,
            myAntenna: myAntenna,
            myKey: myKey
        )
        session.qsoCount = qsoCount
        return session
    }

    private func input(for session: LoggingSession) -> SessionItemInput {
        SessionItemInput(
            id: session.id,
            myRig: session.myRig,
            myAntenna: session.myAntenna,
            myKey: session.myKey,
            myMic: session.myMic,
            qsoCount: session.qsoCount
        )
    }

    private func qso(_ spec: Spec, session: UUID) -> QSO {
        let entry = QSO(
            callsign: spec.call,
            band: spec.band,
            mode: spec.mode,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
        entry.loggingSessionId = session
        entry.myGrid = "FN31"
        entry.theirGrid = spec.theirGrid
        entry.dxcc = spec.dxcc
        return entry
    }

    private func bandRow(_ name: String, _ count: Int) -> ItemTallyRow {
        ItemTallyRow(name: name, count: count)
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
