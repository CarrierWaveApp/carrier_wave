import Foundation

// MARK: - QSOSnapshot

/// Lightweight, Sendable snapshot of QSO data for background computation.
/// Contains only the fields needed for statistics calculation.
struct QSOSnapshot: Sendable {
    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let myCallsign: String
    let theirGrid: String?
    let parkReference: String?
    let importSource: ImportSource
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let dxcc: Int?
}

// MARK: - ComputedStats

/// All computed statistics, sent back to main actor when done.
struct ComputedStats: Sendable {
    var totalQSOs: Int = 0
    var uniqueBands: Int = 0
    var uniqueGrids: Int = 0
    var confirmedQSLs: Int = 0
    var uniqueEntities: Int = 0
    var successfulActivations: Int = 0
    var activityByDate: [Date: Int] = [:]

    // Streak data - raw values that will be converted to StreakInfo on main actor
    var dailyStreakCurrent: Int = 0
    var dailyStreakLongest: Int = 0
    var dailyStreakCurrentStart: Date?
    var dailyStreakLongestStart: Date?
    var dailyStreakLongestEnd: Date?
    var dailyStreakLastActive: Date?

    var potaStreakCurrent: Int = 0
    var potaStreakLongest: Int = 0
    var potaStreakCurrentStart: Date?
    var potaStreakLongestStart: Date?
    var potaStreakLongestEnd: Date?
    var potaStreakLastActive: Date?

    var qrzConfirmedCount: Int = 0
    var lotwConfirmedCount: Int = 0
    var icloudImportedCount: Int = 0
    var uniqueMyCallsigns: Set<String> = []
}

// MARK: - StreakResult

/// Internal result type for streak computation
struct StreakResult: Sendable {
    var current: Int = 0
    var longest: Int = 0
    var currentStart: Date?
    var longestStart: Date?
    var longestEnd: Date?
    var lastActive: Date?
}

// MARK: - StatsComputationActor

