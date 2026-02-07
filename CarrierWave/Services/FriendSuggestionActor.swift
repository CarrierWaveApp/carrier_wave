import Foundation
import SwiftData

// MARK: - CallsignCount

/// Lightweight result of QSO counting per callsign.
struct CallsignCount: Sendable {
    let callsign: String
    let count: Int
}

// MARK: - FriendSuggestionActor

/// Background actor that counts QSOs per callsign for friend suggestions.
/// Creates its own ModelContext to avoid blocking the main thread.
actor FriendSuggestionActor {
    // MARK: Internal

    /// Minimum QSO count to qualify as a suggestion.
    static let minimumQSOCount = 3

    /// Batch size for fetching QSOs.
    static let fetchBatchSize = 1_000

    /// Compute callsigns with 3+ QSOs, excluding the user's own callsign(s).
    func computeCallsignCounts(
        container: ModelContainer,
        ownCallsigns: Set<String>
    ) async throws -> [CallsignCount] {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let callsignCounts = try await fetchAndCount(context: context, ownCallsigns: ownCallsigns)

        return
            callsignCounts
                .filter { $0.count >= Self.minimumQSOCount }
                .sorted { $0.count > $1.count }
    }

    // MARK: Private

    /// Modes that represent metadata rather than actual contacts.
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// Extract the base callsign from a potentially prefixed/suffixed callsign.
    private static func extractBaseCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        let knownSuffixes: Set<String> = [
            "P", "M", "MM", "AM", "QRP", "R", "A", "B", "LH", "LGT", "CW", "SSB", "FT8",
        ]

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            if knownSuffixes.contains(second.uppercased()) {
                return first
            }
            if second.count <= 3 {
                return first
            }
            if first.count <= 2 {
                return second
            }
            return first.count >= second.count ? first : second
        }

        if parts.count == 3 {
            return parts[1]
        }

        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }

    /// Fetch QSOs in batches, count per normalized callsign.
    private func fetchAndCount(
        context: ModelContext,
        ownCallsigns: Set<String>
    ) async throws -> [CallsignCount] {
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0

        if totalCount == 0 {
            return []
        }

        var counts: [String: Int] = [:]
        var offset = 0

        while offset < totalCount {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
            descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.fetchBatchSize

            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else {
                break
            }

            for qso in batch {
                let mode = qso.mode.uppercased()
                if Self.metadataModes.contains(mode) {
                    continue
                }

                let normalized = Self.extractBaseCallsign(qso.callsign.uppercased())
                if normalized.isEmpty || ownCallsigns.contains(normalized) {
                    continue
                }

                counts[normalized, default: 0] += 1
            }

            offset += Self.fetchBatchSize
        }

        return counts.map { CallsignCount(callsign: $0.key, count: $0.value) }
    }
}
