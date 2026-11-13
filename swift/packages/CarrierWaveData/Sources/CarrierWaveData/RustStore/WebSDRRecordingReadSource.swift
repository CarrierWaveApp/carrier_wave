import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - WebSDRRecordingSnapshot

/// A `Sendable`, value-type projection of one WebSDR recording, used to compare the
/// SwiftData and Rust backends field-for-field. Mirrors `FfiWebSdrRecording` exactly
/// so a round-trip through cw-store can be verified column-by-column.
public struct WebSDRRecordingSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiWebSdrRecording) {
        id = ffi.id
        loggingSessionId = ffi.loggingSessionId
        kiwisdrHost = ffi.kiwisdrHost
        kiwisdrName = ffi.kiwisdrName
        startedAt = ffi.startedAt
        endedAt = ffi.endedAt
        frequencyKHz = ffi.frequencyKHz
        mode = ffi.mode
        relativeFilePath = ffi.relativeFilePath
        fileSizeBytes = ffi.fileSizeBytes
        durationSeconds = ffi.durationSeconds
        isComplete = ffi.isComplete
        spotCallsign = ffi.spotCallsign
        spotParkRef = ffi.spotParkRef
        spotParkName = ffi.spotParkName
        spotSummitCode = ffi.spotSummitCode
        spotBand = ffi.spotBand
        isTuneInRecording = ffi.isTuneInRecording
        clipBookmarksData = ffi.clipBookmarksData
        parameterChangesData = ffi.parameterChangesData
    }

    // MARK: Public

    public let id: String
    public let loggingSessionId: String
    public let kiwisdrHost: String
    public let kiwisdrName: String
    public let startedAt: Int64
    public let endedAt: Int64?
    public let frequencyKHz: Double
    public let mode: String
    public let relativeFilePath: String
    public let fileSizeBytes: Int64
    public let durationSeconds: Double
    public let isComplete: Bool
    public let spotCallsign: String?
    public let spotParkRef: String?
    public let spotParkName: String?
    public let spotSummitCode: String?
    public let spotBand: String?
    public let isTuneInRecording: Bool
    public let clipBookmarksData: Data?
    public let parameterChangesData: Data?
}

// MARK: - WebSDRRecordingReadSource

/// Reads WebSDRRecording records — the total count and the full, id-ordered list.
public protocol WebSDRRecordingReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [WebSDRRecordingSnapshot]
}

// MARK: - SwiftDataWebSDRRecordingReadSource

/// Reads WebSDRRecording from a SwiftData `ModelContext`. Snapshots are produced via
/// the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataWebSDRRecordingReadSource: @unchecked Sendable, WebSDRRecordingReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<WebSDRRecording>())
    }

    public func all() async throws -> [WebSDRRecordingSnapshot] {
        try context.fetch(FetchDescriptor<WebSDRRecording>())
            .map { WebSDRRecordingSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustWebSDRRecordingReadSource

/// Reads WebSDRRecording from a `FieldStore` (Rust backend).
public struct RustWebSDRRecordingReadSource: WebSDRRecordingReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.websdrRecordingCount())
    }

    public func all() async throws -> [WebSDRRecordingSnapshot] {
        let filter = FfiWebSdrRecordingFilter(
            loggingSessionId: nil,
            isComplete: nil,
            isTuneInRecording: nil
        )
        return try store.fetchWebsdrRecordings(filter: filter, limit: Self.listBound, offset: 0)
            .map(WebSDRRecordingSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; recordings number a
    /// handful per session, well within the bound.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
