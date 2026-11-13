import CarrierWaveCore
import SwiftData

// MARK: - EntityWriteSinkFactory

/// Wires the per-entity `upsert_*` / `delete_*` FFI into a generic `EntityWriteSink`
/// for each uniform peripheral entity (and LoggingSession), then registers them.
/// QSO and ServicePresence are excluded — they keep dedicated sinks for their
/// presence-row / hidden logic. Built once on mirror setup; the seam reads the
/// rollout mode live via `CwStoreQSOMode.current`, so no rebuild on a shadow↔on
/// toggle. Every store call projects via the canonical `SwiftDataStoreImporter`.
@MainActor
public enum EntityWriteSinkFactory {
    // MARK: Public

    /// Register a sink for every covered entity. Call on mirror setup.
    public static func registerAll(store: FieldStore, mirror: CwStoreMirror?) {
        registerIDKeyed(store: store, mirror: mirror)
        registerNaturalKeyed(store: store, mirror: mirror)
    }

    /// Drop all sinks. Call when the mirror stops (`off` mode).
    public static func clearAll() {
        EntityWriteSinkRegistry.clear()
    }

    // MARK: Private

    /// Entities deleted by their `id` (lowercased UUID string).
    private static func registerIDKeyed(store: FieldStore, mirror: CwStoreMirror?) {
        let uuid = SwiftDataStoreImporter.uuid
        EntityWriteSinkRegistry.register(EntityWriteSink<LoggingSession>(
            store: store, mirror: mirror,
            upsertToStore: {
                try $1.upsertLoggingSession(item: SwiftDataStoreImporter.project($0))
                // Keep the structured rove_stop table (which the Rust split
                // reads) in lockstep with the transitional blob.
                if $0.isRove {
                    try $1.replaceRoveStops(
                        loggingSessionId: uuid($0.id),
                        stops: SwiftDataStoreImporter.projectRoveStops($0)
                    )
                }
            },
            deleteFromStore: { try $1.deleteLoggingSession(id: uuid($0.id)) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<EquipmentItem>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertEquipmentItem(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteEquipmentItem(id: uuid($0.id)) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<RadioMacro>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertRadioMacro(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteRadioMacro(id: uuid($0.id)) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<SessionSpot>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertSessionSpot(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteSessionSpot(id: uuid($0.id)) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<ActivityLog>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertActivityLog(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteActivityLog(id: uuid($0.id)) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<UploadDestination>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertUploadDestination(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteUploadDestination(id: uuid($0.id)) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<WebSDRRecording>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertWebsdrRecording(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteWebsdrRecording(id: uuid($0.id)) }
        ))
    }

    /// Entities deleted by a natural key (no surface `id`).
    private static func registerNaturalKeyed(store: FieldStore, mirror: CwStoreMirror?) {
        let uuid = SwiftDataStoreImporter.uuid
        EntityWriteSinkRegistry.register(EntityWriteSink<ActivationMetadata>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertActivationMetadata(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: {
                try $1.deleteActivationMetadata(
                    parkReference: $0.parkReference,
                    date: Int64($0.date.timeIntervalSince1970)
                )
            }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<WebSDRFavorite>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertWebsdrFavorite(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteWebsdrFavorite(hostPort: $0.hostPort) }
        ))
        EntityWriteSinkRegistry.register(EntityWriteSink<CloudSyncMetadata>(
            store: store, mirror: mirror,
            upsertToStore: { try $1.upsertCloudSyncMetadata(item: SwiftDataStoreImporter.project($0)) },
            deleteFromStore: { try $1.deleteCloudSyncMetadata(entityType: $0.entityType, localId: uuid($0.localId)) }
        ))
    }
}
