import CarrierWaveData
import Foundation
import SwiftData

/// One-time repair: strip the legacy `OP: <nickname>` segment from QSO notes
/// where the notes were not user-authored. Pre-CAR-243 (commit 0db16b86,
/// 2026-05-06) `LoggingSessionManager.combineNotes` prepended `"OP: \(op)"`
/// to every logged QSO's notes, joined with ` | `. The new behavior drops the
/// prefix for new QSOs; this backfill cleans existing rows so the legacy
/// noise stops leaking into any surface that inspects `notes` directly.
///
/// Façade over `BatchedRewrite`.
actor OPPrefixBackfillService {
    // MARK: Lifecycle

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: Internal

    struct BackfillResult {
        let scanned: Int
        let repaired: Int
    }

    let container: ModelContainer

    /// Split `notes` by the ` | ` joiner used by the legacy `combineNotes`
    /// pipeline, drop any segment with the literal `OP: ` prefix (case-
    /// sensitive — the legacy code only emitted uppercase), and rejoin.
    /// Returns an empty string when every segment is stripped; callers
    /// should map that to `nil`.
    static func stripOPSegments(_ notes: String) -> String {
        let separator = " | "
        let segments = notes.components(separatedBy: separator)
        let kept = segments.filter { segment in
            !segment.hasPrefix("OP: ")
        }
        guard kept.count != segments.count else {
            return notes
        }
        return kept.joined(separator: separator)
    }

    /// Scan non-user-authored notes and strip any `OP: …` segments.
    func backfill() async throws -> BackfillResult {
        let result = try await BatchedRewrite<QSO>(
            label: "opPrefix.backfill",
            container: container,
            predicate: #Predicate<QSO> { qso in
                !qso.notesUserAuthored
                    && qso.notes != nil
                    && !qso.isHidden
            }
        ) { qso, _ in
            guard let notes = qso.notes else {
                return false
            }
            let cleaned = Self.stripOPSegments(notes)
            guard cleaned != notes else {
                return false
            }
            qso.notes = cleaned.isEmpty ? nil : cleaned
            return true
        }.run()

        return BackfillResult(scanned: result.scanned, repaired: result.mutated)
    }
}
