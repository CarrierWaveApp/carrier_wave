import CarrierWaveCore
import Foundation

// Oracle for the session-/sequence-based brag-sheet stats (`BragSheetComputationActor`'s
// speed-and-rate, operating-hours, longest-session, largest-Nfer). Split from
// AnalyticsAggregator.swift for file length; mirrors the actor's per-session and
// global-timestamp folds over integer-second timestamps.

public extension AnalyticsAggregator {
    /// Session/sequence stats re-derived independently of the SQL for cross-impl parity.
    static func bragSessionStats(over qsos: [QSO]) -> BragSessionStatsResult {
        let visible = visibleOnly(qsos)
        guard !visible.isEmpty else {
            return BragSessionStatsResult(
                operatingSeconds: nil,
                fastestTenSeconds: nil,
                bestSessionRate: nil,
                fastestActivationSeconds: nil,
                longestSessionSeconds: nil,
                peak15MinCount: 0,
                largestNfer: 0
            )
        }
        let grouped = group(visible)
        let session = foldSessions(grouped.bySession)
        return BragSessionStatsResult(
            operatingSeconds: session.operating,
            fastestTenSeconds: session.fastestTen.map(Double.init),
            bestSessionRate: session.bestRate > 0 ? session.bestRate : nil,
            fastestActivationSeconds: fastestActivation(grouped.byActivation).map(Double.init),
            longestSessionSeconds: session.longest > 0 ? Double(session.longest) : nil,
            peak15MinCount: peak15MinCount(grouped.allTimestamps),
            largestNfer: grouped.parkedSessions.values.map(\.count).max() ?? 0
        )
    }

    // MARK: Private

    private static let activeGapSeconds = 15 * 60

    private struct Grouped {
        var bySession: [String: [Int]] = [:]
        var parkedSessions: [String: Set<String>] = [:]
        var byActivation: [String: [Int]] = [:]
        var allTimestamps: [Int] = []
    }

    private struct SessionFold {
        var operating = 0.0
        var longest = 0
        var fastestTen: Int?
        var bestRate = 0.0
    }

    private static func group(_ qsos: [QSO]) -> Grouped {
        var grouped = Grouped()
        let calendar = sessionCalendar
        for qso in qsos {
            let timestamp = Int(qso.timestamp.timeIntervalSince1970)
            let key = (qso.loggingSessionId ?? qso.id).uuidString
            grouped.allTimestamps.append(timestamp)
            grouped.bySession[key, default: []].append(timestamp)
            if let park = qso.parkReference, !park.isEmpty {
                grouped.parkedSessions[key, default: []].insert(park)
                let day = calendar.startOfDay(for: qso.timestamp).timeIntervalSince1970
                grouped.byActivation["\(park)|\(day)", default: []].append(timestamp)
            }
        }
        return grouped
    }

    private static func foldSessions(_ bySession: [String: [Int]]) -> SessionFold {
        var fold = SessionFold()
        for stamps in bySession.values {
            let sorted = stamps.sorted()
            fold.operating += sorted.count >= 2 ? Double(max(activeTime(sorted), 60)) : 60.0
            fold.longest = max(fold.longest, sorted[sorted.count - 1] - sorted[0])
            guard sorted.count >= 10 else {
                continue
            }
            if let win = zip(sorted, sorted.dropFirst(9)).map({ $1 - $0 }).min() {
                fold.fastestTen = min(fold.fastestTen ?? win, win)
            }
            let active = activeTime(sorted)
            if active > 0 {
                fold.bestRate = max(fold.bestRate, Double(sorted.count) / (Double(active) / 3_600))
            }
        }
        return fold
    }

    /// Sum of inter-QSO gaps ≤ 15 min over a time-sorted session.
    private static func activeTime(_ sorted: [Int]) -> Int {
        zip(sorted, sorted.dropFirst())
            .map { $1 - $0 }
            .filter { $0 <= activeGapSeconds }
            .reduce(0, +)
    }

    /// Shortest 1st→10th span over (park, day) activation groups with ≥ 10 QSOs.
    private static func fastestActivation(_ byActivation: [String: [Int]]) -> Int? {
        var best: Int?
        for stamps in byActivation.values where stamps.count >= 10 {
            let sorted = stamps.sorted()
            let span = sorted[9] - sorted[0]
            best = min(best ?? span, span)
        }
        return best
    }

    /// Most timestamps within any 15-minute window (two-pointer over the sorted set).
    private static func peak15MinCount(_ timestamps: [Int]) -> Int {
        let sorted = timestamps.sorted()
        var best = 0
        var end = 0
        for start in sorted.indices {
            if end < start {
                end = start
            }
            while end < sorted.count, sorted[end] <= sorted[start] + activeGapSeconds {
                end += 1
            }
            best = max(best, end - start)
        }
        return best
    }

    private static var sessionCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
}
