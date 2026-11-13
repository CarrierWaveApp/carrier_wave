import CarrierWaveCore
import Foundation
import SwiftData
import Testing
@testable import CarrierWaveData

// `.serialized`: each test builds its own in-memory SwiftData container +
// main context; running them in parallel intermittently trips SwiftData.
@Suite(.serialized)
struct SwiftDataStoreImporterTests {
    // MARK: Internal

    @Test("imports QSOs into cw-store with field fidelity")
    func importsQsosWithFidelity() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let qso = QSO(
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            frequency: 14.074, // MHz
            timestamp: Date(timeIntervalSince1970: 1_000),
            myCallsign: "W6JY",
            theirGrid: "EM12",
            importSource: .logger,
            power: 5,
            qrzConfirmed: true
        )
        context.insert(qso)
        try context.save()

        let store = try FieldStore.openInMemory(key: "test-key")
        let report = try await SwiftDataStoreImporter(container: container)
            .importAll(into: store, batchSize: 100)

        #expect(report.counts["qso"] == 1)
        #expect(try store.qsoCount() == 1)

        let rows = try store.fetchQsos(filter: Self.allQsos, limit: 10, offset: 0)
        let imported = try #require(rows.first)
        #expect(imported.callsign == "W1AW")
        #expect(imported.theirGrid == "EM12")
        #expect(imported.myCallsign == "W6JY")
        #expect(imported.power == 5)
        #expect(imported.qrzConfirmed)
        // 14.074 MHz in the @Model → 14074 kHz in the store.
        #expect(abs((imported.freqKhz ?? 0) - 14_074) < 0.001)
    }

    @Test("re-import is idempotent (upsert by id, no duplicates)")
    func reImportIsIdempotent() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        for index in 0 ..< 3 {
            context.insert(QSO(
                callsign: "W\(index)AW",
                band: "20m",
                mode: "CW",
                timestamp: Date(timeIntervalSince1970: Double(1_000 + index)),
                myCallsign: "W6JY",
                importSource: .logger
            ))
        }
        try context.save()

        let store = try FieldStore.openInMemory(key: "test-key")
        let importer = SwiftDataStoreImporter(container: container)

        _ = try await importer.importAll(into: store, batchSize: 2) // force multiple batches
        #expect(try store.qsoCount() == 3)

        // Second run overwrites the same ids — count stays 3.
        let second = try await importer.importAll(into: store, batchSize: 2)
        #expect(second.counts["qso"] == 3)
        #expect(try store.qsoCount() == 3)
    }

    @Test("LoggingSession projects JSON arrays + Bool? override faithfully")
    func loggingSessionConversions() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let session = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 5_000))
        session.photoFilenames = ["a.jpg", "b.jpg"]
        session.winterActivationOverride = true // Bool? → store Int64? (1)
        session.qsoCount = 7
        context.insert(session)
        try context.save()

        let store = try FieldStore.openInMemory(key: "test-key")
        let report = try await SwiftDataStoreImporter(container: container).importAll(into: store)

        #expect(report.counts["logging_session"] == 1)
        let rows = try store.fetchLoggingSessions(
            filter: FfiLoggingSessionFilter(myCallsign: nil, since: nil, dirtyOnly: nil),
            limit: 10,
            offset: 0
        )
        let imported = try #require(rows.first)
        #expect(imported.myCallsign == "W6JY")
        #expect(imported.qsoCount == 7)
        #expect(imported.winterActivationOverride == 1)
        // [String] photoFilenames is stored as JSON text.
        #expect(imported.photoFilenames == #"["a.jpg","b.jpg"]"#)
    }

    @Test("importAll reports a key for every supported entity")
    func reportCoversAllEntities() async throws {
        let container = try Self.makeContainer()
        let store = try FieldStore.openInMemory(key: "test-key")
        let report = try await SwiftDataStoreImporter(container: container).importAll(into: store)

        let expected: Set = [
            "qso", "logging_session", "service_presence", "session_spot",
            "activation_metadata", "activity_log", "equipment_item", "radio_macro",
            "websdr_recording", "websdr_favorite", "upload_destination", "cloud_sync_metadata",
        ]
        #expect(Set(report.counts.keys) == expected)
        #expect(report.total == 0) // empty source
    }

    @Test("verify reports count agreement across all tables")
    func verifyCountsAgree() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        for index in 0 ..< 4 {
            context.insert(QSO(
                callsign: "W\(index)AW",
                band: "20m",
                mode: "CW",
                timestamp: Date(timeIntervalSince1970: Double(1_000 + index)),
                myCallsign: "W6JY",
                importSource: .logger
            ))
        }
        context.insert(LoggingSession(myCallsign: "W6JY"))
        try context.save()

        let verify = try await SwiftDataStoreImporter(container: container).verify()
        #expect(verify.ok)
        #expect(verify.mismatches.isEmpty)
        #expect(verify.tables.count == 12)
        let qso = try #require(verify.tables.first { $0.name == "qso" })
        #expect(qso.sourceCount == 4)
        #expect(qso.storedCount == 4)
    }

    @Test("imports a WebSDRFavorite (repro for the fetch crash)")
    func importsWebSDRFavorite() async throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        context.insert(WebSDRFavorite(
            hostPort: "kiwisdr.example.com:8073",
            displayName: "Test SDR",
            location: "CA",
            addedDate: Date(timeIntervalSince1970: 2_000)
        ))
        try context.save()

        let store = try FieldStore.openInMemory(key: "test-key")
        let report = try await SwiftDataStoreImporter(container: container).importAll(into: store)

        #expect(report.counts["websdr_favorite"] == 1)
        #expect(try store.websdrFavoriteCount() == 1)
    }

    // MARK: Private

    private static let allQsos = FfiQsoFilter(
        callsignPrefix: nil, band: nil, mode: nil, since: nil, dirtyOnly: false
    )

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
