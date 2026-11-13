import Foundation
import SwiftData

// MARK: - Factory methods to create models from sync field structs

extension QSO {
    /// Create a new QSO from sync fields. Does not set cloudDirtyFlag.
    static func fromFields(_ fields: QSOFields) -> QSO {
        let qso = QSO(
            id: fields.id,
            callsign: fields.callsign,
            band: fields.band,
            mode: fields.mode,
            frequency: fields.frequency,
            timestamp: fields.timestamp,
            rstSent: fields.rstSent,
            rstReceived: fields.rstReceived,
            myCallsign: fields.myCallsign,
            myGrid: fields.myGrid,
            theirGrid: fields.theirGrid,
            parkReference: fields.parkReference,
            theirParkReference: fields.theirParkReference,
            notes: fields.notes,
            notesUserAuthored: fields.notesUserAuthored,
            importSource: fields.importSource,
            importedAt: fields.importedAt,
            rawADIF: fields.rawADIF,
            name: fields.name,
            qth: fields.qth,
            state: fields.state,
            country: fields.country,
            power: fields.power,
            myRig: fields.myRig,
            stationProfileName: fields.stationProfileName,
            sotaRef: fields.sotaRef,
            wwffRef: fields.wwffRef,
            qrzLogId: fields.qrzLogId,
            qrzConfirmed: fields.qrzConfirmed,
            lotwConfirmedDate: fields.lotwConfirmedDate,
            lotwConfirmed: fields.lotwConfirmed,
            dxcc: fields.dxcc,
            theirLicenseClass: fields.theirLicenseClass,
            satName: fields.satName,
            propMode: fields.propMode
        )
        qso.isHidden = fields.isHidden
        qso.isActivityLogQSO = fields.isActivityLogQSO
        qso.loggingSessionId = fields.loggingSessionId
        qso.modifiedAt = fields.modifiedAt
        qso.stationCallsign = fields.stationCallsign
        qso.spotCommentsData = fields.spotCommentsData
        return qso
    }
}

extension ServicePresence {
    /// Create a new ServicePresence from sync fields, linked to a QSO.
    static func fromFields(
        _ fields: ServicePresenceFields, qso: QSO
    ) -> ServicePresence {
        let sp = ServicePresence(
            id: fields.id,
            serviceType: fields.serviceType,
            isPresent: fields.isPresent,
            needsUpload: fields.needsUpload,
            uploadRejected: fields.uploadRejected,
            isSubmitted: fields.isSubmitted,
            lastConfirmedAt: fields.lastConfirmedAt,
            parkReference: fields.parkReference
        )
        sp.rejectedAtBuild = fields.rejectedAtBuild
        sp.qso = qso
        return sp
    }
}

extension LoggingSession {
    /// Create a new LoggingSession from sync fields.
    static func fromFields(_ fields: LoggingSessionFields) -> LoggingSession {
        let activationType = ActivationType(
            rawValue: fields.activationTypeRawValue
        ) ?? .casual
        let session = LoggingSession(
            id: fields.id,
            myCallsign: fields.myCallsign,
            startedAt: fields.startedAt,
            mode: fields.mode,
            activationType: activationType
        )
        session.endedAt = fields.endedAt
        session.frequency = fields.frequency
        session.statusRawValue = fields.statusRawValue
        session.parkReference = fields.parkReference
        session.sotaReference = fields.sotaReference
        session.wwffReference = fields.wwffReference
        session.myGrid = fields.myGrid
        session.power = fields.power
        session.myRig = fields.myRig
        session.notes = fields.notes
        session.qsoComment = fields.qsoComment
        session.customTitle = fields.customTitle
        session.qsoCount = fields.qsoCount
        session.isRove = fields.isRove
        session.myAntenna = fields.myAntenna
        session.myKey = fields.myKey
        session.myMic = fields.myMic
        session.extraEquipment = fields.extraEquipment
        session.attendees = fields.attendees
        session.photoFilenames = fields.photoFilenames
        session.spotCommentsData = fields.spotCommentsData
        session.roveStopsData = fields.roveStopsData
        session.stationCallsign = fields.stationCallsign
        session.operatorCallsignsRawValue = fields.operatorCallsignsRawValue
        return session
    }
}

extension ActivationMetadata {
    /// Create new ActivationMetadata from sync fields.
    static func fromFields(
        _ fields: ActivationMetadataFields
    ) -> ActivationMetadata {
        let am = ActivationMetadata(
            parkReference: fields.parkReference,
            date: fields.date
        )
        am.title = fields.title
        am.watts = fields.watts
        am.weather = fields.weather
        am.solarConditions = fields.solarConditions
        am.averageWPM = fields.averageWPM
        return am
    }
}

extension SessionSpot {
    /// Create a new SessionSpot from sync fields.
    static func fromFields(_ fields: SessionSpotFields) -> SessionSpot {
        let spot = SessionSpot(
            loggingSessionId: fields.loggingSessionId,
            callsign: fields.callsign,
            frequencyKHz: fields.frequencyKHz,
            mode: fields.mode,
            timestamp: fields.timestamp,
            source: fields.source,
            snr: fields.snr,
            wpm: fields.wpm,
            spotter: fields.spotter,
            spotterGrid: fields.spotterGrid,
            parkRef: fields.parkRef,
            parkName: fields.parkName,
            comments: fields.comments,
            region: fields.region,
            distanceMeters: fields.distanceMeters,
            bearingDegrees: fields.bearingDegrees
        )
        spot.id = fields.id
        return spot
    }
}

extension ActivityLog {
    /// Create a new ActivityLog from sync fields.
    static func fromFields(_ fields: ActivityLogFields) -> ActivityLog {
        let log = ActivityLog(
            id: fields.id,
            name: fields.name,
            myCallsign: fields.myCallsign,
            createdAt: fields.createdAt
        )
        log.stationProfileId = fields.stationProfileId
        log.currentGrid = fields.currentGrid
        log.locationLabel = fields.locationLabel
        log.isActive = fields.isActive
        return log
    }
}

extension RadioMacro {
    /// Create a new RadioMacro from sync fields. Does not set cloudDirtyFlag.
    static func fromFields(_ fields: RadioMacroFields) -> RadioMacro {
        let macro = RadioMacro.from(spec: fields.spec, sortOrder: fields.sortOrder)
        macro.tombstoned = fields.tombstoned
        macro.tombstoneReason = fields.tombstoneReason
        macro.updatedAt = fields.modifiedAt
        return macro
    }
}
