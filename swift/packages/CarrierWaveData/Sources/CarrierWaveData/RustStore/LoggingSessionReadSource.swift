import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - LoggingSessionSnapshot

/// A `Sendable`, value-type projection of one logging session, used to compare the
/// SwiftData and Rust backends field-for-field. Mirrors `FfiLoggingSession` exactly
/// (all ~75 columns) so a round-trip through cw-store can be verified
/// column-by-column. LoggingSession is the most central non-QSO entity; a true
/// field + order parity check guards every view that reads it.
public struct LoggingSessionSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    // swiftlint:disable:next function_body_length
    public init(ffi: FfiLoggingSession) {
        id = ffi.id
        myCallsign = ffi.myCallsign
        startedAt = ffi.startedAt
        endedAt = ffi.endedAt
        frequency = ffi.frequency
        mode = ffi.mode
        activationTypeRawValue = ffi.activationTypeRawValue
        programsRawValue = ffi.programsRawValue
        statusRawValue = ffi.statusRawValue
        parkReference = ffi.parkReference
        sotaReference = ffi.sotaReference
        missionReference = ffi.missionReference
        wwffReference = ffi.wwffReference
        myGrid = ffi.myGrid
        power = ffi.power
        myRig = ffi.myRig
        notes = ffi.notes
        qsoComment = ffi.qsoComment
        customTitle = ffi.customTitle
        qsoCount = ffi.qsoCount
        spotCommentsData = ffi.spotCommentsData
        isRove = ffi.isRove
        roveStopsData = ffi.roveStopsData
        myAntenna = ffi.myAntenna
        myKey = ffi.myKey
        myMic = ffi.myMic
        extraEquipment = ffi.extraEquipment
        attendees = ffi.attendees
        photoFilenames = ffi.photoFilenames
        radioItemId = ffi.radioItemId
        stationCallsign = ffi.stationCallsign
        operatorCallsignsRawValue = ffi.operatorCallsignsRawValue
        solarKIndex = ffi.solarKIndex
        solarFlux = ffi.solarFlux
        solarSunspots = ffi.solarSunspots
        solarPropagationRating = ffi.solarPropagationRating
        solarAIndex = ffi.solarAIndex
        solarBandConditions = ffi.solarBandConditions
        solarTimestamp = ffi.solarTimestamp
        solarConditions = ffi.solarConditions
        weatherTemperatureF = ffi.weatherTemperatureF
        weatherTemperatureC = ffi.weatherTemperatureC
        weatherHumidity = ffi.weatherHumidity
        weatherWindSpeed = ffi.weatherWindSpeed
        weatherWindDirection = ffi.weatherWindDirection
        weatherDescription = ffi.weatherDescription
        weatherTimestamp = ffi.weatherTimestamp
        weather = ffi.weather
        cloudDirtyFlag = ffi.cloudDirtyFlag
        contestId = ffi.contestId
        contestCategory = ffi.contestCategory
        contestOverlayCategory = ffi.contestOverlayCategory
        contestPower = ffi.contestPower
        contestBands = ffi.contestBands
        contestOperator = ffi.contestOperator
        activationLatitude = ffi.activationLatitude
        activationLongitude = ffi.activationLongitude
        activationDistanceMiles = ffi.activationDistanceMiles
        activationElevationGainFeet = ffi.activationElevationGainFeet
        ruckWeightPounds = ffi.ruckWeightPounds
        qrpActivation = ffi.qrpActivation
        withPets = ffi.withPets
        withKids = ffi.withKids
        winlinkSent = ffi.winlinkSent
        aprsSent = ffi.aprsSent
        varacSent = ffi.varacSent
        adaptiveSport = ffi.adaptiveSport
        trackPointsData = ffi.trackPointsData
        totaCategoryRawValue = ffi.totaCategoryRawValue
        personalEffortFactor = ffi.personalEffortFactor
        firstActivationOfTileEver = ffi.firstActivationOfTileEver
        winterActivationOverride = ffi.winterActivationOverride
        tilesActivatedData = ffi.tilesActivatedData
        totaT3CandidatesData = ffi.totaT3CandidatesData
        totaT3SnapshotAt = ffi.totaT3SnapshotAt
        totaOfficialPoints = ffi.totaOfficialPoints
    }

    // MARK: Public

    public let id: String
    public let myCallsign: String
    public let startedAt: Int64
    public let endedAt: Int64?
    public let frequency: Double?
    public let mode: String
    public let activationTypeRawValue: String
    public let programsRawValue: String
    public let statusRawValue: String
    public let parkReference: String?
    public let sotaReference: String?
    public let missionReference: String?
    public let wwffReference: String?
    public let myGrid: String?
    public let power: Int64?
    public let myRig: String?
    public let notes: String?
    public let qsoComment: String?
    public let customTitle: String?
    public let qsoCount: Int64
    public let spotCommentsData: Data?
    public let isRove: Bool
    public let roveStopsData: Data?
    public let myAntenna: String?
    public let myKey: String?
    public let myMic: String?
    public let extraEquipment: String?
    public let attendees: String?
    public let photoFilenames: String
    public let radioItemId: String?
    public let stationCallsign: String?
    public let operatorCallsignsRawValue: String
    public let solarKIndex: Double?
    public let solarFlux: Double?
    public let solarSunspots: Int64?
    public let solarPropagationRating: String?
    public let solarAIndex: Int64?
    public let solarBandConditions: String?
    public let solarTimestamp: Int64?
    public let solarConditions: String?
    public let weatherTemperatureF: Double?
    public let weatherTemperatureC: Double?
    public let weatherHumidity: Int64?
    public let weatherWindSpeed: Double?
    public let weatherWindDirection: String?
    public let weatherDescription: String?
    public let weatherTimestamp: Int64?
    public let weather: String?
    public let cloudDirtyFlag: Bool
    public let contestId: String?
    public let contestCategory: String?
    public let contestOverlayCategory: String?
    public let contestPower: String?
    public let contestBands: String?
    public let contestOperator: String?
    public let activationLatitude: Double?
    public let activationLongitude: Double?
    public let activationDistanceMiles: Double?
    public let activationElevationGainFeet: Double?
    public let ruckWeightPounds: Double?
    public let qrpActivation: Bool
    public let withPets: Bool
    public let withKids: Bool
    public let winlinkSent: Bool
    public let aprsSent: Bool
    public let varacSent: Bool
    public let adaptiveSport: Bool
    public let trackPointsData: Data?
    public let totaCategoryRawValue: String?
    public let personalEffortFactor: Int64?
    public let firstActivationOfTileEver: Bool
    public let winterActivationOverride: Int64?
    public let tilesActivatedData: Data?
    public let totaT3CandidatesData: Data?
    public let totaT3SnapshotAt: Int64?
    public let totaOfficialPoints: Double?
}

