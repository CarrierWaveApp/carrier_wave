import CarrierWaveCore
import CloudKit
import Foundation
import os
import SwiftData

/// Background actor implementing CKSyncEngineDelegate.
/// Handles the heavy lifting: record mapping, conflict resolution, and deduplication.
/// Uses a background ModelContext per performance rules.
actor CloudSyncEngine: CKSyncEngineDelegate {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
        modelContext = ModelContext(container)
        modelContext.autosaveEnabled = false
    }

    // MARK: Internal

    /// Start the CKSyncEngine with persisted state
    func start() async throws {
        let state = try await loadSyncState()
        let config = CKSyncEngine.Configuration(
            database: CKContainer(
                identifier: "iCloud.com.jsvana.FullDuplex"
            ).privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        syncEngine = CKSyncEngine(config)

        // Ensure the zone exists
        try await ensureZoneExists()

        // Schedule initial fetch
        syncEngine?.fetchChanges()
    }

    /// Stop the sync engine and save state
    func stop() async {
        if let engine = syncEngine {
            await saveSyncState(engine.state.serialization)
        }
        syncEngine = nil
    }

    /// Schedule pending changes for records that have dirty flags set
    func schedulePendingChanges() async {
        guard let engine = syncEngine else { return }

        let pendingChanges = await collectDirtyRecordIDs()
        if !pendingChanges.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pendingChanges)
            logger.info("Scheduled \(pendingChanges.count) pending changes for sync")
        }
    }

    /// Forward a remote notification to the sync engine
    func handleRemoteNotification(
        _ userInfo: [AnyHashable: Any]
    ) {
        // CKSyncEngine processes the notification internally
        // Just trigger a fetch
        syncEngine?.fetchChanges()
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated func handleEvent(
        _ event: CKSyncEngine.Event,
        syncEngine: CKSyncEngine
    ) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            await saveSyncState(stateUpdate.stateSerialization)

        case .accountChange(let change):
            await handleAccountChange(change)

        case .fetchedDatabaseChanges(let changes):
            await handleFetchedDatabaseChanges(changes)

        case .fetchedRecordZoneChanges(let changes):
            await handleFetchedRecordZoneChanges(changes)

        case .sentDatabaseChanges:
            break // We don't create/delete zones dynamically

        case .sentRecordZoneChanges(let sentChanges):
            await handleSentRecordZoneChanges(sentChanges)

        case .willFetchChanges:
            break

        case .willFetchRecordZoneChanges:
            break

        case .didFetchRecordZoneChanges(let fetchChanges):
            await handleDidFetchRecordZoneChanges(fetchChanges)

        case .didFetchChanges:
            await postSyncNotification()

        case .willSendChanges:
            break

        case .didSendChanges:
            break

        @unknown default:
            logger.warning("Unknown CKSyncEngine event: \(String(describing: event))")
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await buildNextChangeBatch(context, engine: syncEngine)
    }

    // MARK: Private

    private let container: ModelContainer
    private var modelContext: ModelContext
    private var syncEngine: CKSyncEngine?
    private let logger = Logger(subsystem: "com.jsvana.FullDuplex", category: "CloudSync")

    // Limit batch sizes for CloudKit
    private let sendBatchSize = 100
    // State persistence key
    private let stateKey = "cloudSyncEngineState"

    // MARK: - Zone Management

    private func ensureZoneExists() async throws {
        guard let engine = syncEngine else { return }

        let zone = CKRecordZone(zoneID: CKRecordMapper.zoneID)
        let pendingZone = CKSyncEngine.PendingDatabaseChange.saveZone(zone)
        engine.state.add(pendingDatabaseChanges: [pendingZone])
    }

    // MARK: - State Persistence

    private func loadSyncState() async throws -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateKey) else {
            return nil
        }
        return try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: data
        )
    }

    private func saveSyncState(_ state: CKSyncEngine.State.Serialization) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: stateKey)
        } catch {
            logger.error("Failed to save sync state: \(error)")
        }
    }

    // MARK: - Outbound: Collecting Dirty Records

    private func collectDirtyRecordIDs() -> [CKSyncEngine.PendingRecordZoneChange] {
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []

        // Dirty QSOs
        let qsoDescriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyQSOs = try? modelContext.fetch(qsoDescriptor) {
            for qso in dirtyQSOs {
                guard CKRecordMapper.shouldSync(qso: qso) else { continue }
                let recordID = CKRecordMapper.recordID(type: .qso, id: qso.id)
                changes.append(.saveRecord(recordID))
            }
        }

        // Dirty ServicePresence
        let presenceDescriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyPresence = try? modelContext.fetch(presenceDescriptor) {
            for presence in dirtyPresence {
                let recordID = CKRecordMapper.recordID(
                    type: .servicePresence, id: presence.id
                )
                changes.append(.saveRecord(recordID))
            }
        }

        // Dirty LoggingSessions
        let sessionDescriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtySessions = try? modelContext.fetch(sessionDescriptor) {
            for session in dirtySessions {
                let recordID = CKRecordMapper.recordID(
                    type: .loggingSession, id: session.id
                )
                changes.append(.saveRecord(recordID))
            }
        }

        // Dirty ActivationMetadata
        let metadataDescriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate { $0.cloudDirtyFlag == true }
        )
        if let dirtyMetadata = try? modelContext.fetch(metadataDescriptor) {
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

        return changes
    }

    // MARK: - Outbound: Building Change Batches

    private func buildNextChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        engine: CKSyncEngine
    ) -> CKSyncEngine.RecordZoneChangeBatch? {
        let pendingChanges = engine.state.pendingRecordZoneChanges
        guard !pendingChanges.isEmpty else { return nil }

        let batch = pendingChanges.prefix(sendBatchSize)

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for change in batch {
            switch change {
            case .saveRecord(let recordID):
                if let record = buildRecord(for: recordID) {
                    recordsToSave.append(record)
                } else {
                    // Record no longer exists locally; remove from pending
                    engine.state.remove(pendingRecordZoneChanges: [change])
                }
            case .deleteRecord(let recordID):
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
        guard CKRecordMapper.shouldSync(qso: qso) else { return nil }
        return CKRecordMapper.qsoToCKRecord(qso, existingRecord: existingRecord)
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
        return CKRecordMapper.servicePresenceToCKRecord(
            presence, qsoID: qso.id, existingRecord: existingRecord
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
        return CKRecordMapper.loggingSessionToCKRecord(
            session, existingRecord: existingRecord
        )
    }

    private func buildActivationMetadataRecord(
        id: UUID,
        existingRecord: CKRecord?
    ) -> CKRecord? {
        // ActivationMetadata uses a synthetic UUID, so we look up via sync metadata
        guard let meta = lookupSyncMetadata(
            entityType: CKRecordMapper.RecordType.activationMetadata.rawValue,
            localId: id
        ) else {
            return nil
        }

        // Find the actual ActivationMetadata — we stored the mapping in CloudSyncMetadata
        // We need to find it by iterating since it doesn't have a UUID primary key
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
                return CKRecordMapper.activationMetadataToCKRecord(
                    metadata, existingRecord: existingRecord
                )
            }
        }

        return nil
    }

    // MARK: - Outbound: Handling Sent Changes

    private func handleSentRecordZoneChanges(
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
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.SaveFailure
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
        failure: CKSyncEngine.Event.SentRecordZoneChanges.SaveFailure
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

    private func resolveQSOConflict(
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
            localModDate: clientRecord.modificationDate ?? Date.distantPast,
            remoteModDate: serverRecord.modificationDate ?? Date.distantPast
        )

        // Apply merged fields to local QSO
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        if let qso = try? modelContext.fetch(descriptor).first {
            CKRecordMapper.applyFields(merged, to: qso)
            qso.cloudDirtyFlag = true // re-upload merged version

            upsertSyncMetadata(
                entityType: CKRecordMapper.RecordType.qso.rawValue,
                localId: uuid,
                recordName: serverRecord.recordID.recordName,
                record: serverRecord
            )
        }
    }

    private func resolveServicePresenceConflict(
        uuid: UUID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        guard let localFields = CKRecordMapper.servicePresenceFields(from: clientRecord),
              let remoteFields = CKRecordMapper.servicePresenceFields(from: serverRecord)
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

    private func resolveLoggingSessionConflict(
        uuid: UUID,
        clientRecord: CKRecord,
        serverRecord: CKRecord
    ) {
        guard let localFields = CKRecordMapper.loggingSessionFields(from: clientRecord),
              let remoteFields = CKRecordMapper.loggingSessionFields(from: serverRecord)
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

    private func resolveActivationMetadataConflict(
        serverRecord: CKRecord,
        clientRecord: CKRecord
    ) {
        // Last-writer-wins for ActivationMetadata
        guard let remoteFields = CKRecordMapper.activationMetadataFields(from: serverRecord)
        else {
            return
        }
        processInboundActivationMetadata(
            remoteFields,
            record: serverRecord
        )
    }

    // MARK: - Inbound: Handling Fetched Changes

    private func handleFetchedDatabaseChanges(
        _ changes: CKSyncEngine.Event.FetchedDatabaseChanges
    ) {
        // Handle zone deletions — if our zone was deleted, clear all sync metadata
        for deletion in changes.deletions {
            if deletion.zoneID == CKRecordMapper.zoneID {
                logger.warning("Sync zone was deleted; clearing all sync metadata")
                clearAllSyncMetadata()
            }
        }
    }

    private func handleFetchedRecordZoneChanges(
        _ changes: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) {
        // Process modifications
        for modification in changes.modifications {
            processInboundRecord(modification.record)
        }

        // Process deletions
        for deletion in changes.deletions {
            processInboundDeletion(deletion.recordID)
        }

        try? modelContext.save()
    }

    private func handleDidFetchRecordZoneChanges(
        _ event: CKSyncEngine.Event.DidFetchRecordZoneChanges
    ) {
        // Good place to save any accumulated changes
        try? modelContext.save()
    }

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

        // Skip metadata pseudo-modes
        if CKRecordMapper.metadataModes.contains(fields.mode.uppercased()) {
            return
        }

        let uuid = fields.id

        // 1. Look up by UUID
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1

        if let existingQSO = try? modelContext.fetch(descriptor).first {
            // Existing QSO found by UUID — merge
            let localFields = CKRecordMapper.qsoFields(
                from: CKRecordMapper.qsoToCKRecord(existingQSO)
            )!
            let merged = CloudSyncConflictResolver.mergeQSO(
                local: localFields,
                remote: fields,
                localModDate: existingQSO.importedAt,
                remoteModDate: record.modificationDate ?? Date()
            )
            CKRecordMapper.applyFields(merged, to: existingQSO)
            // Don't set cloudDirtyFlag — this came from the cloud
        } else {
            // 2. Check deduplication key
            let deduplicationKey = fields.deduplicationKey
            let allQSOs = FetchDescriptor<QSO>()
            if let existing = (try? modelContext.fetch(allQSOs))?.first(
                where: { $0.deduplicationKey == deduplicationKey }
            ) {
                // Found by dedup key — merge and link
                let localFields = CKRecordMapper.qsoFields(
                    from: CKRecordMapper.qsoToCKRecord(existing)
                )!
                let merged = CloudSyncConflictResolver.mergeQSO(
                    local: localFields,
                    remote: fields,
                    localModDate: existing.importedAt,
                    remoteModDate: record.modificationDate ?? Date()
                )
                CKRecordMapper.applyFields(merged, to: existing)
            } else {
                // 3. Truly new — create
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
        }

        // Store sync metadata
        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.qso.rawValue,
            localId: uuid,
            recordName: record.recordID.recordName,
            record: record
        )
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
            // Merge using union semantics
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
        } else {
            // New presence record — find parent QSO
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

        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.servicePresence.rawValue,
            localId: uuid,
            recordName: record.recordID.recordName,
            record: record
        )
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
            // Last-writer-wins
            let localFields = CKRecordMapper.loggingSessionFields(
                from: CKRecordMapper.loggingSessionToCKRecord(existing)
            )!
            let merged = CloudSyncConflictResolver.mergeLoggingSession(
                local: localFields,
                remote: fields,
                localModDate: existing.endedAt ?? existing.startedAt,
                remoteModDate: record.modificationDate ?? Date()
            )
            applySessionFields(merged, to: existing)
        } else {
            // New session
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
            modelContext.insert(session)
        }

        upsertSyncMetadata(
            entityType: CKRecordMapper.RecordType.loggingSession.rawValue,
            localId: uuid,
            recordName: record.recordID.recordName,
            record: record
        )
    }

    private func processInboundActivationMetadataRecord(_ record: CKRecord) {
        guard let fields = CKRecordMapper.activationMetadataFields(from: record) else {
            return
        }
        processInboundActivationMetadata(fields, record: record)
    }

    private func processInboundActivationMetadata(
        _ fields: ActivationMetadataFields,
        record: CKRecord
    ) {
        // Look up existing by park+date
        let parkRef = fields.parkReference
        let date = fields.date
        var descriptor = FetchDescriptor<ActivationMetadata>(
            predicate: #Predicate {
                $0.parkReference == parkRef && $0.date == date
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            // Last-writer-wins
            existing.title = fields.title
            existing.watts = fields.watts
            existing.weather = fields.weather
            existing.solarConditions = fields.solarConditions
            existing.averageWPM = fields.averageWPM
            existing.solarKIndex = fields.solarKIndex
            existing.solarFlux = fields.solarFlux
            existing.solarSunspots = fields.solarSunspots
            existing.solarPropagationRating = fields.solarPropagationRating
            existing.solarAIndex = fields.solarAIndex
            existing.solarBandConditions = fields.solarBandConditions
            existing.solarTimestamp = fields.solarTimestamp
            existing.weatherTemperatureF = fields.weatherTemperatureF
            existing.weatherTemperatureC = fields.weatherTemperatureC
            existing.weatherHumidity = fields.weatherHumidity
            existing.weatherWindSpeed = fields.weatherWindSpeed
            existing.weatherWindDirection = fields.weatherWindDirection
            existing.weatherDescription = fields.weatherDescription
            existing.weatherTimestamp = fields.weatherTimestamp
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

    // MARK: - Inbound: Deletions

    private func processInboundDeletion(_ recordID: CKRecord.ID) {
        let recordName = recordID.recordName
        guard let entityType = CKRecordMapper.parseEntityType(from: recordName),
              let uuid = CKRecordMapper.parseUUID(from: recordName)
        else {
            return
        }

        switch entityType {
        case CKRecordMapper.RecordType.qso.rawValue:
            // Soft delete: mark as hidden rather than deleting
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
            var descriptor = FetchDescriptor<LoggingSession>(
                predicate: #Predicate { $0.id == uuid }
            )
            descriptor.fetchLimit = 1
            if let session = try? modelContext.fetch(descriptor).first {
                modelContext.delete(session)
            }

        case CKRecordMapper.RecordType.activationMetadata.rawValue:
            // ActivationMetadata deletion — find via sync metadata
            if let meta = lookupSyncMetadata(entityType: entityType, localId: uuid) {
                deleteSyncMetadata(entityType: entityType, localId: uuid)
                _ = meta // metadata itself already deleted
            }

        default:
            break
        }

        deleteSyncMetadata(entityType: entityType, localId: uuid)
        try? modelContext.save()
    }

    // MARK: - Account Changes

    private func handleAccountChange(
        _ change: CKSyncEngine.Event.AccountChange
    ) {
        switch change.changeType {
        case .signIn:
            logger.info("iCloud account signed in")
            // Mark all records as dirty for initial upload
            Task {
                await markAllRecordsDirty()
                await schedulePendingChanges()
            }

        case .signOut:
            logger.info("iCloud account signed out")
            clearAllSyncMetadata()

        case .switchAccounts:
            logger.info("iCloud account switched")
            clearAllSyncMetadata()
            Task {
                await markAllRecordsDirty()
                await schedulePendingChanges()
            }

        @unknown default:
            break
        }
    }

    // MARK: - Sync Metadata Helpers

    private func lookupSyncMetadata(
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

    private func upsertSyncMetadata(
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

    private func deleteSyncMetadata(entityType: String, localId: UUID) {
        if let existing = lookupSyncMetadata(
            entityType: entityType, localId: localId
        ) {
            modelContext.delete(existing)
        }
    }

    private func clearAllSyncMetadata() {
        let descriptor = FetchDescriptor<CloudSyncMetadata>()
        if let all = try? modelContext.fetch(descriptor) {
            for meta in all {
                modelContext.delete(meta)
            }
        }
        try? modelContext.save()
    }

    // MARK: - Dirty Flag Helpers

    private func clearDirtyFlag(entityType: String, id: UUID) {
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
            // Find via sync metadata mapping
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

    private func markAllRecordsDirty() {
        // Mark all QSOs (excluding metadata pseudo-modes)
        let qsoDescriptor = FetchDescriptor<QSO>()
        if let qsos = try? modelContext.fetch(qsoDescriptor) {
            for qso in qsos where CKRecordMapper.shouldSync(qso: qso) {
                qso.cloudDirtyFlag = true
            }
        }

        // Mark all ServicePresence
        let presenceDescriptor = FetchDescriptor<ServicePresence>()
        if let presences = try? modelContext.fetch(presenceDescriptor) {
            for presence in presences {
                presence.cloudDirtyFlag = true
            }
        }

        // Mark all LoggingSessions
        let sessionDescriptor = FetchDescriptor<LoggingSession>()
        if let sessions = try? modelContext.fetch(sessionDescriptor) {
            for session in sessions {
                session.cloudDirtyFlag = true
            }
        }

        // Mark all ActivationMetadata
        let metadataDescriptor = FetchDescriptor<ActivationMetadata>()
        if let metadata = try? modelContext.fetch(metadataDescriptor) {
            for am in metadata {
                am.cloudDirtyFlag = true
            }
        }

        try? modelContext.save()
    }

    // MARK: - Session Field Application

    private func applySessionFields(
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

    // MARK: - Notifications

    private func postSyncNotification() {
        NotificationCenter.default.post(name: .didSyncQSOs, object: nil)
    }
}
