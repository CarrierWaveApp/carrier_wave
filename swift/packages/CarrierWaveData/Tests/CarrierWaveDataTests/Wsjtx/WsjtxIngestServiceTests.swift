//
//  WsjtxIngestServiceTests.swift
//  CarrierWaveDataTests
//
//  Dedup/insert decisions for QSOs arriving from WSJT-X (CAR-282). No socket:
//  mapped `FfiQso`s and decoded messages are fed straight into the service
//  against an in-memory SwiftData container.
//

import CarrierWaveCore
import Foundation
import SwiftData
import Testing
@testable import CarrierWaveData

// `.serialized`: each test builds its own in-memory SwiftData container.
@Suite(.serialized)
@MainActor
struct WsjtxIngestServiceTests {
    // MARK: Internal

    /// 2026-03-14T18:30:15Z — the QSO time in every sample below.
    static let timeOn: Int64 = 1_773_513_015

    @Test("two mapped QSOs with the same id insert one row")
    func sameIdInsertsOnce() throws {
        let (service, container) = try Self.makeService()
        let context = container.mainContext
        let qso = try Self.mappedQsoLogged()

        let first = service.ingest([qso])
        let second = service.ingest([qso]) // WSJT-X re-broadcast

        #expect(try first == [.inserted(#require(UUID(uuidString: qso.id)))])
        #expect(try second == [.duplicate(#require(UUID(uuidString: qso.id)))])
        #expect(try Self.rowCount(in: context) == 1)
        #expect(service.loggedCount == 1)
        #expect(service.duplicateCount == 1)
        #expect(service.recentEvents.map(\.kind) == [.qsoLogged, .duplicate])

        let stored = try context.fetch(FetchDescriptor<QSO>()).first
        #expect(stored?.callsign == "K1ABC")
        #expect(stored?.importSourceRawValue == ImportSource.wsjtx.rawValue)
        #expect(stored?.importSource == .wsjtx)
        #expect(stored?.loggingSessionId == nil)
    }

    @Test("QSOLogged followed by its LoggedADIF twin logs once")
    func adifTwinIsDuplicate() throws {
        let (service, container) = try Self.makeService()
        let context = container.mainContext
        let fromLogged = try Self.mappedQsoLogged()
        let fromAdif = try wsjtxMapLoggedAdif(
            message: FfiWsjtxLoggedAdif(id: "WSJT-X", adif: Self.sampleAdif),
            context: Self.context
        )
        #expect(fromAdif.count == 1)

        service.ingest([fromLogged])
        let outcome = service.ingest(fromAdif)

        #expect(try outcome == [.duplicate(#require(UUID(uuidString: fromLogged.id)))])
        #expect(try Self.rowCount(in: context) == 1)
        #expect(service.duplicateCount == 1)
    }

    @Test("a manually logged QSO with the same dedup key blocks the WSJT-X copy")
    func dedupKeyMatchesExistingRow() throws {
        let (service, container) = try Self.makeService()
        let context = container.mainContext
        // Logged by hand 20 s later — same 18:30 two-minute bucket, different UUID.
        let manual = QSO(
            callsign: "K1ABC",
            band: "20m",
            mode: "FT8",
            timestamp: Date(timeIntervalSince1970: TimeInterval(Self.timeOn + 20)),
            myCallsign: "W6JY",
            importSource: .logger
        )
        context.insert(manual)
        try context.save()

        let outcome = try service.ingest([Self.mappedQsoLogged()])

        #expect(outcome == [.duplicate(manual.id)])
        #expect(try Self.rowCount(in: context) == 1)
    }

