import CarrierWaveData
import Foundation
import SwiftData

// MARK: - CwStoreSeams

/// CW Sweep's one-liner for a main-context save that co-mutates QSOs, sessions
/// and session spots: routes every touched row through the shared Rust-store
/// seam (`SeamWriteBatch`, cw-store first under `.on`), or does a plain save
/// when no seam is active (`.off`). Call sites keep their own `try?` handling.
@MainActor
enum CwStoreSeams {
    static func save(
        _ context: ModelContext,
        qsos: [QSO] = [],
        sessions: [LoggingSession] = [],
        spots: [SessionSpot] = [],
        deletedSpots: [SessionSpot] = []
    ) throws {
        guard var batch = SeamWriteBatch.make() else {
            try context.save()
            return
        }
        for qso in qsos {
            batch.upsertQSO(qso)
        }
        for session in sessions {
            batch.upsert(session)
        }
        for spot in spots {
            batch.upsert(spot)
        }
        for spot in deletedSpots {
            batch.delete(spot)
        }
        try batch.commit(in: context)
    }

    /// Soft-delete one QSO by id (a hidden, dirty row still syncs; a hard
    /// delete never reaches the journal, so other devices would keep it).
    /// Returns false when the id isn't in the context.
    @discardableResult
    static func hideQSO(id: UUID, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let qso = try? context.fetch(descriptor).first else {
            return false
        }
        qso.isHidden = true
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        try? save(context, qsos: [qso])
        return true
    }
}
