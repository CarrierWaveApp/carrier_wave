import Foundation

// MARK: - Rove helpers

/// Rove-related computed views over `LoggingSession.roveStops`. Lifted out of
/// the main `@Model` block to keep the class body under SwiftLint's 300-line
/// cap; pure read-only logic so an extension is sufficient.
public extension LoggingSession {
    var currentRoveStop: RoveStop? {
        roveStops.last { $0.endedAt == nil } ?? roveStops.last
    }

    var roveStopCount: Int {
        roveStops.count
    }

    var uniqueParkCount: Int {
        Set(roveStops.map { $0.parkReference.uppercased() }).count
    }

    /// Rove stops merged by park (combines revisits into a single entry).
    var mergedRoveStops: [RoveStop] {
        var seen: [String: Int] = [:]
        var merged: [RoveStop] = []

        for stop in roveStops.sorted(by: { $0.startedAt < $1.startedAt }) {
            let key = stop.parkReference.uppercased()
            if let idx = seen[key] {
                merged[idx].qsoCount += stop.qsoCount
                if stop.startedAt < merged[idx].startedAt {
                    merged[idx].startedAt = stop.startedAt
                }
                if let end = stop.endedAt {
                    if let existingEnd = merged[idx].endedAt {
                        merged[idx].endedAt = max(existingEnd, end)
                    } else {
                        merged[idx].endedAt = end
                    }
                } else {
                    merged[idx].endedAt = nil
                }
                if let grid = stop.myGrid {
                    merged[idx].myGrid = grid
                }
            } else {
                seen[key] = merged.count
                merged.append(stop)
            }
        }

        return merged
    }

    /// Total QSOs across all rove stops.
    var roveTotalQSOCount: Int {
        roveStops.reduce(0) { $0 + $1.qsoCount }
    }
}
