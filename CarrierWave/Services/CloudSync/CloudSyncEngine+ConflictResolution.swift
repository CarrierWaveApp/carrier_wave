import CarrierWaveData
import CloudKit
import Foundation
import os
import SwiftData

// MARK: - Conflict Resolution

extension CloudSyncEngine {
    func resolveQSOConflict(
        uuid: UUID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        guard let localFields = CKRecordMapper.qsoFields(from: clientRecord),
              let remoteFields = CKRecordMapper.qsoFields(from: serverRecord)
        else {
            return
        }

        let merged = CloudSyncConflictResolver.mergeQSO(
            local: localFields,
            remote: remoteFields,
            localModDate: localFields.modifiedAt
                ?? clientRecord.modificationDate ?? Date.distantPast,
            remoteModDate: remoteFields.modifiedAt
                ?? serverRecord.modificationDate ?? Date.distantPast
        )

        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        if let qso = try? modelContext.fetch(descriptor).first {
            applyQSOFields(merged, to: qso)
            qso.cloudDirtyFlag = true

            upsertSyncMetadata(
                entityType: CKRecordMapper.RecordType.qso.rawValue,
                localId: uuid,
                recordName: serverRecord.recordID.recordName,
                record: serverRecord
            )
        }
    }

    func resolveServicePresenceConflict(
        uuid: UUID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        guard let localFields = CKRecordMapper.servicePresenceFields(
            from: clientRecord
        ),
            let remoteFields = CKRecordMapper.servicePresenceFields(
                from: serverRecord
            )
        else {
            return
        }

        let merged = CloudSyncConflictResolver.mergeServicePresence(
            local: localFields,
            remote: remoteFields
        )

        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        if let presence = try? modelContext.fetch(descriptor).first {
            presence.isPresent = merged.isPresent
            presence.needsUpload = merged.needsUpload
            presence.uploadRejected = merged.uploadRejected
            presence.isSubmitted = merged.isSubmitted
            presence.lastConfirmedAt = merged.lastConfirmedAt
            presence.cloudDirtyFlag = true

            upsertSyncMetadata(
                entityType: CKRecordMapper.RecordType.servicePresence.rawValue,
                localId: uuid,
                recordName: serverRecord.recordID.recordName,
                record: serverRecord
            )
        }
    }

    func resolveLoggingSessionConflict(
        uuid: UUID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        guard let localFields = CKRecordMapper.loggingSessionFields(
            from: clientRecord
        ),
            let remoteFields = CKRecordMapper.loggingSessionFields(
                from: serverRecord
            )
        else {
            return
        }

        let merged = CloudSyncConflictResolver.mergeLoggingSession(
            local: localFields,
            remote: remoteFields,
            localModDate: clientRecord.modificationDate ?? Date.distantPast,
            remoteModDate: serverRecord.modificationDate ?? Date.distantPast
        )

        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        if let session = try? modelContext.fetch(descriptor).first {
            applySessionFields(merged, to: session)
            session.cloudDirtyFlag = true

            upsertSyncMetadata(
                entityType: CKRecordMapper.RecordType.loggingSession.rawValue,
                localId: uuid,
                recordName: serverRecord.recordID.recordName,
                record: serverRecord
            )
        }
    }

    func resolveActivationMetadataConflict(
        serverRecord: CKRecord,
        clientRecord _: CKRecord
    ) {
        guard let remoteFields = CKRecordMapper.activationMetadataFields(from: serverRecord)
        else {
            return
        }
        processInboundActivationMetadata(
            remoteFields,
            record: serverRecord
        )
    }

    func resolveSessionSpotConflict(
        uuid: UUID,
        serverRecord: CKRecord
    ) {
        // Spots are immutable once recorded — accept server version
        guard let remoteFields = CKRecordMapper.sessionSpotFields(from: serverRecord) else {
            return
        }

        var descriptor = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        if let spot = try? modelContext.fetch(descriptor).first {
            applySessionSpotFields(remoteFields, to: spot)
            // Don't set cloudDirtyFlag — we accepted the server version,
            // so local now matches server. Re-uploading would cause ping-pong.

            upsertSyncMetadata(
                entityType: CKRecordMapper.RecordType.sessionSpot.rawValue,
                localId: uuid,
                recordName: serverRecord.recordID.recordName,
                record: serverRecord
            )
        }
    }

    func resolveActivityLogConflict(
        uuid: UUID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        guard let localFields = CKRecordMapper.activityLogFields(from: clientRecord),
              let remoteFields = CKRecordMapper.activityLogFields(from: serverRecord)
        else {
            return
        }

        let merged = CloudSyncConflictResolver.mergeActivityLog(
            local: localFields,
            remote: remoteFields,
            localModDate: clientRecord.modificationDate ?? Date.distantPast,
            remoteModDate: serverRecord.modificationDate ?? Date.distantPast
        )

        var descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        if let log = try? modelContext.fetch(descriptor).first {
            applyActivityLogFields(merged, to: log)
            log.cloudDirtyFlag = true

            upsertSyncMetadata(
                entityType: CKRecordMapper.RecordType.activityLog.rawValue,
                localId: uuid,
                recordName: serverRecord.recordID.recordName,
                record: serverRecord
            )
        }
    }
}
