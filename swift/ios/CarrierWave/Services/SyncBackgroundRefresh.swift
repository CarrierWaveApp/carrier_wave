import BackgroundTasks
import CarrierWaveData
import UIKit

// MARK: - SyncBackgroundRefresh

/// Phase 7.3 background trigger for the E2E server sync: a `BGAppRefreshTask`
/// that runs one `SyncKeyService.runBackgroundPass` when iOS grants a refresh
/// window. Registered at launch (before `didFinishLaunching` returns) and
/// (re)scheduled on foreground + background transitions.
///
/// Gated on enrollment: scheduling is skipped (and any pending request
/// cancelled) unless the data key for the active base URL is present, so
/// un-enrolled installs never wake for nothing. The pass itself only ever
/// uses the batch push/pull FFI calls (one Rust-side transaction each), the
/// suspension-safe shape from the 0xdead10cc fix (5acf47d4); the BGTask's own
/// expiration handler covers the window running out.
enum SyncBackgroundRefresh {
    // MARK: Internal

    nonisolated static let taskIdentifier = "com.jsvana.FullDuplex.sync-refresh"

    /// Must run before the app finishes launching (called from
    /// `CarrierWaveApp.init`).
    nonisolated static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Queue the next refresh window. Safe to call repeatedly; BGTaskScheduler
    /// replaces the pending request for the same identifier.
    @MainActor
    static func schedule() {
        guard SyncKeyService.isEnrolledForActiveServer else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // BGTaskScheduler.Error.unavailable is expected in simulators/
            // extensions; anything else is worth seeing in the sync log.
            SyncDebugLog.shared.info(
                "Background sync: could not schedule refresh — \(error.localizedDescription)"
            )
        }
    }

    // MARK: Private

    /// Thread-safe once-only completion for a `BGAppRefreshTask`: the work
    /// task and the expiration handler race on different queues, and calling
    /// `setTaskCompleted` twice is a runtime error. `setTaskCompleted` itself
    /// is documented thread-safe, hence `@unchecked Sendable` around the
    /// NSLock-guarded flag.
    nonisolated private final class BGTaskCompletion: @unchecked Sendable {
        // MARK: Lifecycle

        init(_ task: BGAppRefreshTask) {
            self.task = task
        }

        // MARK: Internal

        func complete(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else {
                return
            }
            completed = true
            task.setTaskCompleted(success: success)
        }

        // MARK: Private

        private let task: BGAppRefreshTask
        private let lock = NSLock()
        private var completed = false
    }

    private static let minimumInterval: TimeInterval = 15 * 60

    nonisolated private static func handle(_ task: BGAppRefreshTask) {
        let completion = BGTaskCompletion(task)
        let work = Task { @MainActor in
            let success = await SyncKeyService.runBackgroundPass(trigger: "bg-refresh")
            schedule()
            completion.complete(success: success)
        }
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }
}
