import Foundation
import SwiftData

// MARK: - AsyncQSOStatistics

/// Wrapper for QSOStatistics that computes expensive stats on a background thread.
/// Fetches on main thread (required for SwiftData), converts to snapshots,
/// then computes stats on background actor.
@MainActor
@Observable
final class AsyncQSOStatistics {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Batch size for fetching - small batches with yields to keep UI responsive during fetch
    static let fetchBatchSize = 100

    // MARK: - Published Stats

    private(set) var totalQSOs: Int = 0
    private(set) var uniqueBands: Int = 0
    private(set) var uniqueGrids: Int = 0
    private(set) var confirmedQSLs: Int?
    private(set) var uniqueEntities: Int?
    private(set) var successfulActivations: Int?
    private(set) var activityByDate: [Date: Int]?
    private(set) var dailyStreak: StreakInfo?
    private(set) var potaActivationStreak: StreakInfo?

    // MARK: - Service stats

    private(set) var qrzConfirmedCount: Int = 0
    private(set) var lotwConfirmedCount: Int = 0
    private(set) var icloudImportedCount: Int = 0
    private(set) var uniqueMyCallsigns: Set<String> = []

    // MARK: - Computation state

    private(set) var isComputing = false
    private(set) var progress: Double = 0.0
    private(set) var progressPhase: String = ""

    /// Whether stats have been computed at least once
    private(set) var hasComputed = false

    /// Compute statistics from the model context.
    /// Fetches on main thread with yields, then computes on background.
    /// If already computing or already computed, this is a no-op.
    /// Use `recompute()` to force a fresh computation.
    func compute(from modelContext: ModelContext) {
        // Skip if already computing or already have results
        if isComputing || hasComputed {
            return
        }

        startComputation(from: modelContext)
    }

    /// Force recomputation of statistics (e.g., after sync)
    func recompute(from modelContext: ModelContext) {
        // Cancel any in-flight computation and start fresh
        computeTask?.cancel()
        hasComputed = false
        startComputation(from: modelContext)
    }

    /// Access underlying QSOStatistics for drill-down views.
    /// Lazily fetches QSOs from main context if not already loaded.
    func getStats() -> QSOStatistics? {
        // Return cached stats if available
        if let stats {
            return stats
        }

        // If we have no context or are still computing, return nil
        guard let context = mainModelContext, !isComputing else {
            return nil
        }

        // Lazily fetch QSOs on main thread for drill-down
        // This is acceptable because it's triggered by explicit user navigation
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        guard let qsos = try? context.fetch(descriptor) else {
            return nil
        }

        let newStats = QSOStatistics(qsos: qsos)
        stats = newStats
        return newStats
    }

    /// Cancel any in-flight computation.
    func cancel() {
        computeTask?.cancel()
        cleanup()
    }

    // MARK: Private

    private var stats: QSOStatistics?
    private var mainModelContext: ModelContext?
    private var computeTask: Task<Void, Never>?
    private let computationActor = StatsComputationActor()

    private func startComputation(from modelContext: ModelContext) {
        isComputing = true
        progress = 0.0
        progressPhase = "Starting..."

        // Store reference to main context for lazy QSOStatistics loading
        mainModelContext = modelContext

        computeTask = Task {
            do {
                // Phase 1: Fetch and convert to snapshots on main thread with yields
                let snapshots = await fetchAndConvertToSnapshots(from: modelContext)

                guard !Task.isCancelled else {
                    cleanup()
                    return
                }

                // Phase 2: Compute stats on background actor
                let result = try await computationActor.computeStats(
                    from: snapshots,
                    onProgress: { [weak self] progress, phase in
                        Task { @MainActor [weak self] in
                            // Adjust progress to account for fetch phase (0-50%)
                            self?.progress = 0.5 + progress * 0.5
                            self?.progressPhase = phase
                        }
                    }
                )

                // Apply results on main actor
                applyResults(result)
            } catch is CancellationError {
                cleanup()
            } catch {
                cleanup()
            }
        }
    }

    /// Fetch QSOs in batches on main thread and convert to Sendable snapshots.
    /// Uses yields between batches to keep UI responsive.
    @MainActor
    private func fetchAndConvertToSnapshots(from modelContext: ModelContext) async -> [QSOSnapshot] {
        progressPhase = "Counting QSOs..."

        // Get total count
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        let totalCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        if totalCount == 0 {
            return []
        }

        var snapshots: [QSOSnapshot] = []
        snapshots.reserveCapacity(totalCount)

        var offset = 0
        let batchSize = Self.fetchBatchSize

        progressPhase = "Loading QSOs..."

        while offset < totalCount {
            // Yield before each batch to keep UI responsive
            await Task.yield()

            guard !Task.isCancelled else {
                return []
            }

            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            // Convert to snapshots (this accesses @Model properties on main actor)
            for qso in batch {
                let snapshot = QSOSnapshot(
                    id: qso.id,
                    callsign: qso.callsign,
                    band: qso.band,
                    mode: qso.mode,
                    frequency: qso.frequency,
                    timestamp: qso.timestamp,
                    myCallsign: qso.myCallsign,
                    theirGrid: qso.theirGrid,
                    parkReference: qso.parkReference,
                    importSource: qso.importSource,
                    qrzConfirmed: qso.qrzConfirmed,
                    lotwConfirmed: qso.lotwConfirmed,
                    dxcc: qso.dxcc
                )
                snapshots.append(snapshot)
            }

            offset += batchSize

            // Update progress (fetch phase is 0-50%)
            progress = 0.5 * Double(offset) / Double(totalCount)
            progressPhase = "Loading QSOs... \(min(offset, totalCount))/\(totalCount)"
        }

        return snapshots
    }

    private func applyResults(_ computed: ComputedStats) {
        totalQSOs = computed.totalQSOs
        uniqueBands = computed.uniqueBands
        uniqueGrids = computed.uniqueGrids
        confirmedQSLs = computed.confirmedQSLs
        uniqueEntities = computed.uniqueEntities
        successfulActivations = computed.successfulActivations
        activityByDate = computed.activityByDate

        // Convert streak data to StreakInfo
        dailyStreak = StreakInfo(
            id: "daily",
            category: .daily,
            subcategory: nil,
            currentStreak: computed.dailyStreakCurrent,
            longestStreak: computed.dailyStreakLongest,
            currentStartDate: computed.dailyStreakCurrentStart,
            longestStartDate: computed.dailyStreakLongestStart,
            longestEndDate: computed.dailyStreakLongestEnd,
            lastActiveDate: computed.dailyStreakLastActive
        )

        potaActivationStreak = StreakInfo(
            id: "pota",
            category: .pota,
            subcategory: nil,
            currentStreak: computed.potaStreakCurrent,
            longestStreak: computed.potaStreakLongest,
            currentStartDate: computed.potaStreakCurrentStart,
            longestStartDate: computed.potaStreakLongestStart,
            longestEndDate: computed.potaStreakLongestEnd,
            lastActiveDate: computed.potaStreakLastActive
        )

        qrzConfirmedCount = computed.qrzConfirmedCount
        lotwConfirmedCount = computed.lotwConfirmedCount
        icloudImportedCount = computed.icloudImportedCount
        uniqueMyCallsigns = computed.uniqueMyCallsigns

        // Clear cached stats so getStats() will lazily reload if needed
        stats = nil

        progress = 1.0
        progressPhase = ""
        isComputing = false
        hasComputed = true
    }

    private func cleanup() {
        isComputing = false
        progress = 0.0
        progressPhase = ""
    }
}
