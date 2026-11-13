import CarrierWaveData
import Foundation

// MARK: - ServerSyncHostHooks

/// iOS bindings for the shared Carrier Wave Sync code in `CarrierWaveData`:
/// diagnostics into the persisted `SyncDebugLog`, background-task assertions
/// around long passes, and the cw-store key backup after a passphrase is
/// created or entered. Installed once from `CarrierWaveApp.init`.
@MainActor
enum ServerSyncHostHooks {
    static func install() {
        ServerSyncLog.install(SyncDebugLogSink())
        SuspensionGuardFactory.install { name in BackgroundTaskAssertion(name: name) }
        SyncKeyService.passphraseProvisioner = { passphrase in
            await CwStoreKeyRecovery.provision(passphrase: passphrase)
        }
    }
}

// MARK: - SyncDebugLogSink

private struct SyncDebugLogSink: ServerSyncLogging {
    func info(_ message: String) {
        Task { @MainActor in SyncDebugLog.shared.info(message) }
    }

    func error(_ message: String) {
        Task { @MainActor in SyncDebugLog.shared.error(message) }
    }
}

// MARK: - BackgroundTaskAssertion + SuspensionGuard

extension BackgroundTaskAssertion: SuspensionGuard {}
