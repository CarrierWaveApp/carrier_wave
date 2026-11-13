import Foundation
import OSLog
import SwiftData

/// Watermark-driven background seeder that mirrors `QSO` rows into the
/// SQL `qsos` table in batches. Lifts the seed loop out of CW Sweep so
/// the iOS target can reuse it with a smaller batch size.
///
/// Concurrency note: the seed runs on a `Task.detached` and uses its
/// own `ModelContext`. Callers running this alongside other full-table
/// scans (e.g. `StatsComputationActor` on iOS) should serialize
/// externally to avoid concurrent OOM on 4 GB devices.
@MainActor
@Observable
public final class QuerySeedCoordinator {
    // MARK: Lifecycle

    public init(
        store: QueryStore,
        container: ModelContainer,
        batchSize: Int = 5_000,
        loggerSubsystem: String = "com.fullduplex.shared"
    ) {
        self.store = store
        self.container = container
        self.batchSize = batchSize
        self.loggerSubsystem = loggerSubsystem
    }

    // MARK: Public

    public enum SeedState: Equatable, Sendable {
        case idle
        case seeding(processed: Int, total: Int?)
        case ready
        case failed(String)
    }

    public private(set) var state: SeedState = .idle

    public func seedIfNeeded() {
        guard case .idle = state else {
            return
        }
        let store = store
        let container = container
        let batchSize = batchSize
        let loggerSubsystem = loggerSubsystem
        state = .seeding(processed: 0, total: nil)
        Task.detached(priority: .utility) { [weak self] in
            await Self.runSeed(
                store: store,
                container: container,
                batchSize: batchSize,
                loggerSubsystem: loggerSubsystem,
                progress: { [weak self] processed, total in
                    Task { @MainActor in
                        self?.state = .seeding(processed: processed, total: total)
                    }
                }
            )
            await self?.markReady()
        }
    }

    // MARK: Private

    private let store: QueryStore
    private let container: ModelContainer
    private let batchSize: Int
    private let loggerSubsystem: String

    private static func runSeed(
        store: QueryStore,
        container: ModelContainer,
        batchSize: Int,
        loggerSubsystem: String,
        progress: @escaping @Sendable (Int, Int?) -> Void
    ) async {
        do {
            let watermark = try await store.qsoSeedWatermark()
            let context = ModelContext(container)
            var fetched = 0
            var maxModified: Date? = watermark
            var offset = 0

            while true {
                let descriptor = makeDescriptor(
                    after: watermark,
                    offset: offset,
                    limit: batchSize
                )
                let qsos = try context.fetch(descriptor)
                if qsos.isEmpty {
                    break
                }
                let rows = qsos.compactMap(QSOMapper.slimRow(from:))
                if !rows.isEmpty {
                    try await store.upsertQSOs(rows)
                }
                for qso in qsos {
                    let mod = qso.modifiedAt ?? qso.timestamp
                    if maxModified == nil || mod > (maxModified ?? .distantPast) {
                        maxModified = mod
                    }
                }
                fetched += qsos.count
                progress(fetched, nil)
                if qsos.count < batchSize {
                    break
                }
                offset += batchSize
            }

            if let mark = maxModified {
                try await store.setQSOSeedWatermark(mark)
            }
        } catch {
            Logger(subsystem: loggerSubsystem, category: "QuerySeedCoordinator")
                .error("Seed failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func makeDescriptor(
        after watermark: Date?,
        offset: Int,
        limit: Int
    ) -> FetchDescriptor<QSO> { // perf-audit-ignore — fetchLimit set below
        var descriptor: FetchDescriptor<QSO> // perf-audit-ignore — fetchLimit set below
        if let watermark {
            let predicate = #Predicate<QSO> { qso in
                (qso.modifiedAt ?? qso.timestamp) > watermark
            }
            descriptor = FetchDescriptor<QSO>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        } else {
            descriptor = FetchDescriptor<QSO>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        }
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return descriptor
    }

    private func markReady() {
        state = .ready
    }
}
