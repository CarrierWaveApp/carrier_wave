import CarrierWaveCore
import CarrierWaveData
import SwiftData
import UIKit

// MARK: - ServicePresenceWriteSinkRegistry

/// Main-actor handle to the live ServicePresence write seam so sync-upload
/// marking paths can route presence mutations through cw-store in `on`/`shadow`
/// mode. Set by `CarrierWaveApp.applyQSOMirrorMode`; `nil` in `off` mode. Value
/// type, so the registry holds it by value (no weak/strong cycle).
@MainActor
enum ServicePresenceWriteSinkRegistry {
    static var current: ServicePresenceWriteSink?
}

// MARK: - ServicePresenceWriteSink

/// Funnels standalone ServicePresence writes that do NOT ride a `QSOWriteSink`
/// commit — i.e. the sync-upload marking path (`markPresent` / `markUploadedToPark`
/// flipping `needsUpload`/`isSubmitted`). Presence changes that ride a QSO save are
/// already written by `QSOWriteSink.writeUpsertToStore`; this seam covers the rest.
///
/// Routed by `cwStoreQSOMode`:
/// - `on`: write cw-store FIRST (canonical — abort if it throws), then mutate the
///   SwiftData replica and save with `CwStoreMirror` suppressed so CloudKit still
///   picks up the change but the save does not echo back into cw-store.
/// - `shadow`/anything else: mutate SwiftData and save (the unsuppressed mirror
///   dual-writes in `shadow`). `off` mode never constructs a seam (registry is nil).
@MainActor
struct ServicePresenceWriteSink {
    let store: FieldStore
    let mirror: CwStoreMirror?
    var modeProvider: () -> CwStoreQSOMode = { CwStoreQSOMode.current }

    /// Commit a presence insert/update. The caller has already mutated the
    /// `ServicePresence` in `context`. In `on` mode this writes cw-store FIRST, then
    /// saves SwiftData with the mirror suppressed. Other modes just save (the
    /// unsuppressed mirror dual-writes in `shadow`). Throws if the canonical cw-store
    /// write fails — the caller must `rollback()`.
    func upsert(_ presence: ServicePresence, in context: ModelContext) throws {
        try upsertBatch([presence], in: context)
    }

    /// Commit a batch of presence inserts/updates. `on`: upsert every presence to
    /// cw-store FIRST, then one mirror-suppressed save. Other modes: one plain save.
    func upsertBatch(_ presences: [ServicePresence], in context: ModelContext) throws {
        if modeProvider() == .on {
            for presence in presences {
                try store.upsertServicePresence(item: SwiftDataStoreImporter.project(presence))
            }
            mirror?.beginSeamWrite(for: context)
            defer { mirror?.endSeamWrite(for: context) }
            try context.save()
        } else {
            try context.save()
        }
    }
}

// MARK: - ServicePresenceWriteSink + Routing

extension ServicePresenceWriteSink {
    /// Route a presence upsert through the active seam, or fall back to a plain
    /// SwiftData save when no seam is active (`off` mode / experiment disabled). The
    /// caller has already mutated the presence in `context`.
    @MainActor
    static func commitUpsert(_ presence: ServicePresence, in context: ModelContext) throws {
        if let sink = ServicePresenceWriteSinkRegistry.current {
            try sink.upsert(presence, in: context)
        } else {
            try context.save()
        }
    }

    /// Batch upsert through the active seam, or a plain save when no seam is active.
    @MainActor
    static func commitUpsertBatch(_ presences: [ServicePresence], in context: ModelContext) throws {
        if let sink = ServicePresenceWriteSinkRegistry.current {
            try sink.upsertBatch(presences, in: context)
        } else {
            try context.save()
        }
    }
}
