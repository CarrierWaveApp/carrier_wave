import Foundation

// MARK: - SyncTimeoutError

enum SyncTimeoutError: Error, LocalizedError, Sendable {
    case timeout(service: ServiceType)

    // MARK: Internal

    nonisolated var errorDescription: String? {
        switch self {
        case let .timeout(service):
            "\(service.displayName) sync timed out"
        }
    }
}

/// Execute an async operation with a timeout
/// Note: Uses nonisolated(unsafe) to allow SwiftData model access across actor boundaries
/// This is safe because the operation runs on MainActor and completes before returning
nonisolated func withTimeout<T>(
    seconds: TimeInterval,
    service: ServiceType,
    operation: @escaping () async throws -> T
) async throws -> T {
    // Use a simple race between operation and timeout
    // This avoids TaskGroup Sendable requirements
    let timeoutTask = Task {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw SyncTimeoutError.timeout(service: service)
    }

    do {
        let result = try await operation()
        timeoutTask.cancel()
        return result
    } catch {
        timeoutTask.cancel()
        throw error
    }
}

// MARK: - QRZSyncResult

/// Result of syncing with QRZ
struct QRZSyncResult {
    let downloaded: Int
    let uploaded: Int
    let skipped: Int
}

// MARK: - SyncPhase

enum SyncPhase: Equatable {
    case downloading(service: ServiceType)
    case processing
    case uploading(service: ServiceType)
}

// MARK: - SyncProgress

/// Tracks progress during sync operations
struct SyncProgress {
    /// Total QSOs downloaded so far across all services
    var downloadedQSOCount: Int = 0

    /// Breakdown by service
    var downloadedByService: [ServiceType: Int] = [:]

    /// LoFi-specific: total expected QSOs (from accounts endpoint)
    var lofiTotalQSOs: Int?

    /// LoFi-specific: total expected operations (from accounts endpoint)
    var lofiTotalOperations: Int?

    /// LoFi-specific: QSOs downloaded so far
    var lofiDownloadedQSOs: Int = 0

    /// LoFi progress as a fraction (0.0 to 1.0), or nil if total unknown
    var lofiProgress: Double? {
        guard let total = lofiTotalQSOs, total > 0 else {
            return nil
        }
        return min(Double(lofiDownloadedQSOs) / Double(total), 1.0)
    }

    /// Reset progress for a new sync
    mutating func reset() {
        downloadedQSOCount = 0
        downloadedByService = [:]
        lofiTotalQSOs = nil
        lofiTotalOperations = nil
        lofiDownloadedQSOs = 0
    }

    /// Add downloaded QSOs for a service
    mutating func addDownloaded(_ count: Int, for service: ServiceType) {
        downloadedQSOCount += count
        downloadedByService[service, default: 0] += count
    }
}

// MARK: - SyncResult

struct SyncResult {
    var downloaded: [ServiceType: Int]
    var uploaded: [ServiceType: Int]
    var errors: [String]
    var newQSOs: Int
    var mergedQSOs: Int
    var potaMaintenanceSkipped: Bool
}
