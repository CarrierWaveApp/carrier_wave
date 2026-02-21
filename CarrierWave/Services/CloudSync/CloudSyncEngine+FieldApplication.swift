import Foundation
import SwiftData

// MARK: - Field Application (Sendable structs → Model)

extension CloudSyncEngine {
    func applyQSOFields(_ fields: QSOFields, to qso: QSO) {
        qso.callsign = fields.callsign
        qso.band = fields.band
        qso.mode = fields.mode
        qso.frequency = fields.frequency
        qso.timestamp = fields.timestamp
        qso.rstSent = fields.rstSent
        qso.rstReceived = fields.rstReceived
        qso.myCallsign = fields.myCallsign
        qso.myGrid = fields.myGrid
        qso.theirGrid = fields.theirGrid
        qso.parkReference = fields.parkReference
        qso.theirParkReference = fields.theirParkReference
        qso.notes = fields.notes
        qso.importSource = fields.importSource
        qso.importedAt = fields.importedAt
        qso.modifiedAt = fields.modifiedAt
        qso.rawADIF = fields.rawADIF
        qso.name = fields.name
        qso.qth = fields.qth
        qso.state = fields.state
        qso.country = fields.country
        qso.power = fields.power
        qso.myRig = fields.myRig
        qso.stationProfileName = fields.stationProfileName
        qso.sotaRef = fields.sotaRef
        qso.qrzLogId = fields.qrzLogId
        qso.qrzConfirmed = fields.qrzConfirmed
        qso.lotwConfirmedDate = fields.lotwConfirmedDate
        qso.lotwConfirmed = fields.lotwConfirmed
        qso.dxcc = fields.dxcc
        qso.theirLicenseClass = fields.theirLicenseClass
        qso.isHidden = fields.isHidden
        qso.isActivityLogQSO = fields.isActivityLogQSO
        qso.loggingSessionId = fields.loggingSessionId
    }

    func applySessionFields(
        _ fields: LoggingSessionFields,
        to session: LoggingSession
    ) {
        session.myCallsign = fields.myCallsign
        session.startedAt = fields.startedAt
        session.endedAt = fields.endedAt
        session.frequency = fields.frequency
        session.mode = fields.mode
        session.activationTypeRawValue = fields.activationTypeRawValue
        session.statusRawValue = fields.statusRawValue
        session.parkReference = fields.parkReference
        session.sotaReference = fields.sotaReference
        session.myGrid = fields.myGrid
        session.power = fields.power
        session.myRig = fields.myRig
        session.notes = fields.notes
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
        applySessionSolarWeather(fields, to: session)
    }

    func applySessionSolarWeather(
        _ fields: LoggingSessionFields,
        to session: LoggingSession
    ) {
        session.solarKIndex = fields.solarKIndex
        session.solarFlux = fields.solarFlux
        session.solarSunspots = fields.solarSunspots
        session.solarPropagationRating = fields.solarPropagationRating
        session.solarAIndex = fields.solarAIndex
        session.solarBandConditions = fields.solarBandConditions
        session.solarTimestamp = fields.solarTimestamp
        session.solarConditions = fields.solarConditions
        session.weatherTemperatureF = fields.weatherTemperatureF
        session.weatherTemperatureC = fields.weatherTemperatureC
        session.weatherHumidity = fields.weatherHumidity
        session.weatherWindSpeed = fields.weatherWindSpeed
        session.weatherWindDirection = fields.weatherWindDirection
        session.weatherDescription = fields.weatherDescription
        session.weatherTimestamp = fields.weatherTimestamp
        session.weather = fields.weather
    }

    func applyActivationMetadataSolarWeather(
        _ fields: ActivationMetadataFields,
        to metadata: ActivationMetadata
    ) {
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
