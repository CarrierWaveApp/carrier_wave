import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - SyncService Process Methods

extension SyncService {
    struct ProcessResult {
        // MARK: Internal

        let created: Int
        let merged: Int
        let createdQSOIds: [UUID]

        /// Fetch created QSOs from context (for activity detection).
        /// Call this on the main actor after processing completes.
        /// Limited to most recent QSOs to avoid UI hang on large syncs.
        func fetchCreatedQSOs(from context: ModelContext) -> [QSO] {
            guard !createdQSOIds.isEmpty else {
                return []
            }

            // For large syncs, skip activity detection to avoid UI hang
            // Activity detection is most useful for small incremental syncs
            guard createdQSOIds.count <= Self.maxActivityDetectionQSOs else {
                return []
            }

            // Fetch in batches to avoid slow ids.contains() predicate
            var results: [QSO] = []
            for id in createdQSOIds {
                var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                if let qso = try? context.fetch(descriptor).first {
                    results.append(qso)
                }
            }
            return results
        }

        // MARK: Private

        /// Maximum QSOs to fetch for activity detection (avoid UI hang on large syncs)
        private static let maxActivityDetectionQSOs = 100
    }

    /// Background actor for heavy QSO processing work.
    /// Internal so repair extension files can access it.
    static let processingActor = QSOProcessingActor()

    /// Process downloaded QSOs on a background thread to avoid blocking the UI.
    /// Returns counts and created QSO IDs; use fetchCreatedQSOs() to get actual QSO objects.
    func processDownloadedQSOsAsync(_ fetched: [FetchedQSO]) async throws -> ProcessResult {
        let result = try await Self.processingActor.processDownloadedQSOs(
            fetched, container: modelContext.container
        ) { progress in
            Task { @MainActor in
                self.syncProgress.updateProcessing(
                    processed: progress.processed, total: progress.total, phase: progress.phase
                )
            }
        }
        for message in result.logMessages {
            SyncDebugLog.shared.info(message)
        }
        return ProcessResult(
            created: result.created, merged: result.merged,
            createdQSOIds: result.createdQSOIds
        )
    }

    /// Reconcile QRZ presence records against what QRZ actually returned.
    /// Now runs on background thread to avoid blocking UI.
    /// Returns the number of presence records reset to needsUpload.
    @discardableResult
    func reconcileQRZPresenceAsync(downloadedKeys: Set<String>) async throws -> Int {
        let aliasService = CallsignAliasService.shared
        let userCallsigns = aliasService.getAllUserCallsigns()

        return try await Self.processingActor.reconcileQRZPresence(
            downloadedKeys: downloadedKeys,
            userCallsigns: userCallsigns,
            container: modelContext.container
        )
    }

    /// Reconcile POTA presence records against upload job log.
    /// Fetches jobs from POTA API, then checks every POTA ServicePresence record:
    /// - isPresent=true with no completed job -> reset to needsUpload=true
    /// - isSubmitted=true with completed job -> confirm as uploaded
    /// - isSubmitted=true with failed job -> reset to needsUpload=true
    /// Returns the POTA reconciliation result, or nil if skipped/failed.
    @discardableResult
    func reconcilePOTAPresenceAsync() async
        -> QSOProcessingActor.POTAReconcileResult?
    {
        let debugLog = SyncDebugLog.shared

        guard potaAuthService.isConfigured else {
            debugLog.debug("POTA reconciliation skipped: not configured", service: .pota)
            return nil
        }

        do {
            let fetchStart = Date()
            let jobs = try await potaClient.fetchJobs()
            let fetchDurationMs = Int(Date().timeIntervalSince(fetchStart) * 1_000)
            let activationKeys = buildPOTAActivationKeys(from: jobs)

            debugLog.debug(
                "POTA reconciliation: fetched \(jobs.count) jobs in \(fetchDurationMs)ms, "
                    + "\(activationKeys.confirmed.count) confirmed, "
                    + "\(activationKeys.failed.count) failed, "
                    + "\(activationKeys.inProgress.count) in-progress, "
                    + "\(activationKeys.nilDateFailed.count) nil-date-failed",
                service: .pota
            )

            // Log each job's details for debugging
            let jobDateFormatter = DateFormatter()
            jobDateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            jobDateFormatter.timeZone = TimeZone(identifier: "UTC")
            for job in jobs {
                let submittedStr = jobDateFormatter.string(from: job.submitted)
                let processedStr = job.processed.map { jobDateFormatter.string(from: $0) } ?? "n/a"
                let firstQSOStr = job.firstQSO.map { jobDateFormatter.string(from: $0) } ?? "n/a"
                debugLog.debug(
                    "  Job #\(job.jobId): \(job.reference) status=\(job.status.displayName) "
                        + "callsign=\(job.callsignUsed ?? "nil") "
                        + "total=\(job.totalQsos) inserted=\(job.insertedQsos) "
                        + "submitted=\(submittedStr) processed=\(processedStr) "
                        + "firstQSO=\(firstQSOStr)",
                    service: .pota
                )
            }

            let result = try await Self.processingActor.reconcilePOTAPresence(
                activationKeys: activationKeys,
                container: modelContext.container
            )

            logPOTAReconcileResult(result)
            return result
        } catch {
            debugLog.error(
                "POTA reconciliation failed: \(error.localizedDescription)", service: .pota
            )
            return nil
        }
    }

