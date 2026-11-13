// cw-store Recovery Service
//
// User-initiated recovery for an orphaned encrypted cw-store (SQLCipher
// "file is not a database" — a lost/rotated at-rest key). Preserves the
// unopenable file (moved aside, NEVER deleted) and re-seeds a fresh store
// from SwiftData, which stays the authoritative copy of QSOs/sessions.
// Reference data (POTA/SOTA/…) re-downloads on next access; clubs/friends
// re-sync from the server. See
// docs/plans/2026-07-08-cwstore-passphrase-recovery.md.

import CarrierWaveData
import SwiftData
import UIKit

// MARK: - CwStoreRecoveryService

@MainActor
@Observable
final class CwStoreRecoveryService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    enum State: Equatable {
        case idle
        case rebuilding
        case done
        case failed(String)
    }

    static let shared = CwStoreRecoveryService()

    /// Posted after a successful rebuild so the app re-establishes the live QSO
    /// mirror against the fresh store (the mirror failed to start at launch
    /// because the store was orphaned). Without this, QSOs logged between the
    /// rebuild and the next relaunch reach SwiftData but never the fresh
    /// cw-store — and the now-set seed marker means they're never back-filled.
    static let didRebuildNotification = Notification.Name("CwStoreDidRebuild")

    private(set) var state: State = .idle

    /// Wired once at app launch so recovery can re-seed from the live SwiftData
    /// store.
    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Whether the cw-store currently fails to open because it is orphaned
    /// (undecryptable with the current key), as opposed to opening fine. Probed
    /// on demand — cheap, reuses the cached instance once open succeeds.
    func storeNeedsRecovery() async -> Bool {
        do {
            _ = try await CwStoreProvider.shared.store()
            return false
        } catch {
            return CwStoreProvider.isUnopenableStoreError(error)
        }
    }

    /// Preserve the orphaned store (rename aside, never delete), clear the seed
    /// marker, and re-seed a fresh store from SwiftData. After this the store
    /// opens again, so reference-data downloads work immediately, and the live
    /// QSO mirror is re-established (via `didRebuildNotification`) so no relaunch
    /// is needed.
    func rebuildFromSwiftData() async {
        guard state != .rebuilding else {
            return
        }
        state = .rebuilding
        do {
            try await CwStoreProvider.shared.moveOrphanedStoreAside()
            // Force the seed import to run again against the fresh store.
            UserDefaults.standard.removeObject(forKey: CwStoreImportCoordinator.importMarkerKey)
            if let container {
                let version = Bundle.main
                    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
                _ = try await CwStoreImportCoordinator
                    .appGroup(version: version)
                    .runIfNeeded(from: container)
            }
            state = .done
            NotificationCenter.default.post(name: Self.didRebuildNotification, object: nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Private

    private var container: ModelContainer?
}
