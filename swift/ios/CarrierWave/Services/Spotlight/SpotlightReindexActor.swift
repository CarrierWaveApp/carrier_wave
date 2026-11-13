import CarrierWaveData
import OSLog
import SwiftData
import UIKit

// MARK: - SpotlightReindexActor

/// Background actor responsible for scanning SwiftData and feeding
/// snapshots into the ``SpotlightIndexer``.
///
/// Follows the batched fetch pattern from docs/PERFORMANCE.md: a fresh
/// ``ModelContext`` per batch, bounded fetches with ``fetchLimit`` equal
/// to ``Self/batchSize``, and ``Task/checkCancellation()`` between batches.
///
/// Coalesces concurrent callers onto a single in-flight task so repeated
/// scene-phase transitions during startup don't trigger overlapping scans.
actor SpotlightReindexActor {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SpotlightReindexActor()

    /// Perform a reindex pass, choosing full rebuild or incremental
    /// automatically. Safe to call repeatedly — concurrent callers share
    /// the in-flight task instead of launching parallel scans.
    func reindexIfNeeded(container: ModelContainer) async {
        if let existing = activeTask {
            await existing.value
            return
        }
        let task = Task { await self.performReindex(container: container) }
        activeTask = task
        await task.value
        activeTask = nil
    }

    /// Force a full rebuild regardless of the stored schema version. Used
    /// by the Spotlight debug view. Waits for any in-flight pass to finish,
    /// resets the stored version to 0 so the next pass takes the full
    /// rebuild branch, then runs the pass.
    func forceFullRebuild(container: ModelContainer) async {
        if let existing = activeTask {
            await existing.value
        }
        UserDefaults.standard.set(0, forKey: SpotlightConstants.schemaVersionKey)
        await reindexIfNeeded(container: container)
    }

    // MARK: Private

    private static let batchSize = 1_000
    private static let logger = Logger(
        subsystem: "app.carrierwave", category: "SpotlightReindex"
    )

    private var activeTask: Task<Void, Never>?

    private func performReindex(container: ModelContainer) async {
        Self.logger.info("performReindex entry")
        let startedAt = Date()
        await markEntry(startedAt: startedAt)

        guard await checkAvailability() else {
            return
        }

        let defaults = UserDefaults.standard
        let currentVersion = SpotlightConstants.currentSchemaVersion
        let storedVersion = defaults.integer(forKey: SpotlightConstants.schemaVersionKey)
        await updateState { state in
            state.currentVersion = currentVersion
            state.storedVersion = storedVersion
            state.lastQSOIndexed = 0
            state.lastSessionIndexed = 0
        }

        do {
            if storedVersion != currentVersion {
                try await runFullRebuild(
                    container: container,
                    storedVersion: storedVersion,
                    currentVersion: currentVersion,
                    startedAt: startedAt
                )
            } else {
                try await runIncrementalPass(container: container, startedAt: startedAt)
            }
            defaults.set(startedAt, forKey: SpotlightConstants.lastIncrementalKey)
            await markCompleted(startedAt: startedAt)
        } catch is CancellationError {
            Self.logger.info("Reindex cancelled")
            await markFailure(phase: "cancelled", error: "cancelled")
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Reindex failed: \(message, privacy: .public)")
            await markFailure(phase: "failed", error: message)
        }
    }

    private func markEntry(startedAt: Date) async {
        await updateState { state in
            state.isRunning = true
            state.currentPhase = "checking availability"
            state.lastEntryAt = startedAt
            state.lastError = nil
            state.lastIndexError = nil
            state.indexErrorCount = 0
        }
    }

    private func checkAvailability() async -> Bool {
        let available = await SpotlightIndexer.shared.isAvailable
        Self.logger.info("CoreSpotlight isAvailable=\(available, privacy: .public)")
        await updateState { $0.lastAvailable = available }
        if !available {
            Self.logger.warning(
                "Skipping reindex: CSSearchableIndex.isIndexingAvailable() returned false"
            )
            await markFailure(
                phase: "unavailable",
                error: "CSSearchableIndex.isIndexingAvailable() returned false"
            )
        }
        return available
    }

    private func markFailure(phase: String, error: String) async {
        await updateState { state in
            state.isRunning = false
            state.currentPhase = phase
            state.lastError = error
        }
    }

    /// Non-fatal: a single batch's `indexSearchableItems` callback
    /// reported an error. The pass continues but the error is surfaced
    /// to the debug view so users without Console access can see it.
    private func recordIndexError(_ message: String) async {
        Self.logger.error(
            "indexSearchableItems reported error: \(message, privacy: .public)"
        )
        await updateState { state in
            state.lastIndexError = message
            state.indexErrorCount += 1
        }
    }

    private func runFullRebuild(
        container: ModelContainer,
        storedVersion: Int,
        currentVersion: Int,
        startedAt: Date
    ) async throws {
        Self.logger.info("Full rebuild: stored=\(storedVersion) current=\(currentVersion)")
        await updateState { state in
            state.lastPath = "full rebuild"
            state.currentPhase = "deindex all"
        }
        await SpotlightIndexer.shared.deindexAll()
        Self.logger.info("deindexAll complete, starting QSO reindex")
        await updateState { $0.currentPhase = "indexing QSOs" }
        try await reindexAllQSOs(container: container)
        Self.logger.info("QSO reindex complete, starting session reindex")
        await updateState { $0.currentPhase = "indexing sessions" }
        try await reindexAllSessions(container: container)
        UserDefaults.standard.set(
            currentVersion, forKey: SpotlightConstants.schemaVersionKey
        )
        Self.logger.info(
            "Full rebuild finished in \(Date().timeIntervalSince(startedAt), privacy: .public)s"
        )
    }

    private func runIncrementalPass(
        container: ModelContainer, startedAt: Date
    ) async throws {
        let lastRun = UserDefaults.standard.object(
            forKey: SpotlightConstants.lastIncrementalKey
        ) as? Date ?? .distantPast
        Self.logger.info("Incremental pass since \(lastRun, privacy: .public)")
        await updateState { state in
            state.lastPath = "incremental"
            state.currentPhase = "incremental QSOs"
        }
        try await reindexQSOs(container: container, since: lastRun)
        await updateState { $0.currentPhase = "incremental sessions" }
        try await reindexSessions(container: container, since: lastRun)
        Self.logger.info(
            "Incremental finished in \(Date().timeIntervalSince(startedAt), privacy: .public)s"
        )
    }

    private func markCompleted(startedAt: Date) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        let stored = UserDefaults.standard.integer(
            forKey: SpotlightConstants.schemaVersionKey
        )
        await updateState { state in
            state.isRunning = false
            state.currentPhase = "idle"
            state.lastCompletedAt = Date()
            state.lastElapsed = elapsed
            state.storedVersion = stored
        }
    }

    private func updateState(_ apply: @Sendable @MainActor (SpotlightDebugState) -> Void) async {
        await MainActor.run {
            apply(SpotlightDebugState.shared)
        }
    }
}

