import Foundation

// MARK: - Server-sync selection seam (Phase 7.2)

/// `CwStoreSyncMode` seam: when the user flips the sync engine to
/// `.serverSync`, the journal engine's entry points (`start`,
/// `schedulePendingChanges`, `fetchChanges`) route to an injected runner that
/// drives one `sync_run_once` pass against the E2E Carrier Wave server,
/// instead of touching `CKSyncEngine` at all. Default mode is `.off`; the
/// authority flip is user-gated on a two-device round-trip verification.
public extension CloudSyncJournalEngine {
    /// One pass against the E2E Carrier Wave server (`sync_run_once` via
    /// cw-ffi). Injected by the host app — the engine cannot mint bearer
    /// tokens or read the per-server data key itself. Returns success.
    typealias ServerSyncRunner = @Sendable () async -> Bool

    /// Install the runner used when `CwStoreSyncMode == .serverSync`. With no
    /// runner installed, server-sync mode is a no-op rather than falling back
    /// to CloudKit.
    func setServerSyncRunner(_ runner: ServerSyncRunner?) {
        serverSyncRunner = runner
    }
}

extension CloudSyncJournalEngine {
    /// Returns `true` when `CwStoreSyncMode == .serverSync` routed this call
    /// to the server-sync runner instead of CloudKit.
    func routeToServerSyncIfEnabled() async -> Bool {
        guard CwStoreSyncMode.current.drivesServerSync else {
            return false
        }
        _ = await serverSyncRunner?()
        return true
    }
}
