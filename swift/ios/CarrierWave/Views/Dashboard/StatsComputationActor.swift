import CarrierWaveData
import Foundation
import SwiftData

// MARK: - StatsQSOSnapshot

/// Lightweight, Sendable snapshot of QSO data for background computation.
/// Contains only the fields needed for statistics calculation.
/// Named StatsQSOSnapshot to avoid conflict with CarrierWaveCore.QSOSnapshot.
struct StatsQSOSnapshot {
    let id: UUID
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let myCallsign: String
    let theirGrid: String?
    let state: String?
    let parkReference: String?
    let theirParkReference: String?
    let importSource: ImportSource
    let qrzConfirmed: Bool
    let lotwConfirmed: Bool
    let dxcc: Int?
    let loggingSessionId: UUID?

    /// Pre-computed UTC start-of-day for this QSO's timestamp.
    /// Avoids redundant Calendar.startOfDay calls across streak computations.
    let utcDateOnly: Date

    /// Pre-computed local-timezone start-of-day for this QSO's timestamp.
    let localDateOnly: Date
}

// MARK: - WASSource

/// Source filter for WAS data
nonisolated enum WASSource: String, Hashable, CaseIterable {
    case qthOnly = "From QTH"
    case all = "All"
}

// MARK: - WASFilterKey

/// Combined filter key for pre-computed WAS data
nonisolated struct WASFilterKey: Hashable {
    let source: WASSource
    let mode: String? // nil = all modes
}

// MARK: - WASStateData

/// Pre-computed state counts and callsigns for a WAS filter combination
nonisolated struct WASStateData {
    var stateCounts: [String: Int] = [:]
    var stateCallsigns: [String: [String]] = [:]
}

// MARK: - ComputedStreakInfo

/// Sendable streak data for cross-actor transfer.
/// Converted to StreakInfo on the main actor.
struct ComputedStreakInfo {
    let id: String
    let categoryRaw: String
    let subcategory: String?
    let current: Int
    let longest: Int
    let currentStart: Date?
    let longestStart: Date?
    let longestEnd: Date?
    let lastActive: Date?
}

// MARK: - ComputedStats

/// All computed statistics, sent back to main actor when done.
struct ComputedStats {
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

    /// Attempted activations (park+date combos with <10 QSOs)
    var attemptedActivations: Int = 0

    /// All per-mode streaks (sorted by current streak descending)
    var allModeStreaks: [ComputedStreakInfo] = []
    /// All per-band streaks (sorted by current streak descending)
    var allBandStreaks: [ComputedStreakInfo] = []

    // Count metrics
    var qsosThisWeek: Int = 0
    var qsosThisMonth: Int = 0
    var qsosThisYear: Int = 0
    var activationsThisMonth: Int = 0
    var activationsThisYear: Int = 0
    var huntsThisWeek: Int = 0
    var huntsThisMonth: Int = 0
    var newDXCCThisYear: Int = 0

    var metadataExcludedCount: Int = 0

    // Intermediate counts for filter pipeline explanations
    var qsosWithDXCC: Int = 0
    var qsosWithGrid: Int = 0
    var qsosWithFrequency: Int = 0
    var qsosWithParkRef: Int = 0
    var uniqueCallsignCount: Int = 0
    var uniqueHunterCallsignCount: Int = 0
    var uniqueFrequencyGroupCount: Int = 0
    var totalActivationGroups: Int = 0

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

    // WAS (Worked All States)
    // Keyed by WASFilterKey (source × mode) for client-side filtering
    var wasData: [WASFilterKey: WASStateData] = [:]
    var wasAvailableModes: [String] = [] // Sorted modes with state QSOs
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

    /// Fetch all LoggingSession IDs for categorizing QSOs as activation vs hunter.
    /// QSOs linked to a LoggingSession are activation QSOs; all others are hunter QSOs.
    /// Uses propertiesToFetch to avoid loading full session objects.
    static func fetchLoggingSessionIds(context: ModelContext) -> Set<UUID> {
        var descriptor = FetchDescriptor<LoggingSession>()
        descriptor.propertiesToFetch = [\.id]
        guard let sessions = try? context.fetch(descriptor) else {
            return []
        }
        return Set(sessions.map(\.id))
    }