// MARK: - QSO batching

extension SpotlightReindexActor {
    func reindexAllQSOs(container: ModelContainer) async throws {
        try await reindexQSOBatches(container: container) {
            #Predicate<QSO> { !$0.isHidden }
        }
    }

    func reindexQSOs(container: ModelContainer, since: Date) async throws {
        // Catch both newly imported and locally edited QSOs. `modifiedAt`
        // is optional (nil for QSOs that have never been edited), so we
        // coalesce to `.distantPast` — captured as a local so the SwiftData
        // predicate macro can reference it as a simple value.
        let fallback = Date.distantPast
        try await reindexQSOBatches(container: container) {
            #Predicate<QSO> { qso in
                !qso.isHidden && (
                    qso.importedAt >= since ||
                        (qso.modifiedAt ?? fallback) >= since
                )
            }
        }
    }

    private func reindexQSOBatches(
        container: ModelContainer,
        predicate: () -> Predicate<QSO>
    ) async throws {
        let resolved = predicate()
        var offset = 0
        var totalIndexed = 0

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false

            var descriptor = FetchDescriptor<QSO>(
                predicate: resolved,
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = offset

            let batch: [QSO]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                let message = error.localizedDescription
                Self.logger.error(
                    "QSO fetch failed at offset=\(offset, privacy: .public): \(message, privacy: .public)"
                )
                throw error
            }
            if batch.isEmpty {
                break
            }

            let snapshots = batch
                .filter { !QSOMode.isMetadata($0.mode) }
                .map(QSOSpotlightSnapshot.init)

            let indexError = await SpotlightIndexer.shared.indexQSOs(snapshots)
            if let indexError {
                await recordIndexError(indexError.localizedDescription)
            } else {
                totalIndexed += snapshots.count
                let running = totalIndexed
                await updateState { $0.lastQSOIndexed = running }
            }

            offset += batch.count
            if batch.count < Self.batchSize {
                break
            }
        }

        Self.logger.info("Indexed \(totalIndexed, privacy: .public) QSOs")
    }
}

// MARK: - Session batching

extension SpotlightReindexActor {
    func reindexAllSessions(container: ModelContainer) async throws {
        try await reindexSessionBatches(container: container, predicate: nil)
    }

    func reindexSessions(container: ModelContainer, since: Date) async throws {
        let predicate = #Predicate<LoggingSession> { $0.startedAt >= since }
        try await reindexSessionBatches(container: container, predicate: predicate)
    }

    private func reindexSessionBatches(
        container: ModelContainer,
        predicate: Predicate<LoggingSession>?
    ) async throws {
        var offset = 0
        var totalIndexed = 0

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false

            var descriptor = FetchDescriptor<LoggingSession>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = Self.batchSize
            descriptor.fetchOffset = offset

            let batch: [LoggingSession]
            do {
                batch = try context.fetch(descriptor)
            } catch {
                let message = error.localizedDescription
                Self.logger.error(
                    "Session fetch failed at offset=\(offset, privacy: .public): \(message, privacy: .public)"
                )
                throw error
            }
            if batch.isEmpty {
                break
            }

            let snapshots = batch.map(SessionSpotlightSnapshot.init)
            let indexError = await SpotlightIndexer.shared.indexSessions(snapshots)
            if let indexError {
                await recordIndexError(indexError.localizedDescription)
            } else {
                totalIndexed += snapshots.count
                let running = totalIndexed
                await updateState { $0.lastSessionIndexed = running }
            }

            offset += batch.count
            if batch.count < Self.batchSize {
                break
            }
        }

        Self.logger.info("Indexed \(totalIndexed, privacy: .public) sessions")
    }
}
