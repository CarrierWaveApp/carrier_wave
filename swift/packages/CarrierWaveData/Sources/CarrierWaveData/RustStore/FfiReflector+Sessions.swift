import CarrierWaveCore
import Foundation
import SwiftData

// `function_body_length` is disabled for the same reason as in `FfiReflector.swift`:
// the LoggingSession field map is a wide, inherent 75-column copy; splitting it
// would obscure, not clarify.
// swiftlint:disable function_body_length

// MARK: - Session-side reflection (LoggingSession / SessionSpot / ActivationMetadata)

/// The session-entity half of the reverse reflector (C2). Same contract as the
/// hunter-side overloads: in-place update preserving `@Observable` identity (the
/// manager holds `activeSession`), or hydrated insert, saved mirror-suppressed.
extension FfiReflector {
    // MARK: Public

    /// `LoggingSession`. Inverse of `project(_ session: LoggingSession)`. Built via
    /// the minimal initializer (only `myCallsign` is required) then every column
    /// set directly, bypassing the init's `programs`/`activationType` derivation so
    /// `programsRawValue` / `activationTypeRawValue` round-trip verbatim.
    nonisolated public static func hydrate(_ ffi: FfiLoggingSession) -> LoggingSession {
        let session = LoggingSession(myCallsign: ffi.myCallsign)
        session.id = UUID(uuidString: ffi.id) ?? session.id
        applyFields(ffi, to: session)
        return session
    }

    /// Reflect a `LoggingSession` record into the SwiftData replica. In-place
    /// update (never delete+insert) so a held `activeSession` reference and any
    /// SwiftUI observation survive. Saved mirror-suppressed.
    @MainActor
    public static func reflect(
        _ ffi: FfiLoggingSession,
        into context: ModelContext,
        mirror: CwStoreMirror?
    ) throws -> LoggingSession {
        let model: LoggingSession
        if let id = UUID(uuidString: ffi.id), let existing = fetchLoggingSession(id: id, in: context) {
            applyFields(ffi, to: existing)
            model = existing
        } else {
            model = hydrate(ffi)
            context.insert(model)
        }
        mirror?.beginSeamWrite(for: context)
        defer { mirror?.endSeamWrite(for: context) }
        try context.save()
        return model
    }

    /// `RoveStop` values from structured `rove_stop` rows — the read-back half of
    /// the table cutover. Inverse of `SwiftDataStoreImporter.projectRoveStops`;
    /// the caller re-embeds the result into the session's transitional blob.
    nonisolated public static func hydrateRoveStops(_ rows: [FfiRoveStop]) -> [RoveStop] {
        rows.map { row in
            RoveStop(
                id: UUID(uuidString: row.id) ?? UUID(),
                parkReference: row.parkReference,
                startedAt: Date(timeIntervalSince1970: TimeInterval(row.startedAt)),
                endedAt: row.endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                myGrid: row.myGrid,
                qsoCount: Int(row.qsoCount),
                notes: row.notes
            )
        }
    }

    /// `SessionSpot`. Inverse of `project(_ spot: SessionSpot)`. The initializer
    /// generates a fresh `id`; it is overwritten with the record's id.
    nonisolated public static func hydrate(_ ffi: FfiSessionSpot) -> SessionSpot {
        let spot = SessionSpot(
            loggingSessionId: UUID(uuidString: ffi.loggingSessionId) ?? UUID(),
            callsign: ffi.callsign,
            frequencyKHz: ffi.frequencyKHz,
            mode: ffi.mode,
            timestamp: Date(timeIntervalSince1970: TimeInterval(ffi.timestamp)),
            source: ffi.source,
            snr: ffi.snr.map(Int.init),
            wpm: ffi.wpm.map(Int.init),
            spotter: ffi.spotter,
            spotterGrid: ffi.spotterGrid,
            parkRef: ffi.parkRef,
            parkName: ffi.parkName,
            comments: ffi.comments,
            region: ffi.region,
            distanceMeters: ffi.distanceMeters,
            bearingDegrees: ffi.bearingDegrees
        )
        spot.id = UUID(uuidString: ffi.id) ?? spot.id
        spot.cloudDirtyFlag = ffi.cloudDirtyFlag
        return spot
    }

    /// Reflect a `SessionSpot` record into the SwiftData replica (in-place update
    /// or hydrated insert), saved mirror-suppressed.
    @MainActor
    public static func reflect(
        _ ffi: FfiSessionSpot,
        into context: ModelContext,
        mirror: CwStoreMirror?
    ) throws -> SessionSpot {
        let model: SessionSpot
        if let id = UUID(uuidString: ffi.id), let existing = fetchSessionSpot(id: id, in: context) {
            applyFields(ffi, to: existing)
            model = existing
        } else {
            model = hydrate(ffi)
            context.insert(model)
        }
        mirror?.beginSeamWrite(for: context)
        defer { mirror?.endSeamWrite(for: context) }
        try context.save()
        return model
    }

