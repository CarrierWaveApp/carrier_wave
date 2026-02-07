import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - QSOProcessingActor

/// Background actor for processing downloaded QSOs without blocking the main thread.
/// Creates its own ModelContext from the container to perform all work off the main thread.
actor QSOProcessingActor {
    // MARK: Internal

    /// Result of processing, returned to main actor
    struct ProcessingResult: Sendable {
        let created: Int
        let merged: Int
        /// IDs of newly created QSOs (for activity detection on main actor)
        let createdQSOIds: [UUID]
        /// Log messages generated during processing (for SyncDebugLog on main actor)
        var logMessages: [String]
    }

    /// Progress callback info
    struct ProgressInfo: Sendable {
        let processed: Int
        let total: Int
        let phase: String
    }

    /// Process fetched QSOs on background thread, returning counts and created QSO IDs.
    func processDownloadedQSOs(
        _ fetched: [FetchedQSO],
        container: ModelContainer,
        onProgress: (@Sendable (ProgressInfo) -> Void)? = nil
    ) async throws -> ProcessingResult {
        var logMessages: [String] = []

        // Create background context
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let totalFetched = fetched.count

        // Group fetched QSOs by deduplication key
        onProgress?(ProgressInfo(processed: 0, total: totalFetched, phase: "Grouping QSOs..."))
        let byKey = groupByDeduplicationKey(fetched)

        // Log source breakdown
        let breakdownStr = buildSourceBreakdown(fetched)
        logMessages.append("Processing \(fetched.count) QSOs: \(breakdownStr)")

        // Fetch existing QSO deduplication keys (not full objects - we only need keys)
        onProgress?(ProgressInfo(processed: 0, total: totalFetched, phase: "Loading database..."))
        let existingByKey = try await fetchExistingQSOKeys(context: context)
        logMessages.append("Found \(existingByKey.count) existing QSOs in database")

        // Process and save QSOs in batches
        var result = try await processQSOGroups(
            byKey: byKey,
            existingByKey: existingByKey,
            context: context,
            onProgress: onProgress
        )

        logMessages.append("Process result: created=\(result.created), merged=\(result.merged)")
        result.logMessages = logMessages
        return result
    }

    // MARK: Private

    /// Process QSO groups with batched saves to avoid UI stalls.
    private func processQSOGroups(
        byKey: [String: [FetchedQSO]],
        existingByKey: [String: UUID],
        context: ModelContext,
        onProgress: (@Sendable (ProgressInfo) -> Void)?
    ) async throws -> ProcessingResult {
        var created = 0
        var merged = 0
        var createdQSOIds: [UUID] = []

        let totalGroups = byKey.count
        var processedGroups = 0
        let saveBatchSize = 500
        var unsavedCount = 0

        for (key, fetchedGroup) in byKey {
            try Task.checkCancellation()

            if let existingId = existingByKey[key] {
                try mergeIntoExisting(
                    existingId: existingId, fetchedGroup: fetchedGroup, context: context
                )
                merged += 1
            } else {
                let newId = try createNewQSOFromGroup(fetchedGroup, context: context)
                createdQSOIds.append(newId)
                created += 1
            }

            processedGroups += 1
            unsavedCount += 1

            // Save in batches to avoid one huge save at the end
            if unsavedCount >= saveBatchSize {
                onProgress?(
                    ProgressInfo(
                        processed: processedGroups, total: totalGroups, phase: "Saving batch..."
                    )
                )
                try context.save()
                unsavedCount = 0
                await Task.yield()
            } else if processedGroups.isMultiple(of: 100) {
                onProgress?(
                    ProgressInfo(
                        processed: processedGroups, total: totalGroups, phase: "Processing QSOs..."
                    )
                )
                await Task.yield()
            }
        }

        // Save any remaining changes
        if unsavedCount > 0 {
            onProgress?(
                ProgressInfo(
                    processed: totalGroups, total: totalGroups, phase: "Saving..."
                )
            )
            try context.save()
        }

        return ProcessingResult(
            created: created, merged: merged, createdQSOIds: createdQSOIds, logMessages: []
        )
    }

    /// Fetch existing QSO deduplication keys in batches.
    private func fetchExistingQSOKeys(context: ModelContext) async throws -> [String: UUID] {
        var result: [String: UUID] = [:]

        // Get total count
        let countDescriptor = FetchDescriptor<QSO>()
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0

        if totalCount == 0 {
            return result
        }

        result.reserveCapacity(totalCount)

        let batchSize = 1_000
        var offset = 0

        while offset < totalCount {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<QSO>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }

            for qso in batch {
                let key = Self.computeDeduplicationKey(
                    callsign: qso.callsign,
                    band: qso.band,
                    mode: qso.mode,
                    timestamp: qso.timestamp
                )
                result[key] = qso.id
            }

            offset += batchSize

            // Yield to allow other tasks to run
            if offset.isMultiple(of: 5_000) {
                await Task.yield()
            }
        }

        return result
    }

    /// Group fetched QSOs by their deduplication key.
    private func groupByDeduplicationKey(_ fetched: [FetchedQSO]) -> [String: [FetchedQSO]] {
        var byKey: [String: [FetchedQSO]] = [:]
        for qso in fetched {
            let key = Self.computeDeduplicationKey(
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp
            )
            byKey[key, default: []].append(qso)
        }
        return byKey
    }

    private func buildSourceBreakdown(_ fetched: [FetchedQSO]) -> String {
        var sourceBreakdown: [ServiceType: Int] = [:]
        for qso in fetched {
            sourceBreakdown[qso.source, default: 0] += 1
        }
        return sourceBreakdown.map { "\($0.key.displayName)=\($0.value)" }.joined(separator: ", ")
    }

    /// Merge fetched data into an existing QSO by ID.
    private func mergeIntoExisting(
        existingId: UUID,
        fetchedGroup: [FetchedQSO],
        context: ModelContext
    ) throws {
        // Fetch the existing QSO by ID
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == existingId })
        descriptor.fetchLimit = 1
        guard let existing = try context.fetch(descriptor).first else {
            return
        }

        for fetched in fetchedGroup {
            // Merge fields (richest data wins)
            existing.frequency = existing.frequency ?? fetched.frequency
            existing.rstSent = existing.rstSent.nonEmpty ?? fetched.rstSent
            existing.rstReceived = existing.rstReceived.nonEmpty ?? fetched.rstReceived
            existing.myGrid = existing.myGrid.nonEmpty ?? fetched.myGrid
            existing.theirGrid = existing.theirGrid.nonEmpty ?? fetched.theirGrid
            existing.parkReference = existing.parkReference.nonEmpty ?? fetched.parkReference
            existing.theirParkReference =
                existing.theirParkReference.nonEmpty ?? fetched.theirParkReference
            existing.notes = existing.notes.nonEmpty ?? fetched.notes
            existing.rawADIF = existing.rawADIF.nonEmpty ?? fetched.rawADIF
            existing.name = existing.name.nonEmpty ?? fetched.name
            existing.qth = existing.qth.nonEmpty ?? fetched.qth
            existing.state = existing.state.nonEmpty ?? fetched.state
            existing.country = existing.country.nonEmpty ?? fetched.country
            existing.power = existing.power ?? fetched.power
            existing.sotaRef = existing.sotaRef.nonEmpty ?? fetched.sotaRef

            // QRZ-specific
            if fetched.source == .qrz {
                existing.qrzLogId = existing.qrzLogId ?? fetched.qrzLogId
                existing.qrzConfirmed = existing.qrzConfirmed || fetched.qrzConfirmed
                existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
                // DXCC from QRZ if we don't have one yet
                existing.dxcc = existing.dxcc ?? fetched.dxcc
            }

            // LoTW-specific
            if fetched.source == .lotw {
                if fetched.lotwConfirmed {
                    existing.lotwConfirmed = true
                    existing.lotwConfirmedDate =
                        existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
                }
                existing.dxcc = existing.dxcc ?? fetched.dxcc
            }

            // Update or create ServicePresence
            markPresent(qso: existing, service: fetched.source, context: context)
        }
    }

    /// Create a new QSO from a group of fetched QSOs (merges all sources).
    private func createNewQSOFromGroup(_ fetchedGroup: [FetchedQSO], context: ModelContext) throws
        -> UUID
    {
        let merged = mergeFetchedGroup(fetchedGroup)
        let newQSO = createQSO(from: merged)
        context.insert(newQSO)

        // Create presence records for all sources that had this QSO
        let sources = Set(fetchedGroup.map(\.source))

        for service in ServiceType.allCases {
            // POTA uploads only apply to QSOs where user was activating from a park
            let skipPOTAUpload = service == .pota && (newQSO.parkReference?.isEmpty ?? true)

            let presence =
                if sources.contains(service) {
                    ServicePresence.downloaded(from: service, qso: newQSO)
                } else if service.supportsUpload, !skipPOTAUpload {
                    ServicePresence.needsUpload(to: service, qso: newQSO)
                } else {
                    ServicePresence(serviceType: service, isPresent: false, qso: newQSO)
                }
            context.insert(presence)
            newQSO.servicePresence.append(presence)
        }

        return newQSO.id
    }

    /// Mark QSO as present in a service.
    private func markPresent(qso: QSO, service: ServiceType, context: ModelContext) {
        if let existing = qso.presence(for: service) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: qso)
            context.insert(newPresence)
            qso.servicePresence.append(newPresence)
        }
    }

    /// Merge multiple fetched QSOs into one.
    private func mergeFetchedGroup(_ group: [FetchedQSO]) -> FetchedQSO {
        guard var merged = group.first else {
            fatalError("Empty group in mergeFetchedGroup")
        }

        for other in group.dropFirst() {
            merged = FetchedQSO(
                callsign: merged.callsign,
                band: merged.band,
                mode: merged.mode,
                frequency: merged.frequency ?? other.frequency,
                timestamp: merged.timestamp,
                rstSent: merged.rstSent.nonEmpty ?? other.rstSent,
                rstReceived: merged.rstReceived.nonEmpty ?? other.rstReceived,
                myCallsign: merged.myCallsign.isEmpty ? other.myCallsign : merged.myCallsign,
                myGrid: merged.myGrid.nonEmpty ?? other.myGrid,
                theirGrid: merged.theirGrid.nonEmpty ?? other.theirGrid,
                parkReference: merged.parkReference.nonEmpty ?? other.parkReference,
                theirParkReference: merged.theirParkReference.nonEmpty ?? other.theirParkReference,
                notes: merged.notes.nonEmpty ?? other.notes,
                rawADIF: merged.rawADIF.nonEmpty ?? other.rawADIF,
                name: merged.name.nonEmpty ?? other.name,
                qth: merged.qth.nonEmpty ?? other.qth,
                state: merged.state.nonEmpty ?? other.state,
                country: merged.country.nonEmpty ?? other.country,
                power: merged.power ?? other.power,
                sotaRef: merged.sotaRef.nonEmpty ?? other.sotaRef,
                qrzLogId: merged.qrzLogId ?? other.qrzLogId,
                qrzConfirmed: merged.qrzConfirmed || other.qrzConfirmed,
                lotwConfirmedDate: merged.lotwConfirmedDate ?? other.lotwConfirmedDate,
                lotwConfirmed: merged.lotwConfirmed || other.lotwConfirmed,
                dxcc: merged.dxcc ?? other.dxcc,
                source: merged.source
            )
        }

        return merged
    }

    /// Create a QSO from merged fetched data.
    private func createQSO(from fetched: FetchedQSO) -> QSO {
        QSO(
            callsign: fetched.callsign,
            band: fetched.band,
            mode: fetched.mode,
            frequency: fetched.frequency,
            timestamp: fetched.timestamp,
            rstSent: fetched.rstSent,
            rstReceived: fetched.rstReceived,
            myCallsign: fetched.myCallsign,
            myGrid: fetched.myGrid,
            theirGrid: fetched.theirGrid,
            parkReference: fetched.parkReference,
            theirParkReference: fetched.theirParkReference,
            notes: fetched.notes,
            importSource: fetched.source.toImportSource,
            rawADIF: fetched.rawADIF,
            name: fetched.name,
            qth: fetched.qth,
            state: fetched.state,
            country: fetched.country,
            power: fetched.power,
            sotaRef: fetched.sotaRef,
            qrzLogId: fetched.qrzLogId,
            qrzConfirmed: fetched.qrzConfirmed,
            lotwConfirmedDate: fetched.lotwConfirmedDate,
            lotwConfirmed: fetched.lotwConfirmed,
            dxcc: fetched.dxcc
        )
    }
}

