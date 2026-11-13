import Foundation

/// Process-wide store of session IDs that the user just ended locally on
/// this device. Used by the continuity layer to ignore CloudKit / LAN
/// adopt notifications that arrive seconds after `endSession()` and would
/// otherwise resurrect the just-ended session.
///
/// The window is short (`graceInterval`) — long enough to absorb a
/// CloudKit fetch echo that lands while the user is in Settings, but not
/// so long that a deliberate resume from the sessions list is suppressed.
@MainActor
final class SessionContinuityState {
    // MARK: Internal

    static let shared = SessionContinuityState()

    /// How long after `endSession()` we ignore adopt notifications for
    /// that session ID. 60 seconds covers a typical CloudKit echo and
    /// LAN snapshot replay.
    static let graceInterval: TimeInterval = 60

    /// Mark a session as just-ended on this device.
    func markEnded(_ id: UUID) {
        sweep()
        endedAt[id] = Date()
    }

    /// Should we suppress adopt notifications for this session ID right now?
    func recentlyEnded(_ id: UUID) -> Bool {
        sweep()
        guard let when = endedAt[id] else {
            return false
        }
        return Date().timeIntervalSince(when) < Self.graceInterval
    }

    // MARK: Private

    private var endedAt: [UUID: Date] = [:]

    /// Drop entries past the grace window so the dictionary doesn't grow.
    private func sweep() {
        let cutoff = Date().addingTimeInterval(-Self.graceInterval)
        endedAt = endedAt.filter { $0.value > cutoff }
    }
}
