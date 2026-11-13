import Foundation
import SwiftData

// MARK: - Field Extraction (Model → Sendable structs)

extension CloudSyncJournalEngine {
    func extractQSOFields(_ qso: QSO) -> QSOFields {
        QSOFields(
            id: qso.id,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            timestamp: qso.timestamp,
            rstSent: qso.rstSent,
            rstReceived: qso.rstReceived,
            myCallsign: qso.myCallsign,
            myGrid: qso.myGrid,
            theirGrid: qso.theirGrid,
            parkReference: qso.parkReference,
            theirParkReference: qso.theirParkReference,
            notes: qso.notes,
            importSource: qso.importSource,
            importedAt: qso.importedAt,
            modifiedAt: qso.modifiedAt,
            rawADIF: qso.rawADIF,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.power,
            myRig: qso.myRig,
            stationProfileName: qso.stationProfileName,
            sotaRef: qso.sotaRef,
            wwffRef: qso.wwffRef,
            qrzLogId: qso.qrzLogId,
            qrzConfirmed: qso.qrzConfirmed,
            lotwConfirmedDate: qso.lotwConfirmedDate,
            lotwConfirmed: qso.lotwConfirmed,
            dxcc: qso.dxcc,
            theirLicenseClass: qso.theirLicenseClass,
            isHidden: qso.isHidden,
            isActivityLogQSO: qso.isActivityLogQSO,
            loggingSessionId: qso.loggingSessionId,
            stationCallsign: qso.stationCallsign,
            spotCommentsData: qso.spotCommentsData,
            notesUserAuthored: qso.notesUserAuthored,
            satName: qso.satName,
            propMode: qso.propMode
        )
    }

    func extractServicePresenceFields(
        _ presence: ServicePresence, qsoID: UUID
    ) -> ServicePresenceFields {
        ServicePresenceFields(
            id: presence.id,
            serviceType: presence.serviceType,
            isPresent: presence.isPresent,
            needsUpload: presence.needsUpload,
            uploadRejected: presence.uploadRejected,
            rejectedAtBuild: presence.rejectedAtBuild,
            isSubmitted: presence.isSubmitted,
            lastConfirmedAt: presence.lastConfirmedAt,
            parkReference: presence.parkReference,
            qsoUUID: qsoID
        )
    }

    func extractLoggingSessionFields(
        _ session: LoggingSession
    ) -> LoggingSessionFields {
        LoggingSessionFields(
            id: session.id,
            myCallsign: session.myCallsign,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            frequency: session.frequency,
            mode: session.mode,
            activationTypeRawValue: session.activationTypeRawValue,
            statusRawValue: session.statusRawValue,
            parkReference: session.parkReference,
            sotaReference: session.sotaReference,
            wwffReference: session.wwffReference,
            myGrid: session.myGrid,
            power: session.power,
            myRig: session.myRig,
            notes: session.notes,
            qsoComment: session.qsoComment,
            customTitle: session.customTitle,
            qsoCount: session.qsoCount,
            isRove: session.isRove,
            myAntenna: session.myAntenna,
            myKey: session.myKey,
            myMic: session.myMic,
            extraEquipment: session.extraEquipment,
            attendees: session.attendees,
            photoFilenames: session.photoFilenames,
            spotCommentsData: session.spotCommentsData,
            roveStopsData: session.roveStopsData,
            solarKIndex: session.solarKIndex,
            solarFlux: session.solarFlux,
            solarSunspots: session.solarSunspots,
            solarPropagationRating: session.solarPropagationRating,
            solarAIndex: session.solarAIndex,
            solarBandConditions: session.solarBandConditions,
            solarTimestamp: session.solarTimestamp,
            solarConditions: session.solarConditions,
            weatherTemperatureF: session.weatherTemperatureF,
            weatherTemperatureC: session.weatherTemperatureC,
            weatherHumidity: session.weatherHumidity,
            weatherWindSpeed: session.weatherWindSpeed,
            weatherWindDirection: session.weatherWindDirection,
            weatherDescription: session.weatherDescription,
            weatherTimestamp: session.weatherTimestamp,
            weather: session.weather,
            stationCallsign: session.stationCallsign,
            operatorCallsignsRawValue: session.operatorCallsignsRawValue
        )
    }

    func extractSessionSpotFields(
        _ spot: SessionSpot
    ) -> SessionSpotFields {
        SessionSpotFields(
            id: spot.id,
            loggingSessionId: spot.loggingSessionId,
            callsign: spot.callsign,
            frequencyKHz: spot.frequencyKHz,
            mode: spot.mode,
            timestamp: spot.timestamp,
            source: spot.source,
            snr: spot.snr,
            wpm: spot.wpm,
            spotter: spot.spotter,
            spotterGrid: spot.spotterGrid,
            parkRef: spot.parkRef,
            parkName: spot.parkName,
            comments: spot.comments,
            region: spot.region,
            distanceMeters: spot.distanceMeters,
            bearingDegrees: spot.bearingDegrees
        )
    }

