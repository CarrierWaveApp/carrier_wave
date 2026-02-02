import Foundation
import SwiftData

// MARK: - AsyncQSOStatistics

/// Wrapper for QSOStatistics that computes expensive stats on a background thread.
/// All fetching and computation happens off the main thread via StatsComputationActor.
/// Only the final result application runs on the main actor.
@MainActor
@Observable
final class AsyncQSOStatistics {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

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
    /// All fetching and computation happens on a background thread.
    /// If already computing or already computed, this is a no-op.
    /// Use `recompute()` to force a fresh computation.
    func compute(from modelContext: ModelContext) {
        compute(from: modelContext.container)
    }

    /// Compute statistics from the model container.
    /// All fetching and computation happens on a background thread.
    func compute(from container: ModelContainer) {
        // Skip if already computing or already have results
        if isComputing || hasComputed {
            return
        }

        startComputation(from: container)
    }

    /// Force recomputation of statistics (e.g., after sync)
    func recompute(from modelContext: ModelContext) {
        recompute(from: modelContext.container)
    }

    /// Force recomputation of statistics from container
    func recompute(from container: ModelContainer) {
        // Cancel any in-flight computation and start fresh
        computeTask?.cancel()
        hasComputed = false
        startComputation(from: container)
    }

    /// Access underlying QSOStatistics for drill-down views.
    /// Returns cached stats if available, or nil if not yet computed.
    func getStats() -> QSOStatistics? {
        stats
    }

    /// Cancel any in-flight computation.
    func cancel() {
        computeTask?.cancel()
        cleanup()
    }

    /// Reset all stats to initial state.
    /// Call this when data is deleted (e.g., "Clear All QSOs").
    func reset() {
        computeTask?.cancel()
        cleanup()

        totalQSOs = 0
        uniqueBands = 0
        uniqueGrids = 0
        confirmedQSLs = nil
        uniqueEntities = nil
        successfulActivations = nil
        activityByDate = nil
        dailyStreak = nil
        potaActivationStreak = nil
        qrzConfirmedCount = 0
        lotwConfirmedCount = 0
        icloudImportedCount = 0
        uniqueMyCallsigns = []
        stats = nil
        hasComputed = false
    }

    // MARK: Private

    /// Throttle interval for progress updates to reduce main thread work
    private static let progressUpdateInterval: TimeInterval = 0.1

    private var stats: QSOStatistics?
    private var modelContainer: ModelContainer?
    private var computeTask: Task<Void, Never>?
    private let computationActor = StatsComputationActor()

    private var lastProgressUpdate: Date = .distantPast

    private func startComputation(from container: ModelContainer) {
        isComputing = true
        progress = 0.0
        progressPhase = "Starting..."

        // Store reference to container for lazy QSOStatistics loading
        modelContainer = container

        computeTask = Task {
            do {
                let result = try await computationActor.computeStats(
                    container: container,
                    onProgress: { [weak self] progress, phase in
                        Task { @MainActor [weak self] in
                            guard let self else {
                                return
                            }
                            // Throttle progress updates to reduce UI churn
                            let now = Date()
                            if now.timeIntervalSince(lastProgressUpdate)
                                >= Self.progressUpdateInterval
                            {
                                self.progress = progress
                                progressPhase = phase
                                lastProgressUpdate = now
                            }
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

        // NOTE: We intentionally do NOT clear `stats` here.
        // Keeping old stats available prevents UI hangs when navigating to drill-down views.
        // The stats will be slightly stale until the user navigates to a detail view,
        // which is acceptable since the summary values above are already updated.

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
