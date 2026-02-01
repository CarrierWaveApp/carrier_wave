import Foundation
import SwiftData

// MARK: - AsyncServicePresenceCounts

/// Computes ServicePresence counts in the background to avoid blocking UI.
/// Fetches in batches and counts in memory to work around SwiftData predicate limitations.
@MainActor
@Observable
final class AsyncServicePresenceCounts {
    // MARK: Lifecycle

    init() {}

    // MARK: Internal

    /// Batch size for fetching
    static let batchSize = 1000

    /// Counts by service type
    private(set) var uploadedCounts: [ServiceType: Int] = [:]
    private(set) var pendingCounts: [ServiceType: Int] = [:]

    private(set) var isComputing = false

    /// Get uploaded count for a service
    func uploadedCount(for service: ServiceType) -> Int {
        uploadedCounts[service] ?? 0
    }

    /// Get pending count for a service
    func pendingCount(for service: ServiceType) -> Int {
        pendingCounts[service] ?? 0
    }

    /// Compute counts from database in background
    func compute(from modelContext: ModelContext) {
        computeTask?.cancel()
        isComputing = true

        computeTask = Task {
            await computeCounts(modelContext: modelContext)
        }
    }

    /// Cancel any in-flight computation
    func cancel() {
        computeTask?.cancel()
        isComputing = false
    }

    // MARK: Private

    private var computeTask: Task<Void, Never>?

    private func computeCounts(modelContext: ModelContext) async {
        // Initialize counts
        var uploaded: [ServiceType: Int] = [:]
        var pending: [ServiceType: Int] = [:]

        for serviceType in ServiceType.allCases {
            uploaded[serviceType] = 0
            pending[serviceType] = 0
        }

        // Fetch in batches
        var offset = 0
        let batchSize = Self.batchSize

        while true {
            guard !Task.isCancelled else {
                isComputing = false
                return
            }

            var descriptor = FetchDescriptor<ServicePresence>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }

            if batch.isEmpty {
                break
            }

            // Count in memory
            for presence in batch {
                if presence.isPresent {
                    uploaded[presence.serviceType, default: 0] += 1
                }
                if presence.needsUpload {
                    pending[presence.serviceType, default: 0] += 1
                }
            }

            offset += batchSize

            // Yield between batches
            await Task.yield()
        }

        // Update published values
        uploadedCounts = uploaded
        pendingCounts = pending
        isComputing = false
    }
}
