import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SessionSpotSnapshot

/// A `Sendable`, value-type projection of one session spot, used to compare the
/// SwiftData and Rust backends field-for-field. Mirrors `FfiSessionSpot` exactly so
/// a round-trip through cw-store can be verified column-by-column.
public struct SessionSpotSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiSessionSpot) {
        id = ffi.id
        loggingSessionId = ffi.loggingSessionId
        callsign = ffi.callsign
        frequencyKHz = ffi.frequencyKHz
        mode = ffi.mode
        timestamp = ffi.timestamp
        source = ffi.source
        snr = ffi.snr
        wpm = ffi.wpm
        spotter = ffi.spotter
        spotterGrid = ffi.spotterGrid
        parkRef = ffi.parkRef
        parkName = ffi.parkName
        comments = ffi.comments
        region = ffi.region
        distanceMeters = ffi.distanceMeters
        bearingDegrees = ffi.bearingDegrees
        cloudDirtyFlag = ffi.cloudDirtyFlag
    }

    // MARK: Public

    public let id: String
    public let loggingSessionId: String
    public let callsign: String
    public let frequencyKHz: Double
    public let mode: String
    public let timestamp: Int64
    public let source: String
    public let snr: Int64?
    public let wpm: Int64?
    public let spotter: String?
    public let spotterGrid: String?
    public let parkRef: String?
    public let parkName: String?
    public let comments: String?
    public let region: String
    public let distanceMeters: Double?
    public let bearingDegrees: Double?
    public let cloudDirtyFlag: Bool
}

// MARK: - SessionSpotReadSource

/// Reads SessionSpot records — the total count and the full, id-ordered list.
public protocol SessionSpotReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [SessionSpotSnapshot]
}

// MARK: - SwiftDataSessionSpotReadSource

/// Reads SessionSpot from a SwiftData `ModelContext`. Snapshots are produced via the
/// canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison against
/// the Rust backend is a faithful round-trip check (no duplicated field logic).
/// `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataSessionSpotReadSource: @unchecked Sendable, SessionSpotReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<SessionSpot>())
    }

    public func all() async throws -> [SessionSpotSnapshot] {
        try context.fetch(FetchDescriptor<SessionSpot>())
            .map { SessionSpotSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustSessionSpotReadSource

/// Reads SessionSpot from a `FieldStore` (Rust backend).
public struct RustSessionSpotReadSource: SessionSpotReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.sessionSpotCount())
    }

    public func all() async throws -> [SessionSpotSnapshot] {
        let filter = FfiSessionSpotFilter(loggingSessionId: nil, since: nil, dirtyOnly: false)
        return try store.fetchSessionSpots(filter: filter, limit: Self.listBound, offset: 0)
            .map(SessionSpotSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows. Session spots can be
    /// numerous over a long activation; this read source is for parity verification
    /// of the bounded window, not the live spot feed.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
