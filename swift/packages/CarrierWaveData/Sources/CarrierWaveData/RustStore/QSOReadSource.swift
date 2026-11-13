import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - CwStoreQSOMode

/// Rollout state for serving QSO reads from the Rust store. Stored in
/// `@AppStorage("cwStoreQSOMode")`. SwiftData is always the system of record.
public enum CwStoreQSOMode: String, CaseIterable, Sendable {
    case off // today's behavior; mirror not observing
    case shadow // mirror dual-writes; reads from SwiftData + compared to Rust
    case on // mirror dual-writes; reads served from Rust

    // MARK: Public

    public static let appStorageKey = "cwStoreQSOMode"

    /// The current rollout state read from `UserDefaults` (the backing store for
    /// the `@AppStorage("cwStoreQSOMode")` toggle). Lets non-View code (the write
    /// seam, `LoggingSessionManager`) route by mode without a SwiftUI binding.
    ///
    /// Default is `.on` on **iOS only** (Phase 1c): QSO reads + the CloudKit
    /// journal's QSO store-access run on the Rust store unless the user explicitly
    /// picks another mode. Pairs with `.rustStoreQSO` graduating to default-on; the
    /// picker in Settings → Experiments is the kill switch back to `.off`.
    ///
    /// macOS (CW Sweep) is `.on` by default too (2026-10-05): its writes go
    /// through the shared seams (cw-store first), and server-sync pulls are
    /// replicated into its SwiftData follower by `SwiftDataSyncReplica`, so
    /// the UI — which still reads SwiftData — sees inbound rows. The
    /// `cwStoreQSOMode` default is the kill switch back to `.off`.
    public static var current: CwStoreQSOMode {
        guard let raw = UserDefaults.standard.string(forKey: appStorageKey),
              let mode = CwStoreQSOMode(rawValue: raw)
        else {
            return .on
        }
        return mode
    }
}

// MARK: - QSOReadSource

/// A source that can report the total count of QSO records.
public protocol QSOReadSource: Sendable {
    func count() async throws -> Int
}

// MARK: - SwiftDataQSOReadSource

/// Reads the QSO count from a SwiftData `ModelContext`.
/// `ModelContext` is not `Sendable`; this struct omits the `: Sendable` conformance
/// and instead satisfies the protocol via an `@unchecked Sendable` witness. Callers
/// that hold `SwiftDataQSOReadSource` should pin it to `@MainActor` (as shown in tests).
public struct SwiftDataQSOReadSource: @unchecked Sendable, QSOReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        let descriptor = FetchDescriptor<QSO>()
        return try context.fetchCount(descriptor)
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - QSOQueryReadSource

/// Extended read capability available only on `RustQSOReadSource`.
/// `SwiftDataQSOReadSource` cannot satisfy this protocol in the package
/// because query compilation requires the app-target `QueryCompiler`.
public protocol QSOQueryReadSource: Sendable {
    func count(query: String) async throws -> Int
    func page(query: String, limit: Int, offset: Int) async throws -> [QSORowSnapshot]
}

// MARK: - RustQSOReadSource

/// Reads QSO records from a `FieldStore` (Rust backend).
public struct RustQSOReadSource: QSOReadSource, QSOQueryReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.qsoCount())
    }

    public func count(query: String) async throws -> Int {
        try Int(store.qsoCountQuery(query: query))
    }

    public func page(query: String, limit: Int, offset: Int) async throws -> [QSORowSnapshot] {
        try store.fetchQsosQuery(query: query, limit: Int64(limit), offset: Int64(offset))
            .map(QSORowSnapshot.init(ffi:))
    }

    // MARK: Private

    private let store: FieldStore
}
