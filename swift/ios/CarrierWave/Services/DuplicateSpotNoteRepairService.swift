import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: deduplicate spot comments that were appended multiple times
/// to QSO notes. This happened because the in-memory dedup set was cleared on
/// every app restart, causing all spot comments to be re-appended on each launch.
///
/// Façade over `BatchedRewrite`.
actor DuplicateSpotNoteRepairService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct RepairResult {
        let scanned: Int
        let repaired: Int
    }

    let container: ModelContainer

    /// Scan QSOs with notes containing `[Spot:` and deduplicate repeated segments.
    func repair() async throws -> RepairResult {
        let result = try await BatchedRewrite<QSO>(
            label: "duplicateSpotNote.repair",
            container: container,
            predicate: #Predicate<QSO> { qso in
                qso.notes != nil && !qso.isHidden
            }
        ) { qso, _ in
            guard let notes = qso.notes, notes.contains("[Spot:") else {
                return false
            }
            let cleaned = Self.deduplicateNotes(notes)
            guard cleaned != notes else {
                return false
            }
            qso.notes = cleaned
            return true
        }.run()

        return RepairResult(scanned: result.scanned, repaired: result.mutated)
    }

    // MARK: Private

    /// Split notes by ` | `, remove duplicate segments, rejoin.
    private static func deduplicateNotes(_ notes: String) -> String {
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
