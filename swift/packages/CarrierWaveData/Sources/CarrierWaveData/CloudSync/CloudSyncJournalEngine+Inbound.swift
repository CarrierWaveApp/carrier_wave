import CloudKit
import Foundation
import SwiftData

// MARK: - Inbound: Applying Journal Entries from CloudKit

extension CloudSyncJournalEngine {
    /// Process inbound journal CKRecords and apply their operations.
    func handleInboundChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) {
        ensureModelContext()
        // CAR-244: gate the ModelContext.didSave observer so the save below
        // doesn't immediately reschedule outbound (inbound→outbound echo).
        isApplyingInbound = true
        defer { isApplyingInbound = false }

        let startTime = ContinuousClock.now
        var totalOps = 0
        var journalEntryCount = 0
        // Track LoggingSession UUIDs touched by this batch so we can
        // emit a continuity notification (and run the active-session
        // normalizer) once everything has been applied.
        touchedSessionIDsThisBatch.removeAll()
        for modification in changes.modifications {
            let record = modification.record
            guard record.recordType == JournalPayload.recordType else {
                // Skip legacy per-record types during migration
                continue
            }
            guard let payload = JournalPayload.from(record: record) else {
                logger.warning(
                    "Failed to decode journal: \(record.recordID.recordName)"
                )
                continue
            }
            // Skip our own journal entries
            guard payload.deviceId != currentDeviceId() else {
                continue
            }
            applyPayload(payload)
            totalOps += payload.operations.count
            journalEntryCount += 1
        }

        if totalOps > 0 {
            normalizeActiveSessionsAfterInbound()
            try? modelContext.save()
            let elapsed = ContinuousClock.now - startTime
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18
            let event = CloudSyncEvent(
                category: .fetch,
                detail: "Applied \(totalOps) ops from \(journalEntryCount) journal entries",
                recordCount: totalOps,
                duration: seconds,
                journalTailCount: journalEntryCount
            )
            Task { [eventLog] in await eventLog.append(event) }
            Task {
                await delegate?.journalEngine(self, didLogEvent: event)
            }
            Task {
                await delegate?.journalEngine(
                    self, didUpdateStatus: "Applied \(totalOps) changes"
                )
            }
            postContinuityNotificationIfNeeded()
        }
    }

    // MARK: - Active session continuity

    /// Keep at most one LoggingSession with `status == .active`. When
    /// inbound CloudKit changes flip a remote session to active, this
    /// pauses any older local-active sessions so the most recently
    /// started session "wins" — the same conflict rule both devices
    /// run, so they converge without coordination.
    private func normalizeActiveSessionsAfterInbound() {
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.statusRawValue == "active" },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        desc.fetchLimit = 20
        guard let sessions = try? modelContext.fetch(desc), sessions.count > 1 else {
            return
        }
        // Dedup by UUID — CloudKit mirroring can produce ~3x duplicates.
        var seen: Set<UUID> = []
        var winner: LoggingSession?
        for session in sessions {
            guard seen.insert(session.id).inserted else {
                continue
            }
            if winner == nil {
                winner = session
                continue
            }
            // Older actives get paused. Marking dirty so the pause
            // propagates to the other devices on next outbound.
            session.status = .paused
            session.cloudDirtyFlag = true
        }
    }

    private func postContinuityNotificationIfNeeded() {
        let touched = Array(touchedSessionIDsThisBatch)
        guard !touched.isEmpty else {
            return
        }
        let origin = SessionContinuityOrigin.cloudkit.rawValue
        // Always post on main so SwiftUI views observing it can update
        // without trampolining themselves. Capture only Sendable values
        // (UUIDs + a String) into the closure and assemble userInfo at
        // the point of post.
        let post: @Sendable () -> Void = {
            NotificationCenter.default.post(
                name: .cwLoggingSessionRemotelyChanged,
                object: nil,
                userInfo: [
                    SessionContinuityUserInfoKey.affectedSessionIDsKey: touched,
                    SessionContinuityUserInfoKey.originKey: origin,
                ]
            )
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async {
                post()
            }
        }
    }

    /// Apply all operations in a journal payload to SwiftData.
    private func applyPayload(_ payload: JournalPayload) {
        for operation in payload.operations {
            applyOperation(operation, timestamp: payload.timestamp)
        }
    }

    // MARK: - Operation Application

    private func applyOperation(
        _ op: JournalOperation, timestamp: Date
    ) {
        switch op {
        case let .upsertQSO(fields):
            applyQSOUpsert(fields, remoteTimestamp: timestamp)
        case let .upsertServicePresence(fields):
            applyServicePresenceUpsert(fields)
        case let .upsertLoggingSession(fields):
            applyLoggingSessionUpsert(fields, remoteTimestamp: timestamp)
        case let .upsertActivationMetadata(fields):
            applyActivationMetadataUpsert(fields, remoteTimestamp: timestamp)
        case let .upsertSessionSpot(fields):
            applySessionSpotUpsert(fields)
        case let .upsertActivityLog(fields):
            applyActivityLogUpsert(fields)
        case let .upsertRadioMacro(fields):
            applyRadioMacroUpsert(fields)
        case let .delete(entityType, id):
            applyDeletion(entityType: entityType, id: id)
        }
    }

    private func applyQSOUpsert(
        _ fields: QSOFields, remoteTimestamp: Date
    ) {
        if let qsoJournalStore {
            // Store-authoritative: merge-or-insert into cw-store. Reuses the same
            // CloudSyncConflictResolver.mergeQSO and preserves the FfiQso-only
            // columns + dirty flag (no ping-pong). No QueryFacade mirror needed —
            // the store's own observation drives the `.on`-mode read sources.
            try? qsoJournalStore.applyInbound(fields, remoteTimestamp: remoteTimestamp)
            return
        }
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == fields.id }, limit: 1
        )
        if let existing = try? modelContext.boundedFetch(desc).first {
            let localFields = extractQSOFields(existing)
            let localMod = existing.modifiedAt ?? existing.importedAt
            let merged = CloudSyncConflictResolver.mergeQSO(
                local: localFields, remote: fields,
                localModDate: localMod, remoteModDate: remoteTimestamp
            )
            applyQSOFields(merged, to: existing)
            // Do NOT set cloudDirtyFlag — prevents sync ping-pong
            QueryFacade.mirrorQSO(existing)
        } else {
            let qso = QSO.fromFields(fields)
            modelContext.insert(qso)
            QueryFacade.mirrorQSO(qso)
        }
    }

    private func applyServicePresenceUpsert(
        _ fields: ServicePresenceFields
    ) {
        let desc = BoundedDescriptor<ServicePresence>(
            predicate: #Predicate { $0.id == fields.id }, limit: 1
        )
        if let existing = try? modelContext.boundedFetch(desc).first {
            let localFields = extractServicePresenceFields(
                existing, qsoID: existing.qso?.id ?? UUID()
            )
            let merged = CloudSyncConflictResolver.mergeServicePresence(
                local: localFields, remote: fields
            )
            applyServicePresenceFields(merged, to: existing)
        } else if let qsoUUID = fields.qsoUUID {
            let qsoDesc = BoundedDescriptor<QSO>(
                predicate: #Predicate { $0.id == qsoUUID }, limit: 1
            )
            if let qso = try? modelContext.boundedFetch(qsoDesc).first {
                let sp = ServicePresence.fromFields(fields, qso: qso)
                modelContext.insert(sp)
            }
        }
    }

    private func applyLoggingSessionUpsert(
        _ fields: LoggingSessionFields, remoteTimestamp: Date
    ) {
        touchedSessionIDsThisBatch.insert(fields.id)
        var desc = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.id == fields.id }
        )
        desc.fetchLimit = 1
        if let existing = try? modelContext.fetch(desc).first {
            let localFields = extractLoggingSessionFields(existing)
            let localMod = existing.endedAt ?? existing.startedAt
            let merged = CloudSyncConflictResolver.mergeLoggingSession(
                local: localFields, remote: fields,
                localModDate: localMod, remoteModDate: remoteTimestamp
            )
            applySessionFields(merged, to: existing)
        } else {
            let session = LoggingSession.fromFields(fields)
            modelContext.insert(session)
        }
    }

    private func applyActivationMetadataUpsert(
        _ fields: ActivationMetadataFields, remoteTimestamp _: Date
    ) {
        let park = fields.parkReference
        let date = fields.date
        let desc = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate {
                $0.parkReference == park && $0.date == date
            }
        )
        if let existing = try? modelContext.fetch(desc).first {
            applyActivationMetadataFields(fields, to: existing)
        } else {
            let am = ActivationMetadata.fromFields(fields)
            modelContext.insert(am)
        }
    }

    private func applySessionSpotUpsert(_ fields: SessionSpotFields) {
        var desc = FetchDescriptor<SessionSpot>(
            predicate: #Predicate { $0.id == fields.id }
        )
        desc.fetchLimit = 1
        if let existing = try? modelContext.fetch(desc).first {
            applySessionSpotFields(fields, to: existing)
        } else {
            let spot = SessionSpot.fromFields(fields)
            modelContext.insert(spot)
        }
    }

    private func applyActivityLogUpsert(_ fields: ActivityLogFields) {
        var desc = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.id == fields.id }
        )
        desc.fetchLimit = 1
        if let existing = try? modelContext.fetch(desc).first {
            applyActivityLogFields(fields, to: existing)
        } else {
            let log = ActivityLog.fromFields(fields)
            modelContext.insert(log)
        }
    }

    private func applyRadioMacroUpsert(_ fields: RadioMacroFields) {
        let macroID = fields.id
        var desc = FetchDescriptor<RadioMacro>(
            predicate: #Predicate { $0.id == macroID }
        )
        desc.fetchLimit = 1
        if let existing = try? modelContext.fetch(desc).first {
            applyRadioMacroFields(fields, to: existing)
            // Do NOT set cloudDirtyFlag — prevents sync ping-pong.
        } else {
            let macro = RadioMacro.fromFields(fields)
            modelContext.insert(macro)
        }
    }

    /// Apply a QSO deletion (soft-delete via `isHidden`). Routes to the Rust
    /// store when QSO authority is flipped, else SwiftData.
    private func applyQSODeletion(id: UUID) {
        if let qsoJournalStore {
            try? qsoJournalStore.softDelete(id: id)
            return
        }
        let desc = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == id }, limit: 1
        )
        if let qso = try? modelContext.boundedFetch(desc).first {
            qso.isHidden = true // Soft delete
        }
    }

    private func applyDeletion(
        entityType: JournalEntityType, id: UUID
    ) {
        switch entityType {
        case .qso:
            applyQSODeletion(id: id)
        case .servicePresence:
            let desc = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate { $0.id == id }, limit: 1
            )
            if let sp = try? modelContext.boundedFetch(desc).first {
                modelContext.delete(sp)
            }
        case .loggingSession:
            var desc = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let session = try? modelContext.fetch(desc).first {
                modelContext.delete(session)
            }
        case .sessionSpot:
            var desc = FetchDescriptor<SessionSpot>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let spot = try? modelContext.fetch(desc).first {
                modelContext.delete(spot)
            }
        case .activityLog:
            var desc = FetchDescriptor<ActivityLog>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let log = try? modelContext.fetch(desc).first {
                modelContext.delete(log)
            }
        case .radioMacro:
            var desc = FetchDescriptor<RadioMacro>(
                predicate: #Predicate { $0.id == id }
            )
            desc.fetchLimit = 1
            if let macro = try? modelContext.fetch(desc).first {
                modelContext.delete(macro)
            }
        case .activationMetadata:
            break
        }
    }

    // MARK: - Snapshot Bootstrap

    func attemptSnapshotBootstrap() async {
        await delegate?.journalEngine(
            self, didUpdateStatus: "Checking for snapshot..."
        )
        guard let info = await snapshotService.remoteSnapshotInfo() else {
            logger.info("No remote snapshot — starting fresh")
            return
        }
        guard info.schemaVersion <= CloudSyncSnapshotService.schemaVersion,
              info.qsoCount > 0
        else {
            return
        }

        await delegate?.journalEngine(
            self,
            didUpdateStatus: "Downloading snapshot (\(info.qsoCount) QSOs)..."
        )
        do {
            let result = try await snapshotService.downloadSnapshot()
            defer {
                try? FileManager.default.removeItem(
                    at: result.fileURL.deletingLastPathComponent()
                )
            }
            restoreSnapshot(from: result.fileURL, qsoCount: info.qsoCount)

            let bootstrapEvent = CloudSyncEvent(
                category: .fetch,
                detail: "Snapshot bootstrap: \(info.qsoCount) QSOs",
                recordCount: info.qsoCount,
                duration: result.duration,
                byteCount: result.fileSize
            )
            Task { [eventLog] in await eventLog.append(bootstrapEvent) }
            Task {
                await delegate?.journalEngine(
                    self, didLogEvent: bootstrapEvent
                )
            }
        } catch {
            logger.error("Snapshot bootstrap failed: \(error)")
        }
    }

    private func restoreSnapshot(from url: URL, qsoCount: Int) {
        guard let storeURL = container.configurations.first?.url else {
            return
        }

        // Validate snapshot actually contains QSO rows
        guard SnapshotValidator.hasQSOs(at: url) else {
            logger.error(
                "Snapshot has no QSO rows despite metadata claiming \(qsoCount) — aborting restore"
            )
            return
        }

        // Emergency backup before replacing
        SnapshotValidator.backupBeforeRestore(
            storeURL: storeURL, logger: logger
        )

        let fm = FileManager.default
        do {
            try? fm.removeItem(at: storeURL)
            try? fm.removeItem(
                at: storeURL.appendingPathExtension("wal")
            )
            try? fm.removeItem(
                at: storeURL.appendingPathExtension("shm")
            )
            try fm.moveItem(at: url, to: storeURL)
            modelContext = ModelContext(container)
            modelContext.autosaveEnabled = false
            logger.info("Snapshot restored: \(qsoCount) QSOs")
        } catch {
            logger.error("Snapshot restore failed: \(error)")
        }
    }

    private func currentDeviceId() -> String {
        UserDefaults.standard.string(
            forKey: "cloudSyncDeviceId"
        ) ?? ""
    }
}
