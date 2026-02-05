import CarrierWaveCore
import Foundation

// MARK: - StatsComputationActor Computation Extensions

extension StatsComputationActor {
    func computeActivationsAndActivity(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.75, "Computing activations...")

        try Task.checkCancellation()
        // Compute activations (park + UTC date combinations)
        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let activationGroups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(Self.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        stats.successfulActivations = activationGroups.values.filter { $0.count >= 10 }.count
        onProgress(0.80, "Computing activity grid...")

        try Task.checkCancellation()
        // Activity by date
        var activity: [Date: Int] = [:]
        let calendar = Calendar.current
        for qso in realQSOs {
            let dateOnly = calendar.startOfDay(for: qso.timestamp)
            activity[dateOnly, default: 0] += 1
        }
        stats.activityByDate = activity
    }

    /// Compute top frequency, friend, and hunter for the favorites card
    func computeTopFavorites(into stats: inout ComputedStats, from qsos: [StatsQSOSnapshot]) {
        // Top frequency - group by rounded frequency
        // Note: qso.frequency is stored in MHz
        var frequencyCounts: [Double: Int] = [:]
        for qso in qsos {
            if let freqMHz = qso.frequency, freqMHz > 0 {
                // Round to nearest kHz (0.001 MHz) for grouping
                let roundedMHz = (freqMHz * 1_000).rounded() / 1_000
                frequencyCounts[roundedMHz, default: 0] += 1
            }
        }
        if let (freqMHz, count) = frequencyCounts.max(by: { $0.value < $1.value }) {
            stats.topFrequency = String(format: "%.3f", freqMHz)
            stats.topFrequencyCount = count
        }

        // Top friend - callsigns we've worked most
        var friendCounts: [String: Int] = [:]
        for qso in qsos {
            let call = qso.callsign.uppercased()
            if !call.isEmpty {
                friendCounts[call, default: 0] += 1
            }
        }
        if let (call, count) = friendCounts.max(by: { $0.value < $1.value }) {
            stats.topFriend = call
            stats.topFriendCount = count
        }

        // Top hunter - callsigns that have worked us at parks (P2P)
        var hunterCounts: [String: Int] = [:]
        for qso in qsos {
            if let park = qso.parkReference, !park.isEmpty {
                let call = qso.callsign.uppercased()
                if !call.isEmpty {
                    hunterCounts[call, default: 0] += 1
                }
            }
        }
        if let (call, count) = hunterCounts.max(by: { $0.value < $1.value }) {
            stats.topHunter = call
            stats.topHunterCount = count
        }
    }
}
