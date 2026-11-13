import CarrierWaveCore
import Foundation
import SwiftData
import Testing
@testable import CarrierWaveData

// End-to-end Phase 4 exit acceptance: prove the *actual on-device seed path*
// (`SwiftDataStoreImporter.importAll`, batched, all 12 entities at once) produces
// a cw-store whose **reads through the read-source seam** match SwiftData — not
// just row counts (`verify`) and not via per-row `project()` seeding (the
// per-entity read-source tests). This closes the gap between "the importer
// fetch/batch path is correct" and "every `.on`-mode read returns identical data."
//
// `.serialized`: each test builds its own in-memory SwiftData container + main
// context; SwiftData trips intermittently when these run in parallel.
// `@MainActor`: `SwiftDataStoreImporter` and the SwiftData read sources are
// main-context bound.
@Suite(.serialized)
@MainActor
struct EndToEndImportParityTests {
    // MARK: Internal

    @Test("importAll → list read sources match SwiftData (field + order parity)")
    func listEntitiesReadParityAfterImportAll() async throws {
        let fixture = try await Self.makeImportedFixture()
        let ctx = fixture.container.mainContext
        let store = fixture.store

        try await expectParity(
            "LoggingSession",
            SwiftDataLoggingSessionReadSource(context: ctx).all(),
            RustLoggingSessionReadSource(store: store).all()
        )
        try await expectParity(
            "SessionSpot",
            SwiftDataSessionSpotReadSource(context: ctx).all(),
            RustSessionSpotReadSource(store: store).all()
        )
        try await expectParity(
            "ActivationMetadata",
            SwiftDataActivationMetadataReadSource(context: ctx).all(),
            RustActivationMetadataReadSource(store: store).all()
        )
        try await expectParity(
            "ActivityLog",
            SwiftDataActivityLogReadSource(context: ctx).all(),
            RustActivityLogReadSource(store: store).all()
        )
        try await expectParity(
            "EquipmentItem",
            SwiftDataEquipmentItemReadSource(context: ctx).all(),
            RustEquipmentItemReadSource(store: store).all()
        )
        try await expectParity(
            "RadioMacro",
            SwiftDataRadioMacroReadSource(context: ctx).all(),
            RustRadioMacroReadSource(store: store).all()
        )
        try await expectParity(
            "WebSDRRecording",
            SwiftDataWebSDRRecordingReadSource(context: ctx).all(),
            RustWebSDRRecordingReadSource(store: store).all()
        )
        try await expectParity(
            "WebSDRFavorite",
            SwiftDataWebSDRFavoriteReadSource(context: ctx).all(),
            RustWebSDRFavoriteReadSource(store: store).all()
        )
        try await expectParity(
            "UploadDestination",
            SwiftDataUploadDestinationReadSource(context: ctx).all(),
            RustUploadDestinationReadSource(store: store).all()
        )
    }

    @Test("importAll → counts agree (report, verify, and count-only read sources)")
    func countsAgreeAfterImportAll() async throws {
        let fixture = try await Self.makeImportedFixture()
        let ctx = fixture.container.mainContext
        let store = fixture.store
        let report = fixture.report

        // The report counts the rows it actually upserted, batched path included.
        #expect(report.counts["qso"] == 3)
        #expect(report.counts["service_presence"] == 2)
        #expect(report.counts["logging_session"] == 2)
        #expect(report.counts["upload_destination"] == 2)

        // QSO + ServicePresence are count-only in the package loop (the QSO row
        // read needs the app-target QueryCompiler), so prove count parity here.
        let sdQso = try await SwiftDataQSOReadSource(context: ctx).count()
        let rustQso = try await RustQSOReadSource(store: store).count()
        #expect(sdQso == 3)
        #expect(sdQso == rustQso)

        let sdPresence = try await SwiftDataServicePresenceReadSource(context: ctx).count()
        let rustPresence = try await RustServicePresenceReadSource(store: store).count()
        #expect(sdPresence == 2)
        #expect(sdPresence == rustPresence)

        // The standalone count-agreement check the on-device coordinator gates on.
        let verification = try await SwiftDataStoreImporter(container: fixture.container).compareCounts(to: store)
        #expect(verification.ok)
        #expect(verification.mismatches.isEmpty)
    }

    // MARK: Private

    /// A seeded in-memory container plus the cw-store it was imported into.
    /// (A struct, not a tuple — `large_tuple` caps tuples at two members.)
    private struct ImportedFixture {
        let container: ModelContainer
        let store: FieldStore
        let report: ImportReport
    }

