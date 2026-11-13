import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncAppliedChange

/// A row the inbound half of a server-sync pass touched (Sendable mirror of
/// the cw-ffi `SyncAppliedKey`).
public struct SyncAppliedChange: Equatable, Sendable {
    // MARK: Lifecycle

    public init(entity: Entity, id: String, deleted: Bool) {
        self.entity = entity
        self.id = id
        self.deleted = deleted
    }

    init(ffi: SyncAppliedKey) {
        entity = switch ffi.table {
        case .qso: .qso
        case .loggingSession: .loggingSession
        case .syncedConfig: .syncedConfig
        default: .other
        }
        id = ffi.id
        deleted = ffi.deleted
    }

    // MARK: Public

    public enum Entity: Equatable, Sendable {
        case qso
        case loggingSession
        case syncedConfig
        case other
    }

    public let entity: Entity
    public let id: String
    /// True only when the row no longer exists (session hard-delete). A QSO
    /// delete is a soft delete and arrives as an upsert with `isHidden` set.
    public let deleted: Bool
}

// MARK: - ServerSyncReplica

/// A host-side secondary copy of the store that must learn about rows a pull
/// applied. Installed by hosts whose UI still reads SwiftData (CW Sweep).
public protocol ServerSyncReplica: Sendable {
    func apply(_ changes: [SyncAppliedChange]) async
}

// MARK: - ServerSyncReplicaRegistry

public enum ServerSyncReplicaRegistry {
    // MARK: Public

    public static var current: (any ServerSyncReplica)? {
        holder.get()
    }

    public static func install(_ replica: (any ServerSyncReplica)?) {
        holder.set(replica)
    }

    // MARK: Private

    private final class Holder: @unchecked Sendable {
        // MARK: Internal

        func set(_ value: (any ServerSyncReplica)?) {
            lock.withLock { self.value = value }
        }

        func get() -> (any ServerSyncReplica)? {
            lock.withLock { value }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value: (any ServerSyncReplica)?
    }

    private static let holder = Holder()
}

// MARK: - SwiftDataSyncReplica

/// Replicates server-pulled rows from cw-store into a SwiftData container so
/// views that still read SwiftData see them. Runs off the main actor on its own
/// `ModelContext`; the save is mirror-suppressed so the follower write never
/// echoes back into cw-store. QSOs and logging sessions only (the entities the
/// server journal carries); `cloudDirtyFlag` is never set, so nothing re-pushes.
public final class SwiftDataSyncReplica: ServerSyncReplica {
    // MARK: Lifecycle

    public init(container: ModelContainer, store: FieldStore, mirror: CwStoreMirror?) {
        self.container = container
        self.store = store
        self.mirror = mirror
    }

    // MARK: Public

    /// Posted on the main queue after a replica save that changed something.
    public static let didApplyNotification = Notification.Name("ServerSyncReplicaDidApply")

    public func apply(_ changes: [SyncAppliedChange]) async {
        let relevant = changes.filter { $0.entity == .qso || $0.entity == .loggingSession }
        guard !relevant.isEmpty else {
            return
        }
        let container = container
        let store = store
        let mirror = mirror
        let applied: Int = await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            var touched = 0
            for change in relevant {
                do {
                    switch change.entity {
                    case .qso:
                        touched += try Self.applyQSO(change, store: store, context: context) ? 1 : 0
                    case .loggingSession:
                        touched += try Self.applySession(change, store: store, context: context) ? 1 : 0
                    default:
                        continue
                    }
                } catch {
                    ServerSyncLog.error("Replica: \(change.entity) \(change.id) failed: \(error.localizedDescription)")
                }
            }
            guard touched > 0 else {
                return 0
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            do {
                try context.save()
            } catch {
                ServerSyncLog.error("Replica: save failed: \(error.localizedDescription)")
                return 0
            }
            return touched
        }.value
        guard applied > 0 else {
            return
        }
        ServerSyncLog.info("Replica: applied \(applied) pulled row(s) into SwiftData")
        await MainActor.run {
            NotificationCenter.default.post(name: Self.didApplyNotification, object: nil)
        }
    }

    // MARK: Private

    private let container: ModelContainer
    private let store: FieldStore
    private let mirror: CwStoreMirror?

    private static func applyQSO(_ change: SyncAppliedChange, store: FieldStore, context: ModelContext) throws -> Bool {
        guard let ffi = try store.fetchQso(id: change.id), let fields = ffi.toQSOFields() else {
            return false
        }
        let qsoId = fields.id
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == qsoId })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first {
            fields.apply(to: existing)
        } else {
            context.insert(QSO.fromFields(fields))
        }
        return true
    }

    private static func applySession(
        _ change: SyncAppliedChange, store: FieldStore, context: ModelContext
    ) throws -> Bool {
        guard let sessionId = UUID(uuidString: change.id) else {
            return false
        }
        var descriptor = FetchDescriptor<LoggingSession>(predicate: #Predicate { $0.id == sessionId })
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        if change.deleted {
            guard let existing else {
                return false
            }
            context.delete(existing)
            return true
        }
        guard let ffi = try store.fetchLoggingSession(id: change.id),
              let fields = ffi.toLoggingSessionFields()
        else {
            return false
        }
        if let existing {
            fields.apply(to: existing)
        } else {
            context.insert(LoggingSession.fromFields(fields))
        }
        return true
    }
}
