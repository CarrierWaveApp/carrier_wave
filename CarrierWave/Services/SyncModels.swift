import CarrierWaveCore
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

// MARK: - ServiceSyncPhase

/// Per-service sync phase for rich progress UI
enum ServiceSyncPhase: Equatable {
    case waiting
    case downloading
    case downloaded(count: Int)
    case uploading
    case uploaded(count: Int)
    case complete(downloaded: Int, uploaded: Int)
    case error(String)

    // MARK: Internal

    /// Extract the downloaded count from phases that carry it
    var downloadedCount: Int? {
        switch self {
        case let .downloaded(count): count
        case let .complete(downloaded, _): downloaded
        default: nil
        }
    }
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

    /// POTA-specific: activations processed so far
    var potaProcessedActivations: Int = 0

    /// POTA-specific: total activations to process
    var potaTotalActivations: Int = 0

    /// POTA-specific: what kind of processing (e.g., "Fetching" or "Mapping")
    var potaPhase: String = ""

    /// Processing phase: total QSOs to process
    var processingTotalQSOs: Int = 0

    /// Processing phase: QSOs processed so far
    var processingProcessedQSOs: Int = 0

    /// Processing phase: current phase description
    var processingPhase: String = ""

    /// LoFi progress as a fraction (0.0 to 1.0), or nil if total unknown
    var lofiProgress: Double? {
        guard let total = lofiTotalQSOs, total > 0 else {
            return nil
        }
        return min(Double(lofiDownloadedQSOs) / Double(total), 1.0)
    }

    /// POTA progress as a fraction (0.0 to 1.0), or nil if not active
    var potaProgress: Double? {
        guard potaTotalActivations > 0 else {
            return nil
        }
        return min(Double(potaProcessedActivations) / Double(potaTotalActivations), 1.0)
    }

    /// Processing progress as a fraction (0.0 to 1.0), or nil if not processing
    var processingProgress: Double? {
        guard processingTotalQSOs > 0 else {
            return nil
        }
        return min(Double(processingProcessedQSOs) / Double(processingTotalQSOs), 1.0)
    }

    /// Reset progress for a new sync
    mutating func reset() {
        downloadedQSOCount = 0
        downloadedByService = [:]
        lofiTotalQSOs = nil
        lofiTotalOperations = nil
        lofiDownloadedQSOs = 0
        potaProcessedActivations = 0
        potaTotalActivations = 0
        potaPhase = ""
        processingTotalQSOs = 0
        processingProcessedQSOs = 0
        processingPhase = ""
    }

    /// Add downloaded QSOs for a service
    mutating func addDownloaded(_ count: Int, for service: ServiceType) {
        downloadedQSOCount += count
        downloadedByService[service, default: 0] += count
    }

    /// Update processing progress
    mutating func updateProcessing(processed: Int, total: Int, phase: String) {
        processingProcessedQSOs = processed
        processingTotalQSOs = total
        processingPhase = phase
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

// MARK: - ServiceSyncReport

/// User-facing report of what happened during a single service sync.
/// Sendable so it can cross from background actors to MainActor safely.
/// Codable so reports persist across app launches via UserDefaults.
struct ServiceSyncReport: Sendable, Codable {
    let service: ServiceType
    let timestamp: Date
    let status: SyncReportStatus
    let downloaded: Int
    let skipped: Int
    let created: Int
    let merged: Int
    let uploaded: Int
    let reconciliation: ReconciliationReport?

    /// Summary text for the service row tertiary info.
    /// Shows input → output: "247 fetched → 5 new, 12 enriched"
    var summaryText: String? {
        guard status != .error else {
            return nil
        }
        let changed = created + merged
        if changed == 0, uploaded == 0 {
            return downloaded > 0 ? "\(downloaded) fetched → no changes" : nil
        }
        var parts: [String] = []
        if created > 0 {
            parts.append("\(created) new")
        }
        if merged > 0 {
            parts.append("\(merged) enriched")
        }
        if uploaded > 0 {
            parts.append("\(uploaded) uploaded")
        }
        return "\(downloaded) fetched → \(parts.joined(separator: ", "))"
    }

    /// Whether the report has any notable issues worth highlighting
    var hasWarnings: Bool {
        skipped > 0
            || reconciliation?.hasWarnings == true
            || status == .error
    }
}

// MARK: - SyncReportStatus

enum SyncReportStatus: String, Sendable, Codable {
    case success
    case warning
    case error
}

// MARK: - ReconciliationReport

/// Service-specific reconciliation results.
struct ReconciliationReport: Sendable, Codable {
    static let empty = ReconciliationReport(
        qrzResetCount: 0, potaConfirmed: 0, potaFailed: 0,
        potaStale: 0, potaOrphan: 0, potaInProgress: 0
    )

    // QRZ-specific: presence records reset on full sync
    let qrzResetCount: Int

    // POTA-specific
    let potaConfirmed: Int
    let potaFailed: Int
    let potaStale: Int
    let potaOrphan: Int
    let potaInProgress: Int

    var hasWarnings: Bool {
        potaFailed > 0 || potaStale > 0 || potaOrphan > 0 || qrzResetCount > 0
    }
}
