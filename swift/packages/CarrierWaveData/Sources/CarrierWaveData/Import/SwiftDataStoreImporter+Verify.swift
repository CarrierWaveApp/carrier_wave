import CarrierWaveCore
import Foundation
import SwiftData

// Verify mode: compare per-table row counts (SwiftData source vs cw-store) to
// guard the "every row made it" invariant cheaply. Field-level fidelity is
// covered by the projection round-trip tests. Actor-isolated like the rest of
// the importer, so the source counts are fetched on the actor's context.

// MARK: - VerifyReport

public struct VerifyReport: Sendable, Equatable {
    public struct Table: Sendable, Equatable {
        public let name: String
        public let sourceCount: Int
        public let storedCount: Int

        public var matches: Bool {
            sourceCount == storedCount
        }
    }

    public let tables: [Table]

    /// Every table's source and stored counts agree.
    public var ok: Bool {
        tables.allSatisfy(\.matches)
    }

    /// Tables whose counts disagree (empty when `ok`).
    public var mismatches: [Table] {
        tables.filter { !$0.matches }
    }
}

// MARK: - Verify

public extension SwiftDataStoreImporter {
    /// Import into a throwaway in-memory store and report per-table count
    /// agreement. Does not touch any on-disk store.
    func verify(batchSize: Int = defaultBatchSize) async throws -> VerifyReport {
        let store = try FieldStore.openInMemory(key: "verify")
        _ = try await importAll(into: store, batchSize: batchSize)
        return try compareCounts(to: store)
    }

    /// Compare the `@Model` source counts against the row counts already present
    /// in `store`. Used after importing into the real store to gate the
    /// completion marker without a second (in-memory) import.
    func compareCounts(to store: FieldStore) throws -> VerifyReport {
        let context = container.mainContext
        let tables: [VerifyReport.Table] = try [
            countTable(context, "qso", QSO.self, store.qsoCount()),
            countTable(context, "logging_session", LoggingSession.self, store.loggingSessionCount()),
            countTable(context, "service_presence", ServicePresence.self, store.servicePresenceCount()),
            countTable(context, "session_spot", SessionSpot.self, store.sessionSpotCount()),
            countTable(context, "activation_metadata", ActivationMetadata.self, store.activationMetadataCount()),
            countTable(context, "activity_log", ActivityLog.self, store.activityLogCount()),
            countTable(context, "equipment_item", EquipmentItem.self, store.equipmentItemCount()),
            countTable(context, "radio_macro", RadioMacro.self, store.radioMacroCount()),
            countTable(context, "websdr_recording", WebSDRRecording.self, store.websdrRecordingCount()),
            countTable(context, "websdr_favorite", WebSDRFavorite.self, store.websdrFavoriteCount()),
            countTable(context, "upload_destination", UploadDestination.self, store.uploadDestinationCount()),
            countTable(context, "cloud_sync_metadata", CloudSyncMetadata.self, store.cloudSyncMetadataCount()),
        ]
        return VerifyReport(tables: tables)
    }

    private func countTable<Model: PersistentModel>(
        _ context: ModelContext,
        _ name: String,
        _: Model.Type,
        _ storedCount: Int64
    ) throws -> VerifyReport.Table {
        let sourceCount = try context.fetchCount(FetchDescriptor<Model>())
        return VerifyReport.Table(
            name: name,
            sourceCount: sourceCount,
            storedCount: Int(storedCount)
        )
    }
}
