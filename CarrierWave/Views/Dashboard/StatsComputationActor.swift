import CarrierWaveCore
import Foundation
import SwiftData

// MARK: - StatsQSOSnapshot

/// Lightweight, Sendable snapshot of QSO data for background computation.
/// Contains only the fields needed for statistics calculation.
/// Named StatsQSOSnapshot to avoid conflict with CarrierWaveCore.QSOSnapshot.
struct StatsQSOSnapshot: Sendable {
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

    // Top favorites for dashboard card
    var topFrequency: String?
    var topFrequencyCount: Int = 0
    var topFriend: String?
    var topFriendCount: Int = 0
    var topHunter: String?
    var topHunterCount: Int = 0
}

// MARK: - StatsComputationActor

/// Background actor for fetching and computing statistics without blocking the main thread.
/// Creates its own ModelContext from the container to perform all work off the main thread.
actor StatsComputationActor {
    // MARK: Internal

    /// Batch size for fetching - larger batches are fine since we're off the main thread
    static let fetchBatchSize = 1_000

    // MARK: - Internal Helpers

    /// Get UTC date for a timestamp (for POTA activation grouping)
    static func utcDateOnly(from date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }

    /// Fetch QSOs and compute all statistics on background thread.
    func computeStats(
        container: ModelContainer,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        // Create background context - this is the key to off-main-thread fetching
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Phase 1: Fetch and convert to snapshots
        let snapshots = try await fetchAndConvertToSnapshots(
            context: context,
            onProgress: onProgress
        )

        if snapshots.isEmpty {
            onProgress(1.0, "")
            return ComputedStats()
        }

        // Phase 2: Compute stats from snapshots
        return try await computeStatsFromSnapshots(snapshots, onProgress: onProgress)
    }

    // MARK: Private

    /// Modes that represent metadata rather than actual contacts
    private static let metadataModes: Set<String> = [
        "INFO", "METADATA", "NOTE", "NOTES", "COMMENT",
    ]

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

    // MARK: - Fetching

    /// Fetch QSOs in batches on background thread and convert to Sendable snapshots.
    private func fetchAndConvertToSnapshots(
        context: ModelContext,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [StatsQSOSnapshot] {
        onProgress(0.0, "Counting QSOs...")

        // Get total count
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0

        if totalCount == 0 {
            return []
        }

        var snapshots: [StatsQSOSnapshot] = []
        snapshots.reserveCapacity(totalCount)

        var offset = 0
        let batchSize = Self.fetchBatchSize

        onProgress(0.02, "Loading QSOs...")

        while offset < totalCount {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? context.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            // Convert to snapshots
            for qso in batch {
                let snapshot = StatsQSOSnapshot(
                    id: qso.id,
                    callsign: qso.callsign,
                    band: qso.band,
                    mode: qso.mode,
                    frequency: qso.frequency,
                    timestamp: qso.timestamp,
                    myCallsign: qso.myCallsign,
                    theirGrid: qso.theirGrid,
                    parkReference: qso.parkReference,
                    importSource: qso.importSource,
                    qrzConfirmed: qso.qrzConfirmed,
                    lotwConfirmed: qso.lotwConfirmed,
                    dxcc: qso.dxcc
                )
                snapshots.append(snapshot)
            }

            offset += batchSize

            // Update progress (fetch phase is 0-50%)
            let fetchProgress = 0.5 * Double(min(offset, totalCount)) / Double(totalCount)
            onProgress(fetchProgress, "Loading QSOs... \(min(offset, totalCount))/\(totalCount)")
        }

        return snapshots
    }

    // MARK: - Statistics Computation

    /// Compute all statistics from pre-fetched snapshots.
    private func computeStatsFromSnapshots(
        _ snapshots: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        onProgress(0.50, "Computing statistics...")

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

    // MARK: - Computation Phases

    private func computeBasicCounts(
        from snapshots: [StatsQSOSnapshot],
        realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        var stats = ComputedStats()

        stats.totalQSOs = realQSOs.count
        onProgress(0.55, "Computing bands...")

        try Task.checkCancellation()
        stats.uniqueBands = Set(realQSOs.map { $0.band.lowercased() }).count
        onProgress(0.58, "Computing grids...")

        try Task.checkCancellation()
        stats.uniqueGrids = Set(realQSOs.compactMap(\.theirGrid).filter { !$0.isEmpty }).count
        onProgress(0.61, "Computing entities...")

        try Task.checkCancellation()
        stats.uniqueEntities = Set(realQSOs.compactMap(\.dxcc)).count
        onProgress(0.64, "Computing confirmations...")

        try Task.checkCancellation()
        stats.confirmedQSLs = realQSOs.filter { $0.lotwConfirmed || $0.qrzConfirmed }.count
        onProgress(0.67, "Computing service stats...")

        try Task.checkCancellation()
        stats.qrzConfirmedCount = snapshots.filter(\.qrzConfirmed).count
        stats.lotwConfirmedCount = snapshots.filter(\.lotwConfirmed).count
        stats.icloudImportedCount = snapshots.filter { $0.importSource == .icloud }.count
        onProgress(0.70, "Computing callsigns...")

        try Task.checkCancellation()
        stats.uniqueMyCallsigns = Set(
            snapshots.map { Self.extractBaseCallsign($0.myCallsign.uppercased()) }
                .filter { !$0.isEmpty }
        )

        // Compute top favorites for dashboard card
        try Task.checkCancellation()
        onProgress(0.72, "Computing favorites...")
        computeTopFavorites(into: &stats, from: realQSOs)

        return stats
    }

    private func computeStreaks(
        into stats: inout ComputedStats,
        from realQSOs: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.85, "Computing daily streak...")

        try Task.checkCancellation()
        let dailyResult = computeDailyStreak(from: realQSOs)
        stats.dailyStreakCurrent = dailyResult.current
        stats.dailyStreakLongest = dailyResult.longest
        stats.dailyStreakCurrentStart = dailyResult.currentStart
        stats.dailyStreakLongestStart = dailyResult.longestStart
        stats.dailyStreakLongestEnd = dailyResult.longestEnd
        stats.dailyStreakLastActive = dailyResult.lastActive
        onProgress(0.92, "Computing POTA streak...")

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

    private func computeDailyStreak(from qsos: [StatsQSOSnapshot]) -> StreakResult {
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

    private func computePOTAStreak(from activationGroups: [String: [StatsQSOSnapshot]])
        -> StreakResult
    {
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

    /// Shared streak computation logic for sorted unique dates
    /// Matches the logic in StreakCalculator.findAllStreaks
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
}

// Additional computation methods are in StatsComputationActor+Extensions.swift
