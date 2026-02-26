import Foundation

// MARK: - BragSheetStatValue

/// A computed stat value for display on a brag sheet card.
/// Each variant captures the data needed for its specific presentation.
nonisolated enum BragSheetStatValue: Sendable, Equatable {
    /// Simple integer count (e.g., "142 QSOs").
    case count(Int)

    /// Formatted distance in km (e.g., "5,400 km").
    case distance(km: Double)

    /// A duration in seconds (e.g., "8m 22s" or "2h 15m").
    case duration(seconds: TimeInterval)

    /// A rate (e.g., "42 QSOs/hr" or "10 in 8m 22s").
    case rate(value: Double, label: String)

    /// A contact detail with callsign, distance, and band.
    case contact(callsign: String, distanceKm: Double?, band: String?)

    /// A power reading with watts, callsign, distance, band.
    case power(watts: Int, callsign: String, distanceKm: Double?, band: String?)

    /// Watts-per-mile efficiency ratio with detail.
    case efficiency(wattsPerMile: Double, detail: String)

    /// Progress toward a goal (e.g., 38/50 states).
    case progress(current: Int, total: Int)

    /// A streak in days.
    case streak(current: Int, longest: Int)

    /// Per-band table (band → callsign → distance).
    case bandTable([BandTableEntry])

    /// Day of week with count.
    case dayOfWeek(day: String, count: Int)

    /// A callsign with count (e.g., "N3ABC × 12").
    case callsignCount(callsign: String, count: Int)

    /// UTC time of day (e.g., "0312Z").
    case timeOfDay(Date)

    /// Park detail with park reference, date, count.
    case parkDetail(park: String, date: Date?, count: Int)

    /// Multiple mode streaks.
    case modeStreakList([ModeStreakEntry])

    /// WPM speed value.
    case wpm(Int)

    /// RST report value (e.g., "599" with count or average).
    case rst(value: String, detail: String?)

    /// No data available for this stat.
    case noData
}

// MARK: - BandTableEntry

nonisolated struct BandTableEntry: Sendable, Equatable, Identifiable {
    let band: String
    let callsign: String
    let distanceKm: Double

    var id: String {
        band
    }
}

// MARK: - ModeStreakEntry

nonisolated struct ModeStreakEntry: Sendable, Equatable, Identifiable {
    let mode: String
    let current: Int
    let longest: Int

    var id: String {
        mode
    }
}

// MARK: - Display Helpers

nonisolated extension BragSheetStatValue {
    /// Whether this stat has meaningful data to display.
    var hasData: Bool {
        self != .noData
    }

    /// Whether this stat can be shown on a share card (has data and a single-value summary).
    var isShareable: Bool {
        hasData && heroValue != "--"
    }

    /// Primary display string for the hero row (large number).
    var heroValue: String {
        switch self {
        case let .count(num): "\(num)"
        case let .distance(km): UnitFormatter.distanceCompact(km)
        case let .duration(seconds): formatDurationCompact(seconds)
        case let .rate(value, _): String(format: "%.0f", value)
        case let .contact(call, _, _): call
        case let .power(watts, _, _, _): "\(watts)W"
        case let .efficiency(wpm, _): String(format: "%.3f", wpm)
        case let .progress(current, total): "\(current)/\(total)"
        case let .streak(count, _): "\(count)d"
        case let .dayOfWeek(day, _): day
        case let .callsignCount(call, _): call
        case let .timeOfDay(date): formatUTCTime(date)
        case let .parkDetail(park, _, _): park
        case let .wpm(words): "\(words)"
        case let .rst(v, _): v
        case .bandTable,
             .modeStreakList: "--"
        case .noData: "--"
        }
    }

    private func formatDurationCompact(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h\(minutes)m"
    }

    private func formatUTCTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date) + "Z"
    }
}