    /// Classified POTA activation keys from the job log.
    /// Key format: "PARKREF|CALLSIGN|YYYY-MM-DD"
    struct POTAActivationKeys {
        /// Activations with completed or duplicate jobs -- POTA has the QSOs
        var confirmed = Set<String>()
        /// Activations with failed jobs -- need re-upload
        var failed = Set<String>()
        /// Activations with pending/processing jobs -- maps key to submitted timestamp
        var inProgress = [String: Date]()
        /// Park+callsign pairs with nil-date completed jobs (all QSOs were duplicates).
        /// Format: "PARKREF|CALLSIGN". Used as fallback when no date-specific key matches
        /// a submitted presence -- prevents orphan-reset loops for all-duplicate re-uploads.
        var nilDateConfirmed = Set<String>()
        /// Park+callsign pairs with nil-date failed/error jobs.
        /// Format: "PARKREF|CALLSIGN". Used to reset submitted QSOs whose jobs failed
        /// without recording a date.
        var nilDateFailed = Set<String>()
    }

    /// Build classified activation key sets from POTA jobs.
    /// In-progress keys map to the job's submitted timestamp for staleness checking.
    func buildPOTAActivationKeys(from jobs: [POTAJob]) -> POTAActivationKeys {
        var keys = POTAActivationKeys()

        for job in jobs {
            guard let callsign = job.callsignUsed else {
                continue
            }
            let normalizedCall = POTAClient.normalizeCallsign(callsign)

            if let utcDate = job.utcDateString {
                let key = "\(job.reference.uppercased())|\(normalizedCall)|\(utcDate)"

                if job.status == .completed || job.status == .duplicate {
                    keys.confirmed.insert(key)
                } else if job.status.isFailure {
                    keys.failed.insert(key)
                } else {
                    keys.inProgress[key] = job.submitted
                }
            } else if job.status == .completed || job.status == .duplicate {
                let parkCallsign =
                    "\(job.reference.uppercased())|\(normalizedCall)"
                keys.nilDateConfirmed.insert(parkCallsign)
            } else if job.status.isFailure {
                let parkCallsign =
                    "\(job.reference.uppercased())|\(normalizedCall)"
                keys.nilDateFailed.insert(parkCallsign)
            }
        }

        // Remove failed keys that also have a completed/duplicate job
        keys.failed.subtract(keys.confirmed)
        // Remove nil-date failed keys that also have a confirmed job
        keys.nilDateFailed.subtract(keys.nilDateConfirmed)
        // Remove in-progress keys that also have a completed/duplicate job
        for key in keys.confirmed {
            keys.inProgress.removeValue(forKey: key)
        }
        return keys
    }

    // MARK: - POTA Reconciliation Logging

    /// Log the results of POTA presence reconciliation.
    private func logPOTAReconcileResult(_ result: QSOProcessingActor.POTAReconcileResult) {
        let debugLog = SyncDebugLog.shared
        let totalChanges =
            result.confirmedCount + result.failedResetCount
                + result.orphanResetCount + result.staleResetCount
        if totalChanges == 0, result.inProgressCount == 0 {
            debugLog.debug(
                "POTA job reconciliation: no changes needed", service: .pota
            )
            return
        }

        if result.confirmedCount > 0 {
            debugLog.info(
                "POTA job reconciliation: confirmed \(result.confirmedCount) submitted upload(s)",
                service: .pota
            )
        }
        if result.failedResetCount > 0 {
            debugLog.warning(
                "POTA job reconciliation: reset \(result.failedResetCount) submitted upload(s) "
                    + "(job failed)",
                service: .pota
            )
        }
        if result.orphanResetCount > 0 {
            debugLog.warning(
                "POTA job reconciliation: reset \(result.orphanResetCount) submitted upload(s) "
                    + "(no matching job found - upload was likely silently dropped)",
                service: .pota
            )
        }
        if result.inProgressCount > 0 {
            debugLog.info(
                "POTA job reconciliation: \(result.inProgressCount) upload(s) still in-progress "
                    + "(pending/processing - waiting for POTA to finish)",
                service: .pota
            )
        }
        if result.staleResetCount > 0 {
            debugLog.warning(
                "POTA job reconciliation: reset \(result.staleResetCount) submitted upload(s) "
                    + "(job pending/processing >30 min - considered stale)",
                service: .pota
            )
        }
    }
}
