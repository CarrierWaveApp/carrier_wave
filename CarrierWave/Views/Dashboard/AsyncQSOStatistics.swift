import CarrierWaveCore
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

    var totalQSOs: Int = 0
    var uniqueBands: Int = 0
    var uniqueGrids: Int = 0
    var confirmedQSLs: Int?
    var uniqueEntities: Int?
    var successfulActivations: Int?
    var activityByDate: [Date: Int]?
    var activationActivityByDate: [Date: Int]?
    var activityLogActivityByDate: [Date: Int]?
    var dailyStreak: StreakInfo?
    var potaActivationStreak: StreakInfo?
    var hunterStreak: StreakInfo?
    var cwStreak: StreakInfo?
    var phoneStreak: StreakInfo?
    var digitalStreak: StreakInfo?

    // Count metrics
    var qsosThisWeek: Int = 0
    var qsosThisMonth: Int = 0
    var qsosThisYear: Int = 0
    var activationsThisMonth: Int = 0
    var activationsThisYear: Int = 0
    var huntsThisWeek: Int = 0
    var huntsThisMonth: Int = 0
    var newDXCCThisYear: Int = 0

    // MARK: - Service stats

    var qrzConfirmedCount: Int = 0
    var lotwConfirmedCount: Int = 0
    var icloudImportedCount: Int = 0
    var uniqueMyCallsigns: Set<String> = []

    // MARK: - Favorites (for dashboard card)

    var topFrequency: String?
    var topFrequencyCount: Int = 0
    var topFriend: String?
    var topFriendCount: Int = 0
    var topHunter: String?
    var topHunterCount: Int = 0

    // MARK: - Computation state

    var isComputing = false
    var progress: Double = 0.0
    var progressPhase: String = ""

    /// Whether stats have been computed at least once
    var hasComputed = false

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

    /// Get the display value for a dashboard metric type
    func metricValue(for type: DashboardMetricType) -> MetricDisplayValue {
        switch type {
        case .onAir:
            .streak(dailyStreak)
        case .activation:
            .streak(potaActivationStreak)
        case .hunter:
            .streak(hunterStreak)
        case .cw:
            .streak(cwStreak)
        case .phone:
            .streak(phoneStreak)
        case .digital:
            .streak(digitalStreak)
        case .qsosWeek:
            .count(qsosThisWeek)
        case .qsosMonth:
            .count(qsosThisMonth)
        case .qsosYear:
            .count(qsosThisYear)
        case .activationsMonth:
            .count(activationsThisMonth)
        case .activationsYear:
            .count(activationsThisYear)
        case .huntsWeek:
            .count(huntsThisWeek)
        case .huntsMonth:
            .count(huntsThisMonth)
        case .newDXCCYear:
            .count(newDXCCThisYear)
        }
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
        activationActivityByDate = nil
        activityLogActivityByDate = nil
        dailyStreak = nil
        potaActivationStreak = nil
        hunterStreak = nil
        cwStreak = nil
        phoneStreak = nil
        digitalStreak = nil
        qsosThisWeek = 0
        qsosThisMonth = 0
        qsosThisYear = 0
        activationsThisMonth = 0
        activationsThisYear = 0
        huntsThisWeek = 0
        huntsThisMonth = 0
        newDXCCThisYear = 0
        qrzConfirmedCount = 0
        lotwConfirmedCount = 0
        icloudImportedCount = 0
        uniqueMyCallsigns = []
        topFrequency = nil
        topFrequencyCount = 0
        topFriend = nil
        topFriendCount = 0
        topHunter = nil
        topHunterCount = 0
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
        applyBasicStats(computed)
        applyStreakStats(computed)
        applyCountMetrics(computed)
        applyServiceStats(computed)
        applyFavorites(computed)
        writeWidgetData(computed)

        // NOTE: We intentionally do NOT clear `stats` here.
        // Keeping old stats available prevents UI hangs when navigating to drill-down views.
        // The stats will be slightly stale until the user navigates to a detail view,
        // which is acceptable since the summary values above are already updated.

        progress = 1.0
        progressPhase = ""
        isComputing = false
        hasComputed = true
    }

    private func applyBasicStats(_ computed: ComputedStats) {
        totalQSOs = computed.totalQSOs
        uniqueBands = computed.uniqueBands
        uniqueGrids = computed.uniqueGrids
        confirmedQSLs = computed.confirmedQSLs
        uniqueEntities = computed.uniqueEntities
        successfulActivations = computed.successfulActivations
        activityByDate = computed.activityByDate
        activationActivityByDate = computed.activationActivityByDate
        activityLogActivityByDate = computed.activityLogActivityByDate
    }

    private func cleanup() {
        isComputing = false
        progress = 0.0
        progressPhase = ""
    }
}
