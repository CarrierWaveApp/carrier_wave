import Foundation

public extension Notification.Name {
    /// Posted when inbound QSO sync completes. Views should re-fetch data.
    nonisolated static let didSyncQSOs = Notification.Name("didSyncQSOs")
}
