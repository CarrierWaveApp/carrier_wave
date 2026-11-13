import Foundation

public extension Notification.Name {
    /// Posted when inbound QSO sync completes. Views should re-fetch data.
    nonisolated static let didSyncQSOs = Notification.Name("didSyncQSOs")

    /// Posted when a QSO is logged locally (logger or activity log). Views should re-fetch data.
    nonisolated static let didLogQSO = Notification.Name("didLogQSO")
}