/// Background actor for computing statistics without blocking the main thread.
/// Receives pre-converted snapshots and computes all stats in background.
actor StatsComputationActor {
    // MARK: Internal

    /// Compute all statistics from pre-fetched snapshots on background thread.
    func computeStats(
        from snapshots: [QSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        if snapshots.isEmpty {
            onProgress(1.0, "")
            return ComputedStats()
        }

        onProgress(0.0, "Computing statistics...")

        // Filter out metadata modes
        let realQSOs = snapshots.filter { !Self.metadataModes.contains($0.mode.uppercased()) }

        // Phase 1: Basic counts
        var stats = try await computeBasicCounts(
            from: snapshots, realQSOs: realQSOs, onProgress: onProgress
        )

        // Phase 2: Activations and activity
        try await computeActivationsAndActivity(
            into: &stats, from: realQSOs, onProgress: onProgress
        )

        // Phase 3: Streaks
        try await computeStreaks(into: &stats, from: realQSOs, onProgress: onProgress)

        onProgress(1.0, "")
        return stats
    }

    // MARK: Private

    /// Modes that represent metadata rather than actual contacts
    private static let metadataModes: Set<String> = [
        "INFO", "METADATA", "NOTE", "NOTES", "COMMENT",
    ]

    // MARK: - Private Helpers

    /// Get UTC date for a timestamp (for POTA activation grouping)
    private static func utcDateOnly(from date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }

    /// Extract the base callsign from a potentially prefixed/suffixed callsign
    private static func extractBaseCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        let knownSuffixes: Set<String> = [
            "P", "M", "MM", "AM", "QRP", "R", "A", "B", "LH", "LGT", "CW", "SSB", "FT8",
        ]

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            if knownSuffixes.contains(second.uppercased()) {
                return first
            }
            if second.count <= 3 {
                return first
            }
            if first.count <= 2 {
                return second
            }
            return first.count >= second.count ? first : second
        }

        if parts.count == 3 {
            return parts[1]
        }

        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }

    // MARK: - Computation Phases

    private func computeBasicCounts(
        from snapshots: [QSOSnapshot],
        realQSOs: [QSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        var stats = ComputedStats()

        stats.totalQSOs = realQSOs.count
        onProgress(0.10, "Computing bands...")

        try Task.checkCancellation()
        stats.uniqueBands = Set(realQSOs.map { $0.band.lowercased() }).count
        onProgress(0.15, "Computing grids...")

        try Task.checkCancellation()
        stats.uniqueGrids = Set(realQSOs.compactMap(\.theirGrid).filter { !$0.isEmpty }).count
        onProgress(0.20, "Computing entities...")

        try Task.checkCancellation()
        stats.uniqueEntities = Set(realQSOs.compactMap(\.dxcc)).count
        onProgress(0.25, "Computing confirmations...")

        try Task.checkCancellation()
        stats.confirmedQSLs = realQSOs.filter { $0.lotwConfirmed || $0.qrzConfirmed }.count
        onProgress(0.30, "Computing service stats...")

        try Task.checkCancellation()
        stats.qrzConfirmedCount = snapshots.filter(\.qrzConfirmed).count
        stats.lotwConfirmedCount = snapshots.filter(\.lotwConfirmed).count
        stats.icloudImportedCount = snapshots.filter { $0.importSource == .icloud }.count
        onProgress(0.35, "Computing callsigns...")

        try Task.checkCancellation()
        stats.uniqueMyCallsigns = Set(
            snapshots.map { Self.extractBaseCallsign($0.myCallsign.uppercased()) }
                .filter { !$0.isEmpty }
        )

        return stats
    }

    private func computeActivationsAndActivity(
        into stats: inout ComputedStats,
        from realQSOs: [QSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.45, "Computing activations...")

        try Task.checkCancellation()
        // Compute activations (park + UTC date combinations)
        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let activationGroups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(Self.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        stats.successfulActivations = activationGroups.values.filter { $0.count >= 10 }.count
        onProgress(0.55, "Computing activity grid...")

        try Task.checkCancellation()
        // Activity by date
        var activity: [Date: Int] = [:]
        let calendar = Calendar.current
        for qso in realQSOs {
            let dateOnly = calendar.startOfDay(for: qso.timestamp)
            activity[dateOnly, default: 0] += 1
        }
        stats.activityByDate = activity
    }

    private func computeStreaks(
        into stats: inout ComputedStats,
        from realQSOs: [QSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.70, "Computing daily streak...")

        try Task.checkCancellation()
        let dailyResult = computeDailyStreak(from: realQSOs)
        stats.dailyStreakCurrent = dailyResult.current
        stats.dailyStreakLongest = dailyResult.longest
        stats.dailyStreakCurrentStart = dailyResult.currentStart
        stats.dailyStreakLongestStart = dailyResult.longestStart
        stats.dailyStreakLongestEnd = dailyResult.longestEnd
        stats.dailyStreakLastActive = dailyResult.lastActive
        onProgress(0.85, "Computing POTA streak...")

        try Task.checkCancellation()
        // Get activation groups for POTA streak
        let parksOnly = realQSOs.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        let activationGroups = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(Self.utcDateOnly(from: qso.timestamp).timeIntervalSince1970)"
        }
        let potaResult = computePOTAStreak(from: activationGroups)
        stats.potaStreakCurrent = potaResult.current
        stats.potaStreakLongest = potaResult.longest
        stats.potaStreakCurrentStart = potaResult.currentStart
        stats.potaStreakLongestStart = potaResult.longestStart
        stats.potaStreakLongestEnd = potaResult.longestEnd
        stats.potaStreakLastActive = potaResult.lastActive
    }

    private func computeDailyStreak(from qsos: [QSOSnapshot]) -> StreakResult {
        guard !qsos.isEmpty else {
            return StreakResult()
        }

        let calendar = Calendar.current
        let uniqueDates = Set(qsos.map { calendar.startOfDay(for: $0.timestamp) }).sorted()

        guard !uniqueDates.isEmpty else {
            return StreakResult()
        }

        var result = StreakResult()
        result.lastActive = uniqueDates.last

        let streakData = computeStreakFromDates(uniqueDates, using: calendar)
        result.current = streakData.current
        result.longest = streakData.longest
        result.currentStart = streakData.currentStart
        result.longestStart = streakData.longestStart
        result.longestEnd = streakData.longestEnd

        return result
    }

    private func computePOTAStreak(from activationGroups: [String: [QSOSnapshot]]) -> StreakResult {
        // Get successful activations (10+ QSOs) and their dates
        let successfulDates = activationGroups.values
            .filter { $0.count >= 10 }
            .compactMap { group -> Date? in
                guard let first = group.first else {
                    return nil
                }
                return Self.utcDateOnly(from: first.timestamp)
            }

        guard !successfulDates.isEmpty else {
            return StreakResult()
        }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let uniqueDates = Set(successfulDates).sorted()

        var result = StreakResult()
        result.lastActive = uniqueDates.last

        let streakData = computeStreakFromDates(uniqueDates, using: calendar)
        result.current = streakData.current
        result.longest = streakData.longest
        result.currentStart = streakData.currentStart
        result.longestStart = streakData.longestStart
        result.longestEnd = streakData.longestEnd

        return result
    }

    /// Shared streak computation logic for sorted unique dates
    private func computeStreakFromDates(_ uniqueDates: [Date], using calendar: Calendar)
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
                    currentStreak += 1
                } else {
                    if currentStreak > longestStreak {
                        longestStreak = currentStreak
                        longestStreakStart = streakStart
                        longestStreakEnd = prev
                    }
                    currentStreak = 1
                    streakStart = date
                }
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
        let isActive = previousDate == today || previousDate == yesterday

        var result = StreakResult()
        result.current = isActive ? currentStreak : 0
        result.longest = longestStreak
        result.currentStart = isActive ? streakStart : nil
        result.longestStart = longestStreakStart
        result.longestEnd = longestStreakEnd
        return result
    }
}
