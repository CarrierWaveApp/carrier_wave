import Foundation

// MARK: - ServerSyncLogging

/// Where the shared server-sync code sends its diagnostics. iOS installs an
/// adapter onto its persisted `SyncDebugLog`; CW Sweep onto its own in-app log.
/// Nothing is logged until a host installs a sink.
public protocol ServerSyncLogging: Sendable {
    func info(_ message: String)
    func error(_ message: String)
}

// MARK: - ServerSyncLog

/// Process-wide sink for `SyncKeyService` / `ServerSnapshotCoordinator` output.
public enum ServerSyncLog {
    // MARK: Public

    public static func install(_ sink: any ServerSyncLogging) {
        holder.set(sink)
    }

    public static func info(_ message: String) {
        holder.get()?.info(message)
    }

    public static func error(_ message: String) {
        holder.get()?.error(message)
    }

    // MARK: Private

    private final class Holder: @unchecked Sendable {
        // MARK: Internal

        func set(_ value: (any ServerSyncLogging)?) {
            lock.withLock { self.value = value }
        }

        func get() -> (any ServerSyncLogging)? {
            lock.withLock { value }
        }

        // MARK: Private

        private let lock = NSLock()
        private var value: (any ServerSyncLogging)?
    }

    private static let holder = Holder()
}

// MARK: - SuspensionGuard

/// Keeps the process alive while a sync pass finishes after the app leaves the
/// foreground. iOS backs this with `UIApplication.beginBackgroundTask`; macOS
/// has no suspension kill and installs nothing.
@MainActor
public protocol SuspensionGuard: AnyObject {
    /// Called just before the grant runs out so the owner can stop at a safe
    /// point (cancel the task that owns the work).
    var onExpiration: (() -> Void)? { get set }
    func release()
}

// MARK: - SuspensionGuardFactory

@MainActor
public enum SuspensionGuardFactory {
    // MARK: Public

    public typealias Make = @MainActor (_ name: String) -> any SuspensionGuard

    /// Install the platform factory. Nil (the default) means no guard is taken.
    public static func install(_ make: Make?) {
        factory = make
    }

    public static func make(name: String) -> (any SuspensionGuard)? {
        factory?(name)
    }

    // MARK: Private

    private static var factory: Make?
}
