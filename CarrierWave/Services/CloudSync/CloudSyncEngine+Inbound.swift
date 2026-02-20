import CarrierWaveCore
import CloudKit
import Foundation
import os
import SwiftData

// MARK: - Inbound: Handling Fetched Changes

extension CloudSyncEngine {
    func handleFetchedDatabaseChanges(
        _ changes: CKSyncEngine.Event.FetchedDatabaseChanges
    ) {
        for deletion in changes.deletions where deletion.zoneID == CKRecordMapper.zoneID {
            logger.warning("Sync zone was deleted; clearing all sync metadata")
            clearAllSyncMetadata()
        }
    }

    func handleFetchedRecordZoneChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) {
        for modification in changes.modifications {
            processInboundRecord(modification.record)
        }

        for deletion in changes.deletions {
            processInboundDeletion(deletion.recordID)
        }

        try? modelContext.save()
    }

    func handleDidFetchRecordZoneChanges(
        _ event: CKSyncEngine.Event.DidFetchRecordZoneChanges
    ) {
        try? modelContext.save()
    }

    // MARK: - Inbound Record Processing

    private func processInboundRecord(_ record: CKRecord) {
        let recordName = record.recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName) else {
            return
        }

        switch entityType {
        case CKRecordMapper.RecordType.qso.rawValue:
            processInboundQSO(record)
        case CKRecordMapper.RecordType.servicePresence.rawValue:
            processInboundServicePresence(record)
        case CKRecordMapper.RecordType.loggingSession.rawValue:
            processInboundLoggingSession(record)
        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            processInboundActivationMetadataRecord(record)
        default:
            logger.warning("Unknown record type: \(entityType)")
        }
    }

    private func processInboundQSO(_ record: CKRecord) {
        guard let fields = CKRecordMapper.qsoFields(from: record) else {
            return
        }

        if CKRecordMapper.metadataModes.contains(fields.mode.uppercased()) {
            return
        }

        let uuid = fields.id

        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1

        if let existingQSO = try? modelContext.fetch(descriptor).first {
            mergeInboundQSO(fields, into: existingQSO, record: record)
        } else {
            mergeOrCreateQSO(fields, record: record)
        }

        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.qso.rawValue,
            localId: uuid,
            recordName: record.recordID.recordName,
            record: record
        )
    }

    private func mergeInboundQSO(
        _ fields: QSOFields,
        into existingQSO: QSO,
        record: CKRecord
    ) {
        let localFields = extractQSOFields(existingQSO)
        let merged = CloudSyncConflictResolver.mergeQSO(
            local: localFields,
            remote: fields,
            localModDate: existingQSO.importedAt,
            remoteModDate: record.modificationDate ?? Date()
        )
        applyQSOFields(merged, to: existingQSO)
    }

    private func mergeOrCreateQSO(_ fields: QSOFields, record: CKRecord) {
        let deduplicationKey = fields.deduplicationKey
        let callsignUpper = fields.callsign
            .trimmingCharacters(in: .whitespaces).uppercased()
        let bandUpper = fields.band.uppercased()
        let tLower = fields.timestamp.addingTimeInterval(-240)
        let tUpper = fields.timestamp.addingTimeInterval(240)

        let descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate {
                $0.callsign == callsignUpper
                    && $0.band == bandUpper
                    && $0.timestamp >= tLower
                    && $0.timestamp <= tUpper
            }
        )
        if let candidates = try? modelContext.fetch(descriptor),
           let existing = candidates.first(where: {
               $0.deduplicationKey == deduplicationKey
           })
        {
            mergeInboundQSO(fields, into: existing, record: record)
        } else {
            insertNewQSO(from: fields)
        }
    }

    private func insertNewQSO(from fields: QSOFields) {
        let newQSO = QSO(
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
            qrzLogId: fields.qrzLogId,
            qrzConfirmed: fields.qrzConfirmed,
            lotwConfirmedDate: fields.lotwConfirmedDate,
            lotwConfirmed: fields.lotwConfirmed,
            dxcc: fields.dxcc,
            theirLicenseClass: fields.theirLicenseClass
        )
        newQSO.isHidden = fields.isHidden
        newQSO.isActivityLogQSO = fields.isActivityLogQSO
        newQSO.loggingSessionId = fields.loggingSessionId
        modelContext.insert(newQSO)
    }

    private func processInboundServicePresence(_ record: CKRecord) {
        guard let fields = CKRecordMapper.servicePresenceFields(from: record) else {
            return
        }

        let uuid = fields.id

        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            mergeInboundServicePresence(fields, into: existing)
        } else {
            insertNewServicePresence(from: fields)
        }

        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.servicePresence.rawValue,
            localId: uuid,
            recordName: record.recordID.recordName,
            record: record
        )
    }

    private func mergeInboundServicePresence(
        _ fields: ServicePresenceFields,
        into existing: ServicePresence
    ) {
        let localFields = ServicePresenceFields(
            id: existing.id,
            serviceType: existing.serviceType,
            isPresent: existing.isPresent,
            needsUpload: existing.needsUpload,
            uploadRejected: existing.uploadRejected,
            isSubmitted: existing.isSubmitted,
            lastConfirmedAt: existing.lastConfirmedAt,
            parkReference: existing.parkReference,
            qsoUUID: existing.qso?.id
        )
        let merged = CloudSyncConflictResolver.mergeServicePresence(
            local: localFields,
            remote: fields
        )
        existing.isPresent = merged.isPresent
        existing.needsUpload = merged.needsUpload
        existing.uploadRejected = merged.uploadRejected
        existing.isSubmitted = merged.isSubmitted
        existing.lastConfirmedAt = merged.lastConfirmedAt
    }

    private func insertNewServicePresence(from fields: ServicePresenceFields) {
        let newPresence = ServicePresence(
            id: fields.id,
            serviceType: fields.serviceType,
            isPresent: fields.isPresent,
            needsUpload: fields.needsUpload,
            uploadRejected: fields.uploadRejected,
            isSubmitted: fields.isSubmitted,
            lastConfirmedAt: fields.lastConfirmedAt,
            parkReference: fields.parkReference
        )

        if let qsoUUID = fields.qsoUUID {
            var qsoDescriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.id == qsoUUID }
            )
            qsoDescriptor.fetchLimit = 1
            if let qso = try? modelContext.fetch(qsoDescriptor).first {
                newPresence.qso = qso
            }
        }

        modelContext.insert(newPresence)
    }

    private func processInboundLoggingSession(_ record: CKRecord) {
        guard let fields = CKRecordMapper.loggingSessionFields(from: record) else {
            return
        }

        let uuid = fields.id

        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            mergeInboundLoggingSession(fields, into: existing, record: record)
        } else {
            insertNewLoggingSession(from: fields)
        }

        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.loggingSession.rawValue,
            localId: uuid,
            recordName: record.recordID.recordName,
            record: record
        )
    }

    private func mergeInboundLoggingSession(
        _ fields: LoggingSessionFields,
        into existing: LoggingSession,
        record: CKRecord
    ) {
        let localFields = extractLoggingSessionFields(existing)
        let merged = CloudSyncConflictResolver.mergeLoggingSession(
            local: localFields,
            remote: fields,
            localModDate: existing.endedAt ?? existing.startedAt,
            remoteModDate: record.modificationDate ?? Date()
        )
        applySessionFields(merged, to: existing)
    }

    private func insertNewLoggingSession(from fields: LoggingSessionFields) {
        let session = LoggingSession(
            id: fields.id,
            myCallsign: fields.myCallsign,
            startedAt: fields.startedAt,
            frequency: fields.frequency,
            mode: fields.mode,
            activationType: ActivationType(rawValue: fields.activationTypeRawValue)
                ?? .casual,
            parkReference: fields.parkReference,
            sotaReference: fields.sotaReference,
            myGrid: fields.myGrid,
            notes: fields.notes,
            power: fields.power,
            myRig: fields.myRig,
            myAntenna: fields.myAntenna,
            myKey: fields.myKey,
            myMic: fields.myMic,
            extraEquipment: fields.extraEquipment,
            attendees: fields.attendees
        )
        session.endedAt = fields.endedAt
        session.statusRawValue = fields.statusRawValue
        session.qsoCount = fields.qsoCount
        session.isRove = fields.isRove
        session.customTitle = fields.customTitle
        session.photoFilenames = fields.photoFilenames
        session.spotCommentsData = fields.spotCommentsData
        session.roveStopsData = fields.roveStopsData
        applySessionSolarWeather(fields, to: session)
        modelContext.insert(session)
    }

    private func processInboundActivationMetadataRecord(_ record: CKRecord) {
        guard let fields = CKRecordMapper.activationMetadataFields(from: record) else {
            return
        }
        processInboundActivationMetadata(fields, record: record)
    }

    func processInboundActivationMetadata(
        _ fields: ActivationMetadataFields,
        record: CKRecord
    ) {
        let parkRef = fields.parkReference
        let date = fields.date
        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate {
                $0.parkReference == parkRef && $0.date == date
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = fields.title
            existing.watts = fields.watts
            existing.weather = fields.weather
            existing.solarConditions = fields.solarConditions
            existing.averageWPM = fields.averageWPM
            applyActivationMetadataSolarWeather(fields, to: existing)
        } else {
            let metadata = ActivationMetadata(
                parkReference: fields.parkReference,
                date: fields.date,
                title: fields.title,
                watts: fields.watts,
                weather: fields.weather,
                solarConditions: fields.solarConditions,
                averageWPM: fields.averageWPM
            )
            applyActivationMetadataSolarWeather(fields, to: metadata)
            modelContext.insert(metadata)
        }

        let syntheticID = CKRecordMapper.activationMetadataID(
            parkReference: fields.parkReference,
            date: fields.date
        )
        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.activationMetadata.rawValue,
            localId: syntheticID,
            recordName: record.recordID.recordName,
            record: record
        )
    }

    // MARK: - Inbound Deletions

    private func processInboundDeletion(_ recordID: CKRecord.ID) {
        let recordName = recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName),
              let uuid = CKRecordMapper.parseUUID(from: recordName)
        else {
            return
        }

        switch entityType {
        case CKRecordMapper.RecordType.qso.rawValue:
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.id == uuid }
            )
            descriptor.fetchLimit = 1
            if let qso = try? modelContext.fetch(descriptor).first {
                qso.isHidden = true
            }

        case CKRecordMapper.RecordType.servicePresence.rawValue:
            var descriptor = FetchDescriptor<ServicePresence>(
                predicate: #Predicate { $0.id == uuid }
            )
            descriptor.fetchLimit = 1
            if let presence = try? modelContext.fetch(descriptor).first {
                modelContext.delete(presence)
            }

        case CKRecordMapper.RecordType.loggingSession.rawValue:
            // Hide QSOs associated with this session before deleting it
            let qsoDescriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.loggingSessionId == uuid }
            )
            if let sessionQSOs = try? modelContext.fetch(qsoDescriptor) {
                for qso in sessionQSOs {
                    qso.isHidden = true
                    qso.cloudDirtyFlag = true
                }
            }

            var descriptor = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == uuid }
            )
            descriptor.fetchLimit = 1
            if let session = try? modelContext.fetch(descriptor).first {
                modelContext.delete(session)
            }

        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            deleteSyncMetadata(entityType: entityType, localId: uuid)

        default:
            break
        }

        deleteSyncMetadata(entityType: entityType, localId: uuid)
        try? modelContext.save()
    }
}
