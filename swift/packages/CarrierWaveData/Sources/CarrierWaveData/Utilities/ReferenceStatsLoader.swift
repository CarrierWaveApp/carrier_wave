// Reference Stats Loader
//
// Generic background actor for computing per-reference activation
// and QSO counts. Replaces ParkStatsLoader, SummitStatsLoader,
// and WWFFRefStatsLoader with a single reusable implementation.

import Foundation
import SwiftData

// MARK: - ReferenceStats

/// Activation and QSO counts for a reference (park, summit, or WWFF area)
public struct ReferenceStats: Sendable {
    // MARK: Lifecycle

    public init(activationCount: Int, qsoCount: Int) {
        self.activationCount = activationCount
        self.qsoCount = qsoCount
    }

    // MARK: Public

    public let activationCount: Int
    public let qsoCount: Int
}

// MARK: - ReferenceField

/// Which QSO reference field to aggregate stats for
public enum ReferenceField: Sendable {
    case parkReference
    case sotaRef
    case wwffRef
}

// MARK: - ReferenceStatsLoader

/// Background actor that computes per-reference activation and QSO counts
/// by batch-fetching QSOs with the specified reference field populated.
public actor ReferenceStatsLoader {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func loadStats(
        container: ModelContainer,
        field: ReferenceField
    ) async -> [String: ReferenceStats] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var stats: [String: (qsoCount: Int, dates: Set<String>)] = [:]
        let batchSize = 1_000
        var offset = 0

        while true {
            let descriptor = BoundedDescriptor<QSO>(
                predicate: predicate(for: field),
                limit: batchSize,
                offset: offset
            )

            guard let batch = try? context.boundedFetch(descriptor) else {
                break
            }
            if batch.isEmpty {
                break
            }

            for qso in batch {
                guard let ref = extractKey(from: qso, field: field),
                      !ref.isEmpty,
                      !QSOMode.isMetadata(qso.mode)
                else {
                    continue
                }
                let key = ref.uppercased()
                let dateStr = dateFormatter.string(from: qso.timestamp)
                var entry = stats[key, default: (qsoCount: 0, dates: [])]
                entry.qsoCount += 1
                entry.dates.insert(dateStr)
                stats[key] = entry
            }

            offset += batchSize
            await Task.yield()
        }

        return stats.mapValues {
            ReferenceStats(activationCount: $0.dates.count, qsoCount: $0.qsoCount)
        }
    }

    // MARK: Private

    private func predicate(for field: ReferenceField) -> Predicate<QSO> {
        switch field {
        case .parkReference:
            return #Predicate { $0.parkReference != nil && !$0.isHidden }
        case .sotaRef:
            return #Predicate { $0.sotaRef != nil && !$0.isHidden }
        case .wwffRef:
            return #Predicate { $0.wwffRef != nil && !$0.isHidden }
        }
    }

    private func extractKey(from qso: QSO, field: ReferenceField) -> String? {
        switch field {
        case .parkReference: qso.parkReference
        case .sotaRef: qso.sotaRef
        case .wwffRef: qso.wwffRef
        }
    }
}
