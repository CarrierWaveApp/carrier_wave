import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: deduplicate ServicePresence records.
///
/// iCloud sync can create multiple ServicePresence records for the same
/// (QSO, serviceType, parkReference) tuple when records arrive with different
/// UUIDs. This repair keeps the best-status record and deletes the rest.
actor ServicePresenceDeduplicationRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let scanned: Int
        let deleted: Int
    }

    func repair() async throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let descriptor = FetchDescriptor<ServicePresence>()
        let allPresence = try context.fetch(descriptor)

        // Group by (qsoID, serviceType, parkReference)
        var groups: [String: [ServicePresence]] = [:]
        for presence in allPresence {
            guard let qsoId = presence.qso?.id else {
                continue
            }
            let park = presence.parkReference ?? ""
            let key = "\(qsoId)|\(presence.serviceTypeRawValue)|\(park)"
            groups[key, default: []].append(presence)
        }

        var deleted = 0
        for (_, records) in groups where records.count > 1 {
            // Sort: isPresent first, then isSubmitted, then by lastConfirmedAt desc
            let sorted = records.sorted { lhs, rhs in
                if lhs.isPresent != rhs.isPresent {
                    return lhs.isPresent
                }
                if lhs.isSubmitted != rhs.isSubmitted {
                    return lhs.isSubmitted
                }
                let lDate = lhs.lastConfirmedAt ?? .distantPast
                let rDate = rhs.lastConfirmedAt ?? .distantPast
                return lDate > rDate
            }

            // Keep the first (best), delete the rest
            for duplicate in sorted.dropFirst() {
                context.delete(duplicate)
                deleted += 1
            }
        }

        if deleted > 0 {
            try context.save()
        }

        return RepairResult(scanned: allPresence.count, deleted: deleted)
    }

    // MARK: Private

    private let container: ModelContainer
}
