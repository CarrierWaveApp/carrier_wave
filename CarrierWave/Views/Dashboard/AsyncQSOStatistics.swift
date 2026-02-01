import Foundation

// MARK: - AsyncQSOStatistics

/// Wrapper for QSOStatistics that computes expensive stats progressively.
/// Uses cooperative yielding (Task.yield) to prevent UI blocking on large datasets.
@MainActor
@Observable
final class AsyncQSOStatistics {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Threshold for progressive loading (compute everything synchronously below this)
    static let progressiveThreshold = 1_000

    // MARK: - Phase 1: Instant stats (always computed synchronously)

    private(set) var totalQSOs: Int = 0
    private(set) var uniqueBands: Int = 0
    private(set) var uniqueGrids: Int = 0

    // MARK: - Phase 2: Deferred stats (nil = still computing)

    private(set) var confirmedQSLs: Int?
    private(set) var uniqueEntities: Int?
    private(set) var successfulActivations: Int?

    // MARK: - Phase 3: Expensive stats

    private(set) var activityByDate: [Date: Int]?
    private(set) var dailyStreak: StreakInfo?
    private(set) var potaActivationStreak: StreakInfo?

    // MARK: - Computation state

    private(set) var isComputing = false

    /// Compute statistics from QSOs, progressively for large datasets.
    /// Cancels any in-flight computation when called.
    func compute(from qsos: [QSO]) {
        // Cancel any in-flight computation
        computeTask?.cancel()

        // Reset deferred values to nil (shows placeholders in UI)
        resetDeferredValues()

        // Create fresh stats object (lazy caching happens inside)
        let newStats = QSOStatistics(qsos: qsos)
        stats = newStats

        // Phase 1: Instant stats (these are cheap - just array access)
        totalQSOs = newStats.totalQSOs
        uniqueBands = newStats.uniqueBands
        uniqueGrids = newStats.uniqueGrids

        // For small datasets, compute everything synchronously
        if qsos.count <= Self.progressiveThreshold {
            computeAllSynchronously(from: newStats)
            return
        }

        // For large datasets, compute progressively with yielding
        isComputing = true
        computeTask = Task {
            await computeProgressively(from: newStats)
        }
    }

    /// Access underlying QSOStatistics for drill-down views.
    /// Returns nil if no computation has been done yet.
    func getStats() -> QSOStatistics? {
        stats
    }

    /// Cancel any in-flight computation.
    func cancel() {
        computeTask?.cancel()
        cleanup()
    }

    // MARK: Private

    private var stats: QSOStatistics?
    private var computeTask: Task<Void, Never>?

    private func resetDeferredValues() {
        confirmedQSLs = nil
        uniqueEntities = nil
        successfulActivations = nil
        activityByDate = nil
        dailyStreak = nil
        potaActivationStreak = nil
    }

    private func computeAllSynchronously(from stats: QSOStatistics) {
        confirmedQSLs = stats.confirmedQSLs
        uniqueEntities = stats.uniqueEntities
        successfulActivations = stats.successfulActivations
        activityByDate = stats.activityByDate
        dailyStreak = stats.dailyStreak
        potaActivationStreak = stats.potaActivationStreak
    }

    private func computeProgressively(from stats: QSOStatistics) async {
        // Phase 2: Medium cost stats
        confirmedQSLs = stats.confirmedQSLs
        await Task.yield()
        guard !Task.isCancelled else {
            return cleanup()
        }

        uniqueEntities = stats.uniqueEntities
        await Task.yield()
        guard !Task.isCancelled else {
            return cleanup()
        }

        successfulActivations = stats.successfulActivations
        await Task.yield()
        guard !Task.isCancelled else {
            return cleanup()
        }

        // Phase 3: Expensive stats
        activityByDate = stats.activityByDate
        await Task.yield()
        guard !Task.isCancelled else {
            return cleanup()
        }

        dailyStreak = stats.dailyStreak
        await Task.yield()
        guard !Task.isCancelled else {
            return cleanup()
        }

        potaActivationStreak = stats.potaActivationStreak
        isComputing = false
    }

    private func cleanup() {
        isComputing = false
    }
}