    func extractActivityLogFields(
        _ log: ActivityLog
    ) -> ActivityLogFields {
        ActivityLogFields(
            id: log.id,
            name: log.name,
            myCallsign: log.myCallsign,
            createdAt: log.createdAt,
            stationProfileId: log.stationProfileId,
            currentGrid: log.currentGrid,
            locationLabel: log.locationLabel,
            isActive: log.isActive
        )
    }

    func extractRadioMacroFields(
        _ macro: RadioMacro
    ) -> RadioMacroFields {
        RadioMacroFields(
            id: macro.id,
            spec: macro.toSpec(),
            tombstoned: macro.tombstoned,
            tombstoneReason: macro.tombstoneReason,
            modifiedAt: macro.updatedAt,
            sortOrder: macro.sortOrder
        )
    }

    func extractActivationMetadataFields(
        _ metadata: ActivationMetadata
    ) -> ActivationMetadataFields {
        ActivationMetadataFields(
            parkReference: metadata.parkReference,
            date: metadata.date,
            title: metadata.title,
            watts: metadata.watts,
            weather: metadata.weather,
            solarConditions: metadata.solarConditions,
            averageWPM: metadata.averageWPM,
            solarKIndex: metadata.solarKIndex,
            solarFlux: metadata.solarFlux,
            solarSunspots: metadata.solarSunspots,
            solarPropagationRating: metadata.solarPropagationRating,
            solarAIndex: metadata.solarAIndex,
            solarBandConditions: metadata.solarBandConditions,
            solarTimestamp: metadata.solarTimestamp,
            weatherTemperatureF: metadata.weatherTemperatureF,
            weatherTemperatureC: metadata.weatherTemperatureC,
            weatherHumidity: metadata.weatherHumidity,
            weatherWindSpeed: metadata.weatherWindSpeed,
            weatherWindDirection: metadata.weatherWindDirection,
            weatherDescription: metadata.weatherDescription,
            weatherTimestamp: metadata.weatherTimestamp
        )
    }
}

// MARK: - Field Application (Sendable structs → Model)

public extension QSOFields {
    /// Copy every synced field onto a model (never touches `cloudDirtyFlag`).
    /// Shared by the CloudKit inbound seam and the server-sync replica.
    func apply(to qso: QSO) {
        qso.callsign = callsign
        qso.band = band
        qso.mode = mode
        qso.frequency = frequency
        qso.timestamp = timestamp
        qso.rstSent = rstSent
        qso.rstReceived = rstReceived
        qso.myCallsign = myCallsign
        qso.myGrid = myGrid
        qso.theirGrid = theirGrid
        qso.parkReference = parkReference
        qso.theirParkReference = theirParkReference
        qso.notes = notes
        qso.importSource = importSource
        qso.importedAt = importedAt
        qso.modifiedAt = modifiedAt
        qso.rawADIF = rawADIF
        qso.name = name
        qso.qth = qth
        qso.state = state
        qso.country = country
        qso.power = power
        qso.myRig = myRig
        qso.stationProfileName = stationProfileName
        qso.sotaRef = sotaRef
        qso.wwffRef = wwffRef
        qso.qrzLogId = qrzLogId
        qso.qrzConfirmed = qrzConfirmed
        qso.lotwConfirmedDate = lotwConfirmedDate
        qso.lotwConfirmed = lotwConfirmed
        qso.dxcc = dxcc
        qso.theirLicenseClass = theirLicenseClass
        qso.isHidden = isHidden
        qso.isActivityLogQSO = isActivityLogQSO
        qso.loggingSessionId = loggingSessionId
        qso.stationCallsign = stationCallsign
        qso.spotCommentsData = spotCommentsData
        qso.notesUserAuthored = notesUserAuthored
        qso.satName = satName
        qso.propMode = propMode
    }
}

public extension LoggingSessionFields {
    /// Copy every synced field onto a model (never touches `cloudDirtyFlag`).
    func apply(to session: LoggingSession) {
        session.myCallsign = myCallsign
        session.startedAt = startedAt
        session.endedAt = endedAt
        session.frequency = frequency
        session.mode = mode
        session.activationTypeRawValue = activationTypeRawValue
        session.statusRawValue = statusRawValue
        session.parkReference = parkReference
        session.sotaReference = sotaReference
        session.wwffReference = wwffReference
        session.myGrid = myGrid
        session.power = power
        session.myRig = myRig
        session.notes = notes
        session.qsoComment = qsoComment
        session.customTitle = customTitle
        session.qsoCount = qsoCount
        session.isRove = isRove
        session.myAntenna = myAntenna
        session.myKey = myKey
        session.myMic = myMic
        session.extraEquipment = extraEquipment
        session.attendees = attendees
        session.photoFilenames = photoFilenames
        session.spotCommentsData = spotCommentsData
        session.roveStopsData = roveStopsData
        session.stationCallsign = stationCallsign
        session.operatorCallsignsRawValue = operatorCallsignsRawValue
        applySolarWeather(to: session)
    }