    /// `ActivationMetadata`. Inverse of `project(_ metadata: ActivationMetadata)`.
    /// The initializer normalises `date` to UTC midnight; the record's `date` is
    /// already midnight, so it round-trips.
    nonisolated public static func hydrate(_ ffi: FfiActivationMetadata) -> ActivationMetadata {
        let metadata = ActivationMetadata(
            parkReference: ffi.parkReference,
            date: Date(timeIntervalSince1970: TimeInterval(ffi.date)),
            title: ffi.title,
            watts: ffi.watts.map(Int.init),
            weather: ffi.weather,
            solarConditions: ffi.solarConditions,
            averageWPM: ffi.averageWpm.map(Int.init)
        )
        applyConditionFields(ffi, to: metadata)
        return metadata
    }

    /// Reflect an `ActivationMetadata` record into the SwiftData replica. The Ffi
    /// record has no id — identity is `(parkReference, UTC-midnight date)`, the
    /// same key the Rust core upserts by. In-place update or hydrated insert,
    /// saved mirror-suppressed.
    @MainActor
    public static func reflect(
        _ ffi: FfiActivationMetadata,
        into context: ModelContext,
        mirror: CwStoreMirror?
    ) throws -> ActivationMetadata {
        let model: ActivationMetadata
        let date = Date(timeIntervalSince1970: TimeInterval(ffi.date))
        if let existing = fetchActivationMetadata(
            parkReference: ffi.parkReference, date: date, in: context
        ) {
            model = existing
            model.title = ffi.title
            model.watts = ffi.watts.map(Int.init)
            model.weather = ffi.weather
            model.solarConditions = ffi.solarConditions
            model.averageWPM = ffi.averageWpm.map(Int.init)
            applyConditionFields(ffi, to: model)
        } else {
            model = hydrate(ffi)
            context.insert(model)
        }
        mirror?.beginSeamWrite(for: context)
        defer { mirror?.endSeamWrite(for: context) }
        try context.save()
        return model
    }

    // MARK: Private

    /// The existing `LoggingSession` with this id in `context`, or nil.
    @MainActor
    private static func fetchLoggingSession(id: UUID, in context: ModelContext) -> LoggingSession? {
        var descriptor = FetchDescriptor<LoggingSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The existing `SessionSpot` with this id in `context`, or nil.
    @MainActor
    private static func fetchSessionSpot(id: UUID, in context: ModelContext) -> SessionSpot? {
        var descriptor = FetchDescriptor<SessionSpot>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The existing `ActivationMetadata` for this park + UTC-midnight date, or nil.
    @MainActor
    private static func fetchActivationMetadata(
        parkReference: String, date: Date, in context: ModelContext
    ) -> ActivationMetadata? {
        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.parkReference == parkReference && $0.date == date }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// In-place field copy for `LoggingSession` (`id` is the key and stays put).
    /// Every column the projection carries, applied verbatim — shared by `hydrate`
    /// and the in-place update path of `reflect`.
    nonisolated private static func applyFields(_ ffi: FfiLoggingSession, to session: LoggingSession) {
        session.myCallsign = ffi.myCallsign
        session.startedAt = Date(timeIntervalSince1970: TimeInterval(ffi.startedAt))
        session.endedAt = ffi.endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        session.frequency = ffi.frequency
        session.mode = ffi.mode
        session.activationTypeRawValue = ffi.activationTypeRawValue
        session.programsRawValue = ffi.programsRawValue
        session.statusRawValue = ffi.statusRawValue
        session.parkReference = ffi.parkReference
        session.sotaReference = ffi.sotaReference
        session.missionReference = ffi.missionReference
        session.wwffReference = ffi.wwffReference
        session.myGrid = ffi.myGrid
        session.power = ffi.power.map(Int.init)
        session.myRig = ffi.myRig
        session.notes = ffi.notes
        session.qsoComment = ffi.qsoComment
        session.customTitle = ffi.customTitle
        session.qsoCount = Int(ffi.qsoCount)
        session.spotCommentsData = ffi.spotCommentsData
        session.isRove = ffi.isRove
        session.roveStopsData = ffi.roveStopsData
        session.myAntenna = ffi.myAntenna
        session.myKey = ffi.myKey
        session.myMic = ffi.myMic
        session.extraEquipment = ffi.extraEquipment
        session.attendees = ffi.attendees
        session.photoFilenames = decodeStringArray(ffi.photoFilenames)
        session.radioItemID = ffi.radioItemId.flatMap { UUID(uuidString: $0) }
        session.stationCallsign = ffi.stationCallsign
        session.operatorCallsignsRawValue = ffi.operatorCallsignsRawValue
        session.solarKIndex = ffi.solarKIndex
        session.solarFlux = ffi.solarFlux
        session.solarSunspots = ffi.solarSunspots.map(Int.init)
        session.solarPropagationRating = ffi.solarPropagationRating
        session.solarAIndex = ffi.solarAIndex.map(Int.init)
        session.solarBandConditions = ffi.solarBandConditions
        session.solarTimestamp = ffi.solarTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        session.solarConditions = ffi.solarConditions
        session.weatherTemperatureF = ffi.weatherTemperatureF
        session.weatherTemperatureC = ffi.weatherTemperatureC
        session.weatherHumidity = ffi.weatherHumidity.map(Int.init)
        session.weatherWindSpeed = ffi.weatherWindSpeed
        session.weatherWindDirection = ffi.weatherWindDirection
        session.weatherDescription = ffi.weatherDescription
        session.weatherTimestamp = ffi.weatherTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        session.weather = ffi.weather
        session.cloudDirtyFlag = ffi.cloudDirtyFlag
        session.contestId = ffi.contestId
        session.contestCategory = ffi.contestCategory
        session.contestOverlayCategory = ffi.contestOverlayCategory
        session.contestPower = ffi.contestPower
        session.contestBands = ffi.contestBands
        session.contestOperator = ffi.contestOperator
        session.activationLatitude = ffi.activationLatitude
        session.activationLongitude = ffi.activationLongitude
        session.activationDistanceMiles = ffi.activationDistanceMiles
        session.activationElevationGainFeet = ffi.activationElevationGainFeet
        session.ruckWeightPounds = ffi.ruckWeightPounds
        session.qrpActivation = ffi.qrpActivation
        session.withPets = ffi.withPets
        session.withKids = ffi.withKids
        session.winlinkSent = ffi.winlinkSent
        session.aprsSent = ffi.aprsSent
        session.varacSent = ffi.varacSent
        session.adaptiveSport = ffi.adaptiveSport
        session.trackPointsData = ffi.trackPointsData
        session.totaCategoryRawValue = ffi.totaCategoryRawValue
        session.personalEffortFactor = ffi.personalEffortFactor.map(Int.init)
        session.firstActivationOfTileEver = ffi.firstActivationOfTileEver
        session.winterActivationOverride = ffi.winterActivationOverride.map { $0 != 0 }
        session.tilesActivatedData = ffi.tilesActivatedData
        session.totaT3CandidatesData = ffi.totaT3CandidatesData
        session.totaT3SnapshotAt = ffi.totaT3SnapshotAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        session.totaOfficialPoints = ffi.totaOfficialPoints
    }

    /// Decode a JSON `[String]` column (inverse of the projection's `jsonStringArray`).
    nonisolated private static func decodeStringArray(_ json: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(json.utf8))) ?? []
    }

