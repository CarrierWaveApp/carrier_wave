import Foundation
import SwiftData

// MARK: - EquipmentSessionSnapshot

/// Lightweight, Sendable snapshot of session equipment data for background computation.
struct EquipmentSessionSnapshot: Sendable {
    let id: UUID
    let startedAt: Date
    let qsoCount: Int
    let myRig: String?
    let myAntenna: String?
    let myKey: String?
    let myMic: String?
}

// MARK: - EquipmentCategory

enum EquipmentCategory: String, CaseIterable, Sendable {
    case radio
    case antenna
    case key
    case mic

    // MARK: Internal

    var displayName: String {
        switch self {
        case .radio: "Radio"
        case .antenna: "Antenna"
        case .key: "Key"
        case .mic: "Microphone"
        }
    }

    var icon: String {
        switch self {
        case .radio: "radio"
        case .antenna: "antenna.radiowaves.left.and.right"
        case .key: "pianokeys"
        case .mic: "mic"
        }
    }
}

// MARK: - EquipmentItemStat

struct EquipmentItemStat: Sendable, Identifiable {
    let name: String
    let category: EquipmentCategory
    let sessionCount: Int
    let totalQSOs: Int
    let avgQSOsPerSession: Double
    let firstUsed: Date
    let lastUsed: Date

    var id: String {
        "\(category.rawValue):\(name)"
    }
}

// MARK: - EquipmentComboStat

struct EquipmentComboStat: Sendable, Identifiable {
    let description: String
    let sessionCount: Int
    let totalQSOs: Int

    var id: String {
        description
    }
}

// MARK: - ComputedEquipmentStats

struct ComputedEquipmentStats: Sendable {
    var topThree: [EquipmentItemStat] = []
    var qsoMagnet: EquipmentItemStat?
    var bestCombo: EquipmentComboStat?
    var gatheringDust: EquipmentItemStat?
    var allItems: [EquipmentItemStat] = []
    var comboRanking: [EquipmentComboStat] = []

    var isEmpty: Bool {
        allItems.isEmpty
    }
}

// MARK: - EquipmentStatsActor

/// Background actor for computing equipment usage statistics from LoggingSession data.
actor EquipmentStatsActor {
    // MARK: Internal

    func computeStats(container: ModelContainer) async throws -> ComputedEquipmentStats {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { $0.qsoCount > 0 }
        )
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]

        guard let sessions = try? context.fetch(descriptor), !sessions.isEmpty else {
            return ComputedEquipmentStats()
        }

        let snapshots = sessions.map { session in
            EquipmentSessionSnapshot(
                id: session.id,
                startedAt: session.startedAt,
                qsoCount: session.qsoCount,
                myRig: session.myRig,
                myAntenna: session.myAntenna,
                myKey: session.myKey,
                myMic: session.myMic
            )
        }

        try Task.checkCancellation()
        return computeFromSnapshots(snapshots)
    }

    // MARK: Private

    // MARK: - Helpers

    private struct Accumulator {
        var category: EquipmentCategory
        var sessions: Int
        var qsos: Int
        var first: Date
        var last: Date
    }

    /// Minimum sessions for QSO Magnet to avoid fluky averages from a single outing
    private static let qsoMagnetMinSessions = 3

    /// Equipment unused for this many days qualifies as "gathering dust"
    private static let gatheringDustDays = 30

    // MARK: - Computation

    private func computeFromSnapshots(
        _ snapshots: [EquipmentSessionSnapshot]
    ) -> ComputedEquipmentStats {
        var stats = ComputedEquipmentStats()
        let allItems = buildItemStats(from: snapshots)

        guard !allItems.isEmpty else {
            return stats
        }

        stats.allItems = allItems
        stats.topThree = Array(allItems.prefix(3))

        stats.qsoMagnet = allItems
            .filter { $0.sessionCount >= Self.qsoMagnetMinSessions }
            .max(by: { $0.avgQSOsPerSession < $1.avgQSOsPerSession })

        let cutoff = Calendar.current.date(
            byAdding: .day, value: -Self.gatheringDustDays, to: Date()
        ) ?? Date()
        stats.gatheringDust = allItems
            .filter { $0.lastUsed < cutoff }
            .min(by: { $0.lastUsed < $1.lastUsed })

        let comboRanking = buildComboStats(from: snapshots)
        stats.comboRanking = comboRanking
        stats.bestCombo = comboRanking.first

        return stats
    }

    private func buildItemStats(
        from snapshots: [EquipmentSessionSnapshot]
    ) -> [EquipmentItemStat] {
        var accumulators: [String: Accumulator] = [:]

        for snapshot in snapshots {
            accumulate(snapshot.myRig, category: .radio, snapshot: snapshot, into: &accumulators)
            accumulate(
                snapshot.myAntenna, category: .antenna,
                snapshot: snapshot, into: &accumulators
            )
            accumulate(snapshot.myKey, category: .key, snapshot: snapshot, into: &accumulators)
            accumulate(snapshot.myMic, category: .mic, snapshot: snapshot, into: &accumulators)
        }

        return accumulators.map { key, acc in
            let name = String(key.drop(while: { $0 != ":" }).dropFirst())
            let avg = acc.sessions > 0 ? Double(acc.qsos) / Double(acc.sessions) : 0
            return EquipmentItemStat(
                name: name,
                category: acc.category,
                sessionCount: acc.sessions,
                totalQSOs: acc.qsos,
                avgQSOsPerSession: avg,
                firstUsed: acc.first,
                lastUsed: acc.last
            )
        }.sorted { $0.sessionCount > $1.sessionCount }
    }

    private func buildComboStats(
        from snapshots: [EquipmentSessionSnapshot]
    ) -> [EquipmentComboStat] {
        var comboCounts: [String: (sessions: Int, qsos: Int)] = [:]

        for snapshot in snapshots {
            guard let rig = snapshot.myRig, !rig.isEmpty,
                  let antenna = snapshot.myAntenna, !antenna.isEmpty
            else {
                continue
            }

            let key = "\(rig) + \(antenna)"
            var existing = comboCounts[key] ?? (0, 0)
            existing.sessions += 1
            existing.qsos += snapshot.qsoCount
            comboCounts[key] = existing
        }

        return comboCounts
            .map {
                EquipmentComboStat(
                    description: $0.key,
                    sessionCount: $0.value.sessions,
                    totalQSOs: $0.value.qsos
                )
            }
            .sorted { $0.sessionCount > $1.sessionCount }
    }

    private func accumulate(
        _ name: String?,
        category: EquipmentCategory,
        snapshot: EquipmentSessionSnapshot,
        into accumulators: inout [String: Accumulator]
    ) {
        guard let name, !name.isEmpty else {
            return
        }
        let key = "\(category.rawValue):\(name)"
        if var existing = accumulators[key] {
            existing.sessions += 1
            existing.qsos += snapshot.qsoCount
            if snapshot.startedAt < existing.first {
                existing.first = snapshot.startedAt
            }
            if snapshot.startedAt > existing.last {
                existing.last = snapshot.startedAt
            }
            accumulators[key] = existing
        } else {
            accumulators[key] = Accumulator(
                category: category,
                sessions: 1,
                qsos: snapshot.qsoCount,
                first: snapshot.startedAt,
                last: snapshot.startedAt
            )
        }
    }
}
