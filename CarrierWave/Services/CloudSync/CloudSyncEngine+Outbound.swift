import CarrierWaveCore
import CloudKit
import Foundation
import os
import SwiftData

// MARK: - Outbound: Collecting Dirty Records & Building Batches

extension CloudSyncEngine {
    func collectDirtyRecordIDs() -> [CKSyncEngine.PendingRecordZoneChange] {
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        collectDirtyQSOChanges(into: &changes)
        collectDirtyServicePresenceChanges(into: &changes)
        collectDirtyLoggingSessionChanges(into: &changes)
        collectDirtyActivationMetadataChanges(into: &changes)
        return changes
    }

    private func collectDirtyQSOChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        let descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyQSOs = try? modelContext.fetch(descriptor) {
            for qso in dirtyQSOs where CKRecordMapper.shouldSync(mode: qso.mode) {
                let recordID = CKRecordMapper.recordID(type: .qso, id: qso.id)
                changes.append(.saveRecord(recordID))
            }
        }
    }

    private func collectDirtyServicePresenceChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        let descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyPresence = try? modelContext.fetch(descriptor) {
            for presence in dirtyPresence {
                let recordID = CKRecordMapper.recordID(
                    type: .servicePresence, id: presence.id
                )
                changes.append(.saveRecord(recordID))
            }
        }
    }

    private func collectDirtyLoggingSessionChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        let descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtySessions = try? modelContext.fetch(descriptor) {
            for session in dirtySessions {
                let recordID = CKRecordMapper.recordID(
                    type: .loggingSession, id: session.id
                )
                changes.append(.saveRecord(recordID))
            }
        }
    }

    private func collectDirtyActivationMetadataChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        let descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyMetadata = try? modelContext.fetch(descriptor) {
            for metadata in dirtyMetadata {
                let syntheticID = CKRecordMapper.activationMetadataID(
                    parkReference: metadata.parkReference,
                    date: metadata.date
                )
                let recordID = CKRecordMapper.recordID(
                    type: .activationMetadata, id: syntheticID
                )
                changes.append(.saveRecord(recordID))
            }
        }
    }

    func buildNextChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        engine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = engine.state.pendingRecordZoneChanges
        guard !pendingChanges.isEmpty else {
            return nil
        }

        let batch = pendingChanges.prefix(sendBatchSize)

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for change in batch {
            switch change {
            case let .saveRecord(recordID):
                if let record = buildRecord(for: recordID) {
                    recordsToSave.append(record)
                } else {
                    // Record no longer exists locally; remove from pending
                    engine.state.remove(pendingRecordZoneChanges: [change])
                }
            case let .deleteRecord(recordID):
                recordIDsToDelete.append(recordID)
            @unknown default:
                break
            }
        }

        guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else {
            return nil
        }

        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete,
            atomicByZone: true
        )
    }

    // MARK: - Record Building

    private func buildRecord(for recordID: CKRecord.ID) -> CKRecord? {
        let recordName = recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName),
              let uuid = CKRecordMapper.parseUUID(from: recordName)
        else {
            return nil
        }

        // Look up existing CKRecord metadata for change tags
        let existingRecord = lookupSyncMetadata(
            entityType: entityType, localId: uuid
        )?.decodedRecord()

        switch entityType {
        case CKRecordMapper.RecordType.qso.rawValue:
            return buildQSORecord(id: uuid, existingRecord: existingRecord)
        case CKRecordMapper.RecordType.servicePresence.rawValue:
            return buildServicePresenceRecord(
                id: uuid, existingRecord: existingRecord
            )
        case CKRecordMapper.RecordType.loggingSession.rawValue:
            return buildLoggingSessionRecord(
                id: uuid, existingRecord: existingRecord
            )
        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            return buildActivationMetadataRecord(
                id: uuid, existingRecord: existingRecord
            )
        default:
            return nil
        }
    }

    private func buildQSORecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let qso = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        guard CKRecordMapper.shouldSync(mode: qso.mode) else {
            return nil
        }
        let fields = extractQSOFields(qso)
        return CKRecordMapper.qsoFieldsToCKRecord(
            fields, existingRecord: existingRecord
        )
    }

    private func buildServicePresenceRecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        var descriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let presence = try? modelContext.fetch(descriptor).first,
              let qso = presence.qso
        else {
            return nil
        }
        let fields = extractServicePresenceFields(presence, qsoID: qso.id)
        return CKRecordMapper.servicePresenceFieldsToCKRecord(
            fields, existingRecord: existingRecord
        )
    }

    private func buildLoggingSessionRecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        let fields = extractLoggingSessionFields(session)
        return CKRecordMapper.loggingSessionFieldsToCKRecord(
            fields, existingRecord: existingRecord
        )
    }

    private func buildActivationMetadataRecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        guard let meta = lookupSyncMetadata(
            entityType: CKRecordMapper.RecordType.activationMetadata.rawValue,
            localId: id
        ) else {
            return nil
        }

        let descriptor = FetchDescriptor<ActivationMetadata>()
        guard let allMetadata = try? modelContext.fetch(descriptor) else {
            return nil
        }

        for metadata in allMetadata where metadata.cloudDirtyFlag {
            let syntheticID = CKRecordMapper.activationMetadataID(
                parkReference: metadata.parkReference,
                date: metadata.date
            )
            if syntheticID == meta.localId {
                let fields = extractActivationMetadataFields(metadata)
                return CKRecordMapper.activationMetadataFieldsToCKRecord(
                    fields, existingRecord: existingRecord
                )
            }
        }

        return nil
    }

    // MARK: - Handling Sent Changes

    func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges
    ) {
        // Handle successfully saved records
        for savedRecord in event.savedRecords {
            handleSuccessfullySavedRecord(savedRecord)
        }

        // Handle failed records
        for failedRecord in event.failedRecordSaves {
            handleFailedRecordSave(failedRecord)
        }

        try? modelContext.save()
    }

    private func handleSuccessfullySavedRecord(_ record: CKRecord) {
        let recordName = record.recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName),
              let uuid = CKRecordMapper.parseUUID(from: recordName)
        else {
            return
        }

        // Store system fields for future change tags
        upsertSyncMetadata(
            entityType: entityType,
            localId: uuid,
            recordName: recordName,
            record: record
        )

        // Clear the dirty flag on the local record
        clearDirtyFlag(entityType: entityType, id: uuid)
    }

    private func handleFailedRecordSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
    ) {
        let error = failure.error

        switch error.code {
        case .serverRecordChanged:
            // Conflict — the server has a newer version. Resolve conflict.
            handleConflict(failure: failure)

        case .zoneNotFound:
            // Zone was deleted; re-create it
            Task {
                try? await ensureZoneExists()
            }

        case .unknownItem:
            // Record doesn't exist on server; clear metadata and retry
            let recordName = failure.record.recordID.recordName
            if let entityType = CKRecordMapper.parseEntityType(from: recordName),
               let uuid = CKRecordMapper.parseUUID(from: recordName)
            {
                deleteSyncMetadata(entityType: entityType, localId: uuid)
            }

        default:
            logger.error(
                "Failed to save record \(failure.record.recordID.recordName): \(error)"
            )
        }
    }

    private func handleConflict(
        failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
    ) {
        guard let serverRecord = failure.error.serverRecord else {
            return
        }

        let recordName = failure.record.recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName),
              let uuid = CKRecordMapper.parseUUID(from: recordName)
        else {
            return
        }

        let clientRecord = failure.record

        switch entityType {
        case CKRecordMapper.RecordType.qso.rawValue:
            resolveQSOConflict(
                uuid: uuid,
                clientRecord: clientRecord,
                serverRecord: serverRecord
            )
        case CKRecordMapper.RecordType.servicePresence.rawValue:
            resolveServicePresenceConflict(
                uuid: uuid,
                clientRecord: clientRecord,
                serverRecord: serverRecord
            )
        case CKRecordMapper.RecordType.loggingSession.rawValue:
            resolveLoggingSessionConflict(
                uuid: uuid,
                clientRecord: clientRecord,
                serverRecord: serverRecord
            )
        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            resolveActivationMetadataConflict(
                serverRecord: serverRecord,
                clientRecord: clientRecord
            )
        default:
            break
        }
    }
}
