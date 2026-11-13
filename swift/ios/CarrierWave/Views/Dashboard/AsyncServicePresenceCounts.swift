import CarrierWaveData
import Foundation
import SwiftData

// MARK: - PresenceSnapshot

/// Lightweight snapshot of ServicePresence for background computation.
struct PresenceSnapshot {
    // MARK: Lifecycle

    init(from presence: ServicePresence, qsoMyCallsign: String) {
        serviceType = presence.serviceType
        isPresent = presence.isPresent
        needsUpload = presence.needsUpload
        self.qsoMyCallsign = qsoMyCallsign.uppercased()
    }

    // MARK: Internal

    let serviceType: ServiceType
    let isPresent: Bool
    let needsUpload: Bool
    let qsoMyCallsign: String
}

// MARK: - PresenceComputationActor

/// Background actor for computing service presence counts.
actor PresenceComputationActor {
    // MARK: Internal

    /// Compute presence counts on background thread.
    /// Counts unique QSOs per service (not ServicePresence records) to avoid
    /// double-counting two-fer POTA activations. Excludes hidden QSOs.
    /// Only counts pending uploads for QSOs matching the primary callsign (if set)
    /// and for services that are actually configured.
    func computeCounts(
        container: ModelContainer,
        primaryCallsign: String?,
        configuredUploadServices: Set<ServiceType>
    ) async throws -> (uploaded: [ServiceType: Int], pending: [ServiceType: Int]) {
        self.configuredUploadServices = configuredUploadServices

        // In `.on`, serve the per-service uploaded/pending counts from cw-store
        // (SQL GROUP BY over the presence↔qso join, deduped by qso_id). Falls back
        // to the SwiftData batch scan below if the store can't be opened.
        if CwStoreQSOMode.current == .on,
           let store = try? await CwStoreProvider.shared.store()
        {
            return try await countsFromStore(
                store: store,
                primaryCallsign: primaryCallsign,
                configuredUploadServices: configuredUploadServices
            )
        }

        let profiler = StartupProfiler.shared
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let upperPrimary = primaryCallsign?.uppercased()

        var uploadedQSOIds: [ServiceType: Set<UUID>] = [:]
        var pendingQSOIds: [ServiceType: Set<UUID>] = [:]
        for serviceType in ServiceType.allCases {
            uploadedQSOIds[serviceType] = []
            pendingQSOIds[serviceType] = []
        }

        let totalCount = (try? context.boundedCount(ServicePresence.self)) ?? 0
        profiler.record("presence.count(\(totalCount))")

        if totalCount == 0 {
            return (counts(from: uploadedQSOIds), counts(from: pendingQSOIds))
        }

        try processBatches(
            container: container,
            totalCount: totalCount,
            upperPrimary: upperPrimary,
            uploadedQSOIds: &uploadedQSOIds,
            pendingQSOIds: &pendingQSOIds
        )

        profiler.record("presence.processed")
        return (counts(from: uploadedQSOIds), counts(from: pendingQSOIds))
    }

    // MARK: Private

    private static let fetchBatchSize = BoundedDescriptor<ServicePresence>.maxLimit

    /// Services configured for upload — only these count toward pending totals.
    private var configuredUploadServices: Set<ServiceType> = []

    /// `.on`-mode path: per-service counts straight from cw-store. The SQL dedupes by
    /// `qso_id` and applies the configured-services + primary-callsign pending filter,
    /// matching `accumulateBatch` above.
    private func countsFromStore(
        store: FieldStore,
        primaryCallsign: String?,
        configuredUploadServices: Set<ServiceType>
    ) async throws -> (uploaded: [ServiceType: Int], pending: [ServiceType: Int]) {
        let rows = try await RustAnalyticsReadSource(store: store).servicePresenceCounts(
            query: "",
            primaryCallsign: primaryCallsign,
            configuredServices: configuredUploadServices.map(\.rawValue)
        )
        var uploaded: [ServiceType: Int] = [:]
        var pending: [ServiceType: Int] = [:]
        for row in rows {
            guard let service = ServiceType(rawValue: row.service) else {
                continue
            }
            uploaded[service] = row.uploaded
            pending[service] = row.pending
        }
        return (uploaded, pending)
    }

    /// Fetch ServicePresence in batches with relationship prefetching to avoid
    /// N+1 lazy loads (was ~15K individual SQLite queries).
    /// Predicate filters hidden QSOs at the SQL level.
    private func processBatches(
        container: ModelContainer,
        totalCount: Int,
        upperPrimary: String?,
        uploadedQSOIds: inout [ServiceType: Set<UUID>],
        pendingQSOIds: inout [ServiceType: Set<UUID>]
    ) throws {
        var offset = 0
        let batchSize = Self.fetchBatchSize

        while offset < totalCount {
            try Task.checkCancellation()

            let batchContext = ModelContext(container)
            batchContext.autosaveEnabled = false

            let descriptor = BoundedDescriptor<ServicePresence>(
                predicate: #Predicate { $0.qso?.isHidden != true },
                limit: batchSize,
                offset: offset,
                relationshipKeyPathsForPrefetching: [\.qso]
            )

            let batch = (try? batchContext.boundedFetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }

            accumulateBatch(
                batch, upperPrimary: upperPrimary,
                uploadedQSOIds: &uploadedQSOIds, pendingQSOIds: &pendingQSOIds
            )

            offset += batch.count
            if batch.count < batchSize {
                break
            }
        }
    }

    private func accumulateBatch(
        _ batch: [ServicePresence],
        upperPrimary: String?,
        uploadedQSOIds: inout [ServiceType: Set<UUID>],
        pendingQSOIds: inout [ServiceType: Set<UUID>]
    ) {
        for presence in batch {
            guard let qso = presence.qso else {
                continue
            }
            let qsoId = qso.id

            if presence.isPresent {
                uploadedQSOIds[presence.serviceType, default: []].insert(qsoId)
            }
            if presence.needsUpload,
               configuredUploadServices.contains(presence.serviceType)
            {
                let qsoCallsign = qso.myCallsign.uppercased()
                let matchesPrimary =
                    qsoCallsign.isEmpty || upperPrimary == nil || qsoCallsign == upperPrimary
                if matchesPrimary {
                    pendingQSOIds[presence.serviceType, default: []].insert(qsoId)
                }
            }
        }
    }

    private func counts(from idSets: [ServiceType: Set<UUID>]) -> [ServiceType: Int] {
        idSets.mapValues(\.count)
    }
}

