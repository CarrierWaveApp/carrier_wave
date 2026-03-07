import CarrierWaveData
import Foundation

// MARK: - StatsComputationActor Computation Extensions

extension StatsComputationActor {
    func computeActivationsAndActivity(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        activityLogIds: Set<UUID>,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.75, "Computing activations...")

        try Task.checkCancellation()
        // Compute activations (park + UTC date combinations)
        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let activationGroups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(Self.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        stats.successfulActivations = activationGroups.values.filter { $0.count >= 10 }.count
        onProgress(0.80, "Computing activity grid...")

        try Task.checkCancellation()
        // Activity by date — combined plus split by type
        // Use UTC calendar to match session/activation grouping (which is UTC-based).
        // Using local time causes mismatches: e.g., a QSO at 06:00 UTC Feb 18 shows as
        // Feb 17 in PST, inflating the wrong day's count vs the Sessions view.
        var activity: [Date: Int] = [:]
        var activationActivity: [Date: Int] = [:]
        var activityLogActivity: [Date: Int] = [:]
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for qso in realQSOs {
            let dateOnly = calendar.startOfDay(for: qso.timestamp)
            activity[dateOnly, default: 0] += 1

            let isActivityLog = qso.loggingSessionId.map { activityLogIds.contains($0) } ?? false
            if isActivityLog {
                activityLogActivity[dateOnly, default: 0] += 1
            } else {
                activationActivity[dateOnly, default: 0] += 1
            }
        }
        stats.activityByDate = activity
        stats.activationActivityByDate = activationActivity
        stats.activityLogActivityByDate = activityLogActivity
    }

    // MARK: - Streak Computation

    /// Compute all streaks and update the stats struct
    func computeStreaks(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        try await computeBasicStreaks(into: &stats, from: realQSOs, onProgress: onProgress)
        try await computeModeFamilyStreaks(into: &stats, from: realQSOs, onProgress: onProgress)
    }

    /// Compute daily, POTA, and hunter streaks
    private func computeBasicStreaks(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.85, "Computing daily streak...")

        try Task.checkCancellation()
        let dailyResult = computeDailyStreak(from: realQSOs)
        applyStreakResult(dailyResult, to: &stats, prefix: "daily")
        onProgress(0.87, "Computing POTA streak...")

        try Task.checkCancellation()
        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let activationGroups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(StatsComputationActor.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        let potaResult = computePOTAStreak(from: activationGroups)
        applyStreakResult(potaResult, to: &stats, prefix: "pota")
        onProgress(0.89, "Computing hunter streak...")

        try Task.checkCancellation()
        let hunterResult = computeHunterStreak(from: realQSOs)
        applyStreakResult(hunterResult, to: &stats, prefix: "hunter")
    }

    /// Compute CW, phone, and digital mode family streaks
    private func computeModeFamilyStreaks(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.91, "Computing mode streaks...")

        try Task.checkCancellation()
        let cwResult = computeModeFamilyStreak(from: realQSOs, family: .cw)
        applyStreakResult(cwResult, to: &stats, prefix: "cw")

        try Task.checkCancellation()
        let phoneResult = computeModeFamilyStreak(from: realQSOs, family: .phone)
        applyStreakResult(phoneResult, to: &stats, prefix: "phone")

