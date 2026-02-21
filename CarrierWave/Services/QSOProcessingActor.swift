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

    // Merge, creation, and QSO factory helpers are in QSOProcessingActor+Merge.swift
}

// MARK: - QSOProcessingActor Helpers

extension QSOProcessingActor {
    /// Reconcile QRZ presence against downloaded keys on background thread.
    /// Returns the number of presence records reset to needsUpload.
    @discardableResult
    func reconcileQRZPresence(
        downloadedKeys: Set<String>,
        userCallsigns: Set<String>,
        container: ModelContainer
    ) async throws -> Int {
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

        return modifiedCount
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
    /// Must match the logic in QSO.deduplicationKey exactly.
    static func computeDeduplicationKey(
        callsign: String,
        band: String,
        mode: String,
        timestamp: Date
    ) -> String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120 // 2 minute buckets
        let trimmedCallsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let canonicalMode = ModeEquivalence.canonicalName(mode).uppercased()
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}
