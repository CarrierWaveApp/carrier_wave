//
//  WsjtxFieldServiceTests.swift
//  CarrierWaveTests
//
//  Field's WSJT-X adapter (CAR-282): upload marking on insert, the session
//  handed to the target resolver, duplicates, and the experiment gate. No
//  socket — mapped QSOs are fed straight into the shared ingest service.
//

import CarrierWaveCore
import CarrierWaveData
import SwiftData
import XCTest
@testable import CarrierWave

@MainActor
final class WsjtxFieldServiceTests: XCTestCase {
    // MARK: Internal

    func testInsertMarksResolvedUploadTargets() throws {
        let (service, container) = try makeService()
        var seenSessions: [LoggingSession?] = []
        service.uploadTargets = { session in
            seenSessions.append(session)
            // Only services with `supportsUpload` take a marker; LoFi/Club Log
            // are no-ops in `markNeedsUpload`, exactly as in the manual logger.
            return [.qrz, .eqsl, .lofi]
        }

        let outcomes = try service.ingest.ingest([Self.mappedQsoLogged()])

        guard case .inserted? = outcomes.first else {
            return XCTFail("expected an insert, got \(outcomes)")
        }
        let stored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<QSO>()).first)
        XCTAssertEqual(stored.callsign, "K1ABC")
        XCTAssertEqual(stored.importSource, .wsjtx)
        XCTAssertEqual(stored.presence(for: .qrz)?.needsUpload, true)
        XCTAssertEqual(stored.presence(for: .eqsl)?.needsUpload, true)
        XCTAssertNil(stored.presence(for: .lofi))
        XCTAssertNil(stored.presence(for: .pota))
        XCTAssertEqual(seenSessions.count, 1)
        XCTAssertTrue(seenSessions.allSatisfy { $0 == nil }, "no active session → resolver sees nil")
    }

    func testInsertAttachesActiveSessionAndHandsItToTargets() throws {
        let (service, container) = try makeService()
        let context = container.mainContext
        let session = LoggingSession(
            myCallsign: "W6JY", mode: "FT8", programs: ["pota"],
            activationType: .pota, parkReference: "US-0001"
        )
        context.insert(session)
        try context.save()
        service.uploadTargets = { session in session?.isPOTA == true ? [.pota] : [] }

        try service.ingest.ingest([Self.mappedQsoLogged()])

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<QSO>()).first)
        XCTAssertEqual(stored.loggingSessionId, session.id)
        XCTAssertEqual(stored.presence(for: .pota)?.needsUpload, true)
        XCTAssertEqual(session.qsoCount, 1)
    }

    func testRebroadcastIsSkippedWithoutNewMarkers() throws {
        let (service, container) = try makeService()
        var resolverCalls = 0
        service.uploadTargets = { _ in
            resolverCalls += 1
            return [.qrz]
        }
        let qso = try Self.mappedQsoLogged()

        service.ingest.ingest([qso])
        let second = service.ingest.ingest([qso])

        guard case .duplicate? = second.first else {
            return XCTFail("expected a duplicate, got \(second)")
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<QSO>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ServicePresence>()), 1)
        XCTAssertEqual(resolverCalls, 1)
    }

    func testStartIsGatedByTheExperiment() async throws {
        let (service, _) = try makeService()
        let key = "experimental.wsjtx.enabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        ExperimentalFeature.setEnabled(.wsjtx, enabled: false)
        service.ingest.isEnabled = true

        await service.startIfEnabled()

        XCTAssertFalse(service.isAvailable)
        XCTAssertFalse(service.ingest.isRunning)
    }

    // MARK: Private

    /// 2026-03-14T18:30:15Z — the QSO time in the sample below.
    private static let timeOn: Int64 = 1_773_513_015

    private static let importContext = FfiWsjtxImportContext(
        stationCallsign: "W6JY",
        importedAt: 1_800_000_000,
        loggingSessionId: nil
    )

    private static let sampleQsoLogged = FfiWsjtxQsoLogged(
        id: "WSJT-X",
        dateTimeOff: timeOn + 45,
        dxCall: "K1ABC",
        dxGrid: "FN42",
        txFrequencyHz: 14_075_245,
        mode: "FT8",
        reportSent: "-10",
        reportReceived: "-05",
        txPower: "50",
        comments: "",
        name: "Bob",
        dateTimeOn: timeOn,
        operatorCall: "",
        myCall: "W6JY",
        myGrid: "CM87xx",
        exchangeSent: "",
        exchangeReceived: "",
        adifPropagationMode: ""
    )

    private static func mappedQsoLogged() throws -> FfiQso {
        try wsjtxMapQsoLogged(message: sampleQsoLogged, context: importContext)
    }

    /// Returns the container too: keep it alive for the test's duration or the
    /// main context's store is torn down under the service.
    private func makeService() throws -> (WsjtxFieldService, ModelContainer) {
        let container = try TestModelContainer.create()
        let suite = "WsjtxFieldServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let service = WsjtxFieldService(ingest: WsjtxIngestService(defaults: defaults))
        service.configure(container: container)
        return (service, container)
    }
}
