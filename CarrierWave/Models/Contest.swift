import Foundation

/// A contest from the WA7BNM Contest Calendar RSS feed.
/// In-memory only — not persisted to SwiftData.
nonisolated struct Contest: Identifiable, Sendable {
    // MARK: Internal

    let id: String // GUID from RSS
    let title: String
    let link: URL?
    let startDate: Date
    let endDate: Date

    /// Whether the contest is currently running.
    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }

    /// Whether the contest hasn't started yet.
    var isUpcoming: Bool {
        Date() < startDate
    }

    /// Human-readable status.
    var statusLabel: String {
        if isActive {
            "Active"
        } else if isUpcoming {
            "Upcoming"
        } else {
            "Ended"
        }
    }

    /// Compact start date string (e.g. "Feb 27, 22:00Z").
    var formattedStart: String {
        Self.formatter.string(from: startDate)
    }

    /// Compact end date string.
    var formattedEnd: String {
        Self.formatter.string(from: endDate)
    }

    // MARK: Private

    private static let formatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt
    }()
}
