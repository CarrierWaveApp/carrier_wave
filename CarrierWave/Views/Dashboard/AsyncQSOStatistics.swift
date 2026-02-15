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

    private(set) var totalQSOs: Int = 0
    private(set) var uniqueBands: Int = 0
    private(set) var uniqueGrids: Int = 0
    private(set) var confirmedQSLs: Int?
    private(set) var uniqueEntities: Int?
    private(set) var successfulActivations: Int?
    private(set) var activityByDate: [Date: Int]?
    private(set) var activationActivityByDate: [Date: Int]?
    private(set) var activityLogActivityByDate: [Date: Int]?
    private(set) var dailyStreak: StreakInfo?
    private(set) var potaActivationStreak: StreakInfo?
    private(set) var hunterStreak: StreakInfo?
    private(set) var cwStreak: StreakInfo?
    private(set) var phoneStreak: StreakInfo?
    private(set) var digitalStreak: StreakInfo?

    // Count metrics
    private(set) var qsosThisWeek: Int = 0
    private(set) var qsosThisMonth: Int = 0
    private(set) var qsosThisYear: Int = 0
    private(set) var activationsThisMonth: Int = 0
    private(set) var activationsThisYear: Int = 0
    private(set) var huntsThisWeek: Int = 0
    private(set) var huntsThisMonth: Int = 0
    private(set) var newDXCCThisYear: Int = 0

    // MARK: - Service stats

    private(set) var qrzConfirmedCount: Int = 0
    private(set) var lotwConfirmedCount: Int = 0
    private(set) var icloudImportedCount: Int = 0
    private(set) var uniqueMyCallsigns: Set<String> = []

    // MARK: - Favorites (for dashboard card)

    private(set) var topFrequency: String?
    private(set) var topFrequencyCount: Int = 0
    private(set) var topFriend: String?
    private(set) var topFriendCount: Int = 0
    private(set) var topHunter: String?
    private(set) var topHunterCount: Int = 0

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

    private func applyStreakStats(_ computed: ComputedStats) {
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

        applyModeStreaks(computed)
        applyHunterStreak(computed)
    }

    private func applyModeStreaks(_ computed: ComputedStats) {
        cwStreak = StreakInfo(
            id: "cw",
            category: .mode,
            subcategory: "CW",
            currentStreak: computed.cwStreakCurrent,
            longestStreak: computed.cwStreakLongest,
            currentStartDate: computed.cwStreakCurrentStart,
            longestStartDate: computed.cwStreakLongestStart,
            longestEndDate: computed.cwStreakLongestEnd,
            lastActiveDate: computed.cwStreakLastActive
        )

        phoneStreak = StreakInfo(
            id: "phone",
            category: .mode,
            subcategory: "Phone",
            currentStreak: computed.phoneStreakCurrent,
            longestStreak: computed.phoneStreakLongest,
            currentStartDate: computed.phoneStreakCurrentStart,
            longestStartDate: computed.phoneStreakLongestStart,
            longestEndDate: computed.phoneStreakLongestEnd,
            lastActiveDate: computed.phoneStreakLastActive
        )

        digitalStreak = StreakInfo(
            id: "digital",
            category: .mode,
            subcategory: "Digital",
            currentStreak: computed.digitalStreakCurrent,
            longestStreak: computed.digitalStreakLongest,
            currentStartDate: computed.digitalStreakCurrentStart,
            longestStartDate: computed.digitalStreakLongestStart,
            longestEndDate: computed.digitalStreakLongestEnd,
            lastActiveDate: computed.digitalStreakLastActive
        )
    }

    private func applyHunterStreak(_ computed: ComputedStats) {
        hunterStreak = StreakInfo(
            id: "hunter",
            category: .hunter,
            subcategory: nil,
            currentStreak: computed.hunterStreakCurrent,
            longestStreak: computed.hunterStreakLongest,
            currentStartDate: computed.hunterStreakCurrentStart,
            longestStartDate: computed.hunterStreakLongestStart,
            longestEndDate: computed.hunterStreakLongestEnd,
            lastActiveDate: computed.hunterStreakLastActive
        )
    }

    private func applyCountMetrics(_ computed: ComputedStats) {
        qsosThisWeek = computed.qsosThisWeek
        qsosThisMonth = computed.qsosThisMonth
        qsosThisYear = computed.qsosThisYear
        activationsThisMonth = computed.activationsThisMonth
        activationsThisYear = computed.activationsThisYear
        huntsThisWeek = computed.huntsThisWeek
        huntsThisMonth = computed.huntsThisMonth
        newDXCCThisYear = computed.newDXCCThisYear
    }

    private func applyServiceStats(_ computed: ComputedStats) {
        qrzConfirmedCount = computed.qrzConfirmedCount
        lotwConfirmedCount = computed.lotwConfirmedCount
        icloudImportedCount = computed.icloudImportedCount
        uniqueMyCallsigns = computed.uniqueMyCallsigns
    }

    private func applyFavorites(_ computed: ComputedStats) {
        topFrequency = computed.topFrequency
        topFrequencyCount = computed.topFrequencyCount
        topFriend = computed.topFriend
        topFriendCount = computed.topFriendCount
        topHunter = computed.topHunter
        topHunterCount = computed.topHunterCount
    }

    private func cleanup() {
        isComputing = false
        progress = 0.0
        progressPhase = ""
    }
}
