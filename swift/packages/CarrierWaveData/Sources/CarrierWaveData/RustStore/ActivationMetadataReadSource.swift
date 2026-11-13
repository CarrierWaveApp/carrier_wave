import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - ActivationMetadataSnapshot

/// A `Sendable`, value-type projection of one activation-metadata row, used to
/// compare the SwiftData and Rust backends field-for-field. Mirrors
/// `FfiActivationMetadata` exactly so a round-trip through cw-store can be verified
/// column-by-column. The table has no surface `id`; rows are keyed by the composite
/// `(parkReference, date)`, which is also the stable ordering key.
public struct ActivationMetadataSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(ffi: FfiActivationMetadata) {
        parkReference = ffi.parkReference
        date = ffi.date
        title = ffi.title
        watts = ffi.watts
        weather = ffi.weather
        solarConditions = ffi.solarConditions
        averageWpm = ffi.averageWpm
        solarKIndex = ffi.solarKIndex
        solarFlux = ffi.solarFlux
        solarSunspots = ffi.solarSunspots
        solarPropagationRating = ffi.solarPropagationRating
        solarAIndex = ffi.solarAIndex
        solarBandConditions = ffi.solarBandConditions
        solarTimestamp = ffi.solarTimestamp
        weatherTemperatureF = ffi.weatherTemperatureF
        weatherTemperatureC = ffi.weatherTemperatureC
        weatherHumidity = ffi.weatherHumidity
        weatherWindSpeed = ffi.weatherWindSpeed
        weatherWindDirection = ffi.weatherWindDirection
        weatherDescription = ffi.weatherDescription
        weatherTimestamp = ffi.weatherTimestamp
        cloudDirtyFlag = ffi.cloudDirtyFlag
    }

    // MARK: Public

    public let parkReference: String
    public let date: Int64
    public let title: String?
    public let watts: Int64?
    public let weather: String?
    public let solarConditions: String?
    public let averageWpm: Int64?
    public let solarKIndex: Double?
    public let solarFlux: Double?
    public let solarSunspots: Int64?
    public let solarPropagationRating: String?
    public let solarAIndex: Int64?
    public let solarBandConditions: String?
    public let solarTimestamp: Int64?
    public let weatherTemperatureF: Double?
    public let weatherTemperatureC: Double?
    public let weatherHumidity: Int64?
    public let weatherWindSpeed: Double?
    public let weatherWindDirection: String?
    public let weatherDescription: String?
    public let weatherTimestamp: Int64?
    public let cloudDirtyFlag: Bool
}

// MARK: - ActivationMetadataReadSource

/// Reads ActivationMetadata records — the total count and the full list ordered by
/// the composite `(parkReference, date)` key.
public protocol ActivationMetadataReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [ActivationMetadataSnapshot]
}

// MARK: - SwiftDataActivationMetadataReadSource

/// Reads ActivationMetadata from a SwiftData `ModelContext`. Snapshots are produced
/// via the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataActivationMetadataReadSource: @unchecked Sendable, ActivationMetadataReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<ActivationMetadata>())
    }

    public func all() async throws -> [ActivationMetadataSnapshot] {
        try context.fetch(FetchDescriptor<ActivationMetadata>())
            .map { ActivationMetadataSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { ($0.parkReference, $0.date) < ($1.parkReference, $1.date) }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustActivationMetadataReadSource

/// Reads ActivationMetadata from a `FieldStore` (Rust backend).
public struct RustActivationMetadataReadSource: ActivationMetadataReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.activationMetadataCount())
    }

    public func all() async throws -> [ActivationMetadataSnapshot] {
        let filter = FfiActivationMetadataFilter(since: nil)
        return try store.fetchActivationMetadatas(filter: filter, limit: Self.listBound, offset: 0)
            .map(ActivationMetadataSnapshot.init(ffi:))
            .sorted { ($0.parkReference, $0.date) < ($1.parkReference, $1.date) }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows; one row per park-day,
    /// well within the bound for a single fetch.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