    /// Build an in-memory SwiftData container, seed a realistic multi-entity
    /// graph, then run the real `importAll` with a small batch size so the
    /// batched fetch path (multiple windows per entity) is exercised.
    private static func makeImportedFixture() async throws -> ImportedFixture {
        let schema = Schema(CarrierWaveSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        seedQSOsAndPresence(into: context)
        seedSessionsSpotsMetadata(into: context)
        seedReferenceEntities(into: context)
        try context.save()

        let store = try FieldStore.openInMemory(key: "end-to-end-import-parity")
        // batchSize 2 forces multiple fetch windows for the 3-row / 2-row entities.
        let report = try await SwiftDataStoreImporter(container: container).importAll(into: store, batchSize: 2)
        return ImportedFixture(container: container, store: store, report: report)
    }

    /// 3 QSOs (spread across modes/flags) + 2 ServicePresence rows attached to them.
    private static func seedQSOsAndPresence(into context: ModelContext) {
        for index in 0 ..< 3 {
            let qso = QSO(
                callsign: "W\(index)AW",
                band: "20m",
                mode: index == 0 ? "FT8" : "CW",
                frequency: 14.074,
                timestamp: Date(timeIntervalSince1970: Double(1_700_000_000 + index)),
                myCallsign: "W6JY",
                theirGrid: "EM12",
                importSource: .logger,
                power: 5,
                qrzConfirmed: index == 0
            )
            context.insert(qso)
            if index < 2 { // 2 presence rows total
                context.insert(ServicePresence(serviceType: .pota, isPresent: true, needsUpload: true, qso: qso))
            }
        }
    }

    /// Sessions (one field-rich), session spots, and activation metadata.
    private static func seedSessionsSpotsMetadata(into context: ModelContext) {
        let pota = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        pota.parkReference = "US-0001"
        pota.qsoCount = 42
        pota.photoFilenames = ["a.jpg", "b.jpg"]
        pota.winterActivationOverride = true
        context.insert(pota)
        context.insert(LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_700_001_000)))

        let sessionId = UUID()
        context.insert(SessionSpot(
            loggingSessionId: sessionId, callsign: "K1ABC", frequencyKHz: 14_285,
            mode: "SSB", timestamp: Date(timeIntervalSince1970: 1_700_000_000), source: "pota"
        ))
        context.insert(SessionSpot(
            loggingSessionId: sessionId, callsign: "K2DEF", frequencyKHz: 14_030,
            mode: "CW", timestamp: Date(timeIntervalSince1970: 1_700_000_100), source: "rbn"
        ))

        context.insert(ActivationMetadata(
            parkReference: "US-0001", date: Date(timeIntervalSince1970: 1_700_000_000),
            title: "Morning CW", watts: 5
        ))
        context.insert(ActivationMetadata(parkReference: "US-0002", date: Date(timeIntervalSince1970: 1_690_000_000)))
    }

    /// Activity logs, equipment, macros, WebSDR recordings/favorites, upload destinations.
    private static func seedReferenceEntities(into context: ModelContext) {
        context.insert(ActivityLog(name: "Log A", myCallsign: "W6JY"))
        context.insert(ActivityLog(name: "Log B", myCallsign: "W6JY"))

        context.insert(EquipmentItem(catalogId: "rig-1", catalogName: "Rig 1", category: .radio))
        context.insert(EquipmentItem(catalogId: "ant-1", catalogName: "Antenna 1", category: .antenna))

        context.insert(RadioMacro(name: "Call CQ", icon: "antenna.radiowaves.left.and.right", tagsCSV: "cw,calling"))
        context.insert(RadioMacro(name: "Set Power", tombstoned: true, tombstoneReason: "superseded"))

        context.insert(WebSDRRecording(
            loggingSessionId: UUID(), kiwisdrHost: "kiwisdr.example:8073",
            kiwisdrName: "Example", frequencyKHz: 14_074, mode: "USB"
        ))
        context.insert(WebSDRRecording(
            loggingSessionId: UUID(), kiwisdrHost: "alpha.example:8074",
            kiwisdrName: "Alpha", frequencyKHz: 7_074, mode: "USB"
        ))

        context.insert(WebSDRFavorite(
            hostPort: "kiwisdr.example.com:8073", displayName: "Test SDR",
            location: "CA", addedDate: Date(timeIntervalSince1970: 2_000)
        ))
        context.insert(WebSDRFavorite(
            hostPort: "alpha.example.com:8074", displayName: "Alpha SDR",
            location: "NV", addedDate: Date(timeIntervalSince1970: 3_000)
        ))

        context.insert(UploadDestination(
            type: .qrz,
            isEnabled: true,
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        context.insert(UploadDestination(type: .pota, isEnabled: false))
    }

    /// `#expect` wrapper so each entity comparison reads as one statement and
    /// carries a clear divergence label.
    private func expectParity<S: Equatable>(_ label: String, _ swiftData: [S], _ rust: [S]) {
        #expect(swiftData == rust, "\(label): SwiftData and Rust read sources diverge after importAll")
    }
}
