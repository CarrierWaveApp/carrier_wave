import CarrierWaveData
import SwiftData
import UIKit

// MARK: - CarrierWaveApp + QSO Mirror

extension CarrierWaveApp {
    func applyQSOMirrorMode(_ mode: CwStoreQSOMode) async {
        guard ExperimentalFeature.isEnabled(.rustStoreQSO) else {
            return
        }
        if mode == .off {
            qsoMirror?.stop()
            qsoMirror = nil
            CwStoreMirrorRegistry.current = nil
            QSOWriteSinkRegistry.current = nil
            ServicePresenceWriteSinkRegistry.current = nil
            SeamWriteBatchRegistry.current = nil
            OffMainStoreSeam.deactivate()
            EntityWriteSinkFactory.clearAll()
            ActivityLogApiRegistry.current = nil
            SessionApiRegistry.current = nil
            LoggerCommandApiRegistry.current = nil
        } else if qsoMirror == nil {
            do {
                let store = try await CwStoreProvider.shared.store()
                let mirror = CwStoreMirror(store: store)
                mirror.start()
                qsoMirror = mirror
                CwStoreMirrorRegistry.current = mirror
                // Built once; not rebuilt on a shadow↔on toggle because the seam
                // reads the rollout mode live via `CwStoreQSOMode.current`.
                QSOWriteSinkRegistry.current = QSOWriteSink(store: store, mirror: mirror)
                ServicePresenceWriteSinkRegistry.current = ServicePresenceWriteSink(store: store, mirror: mirror)
                SeamWriteBatchRegistry.current = (store, mirror)
                OffMainStoreSeam.activate(store: store, mirror: mirror)
                EntityWriteSinkFactory.registerAll(store: store, mirror: mirror)
                ActivityLogApiRegistry.current = ActivityLogApi(store: store)
                SessionApiRegistry.current = SessionApi(store: store)
                LoggerCommandApiRegistry.current = LoggerCommandApi(store: store)
                let container = sharedModelContainer
                let version = Bundle.main
                    .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
                // The first-run import is the app's longest write burst; getting
                // suspended while a batch commit holds the cw-store SQLite lock
                // is a 0xdead10cc kill. The import is resumable, so an expired
                // grant just means it finishes on a later launch.
                let importGuard = BackgroundTaskAssertion(name: "CwStoreImportCoordinator.runIfNeeded")
                defer { importGuard.release() }
                _ = try await CwStoreImportCoordinator
                    .appGroup(version: version).runIfNeeded(from: container)
                // Copy legacy UserDefaults loadouts into the Rust loadout table
                // (idempotent, non-destructive — keeps the UserDefaults copy).
                await LoadoutMigration.runIfNeeded()
                // Heal cw-store orphans left by mirror-blind deletes (bulk
                // delete-all / CloudKit remote deletes) since the last run — the
                // importer is upsert-only and can't prune. Off-main; bounded paging.
                reconcileCwStoreFollower()
            } catch {
                CwStoreWriteLog.shared.record("QSO mirror setup failed: \(error.localizedDescription)")
            }
        }
    }

    /// Re-establish the follower after a live rebuild — the mirror never started
    /// at launch because the store was orphaned. Tear down any stale state, then
    /// rebuild against the fresh store so QSOs logged before the next relaunch
    /// are still mirrored (the seed marker is set, so they'd otherwise be lost to
    /// cw-store until a version bump).
    func reestablishMirrorAfterRebuild(mode: CwStoreQSOMode) async {
        await applyQSOMirrorMode(.off)
        await applyQSOMirrorMode(mode)
    }

    /// Prune cw-store orphans (rows SwiftData no longer has) on a detached task so
    /// the caller isn't blocked. No-op unless the experiment is on and the mode is
    /// shadow/on. Drains the mirror first so in-flight follower writes are applied
    /// before the cw-store snapshot, then reconciles on a background context. Safe to
    /// call from app setup and on every foreground (catches CloudKit remote deletes).
    func reconcileCwStoreFollower() {
        guard ExperimentalFeature.isEnabled(.rustStoreQSO), CwStoreQSOMode.current != .off else {
            return
        }
        let container = sharedModelContainer
        Task.detached(priority: .utility) {
            let mirror = await MainActor.run { CwStoreMirrorRegistry.current }
            await mirror?.drain()
            let logMessage: String?
            do {
                let store = try await CwStoreProvider.shared.store()
                let context = ModelContext(container)
                let report = try CwStoreReconciler(store: store).reconcileAll(in: context)
                logMessage = report.total > 0
                    ? "cw-store reconcile pruned \(report.total) orphan row(s)"
                    : nil
            } catch {
                logMessage = "cw-store reconcile failed: \(error.localizedDescription)"
            }
            if let logMessage {
                await MainActor.run { CwStoreWriteLog.shared.record(logMessage) }
            }
        }
    }
}
