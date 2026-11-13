import CarrierWaveData
import Foundation

// MARK: - AMTService + StreakInfo

extension AMTService {
    /// The Another Morse Trainer practice streak as a dashboard `StreakInfo`,
    /// `nil` until the first stats snapshot exists. AMT reports local-calendar
    /// days, so the dates are local midnights (the `isAtRisk` check uses
    /// `Calendar.current` too).
    var streakInfo: StreakInfo? {
        guard let stats else {
            return nil
        }
        let calendar = Calendar.current
        let lastActive = stats.streak.lastPractisedDay
            .flatMap(AMTActivityFormatting.localDay(fromDayLabel:))
        let current = Int(stats.streak.current)
        let currentStart: Date? = if current > 0, let lastActive {
            calendar.date(byAdding: .day, value: -(current - 1), to: lastActive)
        } else {
            nil
        }
        return StreakInfo(
            id: "amt.practice",
            category: .amtPractice,
            subcategory: nil,
            currentStreak: current,
            longestStreak: Int(stats.streak.longest),
            currentStartDate: currentStart,
            longestStartDate: nil,
            longestEndDate: nil,
            lastActiveDate: lastActive
        )
    }
}
