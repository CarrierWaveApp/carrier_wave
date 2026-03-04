import CarrierWaveData
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
    let theirParkReference: String?
    let importSource: ImportSource
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let dxcc: Int?
    let loggingSessionId: UUID?
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
    var activationActivityByDate: [Date: Int] = [:]
    var activityLogActivityByDate: [Date: Int] = [:]

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

    // Hunter streak
    var hunterStreakCurrent: Int = 0
    var hunterStreakLongest: Int = 0
    var hunterStreakCurrentStart: Date?
    var hunterStreakLongestStart: Date?
    var hunterStreakLongestEnd: Date?
    var hunterStreakLastActive: Date?

    // CW streak
    var cwStreakCurrent: Int = 0
    var cwStreakLongest: Int = 0
    var cwStreakCurrentStart: Date?
    var cwStreakLongestStart: Date?
    var cwStreakLongestEnd: Date?
    var cwStreakLastActive: Date?

    // Phone streak
    var phoneStreakCurrent: Int = 0
    var phoneStreakLongest: Int = 0
    var phoneStreakCurrentStart: Date?
    var phoneStreakLongestStart: Date?
    var phoneStreakLongestEnd: Date?
    var phoneStreakLastActive: Date?

    // Digital streak
    var digitalStreakCurrent: Int = 0
    var digitalStreakLongest: Int = 0
    var digitalStreakCurrentStart: Date?
    var digitalStreakLongestStart: Date?
    var digitalStreakLongestEnd: Date?
    var digitalStreakLastActive: Date?

    // Count metrics
    var qsosThisWeek: Int = 0
    var qsosThisMonth: Int = 0
    var qsosThisYear: Int = 0
    var activationsThisMonth: Int = 0
    var activationsThisYear: Int = 0
    var huntsThisWeek: Int = 0
    var huntsThisMonth: Int = 0
    var newDXCCThisYear: Int = 0

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

    // MARK: - Internal Helpers

    /// Get UTC date for a timestamp (for POTA activation grouping)
    static func utcDateOnly(from date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }

    /// Fetch all ActivityLog IDs for categorizing QSOs as activation vs activity log.
    static func fetchActivityLogIds(context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<ActivityLog>()
        guard let logs = try? context.fetch(descriptor) else {
            return []
        }
        return Set(logs.map(\.id))
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

        // Fetch ActivityLog IDs for categorizing QSOs
        let activityLogIds = Self.fetchActivityLogIds(context: context)

        // Phase 2: Compute stats from snapshots
        return try await computeStatsFromSnapshots(
            snapshots, activityLogIds: activityLogIds, onProgress: onProgress
        )
    }

    // MARK: Private

    /// Modes that represent metadata rather than actual contacts
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

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

    /// Fetch all non-hidden QSOs and convert to Sendable snapshots.
    /// Deduplicates by ID to work around SwiftData returning duplicate records
    /// when CloudKit metadata tables exist in the store (from prior cloudKitDatabase: .automatic).
    private func fetchAndConvertToSnapshots(
        context: ModelContext,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [StatsQSOSnapshot] {
        onProgress(0.0, "Loading QSOs...")

        try Task.checkCancellation()
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        guard let allQSOs = try? context.fetch(descriptor) else {
            return []
        }

        if allQSOs.isEmpty {
            return []
        }

        // Convert to snapshots, deduplicating by ID.
        // SwiftData may return the same record twice when the store contains
        // CloudKit mirroring metadata (ACHANGE/ATRANSACTION tables).
        var seenIds = Set<UUID>()
        seenIds.reserveCapacity(allQSOs.count)
        var snapshots: [StatsQSOSnapshot] = []
        snapshots.reserveCapacity(allQSOs.count)

        for qso in allQSOs {
            guard seenIds.insert(qso.id).inserted else {
                continue
            }
            snapshots.append(StatsQSOSnapshot(
                id: qso.id,
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                frequency: qso.frequency,
                timestamp: qso.timestamp,
                myCallsign: qso.myCallsign,
                theirGrid: qso.theirGrid,
                parkReference: qso.parkReference,
                theirParkReference: qso.theirParkReference,
                importSource: qso.importSource,
                qrzConfirmed: qso.qrzConfirmed,
                lotwConfirmed: qso.lotwConfirmed,
                dxcc: qso.dxcc,
                loggingSessionId: qso.loggingSessionId
            ))
        }

        onProgress(0.50, "Processing...")
        return snapshots
    }

    // MARK: - Statistics Computation

    /// Compute all statistics from pre-fetched snapshots.
    private func computeStatsFromSnapshots(
        _ snapshots: [StatsQSOSnapshot],
        activityLogIds: Set<UUID>,
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
            into: &stats, from: realQSOs, activityLogIds: activityLogIds,
            onProgress: onProgress
        )

        // Phase 3: Streaks (moved to Extensions for line count management)
        try await computeStreaks(into: &stats, from: realQSOs, onProgress: onProgress)

        // Phase 4: Count metrics
        try await computeCountMetrics(into: &stats, from: realQSOs, onProgress: onProgress)

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
}

// Additional computation methods are in StatsComputationActor+Extensions.swift
