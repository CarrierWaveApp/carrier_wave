import CarrierWaveData
import Foundation
import SwiftData

// MARK: - StatsReportBuilder

/// Builds a diagnostic bundle for stats accuracy reporting.
/// Runs on a background actor to avoid blocking the main thread.
/// Targets a single category/identifier for focused trace generation.
actor StatsReportBuilder {
    // MARK: Internal

    /// Export a report as formatted JSON data.
    @MainActor static func exportJSON(report: StatsReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    /// Build a complete diagnostic report for a reported stat inaccuracy.
    func buildReport(
        container: ModelContainer,
        userReport: UserReport,
        category: StatCategoryType
    ) async throws -> StatsReport {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Gather environment info
        let env = try gatherEnvironment(context: context)

        // Fetch relevant QSOs in batches
        let allSnapshots = try await fetchSnapshots(container: container)
        let hiddenCount = try context.boundedCount(
            QSO.self,
            predicate: #Predicate { $0.isHidden }
        )

        // Run filter trace for the specific category/identifier
        let traceResult = runFilterTrace(
            snapshots: allSnapshots,
            category: category,
            identifier: userReport.identifier,
            flaggedCallsigns: userReport.flaggedCallsigns
        )

        // Build stats snapshot
        let realCount = allSnapshots.filter { !QSOMode.isMetadata($0.mode) }.count
        let statsSnapshot = StatsSnapshot(
            totalRealQSOs: realCount,
            totalSnapshots: allSnapshots.count,
            hiddenQSOCount: hiddenCount,
            metadataExcludedCount: allSnapshots.count - realCount,
            deduplicatedCount: env.deduplicationCount,
            categoryItems: traceResult.categoryItems
        )

        return StatsReport(
            version: 1,
            generatedAt: Date(),
            appVersion: env.appVersion,
            userReport: userReport,
            statsSnapshot: statsSnapshot,
            matchingQSOs: traceResult.matchingQSOs,
            excludedQSOs: traceResult.excludedQSOs,
            filterTrace: traceResult.trace,
            environment: env
        )
    }

    // MARK: Private

    private func gatherEnvironment(context: ModelContext) throws -> EnvironmentContext {
        let totalCount = try context.boundedCount(QSO.self)
        let hiddenCount = try context.boundedCount(
            QSO.self,
            predicate: #Predicate { $0.isHidden }
        )

        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return EnvironmentContext(
            appVersion: "\(version) (\(build))",
            buildNumber: build,
            totalQSOCount: totalCount,
            realQSOCount: totalCount - hiddenCount,
            hiddenQSOCount: hiddenCount,
            deduplicationCount: 0,
            computationTimestamp: Date(),
            computationGeneration: 0
        )
    }

    /// Fetch all non-hidden QSOs as lightweight snapshots using batched fetching.
    private func fetchSnapshots(
        container: ModelContainer
    ) async throws -> [StatsQSOSnapshot] {
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
                snapshots.append(snapshotFromQSO(
                    qso,
                    utcCalendar: utcCalendar,
                    localCalendar: localCalendar
                ))
            }

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }

        return snapshots
    }

    private func snapshotFromQSO(
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
}
