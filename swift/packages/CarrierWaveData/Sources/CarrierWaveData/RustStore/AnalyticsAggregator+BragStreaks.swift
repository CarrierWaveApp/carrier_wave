import CarrierWaveCore
import Foundation

// Oracle for the streak-shaped brag-sheet stats (`BragSheetComputationActor+Records`). Split
// from AnalyticsAggregator.swift for file length. All day-bucketing is UTC (matching the Rust
// aggregate's `strftime(...,'unixepoch')` days), folded the same way as `computeStreakFromDates`.

public extension AnalyticsAggregator {
    /// Streak stats re-derived independently of the SQL for cross-impl parity. `today` is the
    /// reference day; a streak is "current" only when its last active day is `today` or
    /// yesterday. Mirrors the actor's streak math, normalized to UTC.
    static func bragStreaks(over qsos: [QSO], today: Date) -> BragStreaksResult {
        let visible = visibleOnly(qsos)
        let calendar = utcCalendar
        let todayDay = calendar.startOfDay(for: today)

        let onAirDays = Set(visible.map { calendar.startOfDay(for: $0.timestamp) })
        let onAir = streak(onAirDays, today: todayDay, calendar: calendar)

        let activationDays = activationDays(visible, calendar: calendar)
        let activation = activationDays.isEmpty ? nil : streak(activationDays, today: todayDay, calendar: calendar)

        var modes: [ModeStreakRow] = []
        for family in ["CW", "Phone", "Digital"] {
            let days = Set(
                visible
                    .filter { modeFamilyLabel($0.mode) == family }
                    .map { calendar.startOfDay(for: $0.timestamp) }
            )
            guard !days.isEmpty else {
                continue
            }
            let value = streak(days, today: todayDay, calendar: calendar)
            modes.append(ModeStreakRow(mode: family, current: value.current, longest: value.longest))
        }

        return BragStreaksResult(onAir: onAir, activation: activation, modes: modes)
    }

    // MARK: Private

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Distinct UTC days carrying a successful (≥ 10 unique-QSO) park activation. Groups parked
    /// QSOs by `(raw park, UTC day)`; uniqueness is `UPPER(callsign)|band|mode|UPPER(park)`.
    private static func activationDays(_ qsos: [QSO], calendar: Calendar) -> Set<Date> {
        let parked = qsos.filter { !($0.parkReference ?? "").isEmpty }
        let groups = Dictionary(grouping: parked) { qso in
            "\(qso.parkReference ?? "")|\(calendar.startOfDay(for: qso.timestamp).timeIntervalSince1970)"
        }
        var days = Set<Date>()
        for group in groups.values where uniqueQSOCount(group) >= 10 {
            if let first = group.first {
                days.insert(calendar.startOfDay(for: first.timestamp))
            }
        }
        return days
    }

    private static func uniqueQSOCount(_ qsos: [QSO]) -> Int {
        var seen = Set<String>()
        for qso in qsos {
            let park = (qso.parkReference ?? "").uppercased()
            seen.insert("\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(park)")
        }
        return seen.count
    }

    /// Fold a set of active days into current/longest (mirrors `computeStreakFromDates`):
    /// consecutive days (1-day gap) extend; the current streak counts only when its last day is
    /// `today` or yesterday.
    private static func streak(_ days: Set<Date>, today: Date, calendar: Calendar) -> StreakValueRow {
        let sorted = days.sorted()
        guard !sorted.isEmpty else {
            return StreakValueRow(current: 0, longest: 0)
        }
        var longest = 0
        var current = 0
        var previous: Date?
        for date in sorted {
            if let prev = previous {
                let diff = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if diff == 1 {
                    current += 1
                } else if diff > 1 {
                    longest = max(longest, current)
                    current = 1
                }
            } else {
                current = 1
            }
            previous = date
        }
        longest = max(longest, current)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let isActive = sorted.last.map {
            calendar.isDate($0, inSameDayAs: today) || calendar.isDate($0, inSameDayAs: yesterday)
        } ?? false
        return StreakValueRow(current: isActive ? current : 0, longest: longest)
    }
}
