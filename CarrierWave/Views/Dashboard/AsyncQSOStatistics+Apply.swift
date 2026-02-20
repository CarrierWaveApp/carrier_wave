import CarrierWaveCore
import Foundation

// MARK: - Result Application

extension AsyncQSOStatistics {
    func writeWidgetData(_ computed: ComputedStats) {
        let yesterday = Calendar.current.date(
            byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())
        )
        let isAtRisk = { (lastActive: Date?, current: Int) -> Bool in
            guard current > 0, let last = lastActive, let cutoff = yesterday else {
                return false
            }
            return last < cutoff
        }

        WidgetDataWriter.writeStreaks(WidgetStreakSnapshot(
            onAirCurrent: computed.dailyStreakCurrent,
            onAirLongest: computed.dailyStreakLongest,
            onAirAtRisk: isAtRisk(computed.dailyStreakLastActive, computed.dailyStreakCurrent),
            activationCurrent: computed.potaStreakCurrent,
            activationLongest: computed.potaStreakLongest,
            activationAtRisk: isAtRisk(computed.potaStreakLastActive, computed.potaStreakCurrent),
            hunterCurrent: computed.hunterStreakCurrent,
            hunterLongest: computed.hunterStreakLongest,
            hunterAtRisk: isAtRisk(computed.hunterStreakLastActive, computed.hunterStreakCurrent),
            cwCurrent: computed.cwStreakCurrent,
            phoneCurrent: computed.phoneStreakCurrent,
            digitalCurrent: computed.digitalStreakCurrent,
            updatedAt: Date()
        ))
        WidgetDataWriter.writeCounts(WidgetCountSnapshot(
            qsosWeek: computed.qsosThisWeek,
            qsosMonth: computed.qsosThisMonth,
            qsosYear: computed.qsosThisYear,
            activationsMonth: computed.activationsThisMonth,
            activationsYear: computed.activationsThisYear,
            huntsWeek: computed.huntsThisWeek,
            huntsMonth: computed.huntsThisMonth,
            newDXCCYear: computed.newDXCCThisYear,
            updatedAt: Date()
        ))
    }

    func applyStreakStats(_ computed: ComputedStats) {
        dailyStreak = StreakInfo(
            id: "daily",
            category: .daily,
            subcategory: nil,
            currentStreak: computed.dailyStreakCurrent,
            longestStreak: computed.dailyStreakLongest,
            currentStartDate: computed.dailyStreakCurrentStart,
            longestStartDate: computed.dailyStreakLongestStart,
            longestEndDate: computed.dailyStreakLongestEnd,
            lastActiveDate: computed.dailyStreakLastActive
        )

        potaActivationStreak = StreakInfo(
            id: "pota",
            category: .pota,
            subcategory: nil,
            currentStreak: computed.potaStreakCurrent,
            longestStreak: computed.potaStreakLongest,
            currentStartDate: computed.potaStreakCurrentStart,
            longestStartDate: computed.potaStreakLongestStart,
            longestEndDate: computed.potaStreakLongestEnd,
            lastActiveDate: computed.potaStreakLastActive
        )

        applyModeStreaks(computed)
        applyHunterStreak(computed)
    }

    func applyModeStreaks(_ computed: ComputedStats) {
        cwStreak = StreakInfo(
            id: "cw",
            category: .mode,
            subcategory: "CW",
            currentStreak: computed.cwStreakCurrent,
            longestStreak: computed.cwStreakLongest,
            currentStartDate: computed.cwStreakCurrentStart,
            longestStartDate: computed.cwStreakLongestStart,
            longestEndDate: computed.cwStreakLongestEnd,
            lastActiveDate: computed.cwStreakLastActive
        )

        phoneStreak = StreakInfo(
            id: "phone",
            category: .mode,
            subcategory: "Phone",
            currentStreak: computed.phoneStreakCurrent,
            longestStreak: computed.phoneStreakLongest,
            currentStartDate: computed.phoneStreakCurrentStart,
            longestStartDate: computed.phoneStreakLongestStart,
            longestEndDate: computed.phoneStreakLongestEnd,
            lastActiveDate: computed.phoneStreakLastActive
        )

        digitalStreak = StreakInfo(
            id: "digital",
            category: .mode,
            subcategory: "Digital",
            currentStreak: computed.digitalStreakCurrent,
            longestStreak: computed.digitalStreakLongest,
            currentStartDate: computed.digitalStreakCurrentStart,
            longestStartDate: computed.digitalStreakLongestStart,
            longestEndDate: computed.digitalStreakLongestEnd,
            lastActiveDate: computed.digitalStreakLastActive
        )
    }

    func applyHunterStreak(_ computed: ComputedStats) {
        hunterStreak = StreakInfo(
            id: "hunter",
            category: .hunter,
            subcategory: nil,
            currentStreak: computed.hunterStreakCurrent,
            longestStreak: computed.hunterStreakLongest,
            currentStartDate: computed.hunterStreakCurrentStart,
            longestStartDate: computed.hunterStreakLongestStart,
            longestEndDate: computed.hunterStreakLongestEnd,
            lastActiveDate: computed.hunterStreakLastActive
        )
    }

    func applyCountMetrics(_ computed: ComputedStats) {
        qsosThisWeek = computed.qsosThisWeek
        qsosThisMonth = computed.qsosThisMonth
        qsosThisYear = computed.qsosThisYear
        activationsThisMonth = computed.activationsThisMonth
        activationsThisYear = computed.activationsThisYear
        huntsThisWeek = computed.huntsThisWeek
        huntsThisMonth = computed.huntsThisMonth
        newDXCCThisYear = computed.newDXCCThisYear
    }

    func applyServiceStats(_ computed: ComputedStats) {
        qrzConfirmedCount = computed.qrzConfirmedCount
        lotwConfirmedCount = computed.lotwConfirmedCount
        icloudImportedCount = computed.icloudImportedCount
        uniqueMyCallsigns = computed.uniqueMyCallsigns
    }

    func applyFavorites(_ computed: ComputedStats) {
        topFrequency = computed.topFrequency
        topFrequencyCount = computed.topFrequencyCount
        topFriend = computed.topFriend
        topFriendCount = computed.topFriendCount
        topHunter = computed.topHunter
        topHunterCount = computed.topHunterCount
    }
}