        try Task.checkCancellation()
        let digitalResult = computeModeFamilyStreak(from: realQSOs, family: .digital)
        applyStreakResult(digitalResult, to: &stats, prefix: "digital")
    }

    /// Apply a StreakResult to the appropriate fields in ComputedStats
    private func applyStreakResult(
        _ result: StreakResult,
        to stats: inout ComputedStats,
        prefix: String
    ) {
        switch prefix {
        case "daily":
            stats.dailyStreakCurrent = result.current
            stats.dailyStreakLongest = result.longest
            stats.dailyStreakCurrentStart = result.currentStart
            stats.dailyStreakLongestStart = result.longestStart
            stats.dailyStreakLongestEnd = result.longestEnd
            stats.dailyStreakLastActive = result.lastActive
        case "pota":
            stats.potaStreakCurrent = result.current
            stats.potaStreakLongest = result.longest
            stats.potaStreakCurrentStart = result.currentStart
            stats.potaStreakLongestStart = result.longestStart
            stats.potaStreakLongestEnd = result.longestEnd
            stats.potaStreakLastActive = result.lastActive
        case "hunter":
            stats.hunterStreakCurrent = result.current
            stats.hunterStreakLongest = result.longest
            stats.hunterStreakCurrentStart = result.currentStart
            stats.hunterStreakLongestStart = result.longestStart
            stats.hunterStreakLongestEnd = result.longestEnd
            stats.hunterStreakLastActive = result.lastActive
        case "cw":
            stats.cwStreakCurrent = result.current
            stats.cwStreakLongest = result.longest
            stats.cwStreakCurrentStart = result.currentStart
            stats.cwStreakLongestStart = result.longestStart
            stats.cwStreakLongestEnd = result.longestEnd
            stats.cwStreakLastActive = result.lastActive
        case "phone":
            stats.phoneStreakCurrent = result.current
            stats.phoneStreakLongest = result.longest
            stats.phoneStreakCurrentStart = result.currentStart
            stats.phoneStreakLongestStart = result.longestStart
            stats.phoneStreakLongestEnd = result.longestEnd
            stats.phoneStreakLastActive = result.lastActive
        case "digital":
            stats.digitalStreakCurrent = result.current
            stats.digitalStreakLongest = result.longest
            stats.digitalStreakCurrentStart = result.currentStart
            stats.digitalStreakLongestStart = result.longestStart
            stats.digitalStreakLongestEnd = result.longestEnd
            stats.digitalStreakLastActive = result.lastActive
        default:
            break
        }
    }

    // MARK: - Streak Helpers

    /// Compute daily streak (days with at least one QSO)
    func computeDailyStreak(from qsos: [StatsQSOSnapshot]) -> StreakResult {
        guard !qsos.isEmpty else {
            return StreakResult(
                current: 0, longest: 0, currentStart: nil,
                longestStart: nil, longestEnd: nil, lastActive: nil
            )
        }

        let calendar = Calendar.current
        let uniqueDates = Set(qsos.map { calendar.startOfDay(for: $0.timestamp) }).sorted()

        guard !uniqueDates.isEmpty else {
            return StreakResult(
                current: 0, longest: 0, currentStart: nil,
                longestStart: nil, longestEnd: nil, lastActive: nil
            )
        }

        let streakData = computeStreakFromDates(uniqueDates, using: calendar)
        return StreakResult(
            current: streakData.current,
            longest: streakData.longest,
            currentStart: streakData.currentStart,
            longestStart: streakData.longestStart,
            longestEnd: streakData.longestEnd,
            lastActive: uniqueDates.last
        )
    }

    /// Compute POTA activation streak (days with successful activations)
    func computePOTAStreak(from activationGroups: [String: [StatsQSOSnapshot]])
        -> StreakResult
    {
        // Get successful activations (10+ QSOs) and their dates
        let successfulDates = activationGroups.values
            .filter { $0.count >= 10 }
            .compactMap { group -> Date? in
                guard let first = group.first else {
                    return nil
                }
                return StatsComputationActor.utcDateOnly(from: first.timestamp)
            }

        guard !successfulDates.isEmpty else {
            return StreakResult(
                current: 0, longest: 0, currentStart: nil,
                longestStart: nil, longestEnd: nil, lastActive: nil
            )
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let uniqueDates = Set(successfulDates).sorted()

        let streakData = computeStreakFromDates(uniqueDates, using: calendar)
        return StreakResult(
            current: streakData.current,
            longest: streakData.longest,
            currentStart: streakData.currentStart,
            longestStart: streakData.longestStart,
            longestEnd: streakData.longestEnd,
            lastActive: uniqueDates.last
        )
    }

    /// Compute hunter streak (days with at least one hunt QSO)
    func computeHunterStreak(from qsos: [StatsQSOSnapshot]) -> StreakResult {
        let hunterQSOs = qsos.filter { qso in
            if let theirPark = qso.theirParkReference, !theirPark.isEmpty {
                return true
            }
            return false
        }
        guard !hunterQSOs.isEmpty else {
            return .empty
        }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let uniqueDates = Set(hunterQSOs.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
        return computeStreakFromDates(uniqueDates, using: calendar)
    }

    /// Compute streak for a specific mode family (CW, phone, digital)
    func computeModeFamilyStreak(
        from qsos: [StatsQSOSnapshot],
        family: ModeFamily
    ) -> StreakResult {
        let filtered = qsos.filter { ModeEquivalence.family(for: $0.mode) == family }
        guard !filtered.isEmpty else {
            return .empty
        }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let uniqueDates = Set(filtered.map { calendar.startOfDay(for: $0.timestamp) }).sorted()
        return computeStreakFromDates(uniqueDates, using: calendar)
    }

    /// Shared streak computation logic for sorted unique dates
    /// Matches the logic in StreakCalculator.findAllStreaks
    func computeStreakFromDates(_ uniqueDates: [Date], using calendar: Calendar)
        -> StreakResult
    {
        var currentStreak = 0
        var longestStreak = 0
        var streakStart: Date?
        var longestStreakStart: Date?
        var longestStreakEnd: Date?
        var previousDate: Date?

        for date in uniqueDates {
            if let prev = previousDate {
                let daysDiff = calendar.dateComponents([.day], from: prev, to: date).day ?? 0
                if daysDiff == 1 {
                    // Consecutive day - extend streak
                    currentStreak += 1
                } else if daysDiff > 1 {
                    // Gap found - save current streak if longest, then reset
                    if currentStreak > longestStreak {
                        longestStreak = currentStreak
                        longestStreakStart = streakStart
                        longestStreakEnd = prev
                    }
                    currentStreak = 1
                    streakStart = date
                }
                // daysDiff == 0 means same day (shouldn't happen with Set dedup) - ignore
            } else {
                currentStreak = 1
                streakStart = date
            }
            previousDate = date
        }

        if currentStreak > longestStreak {
            longestStreak = currentStreak
            longestStreakStart = streakStart
            longestStreakEnd = previousDate
        }

        // Check if current streak is active (includes today or yesterday)
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        // Use calendar comparison instead of direct equality for robustness
        let isActive =
            previousDate.map {
                calendar.isDate($0, inSameDayAs: today)
                    || calendar.isDate($0, inSameDayAs: yesterday)
            } ?? false

        return StreakResult(
            current: isActive ? currentStreak : 0,
            longest: longestStreak,
            currentStart: isActive ? streakStart : nil,
            longestStart: longestStreakStart,
            longestEnd: longestStreakEnd,
            lastActive: previousDate
        )
    }

    /// All 50 US state abbreviations for WAS computation (avoids @MainActor USStates access)
    private static let usStateAbbreviations: Set<String> = [
        "AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "IA", "ID", "IL", "IN", "KS", "KY", "LA", "MA", "MD",
        "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH",
        "NJ", "NM", "NV", "NY", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VA", "VT", "WA", "WI", "WV", "WY",
    ]

    /// Compute WAS (Worked All States) from QTH-only QSOs (no park reference)
    func computeWAS(into stats: inout ComputedStats, from realQSOs: [StatsQSOSnapshot]) {
        // Filter to QTH-only QSOs (not during a POTA activation)
        let qthQSOs = realQSOs.filter { $0.parkReference == nil || $0.parkReference!.isEmpty }

        var stateCounts: [String: Int] = [:]
        var stateCallsigns: [String: [String]] = [:]

        for qso in qthQSOs {
            guard let state = qso.state?.uppercased().trimmingCharacters(in: .whitespaces),
                  !state.isEmpty,
                  Self.usStateAbbreviations.contains(state)
            else {
                continue
            }
            stateCounts[state, default: 0] += 1
            stateCallsigns[state, default: []].append(qso.callsign)
        }

        stats.wasStateCounts = stateCounts
        stats.wasStateCallsigns = stateCallsigns
    }

    /// Compute top frequency, friend, and hunter for the favorites card
    func computeTopFavorites(into stats: inout ComputedStats, from qsos: [StatsQSOSnapshot]) {
        // Top frequency - group by rounded frequency
        // Note: qso.frequency is stored in MHz
        var frequencyCounts: [Double: Int] = [:]
        for qso in qsos {
            if let freqMHz = qso.frequency, freqMHz > 0 {
                // Round to nearest kHz (0.001 MHz) for grouping
                let roundedMHz = (freqMHz * 1_000).rounded() / 1_000
                frequencyCounts[roundedMHz, default: 0] += 1
            }
        }
        if let (freqMHz, count) = frequencyCounts.max(by: { $0.value < $1.value }) {
            stats.topFrequency = String(format: "%.3f", freqMHz)
            stats.topFrequencyCount = count
        }

        // Top friend - callsigns we've worked most
        var friendCounts: [String: Int] = [:]
        for qso in qsos {
            let call = qso.callsign.uppercased()
            if !call.isEmpty {
                friendCounts[call, default: 0] += 1
            }
        }
        if let (call, count) = friendCounts.max(by: { $0.value < $1.value }) {
            stats.topFriend = call
            stats.topFriendCount = count
        }

        // Top hunter - callsigns that have worked us at parks (P2P)
        var hunterCounts: [String: Int] = [:]
        for qso in qsos {
            if let park = qso.parkReference, !park.isEmpty {
                let call = qso.callsign.uppercased()
                if !call.isEmpty {
                    hunterCounts[call, default: 0] += 1
                }
            }
        }
        if let (call, count) = hunterCounts.max(by: { $0.value < $1.value }) {
            stats.topHunter = call
            stats.topHunterCount = count
        }
    }

    /// Compute count metrics (QSOs this week/month/year, activations, hunts, new DXCC)
    func computeCountMetrics(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.95, "Computing count metrics...")
        try Task.checkCancellation()

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now))!

        stats.qsosThisWeek = realQSOs.filter { $0.timestamp >= weekAgo }.count
        stats.qsosThisMonth = realQSOs.filter { $0.timestamp >= monthStart }.count
        stats.qsosThisYear = realQSOs.filter { $0.timestamp >= yearStart }.count

        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }

        let monthActivations = parksOnly.filter { $0.timestamp >= monthStart }
        let monthGroups = Dictionary(grouping: monthActivations) { qso in
            "\(qso.parkReference!)|\(StatsComputationActor.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        stats.activationsThisMonth = monthGroups.values.filter { $0.count >= 10 }.count

        let yearActivations = parksOnly.filter { $0.timestamp >= yearStart }
        let yearGroups = Dictionary(grouping: yearActivations) { qso in
            "\(qso.parkReference!)|\(StatsComputationActor.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        stats.activationsThisYear = yearGroups.values.filter { $0.count >= 10 }.count

        let hunterQSOs = realQSOs.filter { $0.theirParkReference != nil && !$0.theirParkReference!.isEmpty }
        stats.huntsThisWeek = Set(
            hunterQSOs.filter { $0.timestamp >= weekAgo }.compactMap(\.theirParkReference)
        ).count
        stats.huntsThisMonth = Set(
            hunterQSOs.filter { $0.timestamp >= monthStart }.compactMap(\.theirParkReference)
        ).count

        let byDXCC = Dictionary(grouping: realQSOs.filter { $0.dxcc != nil }) { $0.dxcc! }
        stats.newDXCCThisYear = byDXCC.values.filter { qsos in
            guard let earliest = qsos.min(by: { $0.timestamp < $1.timestamp }) else {
                return false
            }
            return earliest.timestamp >= yearStart
        }.count
    }
}