    func applySolarWeather(to session: LoggingSession) {
        session.solarKIndex = solarKIndex
        session.solarFlux = solarFlux
        session.solarSunspots = solarSunspots
        session.solarPropagationRating = solarPropagationRating
        session.solarAIndex = solarAIndex
        session.solarBandConditions = solarBandConditions
        session.solarTimestamp = solarTimestamp
        session.solarConditions = solarConditions
        session.weatherTemperatureF = weatherTemperatureF
        session.weatherTemperatureC = weatherTemperatureC
        session.weatherHumidity = weatherHumidity
        session.weatherWindSpeed = weatherWindSpeed
        session.weatherWindDirection = weatherWindDirection
        session.weatherDescription = weatherDescription
        session.weatherTimestamp = weatherTimestamp
        session.weather = weather
    }
}

extension CloudSyncJournalEngine {
    func applyQSOFields(_ fields: QSOFields, to qso: QSO) {
        fields.apply(to: qso)
    }

    func applyServicePresenceFields(
        _ fields: ServicePresenceFields,
        to presence: ServicePresence
    ) {
        presence.isPresent = fields.isPresent
        presence.needsUpload = fields.needsUpload
        presence.uploadRejected = fields.uploadRejected
        presence.rejectedAtBuild = fields.rejectedAtBuild
        presence.isSubmitted = fields.isSubmitted
        presence.lastConfirmedAt = fields.lastConfirmedAt
    }

    func applySessionFields(
        _ fields: LoggingSessionFields,
        to session: LoggingSession
    ) {
        fields.apply(to: session)
    }

    func applySessionSolarWeather(
        _ fields: LoggingSessionFields,
        to session: LoggingSession
    ) {
        fields.applySolarWeather(to: session)
    }

    func applySessionSpotFields(
        _ fields: SessionSpotFields, to spot: SessionSpot
    ) {
        spot.loggingSessionId = fields.loggingSessionId
        spot.callsign = fields.callsign
        spot.frequencyKHz = fields.frequencyKHz
        spot.mode = fields.mode
        spot.timestamp = fields.timestamp
        spot.source = fields.source
        spot.snr = fields.snr
        spot.wpm = fields.wpm
        spot.spotter = fields.spotter
        spot.spotterGrid = fields.spotterGrid
        spot.parkRef = fields.parkRef
        spot.parkName = fields.parkName
        spot.comments = fields.comments
        spot.region = fields.region
        spot.distanceMeters = fields.distanceMeters
        spot.bearingDegrees = fields.bearingDegrees
    }

    func applyActivityLogFields(
        _ fields: ActivityLogFields, to log: ActivityLog
    ) {
        log.name = fields.name
        log.myCallsign = fields.myCallsign
        log.createdAt = fields.createdAt
        log.stationProfileId = fields.stationProfileId
        log.currentGrid = fields.currentGrid
        log.locationLabel = fields.locationLabel
        log.isActive = fields.isActive
    }

    func applyRadioMacroFields(
        _ fields: RadioMacroFields, to macro: RadioMacro
    ) {
        let spec = fields.spec
        macro.name = spec.name
        macro.icon = spec.icon
        macro.macroDescription = spec.description
        macro.author = spec.author
        macro.tags = spec.tags ?? []
        macro.appliesTo = spec.appliesTo ?? []
        macro.args = spec.args
        macro.steps = spec.steps
        macro.capabilities = spec.capabilities
        macro.registry = spec.registry
        macro.tombstoned = fields.tombstoned
        macro.tombstoneReason = fields.tombstoneReason
        macro.sortOrder = fields.sortOrder
        macro.updatedAt = fields.modifiedAt
    }

    func applyActivationMetadataFields(
        _ fields: ActivationMetadataFields,
        to metadata: ActivationMetadata
    ) {
        metadata.title = fields.title
        metadata.watts = fields.watts
        metadata.weather = fields.weather
        metadata.solarConditions = fields.solarConditions
        metadata.averageWPM = fields.averageWPM
        metadata.solarKIndex = fields.solarKIndex
        metadata.solarFlux = fields.solarFlux
        metadata.solarSunspots = fields.solarSunspots
        metadata.solarPropagationRating = fields.solarPropagationRating
        metadata.solarAIndex = fields.solarAIndex
        metadata.solarBandConditions = fields.solarBandConditions
        metadata.solarTimestamp = fields.solarTimestamp
        metadata.weatherTemperatureF = fields.weatherTemperatureF
        metadata.weatherTemperatureC = fields.weatherTemperatureC
        metadata.weatherHumidity = fields.weatherHumidity
        metadata.weatherWindSpeed = fields.weatherWindSpeed
        metadata.weatherWindDirection = fields.weatherWindDirection
        metadata.weatherDescription = fields.weatherDescription
        metadata.weatherTimestamp = fields.weatherTimestamp
    }
}