// MARK: - AsyncServicePresenceCounts

/// Computes ServicePresence counts on a background thread to avoid blocking UI.
@MainActor
@Observable
final class AsyncServicePresenceCounts {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Counts by service type
    private(set) var uploadedCounts: [ServiceType: Int] = [:]
    private(set) var pendingCounts: [ServiceType: Int] = [:]

    private(set) var isComputing = false

    /// Whether counts have been computed at least once
    private(set) var hasComputed = false

    /// Get uploaded count for a service
    func uploadedCount(for service: ServiceType) -> Int {
        uploadedCounts[service] ?? 0
    }

    /// Get pending count for a service
    func pendingCount(for service: ServiceType) -> Int {
        pendingCounts[service] ?? 0
    }

    /// Compute counts from model container on background thread.
    /// If already computing or already computed, this is a no-op.
    /// Use `recompute()` to force a fresh computation.
    func compute(from container: ModelContainer) {
        // Skip if already computing or already have results
        if isComputing || hasComputed {
            return
        }

        startComputation(from: container)
    }

    /// Force recomputation of counts (e.g., after sync)
    func recompute(from container: ModelContainer) {
        computeTask?.cancel()
        hasComputed = false
        startComputation(from: container)
    }

    /// Legacy method - compute from ModelContext (extracts container)
    func compute(from modelContext: ModelContext) {
        compute(from: modelContext.container)
    }

    /// Legacy method - recompute from ModelContext (extracts container)
    func recompute(from modelContext: ModelContext) {
        recompute(from: modelContext.container)
    }

    /// Wait for the current computation to finish (no-op if not computing).
    func waitUntilComplete() async {
        await computeTask?.value
    }

    /// Cancel any in-flight computation
    func cancel() {
        computeTask?.cancel()
        isComputing = false
    }

    // MARK: Private

    private var computeTask: Task<Void, Never>?
    private let computationActor = PresenceComputationActor()

    /// Get the primary callsign for filtering pending counts
    private func getPrimaryCallsign() -> String? {
        CallsignAliasService.shared.getCurrentCallsign()
    }

    private func startComputation(from container: ModelContainer) {
        isComputing = true
        let primaryCallsign = getPrimaryCallsign()
        let configured = CarrierWaveData.ServiceConfiguration.configuredUploadServices()

        computeTask = Task {
            do {
                let result = try await computationActor.computeCounts(
                    container: container,
                    primaryCallsign: primaryCallsign,
                    configuredUploadServices: configured
                )
                uploadedCounts = result.uploaded
                pendingCounts = result.pending
                hasComputed = true
                StartupProfiler.shared.record("dashboard.presenceCountsComplete")
            } catch is CancellationError {
                // Cancelled, just clean up
            } catch {
                // Other error, clean up
            }
            isComputing = false
        }
    }
}
