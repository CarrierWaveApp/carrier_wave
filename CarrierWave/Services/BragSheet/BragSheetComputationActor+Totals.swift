import CarrierWaveCore
import Foundation

// MARK: - Totals & Basic Counts

extension BragSheetComputationActor {
    func computeTotalQSOs(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        .count(snapshots.count)
    }

    func computeModeCount(
        _ snapshots: [BragSheetQSOSnapshot], family: ModeFamily
    ) -> BragSheetStatValue {
        let count = snapshots.filter { $0.modeFamily == family }.count
        return .count(count)
    }

    func computeTotalDistance(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let total = snapshots.compactMap(\.distanceKm).reduce(0, +)
        guard total > 0 else { return .noData }
        return .distance(km: total)
    }

    func computeOperatingDays(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let days = Set(snapshots.map { calendar.startOfDay(for: $0.timestamp) })
        return .count(days.count)
    }

    func computeOperatingHours(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        // Group by session, compute active time (exclude gaps >15 min)
        let bySession = Dictionary(grouping: snapshots) { $0.loggingSessionId ?? $0.id }
        var totalSeconds: TimeInterval = 0

        for (_, sessionQSOs) in bySession {
            let sorted = sessionQSOs.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= 2 else {
                totalSeconds += 60 // At least 1 minute for a single QSO
                continue
            }
            var sessionTime: TimeInterval = 0
            for i in 1 ..< sorted.count {
                let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
                if gap <= 15 * 60 { // 15 minute gap threshold
                    sessionTime += gap
                }
            }
            totalSeconds += max(sessionTime, 60)
        }

        let hours = totalSeconds / 3_600
        guard hours > 0 else { return .noData }
        return .duration(seconds: totalSeconds)
    }

    func computeActiveBands(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let bands = Set(snapshots.map { $0.band.lowercased() })
        return .count(bands.count)
    }

    func computeActiveModes(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let modes = Set(snapshots.map { ModeEquivalence.canonicalName($0.mode) })
        return .count(modes.count)
    }

    func computeUniqueCallsigns(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let calls = Set(snapshots.map { $0.callsign.uppercased() })
        return .count(calls.count)
    }

    func computeQRPCount(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let count = snapshots.filter(\.isQRP).count
        return .count(count)
    }

    func computeMilliwattCount(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let count = snapshots.filter(\.isMilliwatt).count
        return .count(count)
    }
}

// MARK: - Speed & Rate

extension BragSheetComputationActor {
    func computeFastest10(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        // Find shortest time to log 10 consecutive contacts in a single session
        let bySession = Dictionary(grouping: snapshots) { $0.loggingSessionId ?? $0.id }
        var bestDuration: TimeInterval = .infinity

        for (_, sessionQSOs) in bySession {
            let sorted = sessionQSOs.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= 10 else { continue }
            for i in 0 ... (sorted.count - 10) {
                let duration = sorted[i + 9].timestamp.timeIntervalSince(sorted[i].timestamp)
                bestDuration = min(bestDuration, duration)
            }
        }

        guard bestDuration < .infinity else { return .noData }
        return .rate(value: 10, label: formatDuration(bestDuration))
    }

    func computePeak15MinRate(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let timestamps = snapshots.map(\.timestamp).sorted()
        guard timestamps.count >= 2 else { return .count(timestamps.count) }

        let window: TimeInterval = 15 * 60
        var bestCount = 0
        for (i, start) in timestamps.enumerated() {
            let end = start.addingTimeInterval(window)
            let count = timestamps[i...].prefix(while: { $0 <= end }).count
            bestCount = max(bestCount, count)
        }

        let projectedHourly = Double(bestCount) * (60.0 / 15.0)
        return .rate(
            value: Double(bestCount),
            label: "\(bestCount) in 15m (\(Int(projectedHourly))/hr)"
        )
    }

    func computeBestSessionRate(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        let bySession = Dictionary(grouping: snapshots) { $0.loggingSessionId ?? $0.id }
        var bestRate = 0.0

        for (_, sessionQSOs) in bySession {
            guard sessionQSOs.count >= 10 else { continue }
            let sorted = sessionQSOs.sorted { $0.timestamp < $1.timestamp }

            // Active time excluding gaps >15 min
            var activeTime: TimeInterval = 0
            for i in 1 ..< sorted.count {
                let gap = sorted[i].timestamp.timeIntervalSince(sorted[i - 1].timestamp)
                if gap <= 15 * 60 {
                    activeTime += gap
                }
            }
            guard activeTime > 0 else { continue }
            let rate = Double(sessionQSOs.count) / (activeTime / 3_600)
            bestRate = max(bestRate, rate)
        }

        guard bestRate > 0 else { return .noData }
        return .rate(value: bestRate, label: String(format: "%.0f QSOs/hr", bestRate))
    }

    func computeFastestActivation(_ snapshots: [BragSheetQSOSnapshot]) -> BragSheetStatValue {
        // Shortest time from 1st to 10th QSO in a POTA activation
        let parksOnly = snapshots.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let groups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }

        var bestDuration: TimeInterval = .infinity
        for (_, qsos) in groups {
            let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
            guard sorted.count >= 10 else { continue }
            let duration = sorted[9].timestamp.timeIntervalSince(sorted[0].timestamp)
            bestDuration = min(bestDuration, duration)
        }

        guard bestDuration < .infinity else { return .noData }
        return .duration(seconds: bestDuration)
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m \(secs)s"
    }
}
