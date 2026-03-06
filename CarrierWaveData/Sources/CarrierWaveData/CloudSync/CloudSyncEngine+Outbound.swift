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
        collectDirtySessionSpotChanges(into: &changes)
        collectDirtyActivityLogChanges(into: &changes)
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

    private func collectDirtySessionSpotChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        let descriptor = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtySpots = try? modelContext.fetch(descriptor) {
            for spot in dirtySpots {
                let recordID = CKRecordMapper.recordID(
                    type: .sessionSpot, id: spot.id
                )
                changes.append(.saveRecord(recordID))
            }
        }
    }

    private func collectDirtyActivityLogChanges(
        into changes: inout [CKSyncEngine.PendingRecordZoneChange]
    ) {
        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyLogs = try? modelContext.fetch(descriptor) {
            for log in dirtyLogs {
                let recordID = CKRecordMapper.recordID(
                    type: .activityLog, id: log.id
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
                    logger.warning(
                        "Skipping record (build returned nil): \(recordID.recordName, privacy: .public)"
                    )
                    let name = recordID.recordName
                    if let eType = CKRecordMapper.parseEntityType(from: name),
                       let eID = CKRecordMapper.parseUUID(from: name)
                    {
                        clearDirtyFlag(entityType: eType, id: eID)
                    }
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
            atomicByZone: false
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
        case CKRecordMapper.RecordType.sessionSpot.rawValue:
            return buildSessionSpotRecord(
                id: uuid, existingRecord: existingRecord
            )
        case CKRecordMapper.RecordType.activityLog.rawValue:
            return buildActivityLogRecord(
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
        let descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        guard let dirtyMetadata = try? modelContext.fetch(descriptor) else {
            return nil
        }

        for metadata in dirtyMetadata {
            let syntheticID = CKRecordMapper.activationMetadataID(
                parkReference: metadata.parkReference,
                date: metadata.date
            )
            if syntheticID == id {
                let fields = extractActivationMetadataFields(metadata)
                return CKRecordMapper.activationMetadataFieldsToCKRecord(
                    fields, existingRecord: existingRecord
                )
            }
        }

        return nil
    }

    private func buildSessionSpotRecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        var descriptor = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let spot = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        let fields = extractSessionSpotFields(spot)
        return CKRecordMapper.sessionSpotFieldsToCKRecord(
            fields, existingRecord: existingRecord
        )
    }

    private func buildActivityLogRecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        var descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let log = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        let fields = extractActivityLogFields(log)
        return CKRecordMapper.activityLogFieldsToCKRecord(
            fields, existingRecord: existingRecord
        )
    }

    // MARK: - Handling Sent Changes

    func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges
    ) {
        logger.info(
            "Batch complete: \(event.savedRecords.count) saved, \(event.failedRecordSaves.count) failed"
        )

        for savedRecord in event.savedRecords {
            handleSuccessfullySavedRecord(savedRecord)
        }

        var hadConflicts = false
        for failedRecord in event.failedRecordSaves {
            if failedRecord.error.code == .serverRecordChanged {
                hadConflicts = true
            }
            handleFailedRecordSave(failedRecord)
        }

        try? modelContext.save()

        if hadConflicts {
            let retries = collectDirtyRecordIDs()
            if !retries.isEmpty, let engine = syncEngine {
                engine.state.add(pendingRecordZoneChanges: retries)
                logger.info("Re-scheduled \(retries.count) records after conflict resolution")
            }
        }
    }

    private func handleSuccessfullySavedRecord(_ record: CKRecord) {
        let recordName = record.recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName),
              let uuid = CKRecordMapper.parseUUID(from: recordName)
        else {
            return
        }

        upsertSyncMetadata(
            entityType: entityType,
            localId: uuid,
            recordName: recordName,
            record: record
        )

        clearDirtyFlag(entityType: entityType, id: uuid)
    }

    private func handleFailedRecordSave(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave
    ) {
        let error = failure.error
        let record = failure.record

        let recType = record.recordType
        let recName = record.recordID.recordName
        let errCode = error.code.rawValue
        let errDesc = error.localizedDescription
        logger.error("Record save failed: type=\(recType, privacy: .public) id=\(recName, privacy: .public)")
        logger.error("  error code=\(errCode, privacy: .public) desc=\(errDesc, privacy: .public)")
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            let uCode = underlying.code
            let uDesc = underlying.localizedDescription
            logger.error("  underlying code=\(uCode, privacy: .public) desc=\(uDesc, privacy: .public)")
            if let serverDesc = underlying.userInfo["ServerErrorDescription"] as? String {
                logger.error("  server says: \(serverDesc, privacy: .public)")
            }
        }

        switch error.code {
        case .serverRecordChanged:
            handleConflict(failure: failure)

        case .batchRequestFailed:
            break

        case .zoneNotFound:
            Task {
                try? await ensureZoneExists()
            }

        case .unknownItem:
            let recordName = record.recordID.recordName
            if let entityType = CKRecordMapper.parseEntityType(from: recordName),
               let uuid = CKRecordMapper.parseUUID(from: recordName)
            {
                deleteSyncMetadata(entityType: entityType, localId: uuid)
            }

        default:
            break
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
        case CKRecordMapper.RecordType.sessionSpot.rawValue:
            resolveSessionSpotConflict(
                uuid: uuid,
                serverRecord: serverRecord
            )
        case CKRecordMapper.RecordType.activityLog.rawValue:
            resolveActivityLogConflict(
                uuid: uuid,
                clientRecord: clientRecord,
                serverRecord: serverRecord
            )
        default:
            break
        }
    }
}
