import Foundation
import SwiftData

// MARK: - SessionBackfillService

/// One-shot migration that groups historically-loose QSOs (those whose
/// `loggingSessionId` is `nil`) into synthetic per-UTC-day `LoggingSession`
/// records.
///
/// Introduced as part of CAR-276 PR5 to honour the post-unification invariant
/// "every QSO has a session." Before this PR landed, CW Sweep mostly logged
/// loose QSOs without any session ceremony — those records now retroactively
/// get a Casual session titled `"Pre-unification log · YYYY-MM-DD"`.
///
/// **Idempotency.** The completion flag is stored in
/// `NSUbiquitousKeyValueStore` (key `sessionsUnificationBackfillCompleted`)
/// so a second device upgrading after iCloud already finished the work sees
/// the flag and skips. The fallback to `UserDefaults` covers users with no
/// iCloud account configured.
///
/// **Performance.** Batched with a `fetchLimit` per pass to stay within the
/// 1,000-record cap from the project performance rules. Runs on a background
/// `ModelContext`; mutates SwiftData in chunks; saves once per day-bucket.
///
/// **Kill switch.** Users can disable backfill via the
/// `disableSessionBackfill` `UserDefaults` flag (settable from a future
/// Experiments toggle); if true, this returns immediately.
public enum SessionBackfillService {
    // MARK: Public

    public struct BackfillSummary: Sendable, Equatable {
        public let sessionsCreated: Int
        public let qsosAttached: Int
        public let skipped: Bool
    }

    public static let completionFlagKey = "sessionsUnificationBackfillCompleted"
    public static let killSwitchKey = "disableSessionBackfill"
    public static let preUnificationSessionTitlePrefix = "Pre-unification log"

    /// Returns `true` if backfill has already run on any device sharing this
    /// iCloud account (or, fallback, on this device if iCloud is unavailable).
    public static func isCompleted() -> Bool {
        if NSUbiquitousKeyValueStore.default.bool(forKey: completionFlagKey) {
            return true
        }
        return UserDefaults.standard.bool(forKey: completionFlagKey)
    }

    /// Mark backfill done. Writes both iCloud KV and UserDefaults so the
    /// next-launch check skips regardless of which store responds first.
    public static func markCompleted() {
        NSUbiquitousKeyValueStore.default.set(true, forKey: completionFlagKey)
        NSUbiquitousKeyValueStore.default.synchronize()
        UserDefaults.standard.set(true, forKey: completionFlagKey)
    }

    /// Group all loose QSOs into per-UTC-day Casual sessions. Safe to call
    /// repeatedly — internal completion guard skips re-runs.
    ///
    /// - Parameter modelContext: a background `ModelContext` bound to the
    ///   shared container. Caller owns the lifecycle.
    /// - Returns: `BackfillSummary` with counts (also useful for tests).
    @discardableResult
    @MainActor
    public static func runIfNeeded(modelContext: ModelContext) async -> BackfillSummary {
        if isCompleted() {
            return BackfillSummary(sessionsCreated: 0, qsosAttached: 0, skipped: true)
        }
        if UserDefaults.standard.bool(forKey: killSwitchKey) {
            return BackfillSummary(sessionsCreated: 0, qsosAttached: 0, skipped: true)
        }
        let summary = perform(modelContext: modelContext)
        markCompleted()
        return summary
    }

    // MARK: Private

    @MainActor
    private static func perform(modelContext: ModelContext) -> BackfillSummary {
        let grouped = collectLooseQSOsByDay(modelContext: modelContext)
        guard !grouped.isEmpty else {
            return BackfillSummary(sessionsCreated: 0, qsosAttached: 0, skipped: false)
        }
        var totalAttached = 0
        for (dayStart, qsos) in grouped {
            totalAttached += attachDayBucket(
                dayStart: dayStart, qsos: qsos, modelContext: modelContext
            )
        }
        return BackfillSummary(
            sessionsCreated: grouped.count,
            qsosAttached: totalAttached,
            skipped: false
        )
    }

    @MainActor
    private static func collectLooseQSOsByDay(modelContext: ModelContext) -> [Date: [QSO]] {
        let utcCalendar = utcCalendar()
        var grouped: [Date: [QSO]] = [:]
        var offset = 0
        let batchSize = 500
        while true {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.loggingSessionId == nil && !$0.isHidden }
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            guard let batch = try? modelContext.fetch(descriptor), !batch.isEmpty else {
                break
            }
            for qso in batch {
                let dayStart = utcCalendar.startOfDay(for: qso.timestamp)
                grouped[dayStart, default: []].append(qso)
            }
            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
        return grouped
    }

    @MainActor
    private static func attachDayBucket(
        dayStart: Date, qsos: [QSO], modelContext: ModelContext
    ) -> Int {
        let sortedQsos = qsos.sorted { $0.timestamp < $1.timestamp }
        guard let firstTimestamp = sortedQsos.first?.timestamp,
              let lastTimestamp = sortedQsos.last?.timestamp
        else {
            return 0
        }
        let title = "\(preUnificationSessionTitlePrefix) · \(formatDay(dayStart))"
        let myCallsign = sortedQsos.first?.myCallsign ?? ""
        let session = LoggingSession(
            myCallsign: myCallsign,
            startedAt: firstTimestamp,
            activationType: .casual
        )
        session.customTitle = title
        session.endedAt = lastTimestamp
        session.statusRawValue = LoggingSessionStatus.completed.rawValue
        session.qsoCount = sortedQsos.count
        session.cloudDirtyFlag = true
        modelContext.insert(session)
        for qso in sortedQsos {
            qso.loggingSessionId = session.id
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
        }
        try? modelContext.save()
        return sortedQsos.count
    }

    private static func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
}
