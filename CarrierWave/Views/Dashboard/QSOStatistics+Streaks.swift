import CarrierWaveCore
import Foundation

// MARK: - QSOStatistics Streak Extensions

extension QSOStatistics {
    /// Daily QSO streak (UTC dates for consistency with POTA)
    var dailyStreak: StreakInfo {
        if let cached = cachedDailyStreak {
            return cached
        }
        let activeDates = Set(cachedRealQSOs.map(\.utcDateOnly))
        let result = StreakCalculator.calculateStreak(from: activeDates, useUTC: true)
        let info = makeStreakInfo(id: "daily", category: .daily, result: result)
        cachedDailyStreak = info
        return info
    }

    /// POTA activation streak (UTC dates, 10+ QSOs per activation)
    var potaActivationStreak: StreakInfo {
        if let cached = cachedPotaActivationStreak {
            return cached
        }
        // Reuse cached activation groups from main class
        let validDates = Set(
            cachedActivationGroups.compactMap { _, qsos -> Date? in
                guard qsos.count >= 10, let first = qsos.first else {
                    return nil
                }
                return first.utcDateOnly
            }
        )
        let result = StreakCalculator.calculateStreak(from: validDates, useUTC: true)
        let info = makeStreakInfo(id: "pota", category: .pota, result: result)
        cachedPotaActivationStreak = info
        return info
    }

    /// Hunter streak (UTC dates, QSOs with park hunts)
    var hunterStreak: StreakInfo {
        if let cached = cachedHunterStreak {
            return cached
        }
        let hunterDates = Set(
            cachedRealQSOs
                .filter { $0.theirParkReference != nil && !$0.theirParkReference!.isEmpty }
                .map(\.utcDateOnly)
        )
        let result = StreakCalculator.calculateStreak(from: hunterDates, useUTC: true)
        let info = makeStreakInfo(id: "hunter", category: .hunter, result: result)
        cachedHunterStreak = info
        return info
    }

    /// All mode streaks sorted by current streak length (UTC dates)
    var modeStreaks: [StreakInfo] {
        if let cached = cachedModeStreaks {
            return cached
        }
        let realQSOs = cachedRealQSOs
        let modes = Set(realQSOs.map { $0.mode.uppercased() })
        let result = modes.map { mode in
            let dates = Set(realQSOs.filter { $0.mode.uppercased() == mode }.map(\.utcDateOnly))
            let result = StreakCalculator.calculateStreak(from: dates, useUTC: true)
            return makeStreakInfo(
                id: "mode-\(mode)", category: .mode, subcategory: mode, result: result
            )
        }.sorted { $0.currentStreak > $1.currentStreak }
        cachedModeStreaks = result
        return result
    }

    /// All band streaks sorted by current streak length (UTC dates)
    var bandStreaks: [StreakInfo] {
        if let cached = cachedBandStreaks {
            return cached
        }
        let realQSOs = cachedRealQSOs
        let bands = Set(realQSOs.map { $0.band.lowercased() })
        let result = bands.map { band in
            let dates = Set(realQSOs.filter { $0.band.lowercased() == band }.map(\.utcDateOnly))
            let result = StreakCalculator.calculateStreak(from: dates, useUTC: true)
            return makeStreakInfo(
                id: "band-\(band)", category: .band, subcategory: band, result: result
            )
        }.sorted { $0.currentStreak > $1.currentStreak }
        cachedBandStreaks = result
        return result
    }

    private func makeStreakInfo(
        id: String, category: StreakCategory, subcategory: String? = nil, result: StreakResult
    ) -> StreakInfo {
        StreakInfo(
            id: id, category: category, subcategory: subcategory,
            currentStreak: result.current, longestStreak: result.longest,
            currentStartDate: result.currentStart, longestStartDate: result.longestStart,
            longestEndDate: result.longestEnd, lastActiveDate: result.lastActive
        )
    }
}