// MARK: - QSOProcessingActor Helpers

extension QSOProcessingActor {
    /// Reconcile QRZ presence against downloaded keys on background thread.
    func reconcileQRZPresence(
        downloadedKeys: Set<String>,
        userCallsigns: Set<String>,
        container: ModelContainer
    ) async throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch ServicePresence records for QRZ that are marked as present
        // This is more efficient than fetching all QSOs
        // Note: SwiftData predicates don't support enum captures, so we fetch all
        // presence records marked as present and filter in memory
        let presenceDescriptor = FetchDescriptor<ServicePresence>(
            predicate: #Predicate<ServicePresence> { $0.isPresent }
        )
        let allPresenceRecords = try context.fetch(presenceDescriptor)
        let presenceRecords = allPresenceRecords.filter { $0.serviceType == .qrz }

        var modifiedCount = 0
        for (index, presence) in presenceRecords.enumerated() {
            try Task.checkCancellation()

            guard let qso = presence.qso else {
                continue
            }

            // Check if QRZ returned this QSO
            let qsoKey = Self.computeDeduplicationKey(
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp
            )
            let isPresent = isQSOPresentInDownloaded(
                qsoDeduplicationKey: qsoKey,
                qsoMyCallsign: qso.myCallsign,
                downloadedKeys: downloadedKeys,
                userCallsigns: userCallsigns
            )

            if !isPresent {
                presence.isPresent = false
                presence.needsUpload = true
                modifiedCount += 1
            }

            // Yield periodically to allow cancellation
            if index.isMultiple(of: 500) {
                await Task.yield()
            }
        }

        if modifiedCount > 0 {
            try context.save()
        }
    }

    /// Check if a QSO is present in the downloaded set, considering callsign aliases.
    func isQSOPresentInDownloaded(
        qsoDeduplicationKey: String,
        qsoMyCallsign: String,
        downloadedKeys: Set<String>,
        userCallsigns: Set<String>
    ) -> Bool {
        // First, check exact match
        if downloadedKeys.contains(qsoDeduplicationKey) {
            return true
        }

        // If the QSO's myCallsign is one of the user's callsigns, check if any variant exists
        let myCallsign = qsoMyCallsign.uppercased()
        guard !myCallsign.isEmpty, userCallsigns.contains(myCallsign) else {
            return false
        }

        // The deduplication key already ignores MYCALLSIGN, so if exact key isn't found,
        // the QSO truly isn't present
        return false
    }

    // POTA Presence Reconciliation is in QSOProcessingActor+POTAReconcile.swift

    /// Compute deduplication key from QSO fields.
    /// Duplicates the logic from QSO.deduplicationKey to avoid actor isolation issues.
    static func computeDeduplicationKey(
        callsign: String,
        band: String,
        mode: String,
        timestamp: Date
    ) -> String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120 // 2 minute buckets
        return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
    }
}
