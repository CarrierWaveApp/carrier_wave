import CarrierWaveData
import Foundation
import SwiftData

// MARK: - QSOProcessingError

enum QSOProcessingError: Error, LocalizedError {
    case emptyGroup

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .emptyGroup:
            "Empty group passed to mergeFetchedGroup"
        }
    }
}

// MARK: - QSOProcessingActor

/// Background actor for processing downloaded QSOs without blocking the main thread.
/// Creates its own ModelContext from the container to perform all work off the main thread.
actor QSOProcessingActor {
    // MARK: Internal

    /// Result of processing, returned to main actor
    struct ProcessingResult {
        let created: Int
        let merged: Int
        /// IDs of newly created QSOs (for activity detection on main actor)
        let createdQSOIds: [UUID]
        /// Log messages generated during processing (for SyncDebugLog on main actor)
        var logMessages: [String]
    }

    /// Progress callback info
    struct ProgressInfo {
        let processed: Int
        let total: Int
        let phase: String
    }

    /// How to handle park references found in comment/notes fields.
    /// Set before each processing run via processDownloadedQSOs().
    var commentParkAction: CommentParkAction = .theirPark

    /// Services that are configured for upload — only these get needsUpload presence records.
    /// Set before each processing run via processDownloadedQSOs().
    var configuredUploadServices: Set<ServiceType> = []

    /// Process fetched QSOs on background thread, returning counts and created QSO IDs.
    func processDownloadedQSOs(
        _ fetched: [FetchedQSO],
        container: ModelContainer,
        configuredUploadServices: Set<ServiceType> = [],
        commentParkAction: CommentParkAction = .theirPark,
        onProgress: (@Sendable (ProgressInfo) -> Void)? = nil
    ) async throws -> ProcessingResult {
        self.configuredUploadServices = configuredUploadServices
        self.commentParkAction = commentParkAction
        var logMessages: [String] = []

        let totalFetched = fetched.count

        // Group fetched QSOs by deduplication key
        onProgress?(ProgressInfo(processed: 0, total: totalFetched, phase: "Grouping QSOs..."))
        let byKey = groupByDeduplicationKey(fetched)

        // Log source breakdown
        let breakdownStr = buildSourceBreakdown(fetched)
        logMessages.append("Processing \(fetched.count) QSOs: \(breakdownStr)")

        // Fetch existing QSO deduplication keys (not full objects - we only need keys)
        onProgress?(ProgressInfo(processed: 0, total: totalFetched, phase: "Loading database..."))
        let existingByKey = try await fetchExistingQSOKeys(container: container)
        logMessages.append("Found \(existingByKey.count) existing QSOs in database")

        // Process and save QSOs in batches
        var result = try await processQSOGroups(
            byKey: byKey,
            existingByKey: existingByKey,
            container: container,
            onProgress: onProgress
        )

        logMessages.append("Process result: created=\(result.created), merged=\(result.merged)")
        result.logMessages = logMessages
        return result
    }

    // MARK: Private

    /// Process QSO groups with batched saves to cap memory usage.
    /// Creates a fresh ModelContext per batch so model objects are released between batches.
    /// This prevents accumulating thousands of QSO + ServicePresence objects in a single context
    /// which would cause OOM crashes on memory-constrained devices (e.g. iPhone 11 with 4GB RAM).
    private func processQSOGroups(
        byKey: [String: [FetchedQSO]],
        existingByKey: [String: UUID],
        container: ModelContainer,
        onProgress: (@Sendable (ProgressInfo) -> Void)?
    ) async throws -> ProcessingResult {
        var created = 0
        var merged = 0
        var createdQSOIds: [UUID] = []
        let groupEntries = Array(byKey)
        let totalGroups = groupEntries.count
        let saveBatchSize = 500

        for batchStart in stride(from: 0, to: totalGroups, by: saveBatchSize) {
            try Task.checkCancellation()
            let batchEnd = min(batchStart + saveBatchSize, totalGroups)

            // Fresh context per batch — old context's model objects are released
            // when it goes out of scope at the end of each iteration
            let context = ModelContext(container)
            context.autosaveEnabled = false

            // Every QSO this batch creates or merges (with its co-mutated presence
            // rows) is routed canonically to cw-store before the suppressed save.
            var touchedQSOs: [QSO] = []
            for idx in batchStart ..< batchEnd {
                let (key, fetchedGroup) = groupEntries[idx]
                if let existingId = existingByKey[key] {
                    if let mergedQSO = try mergeIntoExisting(
                        existingId: existingId, fetchedGroup: fetchedGroup, context: context
                    ) {
                        touchedQSOs.append(mergedQSO)
                    }
                    merged += 1
                } else {
                    let newQSO = try createNewQSOFromGroup(fetchedGroup, context: context)
                    createdQSOIds.append(newQSO.id)
                    touchedQSOs.append(newQSO)
                    created += 1
                }
                let processed = idx + 1
                if processed.isMultiple(of: 100) {
                    onProgress?(ProgressInfo(
                        processed: processed, total: totalGroups, phase: "Processing QSOs..."
                    ))
                    await Task.yield()
                }
            }

            onProgress?(ProgressInfo(
                processed: batchEnd, total: totalGroups, phase: "Saving batch..."
            ))
            // cw-store first in `.on` (QSO + presence), then one per-context-
            // suppressed save; plain save in other modes (mirror follows).
            try OffMainStoreSeam.commitQSOsWithPresence(touchedQSOs, in: context)
            await Task.yield()
        }

        return ProcessingResult(
            created: created, merged: merged, createdQSOIds: createdQSOIds, logMessages: []
        )
    }

    /// Fetch existing QSO deduplication keys in batches.
    /// Uses a fresh ModelContext per batch so QSO model objects are released after key extraction.
    ///
    /// Each existing QSO contributes its current `deduplicationKey` AND, when the
    /// user has edited the contact callsign, its `originalDeduplicationKey`. The
    /// latter lets a download from a remote service that still holds the pre-edit
    /// callsign re-merge into the existing QSO instead of inserting a duplicate.
    /// See CAR-245.
    ///
    /// On collision (a separate QSO's current key equals an edited QSO's
    /// original key — pathological but possible), the current-key entry wins
    /// because it is written second.
    private func fetchExistingQSOKeys(container: ModelContainer) async throws -> [String: UUID] {
        var result: [String: UUID] = [:]

        let countContext = ModelContext(container)
        let totalCount = (try? countContext.boundedCount(QSO.self)) ?? 0

        if totalCount == 0 {
            return result
        }

        result.reserveCapacity(totalCount)
        let batchSize = 1_000
        var offset = 0

        while offset < totalCount {
            try Task.checkCancellation()

            // Fresh context per batch to release QSO model objects after key extraction
            let context = ModelContext(container)
            let descriptor = BoundedDescriptor<QSO>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)],
                limit: batchSize,
                offset: offset
            )

            let batch = (try? context.boundedFetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }

            for qso in batch {
                // Index by original callsign FIRST so a pre-edit-key collision
                // with a brand-new QSO's current key resolves to the brand-new
                // QSO (current key written below clobbers the original entry).
                if let originalKey = qso.originalDeduplicationKey {
                    result[originalKey] = qso.id
                }
                let key = Self.computeDeduplicationKey(
                    callsign: qso.callsign, band: qso.band,
                    mode: qso.mode, timestamp: qso.timestamp
                )
                result[key] = qso.id
            }

            offset += batchSize
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
    /// Uses batched fetching with fresh contexts to cap memory usage.
    @discardableResult
    func reconcileQRZPresence(
        downloadedKeys: Set<String>,
        userCallsigns: Set<String>,
        container: ModelContainer
    ) async throws -> Int {
        var modifiedCount = 0
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()

            // Fresh context per batch to release model objects between iterations
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate<ServicePresence> { $0.isPresent },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var modifiedPresence: [ServicePresence] = []
            for presence in batch where presence.serviceType == .qrz {
                guard let qso = presence.qso, !qso.isHidden else {
                    continue
                }
                let qsoKey = Self.computeDeduplicationKey(
                    callsign: qso.callsign, band: qso.band,
                    mode: qso.mode, timestamp: qso.timestamp
                )
                if !isQSOPresentInDownloaded(
                    qsoDeduplicationKey: qsoKey, qsoMyCallsign: qso.myCallsign,
                    downloadedKeys: downloadedKeys, userCallsigns: userCallsigns
                ) {
                    presence.isPresent = false
                    presence.needsUpload = true
                    modifiedPresence.append(presence)
                }
            }

            if !modifiedPresence.isEmpty {
                // Presence-only off-main save → cw-store first in `.on`, suppressed save.
                try OffMainStoreSeam.commitPresence(modifiedPresence, in: context)
            }
            modifiedCount += modifiedPresence.count
            // Modified records drop out of isPresent predicate; adjust offset
            offset += batch.count - modifiedPresence.count
            await Task.yield()
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

    /// Count how many fetched QSOs are net-new (don't already exist in the DB).
    func countNetNewQSOs(
        _ fetched: [FetchedQSO], container: ModelContainer
    ) async throws -> Int {
        let fetchedKeys = Set(fetched.map {
            Self.computeDeduplicationKey(
                callsign: $0.callsign, band: $0.band, mode: $0.mode, timestamp: $0.timestamp
            )
        })
        let existingKeys = try await fetchExistingQSOKeys(container: container)
        return fetchedKeys.subtracting(existingKeys.keys).count
    }

    /// Mark QSOs as QRZ-confirmed based on a set of confirmed log IDs.
    /// Processes in batches to keep memory bounded.
    struct ConfirmationResult {
        let confirmed: Int
        let matchedLogIds: Set<String>
    }

    func applyQRZConfirmations(
        logIds: Set<String>, container: ModelContainer
    ) async throws -> ConfirmationResult {
        var confirmedCount = 0
        var matchedLogIds = Set<String>()
        let batchSize = 500
        var offset = 0

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> { $0.qrzLogId != nil && !$0.qrzConfirmed },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            var batchConfirmed = 0
            for qso in batch {
                if let logId = qso.qrzLogId, logIds.contains(logId) {
                    qso.qrzConfirmed = true
                    matchedLogIds.insert(logId)
                    batchConfirmed += 1
                }
            }

            if batchConfirmed > 0 {
                try context.save()
                confirmedCount += batchConfirmed
            }

            if batch.count < batchSize {
                break
            }
            // Confirmed QSOs drop out of the predicate (!qrzConfirmed),
            // so only advance offset by the number that remain unconfirmed
            offset += batch.count - batchConfirmed
        }

        if confirmedCount > 0 {
            NSLog("[QRZ] Applied confirmation to %d QSOs from log IDs", confirmedCount)
        }
        return ConfirmationResult(
            confirmed: confirmedCount, matchedLogIds: matchedLogIds
        )
    }

    /// Count how many of the given log IDs already have qrzConfirmed=true locally.
    /// Used to avoid unnecessary backfill fetches for already-confirmed QSOs.
    func countConfirmedLogIds(
        _ logIds: Set<String>, container: ModelContainer
    ) async throws -> Int {
        var matchCount = 0
        let batchSize = BoundedDescriptor<QSO>.maxLimit
        var offset = 0

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate<QSO> { $0.qrzLogId != nil && $0.qrzConfirmed },
                limit: batchSize,
                offset: offset
            )

            let batch = try context.boundedFetch(descriptor)
            if batch.isEmpty {
                break
            }

            matchCount += batch.count { qso in
                if let logId = qso.qrzLogId {
                    return logIds.contains(logId)
                }
                return false
            }

            if batch.count < batchSize {
                break
            }
            offset += batchSize
        }

        return matchCount
    }

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
        let canonicalMode = ModeEquivalence.canonicalNameForDedup(mode)
        return "\(trimmedCallsign)|\(band.uppercased())|\(canonicalMode)|\(rounded)"
    }
}
