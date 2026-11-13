import CarrierWaveCore
import Foundation

// MARK: - UploadDiagnosticStore

/// Tracks upload error diagnostics for user-facing display.
/// Persisted to UserDefaults so diagnostics survive app restarts.
@MainActor
@Observable
final class UploadDiagnosticStore {
    // MARK: Lifecycle

    init() {
        diagnostics = Self.loadFromDisk()
    }

    // MARK: Internal

    static let shared = UploadDiagnosticStore()

    private(set) var diagnostics: [UploadErrorDiagnostic] = []

    /// Diagnostics grouped by category, sorted by priority (action-required first).
    var groupedByCategory: [(UploadErrorCategory, [UploadErrorDiagnostic])] {
        let grouped = Dictionary(grouping: diagnostics, by: \.category)
        return UploadErrorCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else {
                return nil
            }
            return (category, items)
        }
    }

    /// Total QSOs affected across all diagnostics.
    var totalAffectedQSOs: Int {
        diagnostics.reduce(into: 0) { $0 += $1.affectedCount }
    }

    /// Count of diagnostics that require user action (non-transient).
    var actionRequiredCount: Int {
        diagnostics.filter { !$0.category.isTransient }.count
    }

    /// Count of diagnostics that will auto-retry (transient).
    var willRetryCount: Int {
        diagnostics.filter(\.category.isTransient).count
    }

    /// Whether there are any diagnostics to show.
    var hasIssues: Bool {
        !diagnostics.isEmpty
    }

    /// Record a new diagnostic. Merges with existing if same service+category.
    func record(_ diagnostic: UploadErrorDiagnostic) {
        // Merge: if we already have a diagnostic for the same service+category, replace it
        if let existingIndex = diagnostics.firstIndex(where: {
            $0.service == diagnostic.service && $0.category == diagnostic.category
        }) {
            diagnostics[existingIndex] = diagnostic
        } else {
            diagnostics.append(diagnostic)
        }

        // Cap at max stored diagnostics
        if diagnostics.count > maxDiagnostics {
            diagnostics = Array(diagnostics.suffix(maxDiagnostics))
        }

        persistToDisk()
    }

    /// Clear all diagnostics for a service (call after successful upload).
    func clearForService(_ service: ServiceType) {
        diagnostics.removeAll { $0.service == service }
        persistToDisk()
    }

    /// Clear all diagnostics.
    func clearAll() {
        diagnostics.removeAll()
        persistToDisk()
    }

    /// Remove transient errors older than the stale threshold.
    func clearStale() {
        let cutoff = Date().addingTimeInterval(-staleThreshold)
        diagnostics.removeAll { $0.category.isTransient && $0.timestamp < cutoff }
        persistToDisk()
    }

    // MARK: Private

    private static let storageKey = "uploadDiagnostics"

    private let maxDiagnostics = 50
    /// Transient errors older than 1 hour are considered stale
    private let staleThreshold: TimeInterval = 3_600

    private static func loadFromDisk() -> [UploadErrorDiagnostic] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UploadErrorDiagnostic].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func persistToDisk() {
        guard let data = try? JSONEncoder().encode(diagnostics) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
