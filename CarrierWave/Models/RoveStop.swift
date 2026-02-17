import Foundation

// MARK: - RoveStop

/// A single park stop within a POTA rove session.
///
/// Stored as JSON-encoded `Data` on `LoggingSession.roveStopsData`
/// (same pattern as `spotCommentsData`). This avoids a SwiftData
/// relationship and preserves insertion order naturally.
struct RoveStop: Codable, Identifiable, Sendable {
    var id: UUID = .init()

    /// Park reference(s) for this stop (e.g. "US-1234" or "US-1234, US-5678" for n-fer)
    var parkReference: String

    /// When the operator arrived at this park
    var startedAt: Date

    /// When the operator left this park (nil if still active)
    var endedAt: Date?

    /// Grid square at this stop (may differ from session grid if GPS-updated)
    var myGrid: String?

    /// Number of QSOs logged at this stop
    var qsoCount: Int = 0

    /// Per-stop notes
    var notes: String?

    /// Whether this stop is still active (no endedAt)
    var isActive: Bool {
        endedAt == nil
    }

    /// Duration at this stop
    var duration: TimeInterval {
        let end = endedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    /// Formatted duration (e.g. "45m" or "1h 12m")
    var formattedDuration: String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
