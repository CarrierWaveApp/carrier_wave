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
    private(set) var icloudImportedCount: Int = 0
    private(set) var uniqueMyCallsigns: Set<String> = []

    // MARK: - Computation state

    private(set) var isComputing = false

    /// Compute statistics by fetching from database in background.
    /// This is the preferred method - avoids loading all QSOs into memory at once.
    /// Preserves existing values while computing to avoid UI flashing.
    func compute(from modelContext: ModelContext) {
        // Cancel any in-flight computation
        computeTask?.cancel()

        // Don't reset values - keep showing old data until new data is ready
        // This prevents UI flashing during recomputation

        isComputing = true
        computeTask = Task {
            await computeFromDatabase(modelContext: modelContext)
        }
    }

    /// Legacy method for compatibility - compute from pre-fetched QSOs.
    /// Prefer compute(from: ModelContext) to avoid memory pressure.
    /// Preserves existing values while computing to avoid UI flashing.
    func compute(from qsos: [QSO]) {
        // Cancel any in-flight computation
        computeTask?.cancel()

        // Don't reset values - keep showing old data until new data is ready

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
        icloudImportedCount = qsos.filter { $0.importSource == .icloud }.count
        uniqueMyCallsigns = Set(
            qsos.map { Self.extractBaseCallsign($0.myCallsign.uppercased()) }.filter { !$0.isEmpty }
        )

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

    /// Extract the base callsign from a potentially prefixed/suffixed callsign
    /// e.g., "W6JSV/P" -> "W6JSV", "VE3/W6JSV" -> "W6JSV", "W1WC/CW" -> "W1WC"
    private static func extractBaseCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        // Common suffixes that indicate the base callsign is before them
        let knownSuffixes: Set<String> = [
            "P", "M", "MM", "AM", "QRP", "R", "A", "B", "LH", "LGT", "CW", "SSB", "FT8",
        ]

        // For 2 parts: check if second part is a known suffix or short
        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix, first is the base
            if knownSuffixes.contains(second.uppercased()) {
                return first
            }

            // If second is very short (1-3 chars), it's likely a suffix
            if second.count <= 3 {
                return first
            }

            // If first is very short (1-2 chars), it's likely a country prefix
            if first.count <= 2 {
                return second
            }

            // Otherwise, return the longer one
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is the base
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }

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

        guard !Task.isCancelled else {
            return cleanup()
        }

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

        guard !Task.isCancelled else {
            return cleanup()
        }

        // Create stats and compute
        let newStats = QSOStatistics(qsos: qsos)
        stats = newStats

        totalQSOs = newStats.totalQSOs
        uniqueBands = newStats.uniqueBands
        uniqueGrids = newStats.uniqueGrids
        qrzConfirmedCount = qsos.filter(\.qrzConfirmed).count
        lotwConfirmedCount = qsos.filter(\.lotwConfirmed).count
        icloudImportedCount = qsos.filter { $0.importSource == .icloud }.count
        uniqueMyCallsigns = Set(
            qsos.map { Self.extractBaseCallsign($0.myCallsign.uppercased()) }.filter { !$0.isEmpty }
        )

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
            guard !Task.isCancelled else {
                return cleanup()
            }

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

        guard !Task.isCancelled else {
            return cleanup()
        }

        // Create stats from all fetched QSOs
        let newStats = QSOStatistics(qsos: allQSOs)
        stats = newStats

        // Phase 1: Basic stats
        totalQSOs = newStats.totalQSOs
        uniqueBands = newStats.uniqueBands
        uniqueGrids = newStats.uniqueGrids
        qrzConfirmedCount = allQSOs.filter(\.qrzConfirmed).count
        lotwConfirmedCount = allQSOs.filter(\.lotwConfirmed).count
        icloudImportedCount = allQSOs.filter { $0.importSource == .icloud }.count
        uniqueMyCallsigns = Set(
            allQSOs.map { Self.extractBaseCallsign($0.myCallsign.uppercased()) }
                .filter { !$0.isEmpty }
        )

        await Task.yield()
        guard !Task.isCancelled else {
            return cleanup()
        }

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
