import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - RadioMacroSnapshot

/// A `Sendable`, value-type projection of one radio macro, used to compare the
/// SwiftData and Rust backends field-for-field. Mirrors `FfiRadioMacro` exactly so a
/// round-trip through cw-store can be verified column-by-column (including the
/// JSON-blob columns, which are copied verbatim).
public struct RadioMacroSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiRadioMacro) {
        id = ffi.id
        name = ffi.name
        icon = ffi.icon
        macroDescription = ffi.macroDescription
        tagsCsv = ffi.tagsCsv
        appliesToCsv = ffi.appliesToCsv
        author = ffi.author
        argsJson = ffi.argsJson
        stepsJson = ffi.stepsJson
        capabilitiesJson = ffi.capabilitiesJson
        registryJson = ffi.registryJson
        format = ffi.format
        sortOrder = ffi.sortOrder
        createdAt = ffi.createdAt
        updatedAt = ffi.updatedAt
        tombstoned = ffi.tombstoned
        tombstoneReason = ffi.tombstoneReason
        cloudDirtyFlag = ffi.cloudDirtyFlag
    }

    // MARK: Public

    public let id: String
    public let name: String
    public let icon: String?
    public let macroDescription: String?
    public let tagsCsv: String
    public let appliesToCsv: String
    public let author: String?
    public let argsJson: Data
    public let stepsJson: Data
    public let capabilitiesJson: Data
    public let registryJson: Data
    public let format: Int64
    public let sortOrder: Int64
    public let createdAt: Int64
    public let updatedAt: Int64
    public let tombstoned: Bool
    public let tombstoneReason: String?
    public let cloudDirtyFlag: Bool
}

// MARK: - RadioMacroReadSource

/// Reads RadioMacro records — the total count and the full, id-ordered list.
public protocol RadioMacroReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [RadioMacroSnapshot]
}

// MARK: - SwiftDataRadioMacroReadSource

/// Reads RadioMacro from a SwiftData `ModelContext`. Snapshots are produced via the
/// canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison against
/// the Rust backend is a faithful round-trip check (no duplicated field logic).
/// `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataRadioMacroReadSource: @unchecked Sendable, RadioMacroReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<RadioMacro>())
    }

    public func all() async throws -> [RadioMacroSnapshot] {
        try context.fetch(FetchDescriptor<RadioMacro>())
            .map { RadioMacroSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustRadioMacroReadSource

/// Reads RadioMacro from a `FieldStore` (Rust backend).
public struct RustRadioMacroReadSource: RadioMacroReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.radioMacroCount())
    }

    public func all() async throws -> [RadioMacroSnapshot] {
        // `dirtyOnly: false` and `tombstoned: nil` => match every row (no filter).
        let filter = FfiRadioMacroFilter(tombstoned: nil, dirtyOnly: false)
        return try store.fetchRadioMacros(filter: filter, limit: Self.listBound, offset: 0)
            .map(RadioMacroSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; the macro library is a
    /// few dozen rows, so this is ample.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
