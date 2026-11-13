import BackgroundTasks
import UIKit

// MARK: - SatellitePassBackgroundRefresh

/// Background trigger for satellite pass alerts: a `BGAppRefreshTask` that
/// re-runs the alert scheduler (cache-first TLEs, stale fallback offline) so
/// the pending-notification schedule stays fresh while the app is closed.
/// Same shape as `SyncBackgroundRefresh` — registered at launch, (re)scheduled
/// on foreground/background transitions, once-only completion guard.
///
/// Gated on the feature actually being in use: scheduling is skipped (and any
/// pending request cancelled) unless pass alerts are enabled and at least one
/// satellite is favorited. BG windows are best-effort insurance — every app
/// foreground also reschedules, which is the actual workhorse.
enum SatellitePassBackgroundRefresh {
    // MARK: Internal

    nonisolated static let taskIdentifier = "com.jsvana.FullDuplex.satellite-pass-refresh"

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
        let enabled = UserDefaults.standard.bool(forKey: SatellitePassAlertScheduler.enabledKey)
        guard enabled, !FavoriteSatellitesStore.shared.noradIDs.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        // BGTaskScheduler.Error.unavailable is expected in simulators; the
        // feature degrades to foreground-only rescheduling.
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Private

    /// Thread-safe once-only completion (the work task and the expiration
    /// handler race on different queues) — same guard as SyncBackgroundRefresh.
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

    /// TLEs stay accurate for days and the SatNOGS cache max-age is 6 h;
    /// pass times drift by seconds over that window, well inside the alert
    /// lead time.
    private static let minimumInterval: TimeInterval = 6 * 3_600

    nonisolated private static func handle(_ task: BGAppRefreshTask) {
        let completion = BGTaskCompletion(task)
        let work = Task { @MainActor in
            await SatellitePassAlertScheduler.shared.rescheduleNow(trigger: "bg-refresh")
            schedule()
            completion.complete(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
    }
}
