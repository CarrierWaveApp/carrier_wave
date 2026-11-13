import CarrierWaveCore
import Foundation
import SwiftData
import XCTest
@testable import CarrierWaveData

// MARK: - SwiftDataSyncReplicaTests

/// The server-sync replica copies rows a pull applied to cw-store into a
/// SwiftData follower (CW Sweep's UI store) without marking them dirty.
@MainActor
final class SwiftDataSyncReplicaTests: XCTestCase {
    // MARK: Internal

    func testInsertsPulledQSOAndSession() async throws {
        let container = try Self.makeContainer()
        let store = try FieldStore.openInMemory(key: "replica-insert")
        let qso = Self.makeQSO(callsign: "K6ABC")
        let session = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_000))
        try store.upsertQso(qso: SwiftDataStoreImporter.project(qso))
        try store.upsertLoggingSession(item: SwiftDataStoreImporter.project(session))

        let replica = SwiftDataSyncReplica(container: container, store: store, mirror: nil)
        await replica.apply([
            SyncAppliedChange(entity: .qso, id: SwiftDataStoreImporter.uuid(qso.id), deleted: false),
            SyncAppliedChange(entity: .loggingSession, id: SwiftDataStoreImporter.uuid(session.id), deleted: false),
            SyncAppliedChange(entity: .syncedConfig, id: "bragSheet", deleted: false),
        ])

        let context = ModelContext(container)
        let qsos = try context.fetch(Self.allQSOs())
        XCTAssertEqual(qsos.count, 1)
        XCTAssertEqual(qsos.first?.id, qso.id)
        XCTAssertEqual(qsos.first?.callsign, "K6ABC")
        XCTAssertEqual(qsos.first?.cloudDirtyFlag, false, "replicated rows must never re-push")
        let sessions = try context.fetch(FetchDescriptor<LoggingSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, session.id)
        XCTAssertEqual(sessions.first?.myCallsign, "W6JY")
    }

    func testUpdatesExistingRowAndSoftDeleteLandsAsHidden() async throws {
        let container = try Self.makeContainer()
        let store = try FieldStore.openInMemory(key: "replica-update")
        let qso = Self.makeQSO(callsign: "K6ABC")
        let context = ModelContext(container)
        context.insert(qso)
        try context.save()
        // The pull merged a hide + a name onto the store row.
        var row = SwiftDataStoreImporter.project(qso)
        row.isHidden = true
        row.name = "Pat"
        try store.upsertQso(qso: row)

        let replica = SwiftDataSyncReplica(container: container, store: store, mirror: nil)
        await replica.apply([
            SyncAppliedChange(entity: .qso, id: SwiftDataStoreImporter.uuid(qso.id), deleted: false),
        ])

        let fresh = ModelContext(container)
        let rows = try fresh.fetch(Self.allQSOs())
        XCTAssertEqual(rows.count, 1, "an existing row is updated in place, not duplicated")
        XCTAssertEqual(rows.first?.isHidden, true)
        XCTAssertEqual(rows.first?.name, "Pat")
    }

    func testDeletedSessionIsRemovedAndUnknownRowsAreSkipped() async throws {
        let container = try Self.makeContainer()
        let store = try FieldStore.openInMemory(key: "replica-delete")
        let session = LoggingSession(myCallsign: "W6JY", startedAt: Date(timeIntervalSince1970: 1_000))
        let context = ModelContext(container)
        context.insert(session)
        try context.save()

        let replica = SwiftDataSyncReplica(container: container, store: store, mirror: nil)
        await replica.apply([
            SyncAppliedChange(entity: .loggingSession, id: SwiftDataStoreImporter.uuid(session.id), deleted: true),
            // Not in the store: skipped, not fatal.
            SyncAppliedChange(entity: .qso, id: UUID().uuidString.lowercased(), deleted: false),
        ])

        let fresh = ModelContext(container)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<LoggingSession>()).count, 0)
        XCTAssertEqual(try fresh.fetch(Self.allQSOs()).count, 0)
    }

    // MARK: Private

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(CarrierWaveSchema.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func allQSOs() -> FetchDescriptor<QSO> {
        var descriptor = FetchDescriptor<QSO>()
        descriptor.fetchLimit = 10
        return descriptor
    }

    private static func makeQSO(callsign: String) -> QSO {
        QSO(
            callsign: callsign,
            band: "20m",
            mode: "CW",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            myCallsign: "W6JY",
            importSource: .logger
        )
    }
}
