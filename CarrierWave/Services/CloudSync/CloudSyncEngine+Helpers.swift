import CarrierWaveCore
import CloudKit
import Foundation
import os
import SwiftData

// MARK: - Sync Metadata, Dirty Flags, Field Extraction, Notifications

extension CloudSyncEngine {
    // MARK: - Sync Metadata

    func lookupSyncMetadata(
        entityType: String,
        localId: UUID
    ) -> CloudSyncMetadata? {
        var descriptor = FetchDescriptor<CloudSyncMetadata>(
            predicate: #Predicate {
                $0.entityType == entityType && $0.localId == localId
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func upsertSyncMetadata(
        entityType: String,
        localId: UUID,
        recordName: String,
        record: CKRecord
    ) {
        if let existing = lookupSyncMetadata(
            entityType: entityType, localId: localId
        ) {
            existing.encodedSystemFields = CloudSyncMetadata.encodeSystemFields(of: record)
            existing.lastSyncedAt = Date()
        } else {
            let metadata = CloudSyncMetadata(
                entityType: entityType,
                localId: localId,
                recordName: recordName,
                encodedSystemFields: CloudSyncMetadata.encodeSystemFields(of: record),
                lastSyncedAt: Date()
            )
            modelContext.insert(metadata)
        }
    }

    func deleteSyncMetadata(entityType: String, localId: UUID) {
        if let existing = lookupSyncMetadata(
            entityType: entityType, localId: localId
        ) {
            modelContext.delete(existing)
        }
    }

    func clearAllSyncMetadata() {
        let descriptor = FetchDescriptor<CloudSyncMetadata>()
        if let all = try? modelContext.fetch(descriptor) {
            for meta in all {
                modelContext.delete(meta)
            }
        }
        try? modelContext.save()
    }

    // MARK: - Dirty Flag Helpers

    func clearDirtyFlag(entityType: String, id: UUID) {
        switch entityType {
        case CKRecordMapper.RecordType.qso.rawValue:
            var desc = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let qso = try? modelContext.fetch(desc).first {
                qso.cloudDirtyFlag = false
            }

        case CKRecordMapper.RecordType.servicePresence.rawValue:
            var desc = FetchDescriptor<ServicePresence>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let presence = try? modelContext.fetch(desc).first {
                presence.cloudDirtyFlag = false
            }

        case CKRecordMapper.RecordType.loggingSession.rawValue:
            var desc = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let session = try? modelContext.fetch(desc).first {
                session.cloudDirtyFlag = false
            }

        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            if let meta = lookupSyncMetadata(entityType: entityType, localId: id) {
                let descriptor = FetchDescriptor<ActivationMetadata>()
                if let all = try? modelContext.fetch(descriptor) {
                    for am in all {
                        let syntheticID = CKRecordMapper.activationMetadataID(
                            parkReference: am.parkReference, date: am.date
                        )
                        if syntheticID == meta.localId {
                            am.cloudDirtyFlag = false
                            break
                        }
                    }
                }
            }

        default:
            break
        }
    }

    func markAllRecordsDirty() {
        let qsoDescriptor = FetchDescriptor<QSO>()
        if let qsos = try? modelContext.fetch(qsoDescriptor) {
            for qso in qsos where CKRecordMapper.shouldSync(mode: qso.mode) {
                qso.cloudDirtyFlag = true
            }
        }

        let presenceDescriptor = FetchDescriptor<ServicePresence>()
        if let presences = try? modelContext.fetch(presenceDescriptor) {
            for presence in presences {
                presence.cloudDirtyFlag = true
            }
        }

        let sessionDescriptor = FetchDescriptor<LoggingSession>()
        if let sessions = try? modelContext.fetch(sessionDescriptor) {
            for session in sessions {
                session.cloudDirtyFlag = true
            }
        }

        let metadataDescriptor = FetchDescriptor<ActivationMetadata>()
        if let metadata = try? modelContext.fetch(metadataDescriptor) {
            for am in metadata {
                am.cloudDirtyFlag = true
            }
        }

        try? modelContext.save()
    }

    // MARK: - Account Changes

    func handleAccountChange(
        _ change: CKSyncEngine.Event.AccountChange
    ) {
        switch change.changeType {
        case .signIn:
            logger.info("iCloud account signed in")
            Task {
                markAllRecordsDirty()
                await schedulePendingChanges()
            }

        case .signOut:
            logger.info("iCloud account signed out")
            clearAllSyncMetadata()

        case .switchAccounts:
            logger.info("iCloud account switched")
            clearAllSyncMetadata()
            Task {
                markAllRecordsDirty()
                await schedulePendingChanges()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Field Extraction (Model → Sendable structs)

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
            rawADIF: qso.rawADIF,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.power,
            myRig: qso.myRig,
            stationProfileName: qso.stationProfileName,
            sotaRef: qso.sotaRef,
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

    // MARK: - Field Application (Sendable structs → Model)

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

    // MARK: - Notifications

    func postSyncNotification() {
        NotificationCenter.default.post(name: .didSyncQSOs, object: nil)
    }
}
