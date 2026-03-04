import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Field Extraction (Model → Sendable structs)

extension CloudSyncEngine {
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
            loggingSessionId: qso.loggingSessionId
        )
    }

    func extractServicePresenceFields(
        _ presence: ServicePresence,
        qsoID: UUID
    ) -> ServicePresenceFields {
        ServicePresenceFields(
            id: presence.id,
            serviceType: presence.serviceType,
            isPresent: presence.isPresent,
            needsUpload: presence.needsUpload,
            uploadRejected: presence.uploadRejected,
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
            weather: session.weather
        )
    }

    func extractSessionSpotFields(_ spot: SessionSpot) -> SessionSpotFields {
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
            distanceMeters: spot.distanceMeters
        )
    }

    func extractActivityLogFields(_ log: ActivityLog) -> ActivityLogFields {
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
