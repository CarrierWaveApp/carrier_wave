import CarrierWaveCore
import Foundation

// MARK: - AMTDayActivity

/// One Another Morse Trainer practice day, ready for the activity grid.
public struct AMTDayActivity: Hashable, Sendable {
    // MARK: Lifecycle

    public init(seconds: Int, level: Int) {
        self.seconds = seconds
        self.level = level
    }

    // MARK: Public

    /// Practice seconds that day, summed across the user's AMT devices.
    public let seconds: Int
    /// Calendar tile shade 1–4 (AMT's own thresholds: 1 s, 5, 15, 30 min).
    public let level: Int

    /// Opacity for a grid cell: level 1 → 0.4 … level 4 → 1.0, so a single
    /// short session is still visible against an empty cell.
    public var intensity: Double {
        0.2 + Double(min(max(level, 1), 4)) * 0.2
    }

    /// "12 min" / "1 h 05 min" style duration for peeks and rows.
    public var durationText: String {
        AMTActivityFormatting.duration(seconds: seconds)
    }
}

// MARK: - AMTActivityFormatting

public enum AMTActivityFormatting {
    // MARK: Public

    /// Today as the user's local calendar date, the `today=` the stats call
    /// needs so the current streak is exact (not converted to UTC).
    public static func localToday(now: Date = Date()) -> String {
        localDayFormatter.string(from: now)
    }

    /// `yyyy-MM-dd` → UTC midnight of that labelled day (grid cell key).
    public static func utcDay(fromDayLabel label: String) -> Date? {
        dayFormatter.date(from: label)
    }

    /// `yyyy-MM-dd` → local midnight of that labelled day (streak dates
    /// compared with `Calendar.current`).
    public static func localDay(fromDayLabel label: String) -> Date? {
        localDayFormatter.date(from: label)
    }

    /// Fold the stats' activity days into grid-keyed entries.
    public static func activityByUTCDay(_ stats: FfiAmtStats) -> [Date: AMTDayActivity] {
        var out: [Date: AMTDayActivity] = [:]
        out.reserveCapacity(stats.activity.count)
        for day in stats.activity {
            guard let date = utcDay(fromDayLabel: day.day) else {
                continue
            }
            // AMT only lists a day when practice was recorded, so even a few
            // seconds (which round to 0) is a real practice day — never drop it.
            let seconds = max(Int(day.seconds.rounded()), 0)
            out[date] = AMTDayActivity(seconds: seconds, level: max(Int(day.level), 1))
        }
        return out
    }

    public static func duration(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        if minutes < 1 {
            return "<1 min"
        }
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(String(format: "%02d", rest)) min"
    }

    // MARK: Private

    /// AMT keys activity by the user's *local* calendar day (`yyyy-MM-dd`).
    /// The activity grids key cells by UTC midnight of the day label, so a
    /// local day maps onto the grid cell carrying the same label.
    nonisolated(unsafe) private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated(unsafe) private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
