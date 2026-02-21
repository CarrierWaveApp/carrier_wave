import CloudKit
import Foundation
import os
import SwiftData

// MARK: - Inbound: LoggingSession & ActivationMetadata

extension CloudSyncEngine {
    func processInboundLoggingSession(_ record: CKRecord) {
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

    func processInboundActivationMetadataRecord(_ record: CKRecord) {
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
}
