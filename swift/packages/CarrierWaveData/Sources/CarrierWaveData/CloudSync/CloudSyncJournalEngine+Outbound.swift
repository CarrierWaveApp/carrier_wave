import CloudKit
import Foundation
import SwiftData

// MARK: - Outbound: Collecting Dirty Records → Journal Operations

extension CloudSyncJournalEngine {
    /// Collect all dirty records and convert them to journal operations.
    /// Uses batched fetches for QSO and ServicePresence per performance rules.
    func collectDirtyOperations() -> [JournalOperation] {
        var operations: [JournalOperation] = []
        collectDirtyQSOs(into: &operations)
        collectDirtyServicePresence(into: &operations)
        collectDirtySmallTables(into: &operations)
        return operations
    }

    /// Build the next outbound batch from pending journal records.
    func buildNextBatch(
        engine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !pendingJournalRecords.isEmpty else {
            return nil
        }
        let batch = Array(pendingJournalRecords.prefix(10))
        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: batch,
            recordIDsToDelete: [],
            atomicByZone: false
        )
    }

    /// Handle successfully sent journal records.
    func handleSentChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges
    ) {
        let startTime = ContinuousClock.now
        let savedIDs = Set(
            event.savedRecords.map(\.recordID.recordName)
        )
        pendingJournalRecords.removeAll { record in
            savedIDs.contains(record.recordID.recordName)
        }

        // Clear dirty flags for all entities in the saved journal entries
        var totalOps = 0
        for record in event.savedRecords {
            if let payload = JournalPayload.from(record: record) {
                totalOps += payload.operations.count
            }
            clearDirtyFlagsForJournal(record)
        }
        try? modelContext.save()

        let savedCount = event.savedRecords.count
        if savedCount > 0 {
            let elapsed = ContinuousClock.now - startTime
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            let syncEvent = CloudSyncEvent(
                category: .upload,
                detail: "Uploaded \(totalOps) ops in \(savedCount) journal entries",
                recordCount: totalOps,
                duration: seconds
            )
            Task { [eventLog] in await eventLog.append(syncEvent) }
            Task { [totalOps] in
                await delegate?.journalEngine(self, didLogEvent: syncEvent)
                await delegate?.journalEngine(
                    self, didConfirmOperations: totalOps
                )
            }
        }

        for failure in event.failedRecordSaves {
            logger.error(
                "Journal save failed: \(failure.error.localizedDescription)"
            )
        }
    }

    // MARK: - Private: Dirty Record Collection

    private func collectDirtyQSOs(into ops: inout [JournalOperation]) {
        if let qsoJournalStore {
            collectDirtyQSOsFromStore(qsoJournalStore, into: &ops)
            return
        }
        let batchSize = 1_000
        var offset = 0

        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { $0.cloudDirtyFlag == true },
                limit: batchSize,
                offset: offset
            )
            guard let batch = try? modelContext.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }
            for qso in batch {
                if QSOMode.isMetadata(qso.mode) {
                    qso.cloudDirtyFlag = false
                } else {
                    ops.append(.upsertQSO(extractQSOFields(qso)))
                }
            }
            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
    }

    /// Rust-store-authoritative QSO dirty collection. Pages the store's dirty set
    /// (stable — we defer the metadata-mode clear until after paging, so offsets
    /// don't shift mid-scan), emits the real QSOs as upserts, and clears the
    /// metadata-mode rows without an op (mirroring the SwiftData skip). Clears are
    /// chunked to the store's `MAX_FETCH_LIMIT`.
    private func collectDirtyQSOsFromStore(
        _ store: QSOJournalStore, into ops: inout [JournalOperation]
    ) {
        let batchSize: Int64 = 1_000
        var offset: Int64 = 0
        var metadataIds: [String] = []
        while true {
            guard let page = try? store.dirtyQSOPage(limit: batchSize, offset: offset) else {
                break
            }
            let pageCount = page.emittable.count + page.metadataModeIds.count
            for fields in page.emittable {
                ops.append(.upsertQSO(fields))
            }
            metadataIds.append(contentsOf: page.metadataModeIds)
            offset += Int64(pageCount)
            if pageCount < Int(batchSize) {
                break
            }
        }
        var start = 0
        while start < metadataIds.count {
            let end = min(start + Int(batchSize), metadataIds.count)
            _ = try? store.clearDirty(storeIds: Array(metadataIds[start ..< end]))
            start = end
        }
    }

    private func collectDirtyServicePresence(
        into ops: inout [JournalOperation]
    ) {
        let batchSize = 1_000
        var offset = 0

        while true {
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate { $0.cloudDirtyFlag == true },
                limit: batchSize,
                offset: offset
            )
            guard let batch = try? modelContext.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }
            for presence in batch {
                if let qso = presence.qso {
                    ops.append(.upsertServicePresence(
                        extractServicePresenceFields(presence, qsoID: qso.id)
                    ))
                }
            }
            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
    }

    private func collectDirtySmallTables(
        into ops: inout [JournalOperation]
    ) {
        // LoggingSessions
        let sessionDesc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let sessions = try? modelContext.fetch(sessionDesc) {
            for session in sessions {
                ops.append(.upsertLoggingSession(
                    extractLoggingSessionFields(session)
                ))
            }
        }

        // ActivationMetadata
        let metaDesc = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let metadata = try? modelContext.fetch(metaDesc) {
            for am in metadata {
                ops.append(.upsertActivationMetadata(
                    extractActivationMetadataFields(am)
                ))
            }
        }

        // SessionSpots
        let spotDesc = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let spots = try? modelContext.fetch(spotDesc) {
            for spot in spots {
                ops.append(.upsertSessionSpot(
                    extractSessionSpotFields(spot)
                ))
            }
        }

        // ActivityLogs
        let logDesc = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let logs = try? modelContext.fetch(logDesc) {
            for log in logs {
                ops.append(.upsertActivityLog(
                    extractActivityLogFields(log)
                ))
            }
        }

        // RadioMacros
        let macroDesc = FetchDescriptor<RadioMacro>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let macros = try? modelContext.fetch(macroDesc) {
            for macro in macros {
                ops.append(.upsertRadioMacro(
                    extractRadioMacroFields(macro)
                ))
            }
        }
    }

    // MARK: - Dirty Flag Clearing

    private func clearDirtyFlagsForJournal(_ record: CKRecord) {
        guard let payload = JournalPayload.from(record: record) else {
            return
        }
        for operation in payload.operations {
            guard let entityId = operation.entityId else {
                continue
            }
            clearDirtyFlag(
                entityType: operation.entityType,
                id: entityId,
                snapshotModifiedAt: operation.entityModifiedAt
            )
        }
    }

    /// Clear `cloudDirtyFlag` for an entity that was just confirmed-saved to
    /// CloudKit, EXCEPT when the local row has been modified since the
    /// snapshot in this journal was taken — in that case the user edited
    /// between snapshot and confirmation and we must keep the flag set so
    /// the next outbound run picks up the new edit. See CAR-245.
    private func clearDirtyFlag(
        entityType: JournalEntityType, id: UUID,
        snapshotModifiedAt: Date?
    ) {
        switch entityType {
        case .qso:
            clearQSODirtyFlag(id: id, snapshotModifiedAt: snapshotModifiedAt)
        case .servicePresence:
            let desc = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate { $0.id == id }, limit: 1
            )
            if let sp = try? modelContext.boundedFetch(desc).first {
                sp.cloudDirtyFlag = false
            }
        case .loggingSession:
            var desc = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let ls = try? modelContext.fetch(desc).first {
                ls.cloudDirtyFlag = false
            }
        case .sessionSpot:
            var desc = FetchDescriptor<SessionSpot>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let spot = try? modelContext.fetch(desc).first {
                spot.cloudDirtyFlag = false
            }
        case .activityLog:
            var desc = FetchDescriptor<ActivityLog>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let log = try? modelContext.fetch(desc).first {
                log.cloudDirtyFlag = false
            }
        case .radioMacro:
            clearRadioMacroDirtyFlag(id: id, snapshotModifiedAt: snapshotModifiedAt)
        case .activationMetadata:
            break // Uses synthetic IDs, handled differently
        }
    }

    /// Clear a confirmed-saved QSO's dirty flag (CAR-245 guard). Routes to the
    /// Rust store when QSO authority is flipped, else SwiftData.
    private func clearQSODirtyFlag(id: UUID, snapshotModifiedAt: Date?) {
        if let qsoJournalStore {
            // The store applies the CAR-245 newer-than-snapshot guard itself.
            _ = try? qsoJournalStore.clearDirty(ids: [id], notIfModifiedAfter: snapshotModifiedAt)
            return
        }
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == id }, limit: 1
        )
        if let qso = try? modelContext.boundedFetch(desc).first {
            if let snapshotModifiedAt, let localMod = qso.modifiedAt,
               localMod > snapshotModifiedAt
            {
                // User edited after the snapshot — keep dirty so the
                // newer write flushes on the next outbound pass.
                return
            }
            qso.cloudDirtyFlag = false
        }
    }

    private func clearRadioMacroDirtyFlag(
        id: UUID, snapshotModifiedAt: Date?
    ) {
        var desc = FetchDescriptor<RadioMacro>(
            predicate: #Predicate { $0.id == id }
        )
        desc.fetchLimit = 1
        guard let macro = try? modelContext.fetch(desc).first else {
            return
        }
        if let snapshotModifiedAt,
           macro.updatedAt > snapshotModifiedAt
        {
            // User edited after the snapshot — keep dirty so the newer
            // write flushes on the next outbound pass.
            return
        }
        macro.cloudDirtyFlag = false
    }
}
