import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ServicePresenceReadSource

/// A source that can report the total count of ServicePresence records. Presence
/// is already projected onto Logbook rows on the QSO read path (slice B); this
/// standalone source backs the ServicePresence write-seam's count-parity check
/// (the sync-upload marking path mutates presence without going through a QSO
/// write), mirroring how `QSOReadSource`/`LoggingSessionReadSource` start.
public protocol ServicePresenceReadSource: Sendable {
    func count() async throws -> Int
}

// MARK: - SwiftDataServicePresenceReadSource

/// Reads the ServicePresence count from a SwiftData `ModelContext`.
/// `ModelContext` is not `Sendable`; this struct omits the `: Sendable`
/// conformance and instead satisfies the protocol via an `@unchecked Sendable`
/// witness. Callers that hold it should pin it to `@MainActor` (as the tests do).
public struct SwiftDataServicePresenceReadSource: @unchecked Sendable, ServicePresenceReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        let descriptor = FetchDescriptor<ServicePresence>()
        return try context.fetchCount(descriptor)
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustServicePresenceReadSource

/// Reads ServicePresence records from a `FieldStore` (Rust backend).
public struct RustServicePresenceReadSource: ServicePresenceReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.servicePresenceCount())
    }

    // MARK: Private

    private let store: FieldStore
}