// MARK: - LoggingSessionReadSource

/// Reads LoggingSession records — the total count and the full, id-ordered list.
/// The first slice of the cutover proved the total-count invariant; this adds the
/// field/order parity surface (mirroring how `QSOReadSource` and EquipmentItem
/// grew from `count()` to a full snapshot list).
public protocol LoggingSessionReadSource: Sendable {
    func count() async throws -> Int
    func all() async throws -> [LoggingSessionSnapshot]
}

// MARK: - SwiftDataLoggingSessionReadSource

/// Reads LoggingSession from a SwiftData `ModelContext`. Snapshots are produced via
/// the canonical `SwiftDataStoreImporter.project(_:)` mapping so the comparison
/// against the Rust backend is a faithful round-trip check (no duplicated field
/// logic). `ModelContext` is not `Sendable`; this omits the conformance and uses an
/// `@unchecked Sendable` witness — callers should pin it to `@MainActor`.
public struct SwiftDataLoggingSessionReadSource: @unchecked Sendable, LoggingSessionReadSource {
    // MARK: Lifecycle

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Public

    public func count() async throws -> Int {
        try context.fetchCount(FetchDescriptor<LoggingSession>())
    }

    public func all() async throws -> [LoggingSessionSnapshot] {
        try context.fetch(FetchDescriptor<LoggingSession>())
            .map { LoggingSessionSnapshot(ffi: SwiftDataStoreImporter.project($0)) }
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    private let context: ModelContext
}

// MARK: - RustLoggingSessionReadSource

/// Reads LoggingSession records from a `FieldStore` (Rust backend).
public struct RustLoggingSessionReadSource: LoggingSessionReadSource {
    // MARK: Lifecycle

    public init(store: FieldStore) {
        self.store = store
    }

    // MARK: Public

    public func count() async throws -> Int {
        try Int(store.loggingSessionCount())
    }

    public func all() async throws -> [LoggingSessionSnapshot] {
        // All-nil/`nil` fields => match every row (no filter).
        let filter = FfiLoggingSessionFilter(myCallsign: nil, since: nil, dirtyOnly: nil)
        return try store.fetchLoggingSessions(filter: filter, limit: Self.listBound, offset: 0)
            .map(LoggingSessionSnapshot.init(ffi:))
            .sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// Bounded scan. cw-store caps `fetch_*` at 1,000 rows. Sessions number in the
    /// hundreds for an active operator; the parity surface verifies the bounded
    /// window, while the live list paths page as needed.
    private static let listBound: Int64 = 1_000

    private let store: FieldStore
}