    /// Extract the base callsign from a potentially prefixed/suffixed callsign
    static func extractBaseCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        let knownSuffixes: Set = [
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

    /// Fetch QSOs and compute all statistics on background thread.
    func computeStats(
        container: ModelContainer,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        let profiler = StartupProfiler.shared

        // Create background context - this is the key to off-main-thread fetching
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Phase 1: Fetch and convert to snapshots
        profiler.record("stats.fetch.start")
        let snapshots = try await fetchAndConvertToSnapshots(
            container: container,
            onProgress: onProgress
        )
        profiler.record("stats.fetch.done(\(snapshots.count))")
        profiler.setQSOCount(snapshots.count)

        if snapshots.isEmpty {
            onProgress(1.0, "")
            return ComputedStats()
        }

        // Fetch LoggingSession IDs for categorizing QSOs
        profiler.record("stats.sessions.start")
        let sessionIds = Self.fetchLoggingSessionIds(context: context)
        profiler.record("stats.sessions.done(\(sessionIds.count))")

        // Phase 2: Compute stats from snapshots
        var stats = try await computeStatsFromSnapshots(
            snapshots, sessionIds: sessionIds, onProgress: onProgress
        )

        // `.on`: overlay the headline distinct counts from cw-store (SQL DISTINCT).
        // The snapshot scan still runs for streaks/activity/favorites/WAS — those
        // aren't in the analytics catalog — so this is an additive read-cutover of
        // just the headline counts (Rust/SwiftData values should agree; the device
        // shadow sweep is where any seam surfaces).
        if CwStoreQSOMode.current == .on,
           let store = try? await CwStoreProvider.shared.store()
        {
            await Self.overlayRustHeadlineCounts(into: &stats, store: store)
            await Self.overlayRustWASData(into: &stats, store: store)
        }
        return stats
    }

    // MARK: Private

    private static func snapshotFromQSO(
        _ qso: QSO,
        utcCalendar: Calendar,
        localCalendar: Calendar
    ) -> StatsQSOSnapshot {
        StatsQSOSnapshot(
            id: qso.id,
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            frequency: qso.frequency,
            timestamp: qso.timestamp,
            myCallsign: qso.myCallsign,
            theirGrid: qso.theirGrid,
            state: qso.state,
            parkReference: qso.parkReference,
            theirParkReference: qso.theirParkReference,
            importSource: qso.importSource,
            qrzConfirmed: qso.qrzConfirmed,
            lotwConfirmed: qso.lotwConfirmed,
            dxcc: qso.dxcc,
            loggingSessionId: qso.loggingSessionId,
            utcDateOnly: utcCalendar.startOfDay(for: qso.timestamp),
            localDateOnly: localCalendar.startOfDay(for: qso.timestamp)
        )
    }

    // MARK: - Fetching

    /// Fetch all non-hidden QSOs in batches and convert to Sendable snapshots.
    /// Fresh ModelContext per batch caps peak memory to ~3-5 MB per batch instead
    /// of loading 100k+ QSO objects (~300 MB) all at once.
    /// Deduplicates by ID to work around SwiftData returning duplicate records
    /// when CloudKit metadata tables exist in the store.
    private func fetchAndConvertToSnapshots(
        container: ModelContainer,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> [StatsQSOSnapshot] {
        onProgress(0.0, "Loading QSOs...")

        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let localCalendar = Calendar.current

        let batchSize = BoundedDescriptor<QSO>.maxLimit
        var offset = 0
        var seenIds = Set<UUID>()
        var snapshots: [StatsQSOSnapshot] = []

        while true {
            try Task.checkCancellation()

            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = BoundedDescriptor<QSO>(
                predicate: #Predicate { !$0.isHidden },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
                limit: batchSize,
                offset: offset
            )

            guard let batch = try? context.boundedFetch(descriptor),
                  !batch.isEmpty
            else {
                break
            }

            for qso in batch {
                guard seenIds.insert(qso.id).inserted else {
                    continue
                }
                snapshots.append(Self.snapshotFromQSO(
                    qso, utcCalendar: utcCalendar, localCalendar: localCalendar
                ))
            }

            offset += batch.count

            if batch.count < batchSize {
                break
            }

            let progress = min(Double(offset) / 100_000, 0.45)
            onProgress(progress, "Loading QSOs...")
        }

        onProgress(0.50, "Processing...")
        return snapshots
    }

    // MARK: - Statistics Computation

    /// Compute all statistics from pre-fetched snapshots.
    private func computeStatsFromSnapshots(
        _ snapshots: [StatsQSOSnapshot],
        sessionIds: Set<UUID>,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        let profiler = StartupProfiler.shared
        onProgress(0.50, "Computing statistics...")

        // Filter out metadata modes
        let realQSOs = snapshots.filter { !QSOMode.isMetadata($0.mode) }

        // Phase 1: Basic counts
        profiler.record("stats.basicCounts.start")
        var stats = try await computeBasicCounts(
            from: snapshots, realQSOs: realQSOs, onProgress: onProgress
        )
        profiler.record("stats.basicCounts.done")

        // Phase 2: Activations and activity
        profiler.record("stats.activations.start")
        try await computeActivationsAndActivity(
            into: &stats, from: realQSOs, sessionIds: sessionIds,
            onProgress: onProgress
        )
        profiler.record("stats.activations.done")

        // Phase 3: Streaks (moved to Extensions for line count management)
        profiler.record("stats.streaks.start")
        try await computeStreaks(into: &stats, from: realQSOs, onProgress: onProgress)
        profiler.record("stats.streaks.done")

        // Phase 4: Count metrics
        profiler.record("stats.countMetrics.start")
        try await computeCountMetrics(into: &stats, from: realQSOs, onProgress: onProgress)
        profiler.record("stats.countMetrics.done")

        onProgress(1.0, "")
        return stats
    }

    // MARK: - Computation Phases

    private func computeBasicCounts(
        from snapshots: [StatsQSOSnapshot],
        realQSOs _: [StatsQSOSnapshot],
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> ComputedStats {
        onProgress(0.55, "Computing statistics...")
        try Task.checkCancellation()

        // Single pass over all snapshots collects basic counts, favorites,
        // and WAS data — replaces ~12 separate filter/map/count passes.
        var acc = SinglePassAccumulator()
        for qso in snapshots {
            acc.process(qso)
        }

        onProgress(0.74, "Computing WAS...")
        try Task.checkCancellation()

        return acc.finalize()
    }
}

// Additional computation methods are in StatsComputationActor+Extensions.swift
