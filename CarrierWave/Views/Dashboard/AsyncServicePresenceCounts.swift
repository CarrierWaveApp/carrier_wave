import Foundation
import SwiftData

// MARK: - PresenceSnapshot

/// Lightweight snapshot of ServicePresence for background computation.
struct PresenceSnapshot: Sendable {
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
    /// Only counts pending uploads for QSOs matching the primary callsign (if set).
    func computeCounts(
        container: ModelContainer,
        primaryCallsign: String?
    ) async throws -> (uploaded: [ServiceType: Int], pending: [ServiceType: Int]) {
        // Create fresh context to ensure we see latest persisted data
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let upperPrimary = primaryCallsign?.uppercased()

        // Initialize counts
        var uploaded: [ServiceType: Int] = [:]
        var pending: [ServiceType: Int] = [:]

        for serviceType in ServiceType.allCases {
            uploaded[serviceType] = 0
            pending[serviceType] = 0
        }

        // Get total count
        let countDescriptor = FetchDescriptor<ServicePresence>()
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0

        if totalCount == 0 {
            return (uploaded, pending)
        }

        // Fetch in batches
        var offset = 0
        let batchSize = Self.fetchBatchSize

        while offset < totalCount {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<ServicePresence>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty {
                break
            }

            // Count from managed objects directly
            for presence in batch {
                if presence.isPresent {
                    uploaded[presence.serviceType, default: 0] += 1
                }
                if presence.needsUpload {
                    // Only count pending uploads for QSOs matching primary callsign
                    // This matches the filtering logic in SyncService.fetchQSOsNeedingUpload()
                    let qsoCallsign = presence.qso?.myCallsign.uppercased() ?? ""
                    let matchesPrimary =
                        qsoCallsign.isEmpty || upperPrimary == nil || qsoCallsign == upperPrimary
                    if matchesPrimary {
                        pending[presence.serviceType, default: 0] += 1
                    }
                }
            }

            offset += batchSize
        }

        return (uploaded, pending)
    }

    // MARK: Private

    /// Batch size for fetching - larger batches are fine on background thread
    private static let fetchBatchSize = 500
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

        computeTask = Task {
            do {
                let result = try await computationActor.computeCounts(
                    container: container,
                    primaryCallsign: primaryCallsign
                )
                uploadedCounts = result.uploaded
                pendingCounts = result.pending
                hasComputed = true
            } catch is CancellationError {
                // Cancelled, just clean up
            } catch {
                // Other error, clean up
            }
            isComputing = false
        }
    }
}
