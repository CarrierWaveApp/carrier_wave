import CarrierWaveData
import Foundation
import SwiftData

// MARK: - AsyncBragSheetStats

/// Observable wrapper for brag sheet statistics computed on a background thread.
/// Caches all-time snapshots and pre-computes all three periods in parallel.
/// Period switching is instant because results are already available.
@MainActor
@Observable
final class AsyncBragSheetStats {
    // MARK: Internal

    private(set) var weeklyResult: BragSheetComputedResult?
    private(set) var monthlyResult: BragSheetComputedResult?
    private(set) var allTimeResult: BragSheetComputedResult?

    private(set) var isComputing = false
    private(set) var hasComputed = false

    var selectedPeriod: BragSheetPeriod = .weekly

    var configuration: BragSheetConfiguration = .load()

    private(set) var cachedSnapshots: [BragSheetQSOSnapshot]?

    /// The result for the currently selected period.
    var currentResult: BragSheetComputedResult? {
        result(for: selectedPeriod)
    }

    /// Summary line for dashboard card (e.g. "This week: 42 QSOs · 12 DXCC").
    var summaryLine: String? {
        guard let result = weeklyResult, result.qsoCount > 0 else {
            return nil
        }
        let qsos = result.qsoCount
        let config = configuration.weekly
        // Try to find a second interesting stat
        for stat in config.heroStats {
            if let value = result.stats[stat], value.hasData, stat != .totalQSOs {
                return "This week: \(qsos) QSOs · \(value.heroValue) \(stat.displayName)"
            }
        }
        return "This week: \(qsos) QSOs"
    }

    func result(for period: BragSheetPeriod) -> BragSheetComputedResult? {
        switch period {
        case .weekly: weeklyResult
        case .monthly: monthlyResult
        case .allTime: allTimeResult
        }
    }

    func compute(from container: ModelContainer) {
        guard !isComputing, !hasComputed else {
            return
        }
        startComputation(from: container)
    }

    func recompute(from container: ModelContainer) {
        computeTask?.cancel()
        cachedSnapshots = nil
        hasComputed = false
        startComputation(from: container)
    }

    func saveConfiguration() {
        configuration.save()
    }

    func saveAndRecompute(from container: ModelContainer) {
        configuration.save()
        recomputeFromCache(container: container)
    }

    // MARK: Private

    private var computeTask: Task<Void, Never>?
    private let actor = BragSheetComputationActor()

    private func startComputation(from container: ModelContainer) {
        isComputing = true

        computeTask = Task {
            do {
                // Fetch all-time snapshots once
                let snapshots = try await actor.fetchAllSnapshots(container: container)
                cachedSnapshots = snapshots

                try Task.checkCancellation()

                // Compute all three periods in parallel using cached snapshots
                let config = configuration
                async let weekly = actor.computeStats(
                    container: container, period: .weekly,
                    config: config.weekly, allTimeSnapshots: snapshots
                )
                async let monthly = actor.computeStats(
                    container: container, period: .monthly,
                    config: config.monthly, allTimeSnapshots: snapshots
                )
                async let allTime = actor.computeStats(
                    container: container, period: .allTime,
                    config: config.allTime, allTimeSnapshots: snapshots
                )

                let results = try await (weekly, monthly, allTime)
                weeklyResult = results.0
                monthlyResult = results.1
                allTimeResult = results.2
                isComputing = false
                hasComputed = true
            } catch is CancellationError {
                isComputing = false
            } catch {
                isComputing = false
            }
        }
    }

    /// Recompute from cached snapshots (after config change).
    private func recomputeFromCache(container: ModelContainer) {
        guard let snapshots = cachedSnapshots else {
            recompute(from: container)
            return
        }

        computeTask?.cancel()
        isComputing = true

        computeTask = Task {
            do {
                let config = configuration
                async let weekly = actor.computeStats(
                    container: container, period: .weekly,
                    config: config.weekly, allTimeSnapshots: snapshots
                )
                async let monthly = actor.computeStats(
                    container: container, period: .monthly,
                    config: config.monthly, allTimeSnapshots: snapshots
                )
                async let allTime = actor.computeStats(
                    container: container, period: .allTime,
                    config: config.allTime, allTimeSnapshots: snapshots
                )

                let results = try await (weekly, monthly, allTime)
                weeklyResult = results.0
                monthlyResult = results.1
                allTimeResult = results.2
                isComputing = false
                hasComputed = true
            } catch is CancellationError {
                isComputing = false
            } catch {
                isComputing = false
            }
        }
    }
}
