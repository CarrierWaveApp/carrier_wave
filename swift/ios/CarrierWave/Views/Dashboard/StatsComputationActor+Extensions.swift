import CarrierWaveData
import Foundation

// MARK: - StatsComputationActor Computation Extensions

extension StatsComputationActor {
    func computeActivationsAndActivity(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        sessionIds: Set<UUID>,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.75, "Computing activations...")

        try Task.checkCancellation()
        // Compute activations (park + UTC date combinations)
        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let activationGroups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        stats.totalActivationGroups = activationGroups.count
        stats.successfulActivations = activationGroups.values.filter {
            uniqueQSOCount($0) >= 10
        }.count
        stats.attemptedActivations = activationGroups.values.filter {
            uniqueQSOCount($0) < 10
        }.count
        onProgress(0.80, "Computing activity grid...")

        try Task.checkCancellation()
        // Activity by date — combined plus split by type
        // Use UTC calendar to match session/activation grouping (which is UTC-based).
        // Using local time causes mismatches: e.g., a QSO at 06:00 UTC Feb 18 shows as
        // Feb 17 in PST, inflating the wrong day's count vs the Sessions view.
        var activity: [Date: Int] = [:]
        var activationActivity: [Date: Int] = [:]
        var hunterActivity: [Date: Int] = [:]
        for qso in realQSOs {
            let dateOnly = qso.utcDateOnly
            activity[dateOnly, default: 0] += 1

            // QSOs linked to a LoggingSession are activation QSOs;
            // all others (ActivityLog, imported, no session) are hunter QSOs
            let isActivation = qso.loggingSessionId.map { sessionIds.contains($0) } ?? false
            if isActivation {
                activationActivity[dateOnly, default: 0] += 1
            } else {
                hunterActivity[dateOnly, default: 0] += 1
            }
        }
        stats.activityByDate = activity
        stats.activationActivityByDate = activationActivity
        stats.activityLogActivityByDate = hunterActivity
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
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        let potaResult = computePOTAStreak(from: activationGroups)
        applyStreakResult(potaResult, to: &stats, prefix: "pota")
        onProgress(0.89, "Computing hunter streak...")

