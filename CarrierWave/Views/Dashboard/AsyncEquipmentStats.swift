import CarrierWaveData
import Foundation
import SwiftData

// MARK: - AsyncEquipmentStats

/// Observable wrapper for equipment statistics computed on a background thread.
/// Follows the same pattern as AsyncQSOStatistics.
@MainActor
@Observable
final class AsyncEquipmentStats {
    // MARK: Internal

    private(set) var topThree: [EquipmentItemStat] = []
    private(set) var qsoMagnet: EquipmentItemStat?
    private(set) var bestCombo: EquipmentComboStat?
    private(set) var gatheringDust: EquipmentItemStat?
    private(set) var allItems: [EquipmentItemStat] = []
    private(set) var comboRanking: [EquipmentComboStat] = []

    private(set) var isComputing = false
    private(set) var hasComputed = false

    /// Whether any equipment data exists to display
    var hasData: Bool {
        !allItems.isEmpty
    }

    func compute(from container: ModelContainer) {
        guard !isComputing, !hasComputed else {
            return
        }
        startComputation(from: container)
    }

    func recompute(from container: ModelContainer) {
        computeTask?.cancel()
        hasComputed = false
        startComputation(from: container)
    }

    func reset() {
        computeTask?.cancel()
        topThree = []
        qsoMagnet = nil
        bestCombo = nil
        gatheringDust = nil
        allItems = []
        comboRanking = []
        isComputing = false
        hasComputed = false
    }

    // MARK: Private

    private var computeTask: Task<Void, Never>?
    private let actor = EquipmentStatsActor()

    private func startComputation(from container: ModelContainer) {
        isComputing = true

        computeTask = Task {
            do {
                let result = try await actor.computeStats(container: container)
                applyResults(result)
            } catch is CancellationError {
                cleanup()
            } catch {
                cleanup()
            }
        }
    }

    private func applyResults(_ stats: ComputedEquipmentStats) {
        topThree = stats.topThree
        qsoMagnet = stats.qsoMagnet
        bestCombo = stats.bestCombo
        gatheringDust = stats.gatheringDust
        allItems = stats.allItems
        comboRanking = stats.comboRanking
        isComputing = false
        hasComputed = true
    }

    private func cleanup() {
        isComputing = false
    }
}