    /// In-place field copy for `SessionSpot` (`id` is the key and stays put).
    /// Mirrors `hydrate(_ ffi: FfiSessionSpot)`.
    nonisolated private static func applyFields(_ ffi: FfiSessionSpot, to spot: SessionSpot) {
        spot.loggingSessionId = UUID(uuidString: ffi.loggingSessionId) ?? spot.loggingSessionId
        spot.callsign = ffi.callsign
        spot.frequencyKHz = ffi.frequencyKHz
        spot.mode = ffi.mode
        spot.timestamp = Date(timeIntervalSince1970: TimeInterval(ffi.timestamp))
        spot.source = ffi.source
        spot.snr = ffi.snr.map(Int.init)
        spot.wpm = ffi.wpm.map(Int.init)
        spot.spotter = ffi.spotter
        spot.spotterGrid = ffi.spotterGrid
        spot.parkRef = ffi.parkRef
        spot.parkName = ffi.parkName
        spot.comments = ffi.comments
        spot.region = ffi.region
        spot.distanceMeters = ffi.distanceMeters
        spot.bearingDegrees = ffi.bearingDegrees
        spot.cloudDirtyFlag = ffi.cloudDirtyFlag
    }

    /// The solar/weather condition block shared by `hydrate` and the in-place
    /// update path of `reflect` for `ActivationMetadata`.
    nonisolated private static func applyConditionFields(
        _ ffi: FfiActivationMetadata, to metadata: ActivationMetadata
    ) {
        metadata.solarKIndex = ffi.solarKIndex
        metadata.solarFlux = ffi.solarFlux
        metadata.solarSunspots = ffi.solarSunspots.map(Int.init)
        metadata.solarPropagationRating = ffi.solarPropagationRating
        metadata.solarAIndex = ffi.solarAIndex.map(Int.init)
        metadata.solarBandConditions = ffi.solarBandConditions
        metadata.solarTimestamp = ffi.solarTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        metadata.weatherTemperatureF = ffi.weatherTemperatureF
        metadata.weatherTemperatureC = ffi.weatherTemperatureC
        metadata.weatherHumidity = ffi.weatherHumidity.map(Int.init)
        metadata.weatherWindSpeed = ffi.weatherWindSpeed
        metadata.weatherWindDirection = ffi.weatherWindDirection
        metadata.weatherDescription = ffi.weatherDescription
        metadata.weatherTimestamp = ffi.weatherTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        metadata.cloudDirtyFlag = ffi.cloudDirtyFlag
    }
}
