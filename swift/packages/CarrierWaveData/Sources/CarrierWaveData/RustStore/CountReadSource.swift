import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - CountReadSource

/// A source that can report the total count of one entity. The read cutover for
/// each entity starts by proving this total-count invariant (the pattern QSO
/// took). QSO, LoggingSession, and ServicePresence have dedicated read sources
/// because they grow richer (query/snapshot) capabilities; the remaining nine
/// peripheral entities share this generic backbone — one SwiftData impl over
/// `PersistentModel` and one Rust impl over a `FieldStore` count method.
public protocol CountReadSource: Sendable {
    func count() async throws -> Int
}

// MARK: - SwiftDataCountReadSource

/// Counts rows of `Model` in a SwiftData `ModelContext`. `ModelContext` is not
/// `Sendable`; this omits the conformance and uses an `@unchecked Sendable`
/// witness — callers should pin it to `@MainActor` (as the tests do).
public struct SwiftDataCountReadSource<Model: PersistentModel>: @unchecked Sendable, CountReadSource {
    // MARK: Lifecycle

    public init(_: Model.Type, context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustCountReadSource

/// Counts rows of one entity in a `FieldStore` (Rust backend). The per-entity
/// `FieldStore` count method is supplied by the static factories below so call
/// sites stay discoverable and the right FFI method is wired once.
public struct RustCountReadSource: CountReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore, counter: @escaping @Sendable (FieldStore) throws -> Int64) {
        self.store = store
        self.counter = counter
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(counter(store))
    }

    // MARK: Private

    private let store: FieldStore
    private let counter: @Sendable (FieldStore) throws -> Int64
}

// MARK: - RustCountReadSource per-entity factories

public extension RustCountReadSource {
    static func activationMetadata(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.activationMetadataCount() }
    }

    static func activityLog(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.activityLogCount() }
    }

    static func cloudSyncMetadata(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.cloudSyncMetadataCount() }
    }

    static func equipmentItem(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.equipmentItemCount() }
    }

    static func radioMacro(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.radioMacroCount() }
    }

    static func sessionSpot(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.sessionSpotCount() }
    }

    static func uploadDestination(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.uploadDestinationCount() }
    }

    static func websdrFavorite(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.websdrFavoriteCount() }
    }

    static func websdrRecording(store: FieldStore) -> RustCountReadSource {
        RustCountReadSource(store: store) { try $0.websdrRecordingCount() }
    }
}
