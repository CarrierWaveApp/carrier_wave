import UIKit

/// Keeps the process alive while critical writes finish after the user
/// backgrounds the app. Suspension while a cw-store commit holds the SQLite
/// file lock is a `0xdead10cc` RunningBoard kill; the assertion buys ~30 s of
/// background runtime — far more than a *single* batched commit needs.
///
/// The ~30 s is a single budget that starts when the app backgrounds; beginning
/// another assertion does NOT extend it. So for work that can outlast the grant
/// (a full sync whose download phase already spent most of it), the assertion
/// alone isn't enough — when the grant runs out the process is suspended, and if
/// that lands mid-commit it's still a `0xdead10cc` kill. `onExpiration` closes
/// that gap: set it to cancel the task that owns the work so a batched commit
/// loop bails at its next `Task.checkCancellation()` — a safe point *between*
/// SQLite commits — before suspension arrives.
///
/// Call `release()` when the protected work completes (a `defer` at the call
/// site is the expected shape). `release()` is idempotent; the expiration
/// handler releases automatically if the grant runs out first.
@MainActor
final class BackgroundTaskAssertion {
    // MARK: Lifecycle

    init(name: String) {
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.onExpiration?()
            self?.release()
        }
    }

    // MARK: Internal

    /// Invoked from the UIKit expiration handler just before the grant is
    /// released, so long-running work can stop at a safe point before the process
    /// is suspended. The canonical use is cancelling the task that owns the work
    /// (e.g. `SyncService.syncAll`), so a batched SQLite commit loop bails
    /// *between* commits rather than being suspended mid-fsync (`0xdead10cc`).
    var onExpiration: (() -> Void)?

    func release() {
        guard taskID != .invalid else {
            return
        }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }

    // MARK: Private

    private var taskID = UIBackgroundTaskIdentifier.invalid
}
