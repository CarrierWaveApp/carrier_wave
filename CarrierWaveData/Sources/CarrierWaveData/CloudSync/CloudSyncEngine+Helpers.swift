import CloudKit
import Foundation
import os
import SwiftData

// MARK: - Sync Metadata, Dirty Flags, Account Changes, Notifications

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
            clearQSODirtyFlag(id: id)
        case CKRecordMapper.RecordType.servicePresence.rawValue:
            clearServicePresenceDirtyFlag(id: id)
        case CKRecordMapper.RecordType.loggingSession.rawValue:
            clearLoggingSessionDirtyFlag(id: id)
        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            clearActivationMetadataDirtyFlag(entityType: entityType, id: id)
        case CKRecordMapper.RecordType.sessionSpot.rawValue:
            clearSessionSpotDirtyFlag(id: id)
        case CKRecordMapper.RecordType.activityLog.rawValue:
            clearActivityLogDirtyFlag(id: id)
        default:
            break
        }
    }

    private func clearQSODirtyFlag(id: UUID) {
        var desc = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        if let qso = try? modelContext.fetch(desc).first {
            qso.cloudDirtyFlag = false
        }
    }

    private func clearServicePresenceDirtyFlag(id: UUID) {
        var desc = FetchDescriptor<ServicePresence>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        if let presence = try? modelContext.fetch(desc).first {
            presence.cloudDirtyFlag = false
        }
    }

    private func clearLoggingSessionDirtyFlag(id: UUID) {
        var desc = FetchDescriptor<LoggingSession>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        if let session = try? modelContext.fetch(desc).first {
            session.cloudDirtyFlag = false
        }
    }

    private func clearActivationMetadataDirtyFlag(entityType: String, id: UUID) {
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
    }

    private func clearSessionSpotDirtyFlag(id: UUID) {
        var desc = FetchDescriptor<SessionSpot>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        if let spot = try? modelContext.fetch(desc).first {
            spot.cloudDirtyFlag = false
        }
    }

    private func clearActivityLogDirtyFlag(id: UUID) {
        var desc = FetchDescriptor<ActivityLog>(predicate: #Predicate { $0.id == id })
        desc.fetchLimit = 1
        if let log = try? modelContext.fetch(desc).first {
            log.cloudDirtyFlag = false
        }
    }

    func markAllRecordsDirtyImpl() {
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

        let spotDescriptor = FetchDescriptor<SessionSpot>()
        if let spots = try? modelContext.fetch(spotDescriptor) {
            for spot in spots {
                spot.cloudDirtyFlag = true
            }
        }

        let logDescriptor = FetchDescriptor<ActivityLog>()
        if let logs = try? modelContext.fetch(logDescriptor) {
            for log in logs {
                log.cloudDirtyFlag = true
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
                markAllRecordsDirtyImpl()
                await schedulePendingChanges()
            }

        case .signOut:
            logger.info("iCloud account signed out")
            clearAllSyncMetadata()

        case .switchAccounts:
            logger.info("iCloud account switched")
            clearAllSyncMetadata()
            Task {
                markAllRecordsDirtyImpl()
                await schedulePendingChanges()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Record Counts

    func recordCountsImpl() -> CloudSyncRecordCounts {
        let dirtyQSOs = fetchCount(FetchDescriptor<QSO>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        ))
        let dirtyPresence = fetchCount(FetchDescriptor<ServicePresence>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        ))
        let dirtySessions = fetchCount(FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        ))
        let dirtyMetadata = fetchCount(FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        ))
        let dirtySpots = fetchCount(FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        ))
        let dirtyLogs = fetchCount(FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        ))

        return CloudSyncRecordCounts(
            dirtyQSOs: dirtyQSOs,
            dirtyServicePresence: dirtyPresence,
            dirtySessions: dirtySessions,
            dirtyMetadata: dirtyMetadata,
            dirtySpots: dirtySpots,
            dirtyLogs: dirtyLogs,
            syncedRecords: countSyncMetadata()
        )
    }

    private func fetchCount(
        _ descriptor: FetchDescriptor<some PersistentModel>
    ) -> Int {
        (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func countSyncMetadata() -> [String: Int] {
        let descriptor = FetchDescriptor<CloudSyncMetadata>()
        guard let all = try? modelContext.fetch(descriptor) else {
            return [:]
        }
        var counts: [String: Int] = [:]
        for meta in all {
            counts[meta.entityType, default: 0] += 1
        }
        return counts
    }

    // MARK: - Notifications

    func postSyncNotification() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .didSyncQSOs, object: nil)
        }
        await delegate?.cloudSyncEngineDidFinishFetch(self)
    }

    /// Called after each outbound batch completes. Refreshes counts on the delegate.
    func postSendProgress(batchSaved: Int = 0) async {
        let newCounts = recordCountsImpl()
        await delegate?.cloudSyncEngine(self, didUpdateCounts: newCounts, batchSaved: batchSaved)
    }
}
