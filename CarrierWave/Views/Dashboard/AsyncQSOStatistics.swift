import Foundation
import SwiftData

// MARK: - AsyncQSOStatistics

/// Wrapper for QSOStatistics that computes expensive stats progressively.
/// Fetches data in the background to avoid blocking the UI.
/// Uses cooperative yielding (Task.yield) to prevent UI blocking on large datasets.
@MainActor
@Observable
final class AsyncQSOStatistics {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Threshold for progressive loading (compute everything synchronously below this)
    static let progressiveThreshold = 1_000

    /// Batch size for paginated fetching
    static let fetchBatchSize = 500

    // MARK: - Phase 1: Instant stats (from count queries)

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

    // MARK: - Service stats (for dashboard cards)

    private(set) var qrzConfirmedCount: Int = 0
    private(set) var lotwConfirmedCount: Int = 0
    private(set) var uniqueMyCallsigns: Set<String> = []

    // MARK: - Computation state

    private(set) var isComputing = false

    /// Compute statistics by fetching from database in background.
    /// This is the preferred method - avoids loading all QSOs into memory at once.
    func compute(from modelContext: ModelContext) {
        // Cancel any in-flight computation
        computeTask?.cancel()

        // Reset deferred values to nil (shows placeholders in UI)
        resetDeferredValues()

        isComputing = true
        computeTask = Task {
            await computeFromDatabase(modelContext: modelContext)
        }
    }

    /// Legacy method for compatibility - compute from pre-fetched QSOs.
    /// Prefer compute(from: ModelContext) to avoid memory pressure.
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

        // Compute service stats
        qrzConfirmedCount = qsos.filter(\.qrzConfirmed).count
        lotwConfirmedCount = qsos.filter(\.lotwConfirmed).count
        uniqueMyCallsigns = Set(qsos.map { $0.myCallsign.uppercased() }.filter { !$0.isEmpty })

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

    /// Compute stats by fetching from database in batches to avoid memory pressure.
    @MainActor
    private func computeFromDatabase(modelContext: ModelContext) async {
        // Phase 1: Quick count query for total
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        let count = (try? modelContext.fetchCount(countDescriptor)) ?? 0
        totalQSOs = count

        guard !Task.isCancelled else { return cleanup() }

        // For empty or very small datasets, fetch all and compute
        if count <= Self.progressiveThreshold {
            await fetchAllAndCompute(modelContext: modelContext)
            return
        }

        // For large datasets, fetch in batches
        await fetchInBatchesAndCompute(modelContext: modelContext, totalCount: count)
    }

    /// Fetch all QSOs and compute (for small datasets)
    @MainActor
    private func fetchAllAndCompute(modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        guard let qsos = try? modelContext.fetch(descriptor) else {
            cleanup()
            return
        }

        guard !Task.isCancelled else { return cleanup() }

        // Create stats and compute
        let newStats = QSOStatistics(qsos: qsos)
        stats = newStats

        totalQSOs = newStats.totalQSOs
        uniqueBands = newStats.uniqueBands
        uniqueGrids = newStats.uniqueGrids
        qrzConfirmedCount = qsos.filter(\.qrzConfirmed).count
        lotwConfirmedCount = qsos.filter(\.lotwConfirmed).count
        uniqueMyCallsigns = Set(qsos.map { $0.myCallsign.uppercased() }.filter { !$0.isEmpty })

        computeAllSynchronously(from: newStats)
    }

    /// Fetch QSOs in batches and compute progressively (for large datasets)
    @MainActor
    private func fetchInBatchesAndCompute(modelContext: ModelContext, totalCount: Int) async {
        var allQSOs: [QSO] = []
        allQSOs.reserveCapacity(totalCount)

        var offset = 0
        let batchSize = Self.fetchBatchSize

        // Fetch in batches with yielding
        while offset < totalCount {
            guard !Task.isCancelled else { return cleanup() }

            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            allQSOs.append(contentsOf: batch)
            offset += batchSize

            // Yield after each batch to keep UI responsive
            await Task.yield()
        }

        guard !Task.isCancelled else { return cleanup() }

        // Create stats from all fetched QSOs
        let newStats = QSOStatistics(qsos: allQSOs)
        stats = newStats

        // Phase 1: Basic stats
        totalQSOs = newStats.totalQSOs
        uniqueBands = newStats.uniqueBands
        uniqueGrids = newStats.uniqueGrids
        qrzConfirmedCount = allQSOs.filter(\.qrzConfirmed).count
        lotwConfirmedCount = allQSOs.filter(\.lotwConfirmed).count
        uniqueMyCallsigns = Set(allQSOs.map { $0.myCallsign.uppercased() }.filter { !$0.isEmpty })

        await Task.yield()
        guard !Task.isCancelled else { return cleanup() }

        // Continue with progressive computation
        await computeProgressively(from: newStats)
    }

    private func computeAllSynchronously(from stats: QSOStatistics) {
        confirmedQSLs = stats.confirmedQSLs
        uniqueEntities = stats.uniqueEntities
        successfulActivations = stats.successfulActivations
        activityByDate = stats.activityByDate
        dailyStreak = stats.dailyStreak
        potaActivationStreak = stats.potaActivationStreak
        isComputing = false
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
