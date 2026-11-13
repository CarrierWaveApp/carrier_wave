import CarrierWaveCore
import Foundation
import Testing
@testable import CarrierWaveData

@Suite("AMT activity conversion")
struct AMTActivityTests {
    // MARK: Internal

    @Test("days map to UTC-midnight keys with level and rounded seconds")
    func mapsDays() throws {
        let sample = stats(days: [
            FfiAmtActivityDay(day: "2026-10-05", seconds: 120.4, level: 1),
            FfiAmtActivityDay(day: "2026-10-06", seconds: 1_800, level: 4),
            FfiAmtActivityDay(day: "2026-10-04", seconds: 0.3, level: 1), // a few seconds still counts
            FfiAmtActivityDay(day: "not-a-day", seconds: 50, level: 1), // ignored: bad label
        ])
        let map = AMTActivityFormatting.activityByUTCDay(sample)
        #expect(map.count == 3)
        let four = try #require(AMTActivityFormatting.utcDay(fromDayLabel: "2026-10-04"))
        #expect(map[four] == AMTDayActivity(seconds: 0, level: 1))
        let key = try #require(AMTActivityFormatting.utcDay(fromDayLabel: "2026-10-05"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(utc.component(.hour, from: key) == 0)
        #expect(utc.component(.day, from: key) == 5)
        #expect(map[key] == AMTDayActivity(seconds: 120, level: 1))
        let six = try #require(AMTActivityFormatting.utcDay(fromDayLabel: "2026-10-06"))
        #expect(map[six]?.level == 4)
        #expect(map[six]?.intensity == 1.0)
    }

    @Test("local today is the device calendar date, not UTC")
    func localToday() throws {
        // 2026-10-06 23:30 in Los Angeles is already 2026-10-07 in UTC.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let late = try #require(
            la.date(from: DateComponents(year: 2_026, month: 10, day: 6, hour: 23, minute: 30))
        )
        let expected = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: late)
        }()
        #expect(AMTActivityFormatting.localToday(now: late) == expected)
        #expect(AMTActivityFormatting.localToday().count == 10)
    }

    @Test("durations read naturally")
    func durations() {
        #expect(AMTActivityFormatting.duration(seconds: 30) == "<1 min")
        #expect(AMTActivityFormatting.duration(seconds: 59 * 60) == "59 min")
        #expect(AMTActivityFormatting.duration(seconds: 3_600) == "1 h")
        #expect(AMTActivityFormatting.duration(seconds: 3_900) == "1 h 05 min")
        #expect(AMTDayActivity(seconds: 1, level: 1).intensity == 0.4)
    }

    // MARK: Private

    private func stats(days: [FfiAmtActivityDay]) -> FfiAmtStats {
        FfiAmtStats(
            sessions: 1, answered: 10, correct: 9, accuracy: 0.9, practiceSeconds: 600,
            bestTtrMs: 400,
            streak: FfiAmtStreak(current: 2, longest: 5, lastPractisedDay: "2026-10-06"),
            activity: days,
            levelThresholds: [1, 300, 900, 1_800],
            perMode: [],
            updatedAt: 0, fetchedAt: 0
        )
    }
}