    @Test("different QSOs in the same bucket both insert")
    func distinctQsosBothInsert() throws {
        let (service, container) = try Self.makeService()
        let context = container.mainContext
        var other = try Self.mappedQsoLogged()
        other.id = UUID().uuidString
        other.callsign = "N0CALL"

        let outcomes = try service.ingest([Self.mappedQsoLogged(), other])

        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy {
            if case .inserted = $0 {
                true
            } else {
                false
            }
        })
        #expect(try Self.rowCount(in: context) == 2)
        #expect(service.lastLoggedSummary == "N0CALL · 20m FT8")
    }

    @Test("attaches to the active session and bumps its count")
    func attachesToActiveSession() throws {
        let (service, container) = try Self.makeService()
        let context = container.mainContext
        let session = LoggingSession(myCallsign: "W6JY", startedAt: Date(), mode: "FT8", activationType: .casual)
        context.insert(session)
        try context.save()

        var loose = try Self.mappedQsoLogged()
        loose.loggingSessionId = nil
        service.ingest([loose])

        let stored = try context.fetch(FetchDescriptor<QSO>()).first
        #expect(stored?.loggingSessionId == session.id)
        #expect(session.qsoCount == 1)
        #expect(service.makeImportContext().loggingSessionId == session.id.uuidString.lowercased())
    }

    @Test("decoded messages drive the feed; QSOLogged inserts via the mapper")
    func handleMessageRoutesQsoLogged() throws {
        let (service, container) = try Self.makeService()
        let context = container.mainContext

        service.handleMessage(.decode(decode: Self.sampleDecode), from: "127.0.0.1:2237")
        service.handleMessage(.qsoLogged(qso: Self.sampleQsoLogged), from: "127.0.0.1:2237")
        service.handleMessage(.qsoLogged(qso: Self.sampleQsoLogged), from: "127.0.0.1:2237")
        service.handleMessage(.close(id: "WSJT-X"), from: "127.0.0.1:2237")

        #expect(try Self.rowCount(in: context) == 1)
        #expect(service.recentEvents.map(\.kind) == [.decode, .qsoLogged, .duplicate, .info])
        #expect(service.recentEvents.first?.text.contains("CQ K1ABC FN42") == true)
    }

    @Test("port parsing rejects 0 and out-of-range values")
    func parsePort() {
        #expect(WsjtxIngestService.parsePort("2237") == 2_237)
        #expect(WsjtxIngestService.parsePort(" 65535 ") == 65_535)
        #expect(WsjtxIngestService.parsePort("0") == nil)
        #expect(WsjtxIngestService.parsePort("65536") == nil)
        #expect(WsjtxIngestService.parsePort("abc") == nil)
    }

    @Test("settings persist to the injected defaults")
    func settingsPersist() throws {
        let suite = "WsjtxIngestServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let service = WsjtxIngestService(defaults: defaults, defaultHost: WsjtxIngestService.anyHost)
        #expect(service.host == "0.0.0.0")
        #expect(service.port == 2_237)
        #expect(!service.isEnabled)

        service.isEnabled = true
        service.host = "192.168.1.20"
        service.port = 2_238

        let reloaded = WsjtxIngestService(defaults: defaults)
        #expect(reloaded.isEnabled)
        #expect(reloaded.host == "192.168.1.20")
        #expect(reloaded.port == 2_238)
    }

    // MARK: Private

    private static let context = FfiWsjtxImportContext(
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
        comments: "Nice QSO",
        name: "Bob",
        dateTimeOn: timeOn,
        operatorCall: "",
        myCall: "W6JY",
        myGrid: "CM87xx",
        exchangeSent: "",
        exchangeReceived: "",
        adifPropagationMode: ""
    )

    private static let sampleDecode = FfiWsjtxDecode(
        id: "WSJT-X",
        new: true,
        timeMs: 66_615_000,
        snr: -5,
        deltaTime: 0.2,
        deltaFrequency: 1_245,
        mode: "~",
        message: "CQ K1ABC FN42",
        lowConfidence: false,
        offAir: false
    )

    /// The record WSJT-X writes for `sampleQsoLogged`.
    private static let sampleAdif = "WSJT-X ADIF Export<eoh>\n"
        + "<call:5>K1ABC <gridsquare:4>FN42 <mode:3>FT8 <rst_sent:3>-10 <rst_rcvd:3>-05 "
        + "<qso_date:8>20260314 <time_on:6>183015 <band:3>20m <freq:9>14.075245 "
        + "<station_callsign:4>W6JY <my_gridsquare:6>CM87xx <tx_pwr:2>50 <eor>"

    private static func mappedQsoLogged() throws -> FfiQso {
        try wsjtxMapQsoLogged(message: sampleQsoLogged, context: context)
    }

    /// Returns the container too: the caller must keep it alive for the test's
    /// duration or the main context's store is torn down under the service.
    private static func makeService() throws -> (WsjtxIngestService, ModelContainer) {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let suite = "WsjtxIngestServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let service = WsjtxIngestService(defaults: defaults)
        service.configure(container: container)
        return (service, container)
    }

    private static func rowCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<QSO>())
    }
}
