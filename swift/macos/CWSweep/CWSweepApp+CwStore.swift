import CarrierWaveCore
import CarrierWaveData
import Foundation
import SwiftData

// MARK: - CWSweepApp + cw-store mirror

extension CWSweepApp {
    /// Start the shared Rust cw-store mirror for CW Sweep so its local SwiftData
    /// writes dual-write into cw-store, exactly as the iOS app does
    /// (`CarrierWaveApp.applyQSOMirrorMode`). The mirror machinery lives in
    /// `CarrierWaveData`, so both apps run one implementation.
    ///
    /// Wires the mirror, the Rust-authority write seams, the server-sync replica,
    /// the one-time seed import and the orphan reconcile. Reads stay on SwiftData
    /// (the follower); writes go cw-store first under `.on` (the macOS default
    /// since 2026-10-05). A no-op when the hidden `cwStoreQSOMode` default is
    /// `.off` — CW Sweep has no Experiments UI, so that key is the kill switch.
    func applyCwStoreMirrorMode() async {
        guard CwStoreQSOMode.current != .off else {
            return
        }
        guard cwStoreMirror == nil else {
            return
        }
        do {
            let store = try await CwStoreProvider.shared.store()
            let mirror = CwStoreMirror(store: store)
            mirror.start()
            cwStoreMirror = mirror
            CwStoreMirrorRegistry.current = mirror
            // Rust-authority write seams (cw-store first under `.on`), built once
            // like `CarrierWaveApp.applyQSOMirrorMode`; they read the rollout mode
            // live. The replica copies server-pulled rows into SwiftData so the
            // views that still read SwiftData see them.
            QSOWriteSinkRegistry.current = QSOWriteSink(store: store, mirror: mirror)
            SeamWriteBatchRegistry.current = (store, mirror)
            OffMainStoreSeam.activate(store: store, mirror: mirror)
            EntityWriteSinkFactory.registerAll(store: store, mirror: mirror)
            ServerSyncReplicaRegistry.install(
                SwiftDataSyncReplica(container: modelContainer, store: store, mirror: mirror)
            )
            let version = Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
            _ = try await CwStoreImportCoordinator
                .appGroup(version: version)
                .runIfNeeded(from: modelContainer)
            reconcileCwStoreFollower()
        } catch {
            CwStoreWriteLog.shared.record("CW Sweep cw-store mirror setup failed: \(error.localizedDescription)")
        }
    }

    /// Prune cw-store orphans (rows SwiftData no longer has) on a detached task so
    /// the caller isn't blocked. Mirrors `CarrierWaveApp.reconcileCwStoreFollower`:
    /// the mirror is blind to bulk/CloudKit-remote deletes and the importer is
    /// upsert-only, so the follower self-heals here. No-op unless the mode is
    /// shadow/on. Drains the mirror first so in-flight writes land before the
    /// snapshot, then reconciles on a background context.
    func reconcileCwStoreFollower() {
        guard CwStoreQSOMode.current != .off else {
            return
        }
        let container = modelContainer
        Task.detached(priority: .utility) {
            let mirror = await MainActor.run { CwStoreMirrorRegistry.current }
            await mirror?.drain()
            let logMessage: String?
            do {
                let store = try await CwStoreProvider.shared.store()
                let context = ModelContext(container)
                let report = try CwStoreReconciler(store: store).reconcileAll(in: context)
                logMessage = report.total > 0
                    ? "CW Sweep cw-store reconcile pruned \(report.total) orphan row(s)"
                    : nil
            } catch {
                logMessage = "CW Sweep cw-store reconcile failed: \(error.localizedDescription)"
            }
            if let logMessage {
                await MainActor.run { CwStoreWriteLog.shared.record(logMessage) }
            }
        }
    }
}