        try Task.checkCancellation()
        let hunterResult = computeHunterStreak(from: realQSOs)
        applyStreakResult(hunterResult, to: &stats, prefix: "hunter")
    }

    /// Compute CW, phone, and digital mode family streaks, plus all per-mode and per-band streaks
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

        // All per-mode streaks (for StreakDetailView drill-down)
        try Task.checkCancellation()
        stats.allModeStreaks = computeAllModeStreaks(from: realQSOs)

        // All per-band streaks (for StreakDetailView drill-down)
        try Task.checkCancellation()
        stats.allBandStreaks = computeAllBandStreaks(from: realQSOs)
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
            return .empty
        }

        let calendar = Calendar.current
        let uniqueDates = Set(qsos.map(\.localDateOnly)).sorted()

        guard !uniqueDates.isEmpty else {
            return .empty
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
        // Get successful activations (10+ unique QSOs) and their dates
        let successfulDates = activationGroups.values
            .filter { uniqueQSOCount($0) >= 10 }
            .compactMap { $0.first?.utcDateOnly }

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
        let hunterDates = qsos.compactMap { qso -> Date? in
            guard let theirPark = qso.theirParkReference, !theirPark.isEmpty else {
                return nil
            }
            return qso.utcDateOnly
        }
        guard !hunterDates.isEmpty else {
            return .empty
        }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let uniqueDates = Set(hunterDates).sorted()
        return computeStreakFromDates(uniqueDates, using: calendar)
    }

    /// Compute streak for a specific mode family (CW, phone, digital)
    func computeModeFamilyStreak(
        from qsos: [StatsQSOSnapshot],
        family: ModeFamily
    ) -> StreakResult {
        let dates = qsos.compactMap { qso -> Date? in
            guard ModeEquivalence.family(for: qso.mode) == family else {
                return nil
            }
            return qso.utcDateOnly
        }
        guard !dates.isEmpty else {
            return .empty
        }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let uniqueDates = Set(dates).sorted()
        return computeStreakFromDates(uniqueDates, using: calendar)
    }

    /// Shared streak computation logic for sorted unique start-of-day dates.
    /// Uses direct time interval arithmetic instead of expensive Calendar.dateComponents.
    /// Input dates MUST already be start-of-day (midnight) — which they are since we
    /// pre-compute utcDateOnly/localDateOnly on snapshots.
    func computeStreakFromDates(_ uniqueDates: [Date], using calendar: Calendar)
        -> StreakResult
    {
        guard !uniqueDates.isEmpty else {
            return .empty
        }

        // One day in seconds — dates are already start-of-day so interval math is exact
        let oneDay: TimeInterval = 86_400

        var currentStreak = 1
        var longestStreak = 1
        var streakStart = uniqueDates[0]
        var longestStreakStart = uniqueDates[0]
        var longestStreakEnd = uniqueDates[0]

        for idx in 1 ..< uniqueDates.count {
            let gap = uniqueDates[idx].timeIntervalSince(uniqueDates[idx - 1])
            if gap >= oneDay, gap < oneDay * 2 {
                // Consecutive day — extend streak
                currentStreak += 1
            } else if gap >= oneDay * 2 {
                // Gap found — save if longest, then reset
                if currentStreak > longestStreak {
                    longestStreak = currentStreak
                    longestStreakStart = streakStart
                    longestStreakEnd = uniqueDates[idx - 1]
                }
                currentStreak = 1
                streakStart = uniqueDates[idx]
            }
            // gap < oneDay means same day (shouldn't happen with Set dedup)
        }

        if currentStreak > longestStreak {
            longestStreak = currentStreak
            longestStreakStart = streakStart
            longestStreakEnd = uniqueDates[uniqueDates.count - 1]
        }

        // Check if current streak is active (includes today or yesterday)
        let today = calendar.startOfDay(for: Date())
        let lastDate = uniqueDates[uniqueDates.count - 1]
        let sinceLast = today.timeIntervalSince(lastDate)
        let isActive = sinceLast < oneDay * 2

        return StreakResult(
            current: isActive ? currentStreak : 0,
            longest: longestStreak,
            currentStart: isActive ? streakStart : nil,
            longestStart: longestStreakStart,
            longestEnd: longestStreakEnd,
            lastActive: lastDate
        )
    }

    /// Compute streaks for every distinct mode, sorted by current streak descending.
    private func computeAllModeStreaks(from qsos: [StatsQSOSnapshot]) -> [ComputedStreakInfo] {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let modes = Set(qsos.map { $0.mode.uppercased() })
        return modes.map { mode in
            let dates = Set(qsos.filter { $0.mode.uppercased() == mode }.map(\.utcDateOnly))
            let result = computeStreakFromDates(Array(dates).sorted(), using: calendar)
            return ComputedStreakInfo(
                id: "mode-\(mode)", categoryRaw: "mode", subcategory: mode,
                current: result.current, longest: result.longest,
                currentStart: result.currentStart, longestStart: result.longestStart,
                longestEnd: result.longestEnd, lastActive: result.lastActive
            )
        }.sorted { $0.current > $1.current }
    }

    /// Compute streaks for every distinct band, sorted by current streak descending.
    private func computeAllBandStreaks(from qsos: [StatsQSOSnapshot]) -> [ComputedStreakInfo] {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let bands = Set(qsos.map { $0.band.lowercased() })
        return bands.map { band in
            let dates = Set(qsos.filter { $0.band.lowercased() == band }.map(\.utcDateOnly))
            let result = computeStreakFromDates(Array(dates).sorted(), using: calendar)
            return ComputedStreakInfo(
                id: "band-\(band)", categoryRaw: "band", subcategory: band,
                current: result.current, longest: result.longest,
                currentStart: result.currentStart, longestStart: result.longestStart,
                longestEnd: result.longestEnd, lastActive: result.lastActive
            )
        }.sorted { $0.current > $1.current }
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
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        stats.activationsThisMonth = monthGroups.values.filter {
            uniqueQSOCount($0) >= 10
        }.count

        let yearActivations = parksOnly.filter { $0.timestamp >= yearStart }
        let yearGroups = Dictionary(grouping: yearActivations) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        stats.activationsThisYear = yearGroups.values.filter {
            uniqueQSOCount($0) >= 10
        }.count

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

    /// Count unique QSOs in a group (deduplicated by callsign + band + mode + park)
    private func uniqueQSOCount(_ qsos: [StatsQSOSnapshot]) -> Int {
        var seen = Set<String>()
        for qso in qsos {
            let park = qso.parkReference?.uppercased() ?? ""
            let key = "\(qso.callsign.uppercased())|\(qso.band)|\(qso.mode)|\(park)"
            seen.insert(key)
        }
        return seen.count
    }
}
