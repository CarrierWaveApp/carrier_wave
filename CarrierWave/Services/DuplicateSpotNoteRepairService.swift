import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: deduplicate spot comments that were appended multiple times
/// to QSO notes. This happened because the in-memory dedup set was cleared on
/// every app restart, causing all spot comments to be re-appended on each launch.
actor DuplicateSpotNoteRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult: Sendable {
        let scanned: Int
        let repaired: Int
    }

    let container: ModelContainer

    /// Scan QSOs with notes containing `[Spot:` and deduplicate repeated segments.
    func repair() throws -> RepairResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let batchSize = 500
        var totalScanned = 0
        var totalRepaired = 0
        var offset = 0

        while true {
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate<QSO> { qso in
                    qso.notes != nil && !qso.isHidden
                }
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset

            let candidates = try context.fetch(descriptor)
            if candidates.isEmpty {
                break
            }

            totalScanned += candidates.count

            for qso in candidates {
                guard let notes = qso.notes, notes.contains("[Spot:") else {
                    continue
                }

                let cleaned = deduplicateNotes(notes)
                if cleaned != notes {
                    qso.notes = cleaned
                    totalRepaired += 1
                }
            }

            if totalRepaired > 0 {
                try context.save()
            }

            if candidates.count < batchSize {
                break
            }
            offset += batchSize
        }

        return RepairResult(scanned: totalScanned, repaired: totalRepaired)
    }

    // MARK: Private

    /// Split notes by ` | `, remove duplicate segments, rejoin.
    private func deduplicateNotes(_ notes: String) -> String {
        let segments = notes.components(separatedBy: " | ")
        var seen = Set<String>()
        var unique: [String] = []

        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            unique.append(trimmed)
        }

        return unique.joined(separator: " | ")
    }
}
