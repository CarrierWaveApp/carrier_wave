import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - WebSDRFavoriteSnapshot

/// A `Sendable`, value-type projection of one favorited KiwiSDR receiver, used to
/// compare the SwiftData and Rust backends field-for-field. Mirrors
/// `FfiWebSdrFavorite` exactly so a round-trip through cw-store can be verified
/// column-by-column. The table has no surface `id`; rows are keyed by the unique
/// `hostPort`, which is also the stable ordering key.
public struct WebSDRFavoriteSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiWebSdrFavorite) {
        hostPort = ffi.hostPort
        displayName = ffi.displayName
        location = ffi.location
        antenna = ffi.antenna
        addedDate = ffi.addedDate
    }

    // MARK: Public

    public let hostPort: String
    public let displayName: String
    public let location: String
    public let antenna: String?
    public let addedDate: Int64
}

// MARK: - WebSDRFavoriteReadSource

/// Reads WebSDRFavorite records — the total count and the full,
/// `hostPort`-ordered list.
public protocol WebSDRFavoriteReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [WebSDRFavoriteSnapshot]
}

// MARK: - SwiftDataWebSDRFavoriteReadSource

/// Reads WebSDRFavorite from a SwiftData `ModelContext`. Snapshots are produced via
/// the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataWebSDRFavoriteReadSource: @unchecked Sendable, WebSDRFavoriteReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<WebSDRFavorite>())
    }

    public func all() async throws -> [WebSDRFavoriteSnapshot] {
        try context.fetch(FetchDescriptor<WebSDRFavorite>())
            .map { WebSDRFavoriteSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.hostPort < $1.hostPort }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustWebSDRFavoriteReadSource

/// Reads WebSDRFavorite from a `FieldStore` (Rust backend).
public struct RustWebSDRFavoriteReadSource: WebSDRFavoriteReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.websdrFavoriteCount())
    }

    public func all() async throws -> [WebSDRFavoriteSnapshot] {
        try store.fetchWebsdrFavorites(limit: Self.listBound, offset: 0)
            .map(WebSDRFavoriteSnapshot.init(ffi:))
            .sorted { $0.hostPort < $1.hostPort }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; the favorites table is
    /// ~20 rows max, so this is ample.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
