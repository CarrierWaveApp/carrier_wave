import UIKit

// MARK: - SpotCooldownTracker

/// Per-callsign cooldown for hunter-initiated spot reposts.
///
/// The hunter log lets users spot an activator from the long-press menu without
/// logging a QSO. To avoid spamming POTA when several users hammer the same row,
/// we throttle reposts of the same callsign. The cooldown can be bypassed from
/// the UI after a warning prompt.
@MainActor
@Observable
final class SpotCooldownTracker {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = SpotCooldownTracker()

    /// Minimum gap between reposts of the same callsign.
    let cooldown: TimeInterval = 300

    /// Seconds elapsed since the last spot of `callsign`, or `nil` if never spotted.
    func elapsedSinceLastSpot(for callsign: String) -> TimeInterval? {
        guard let last = lastSpotByCallsign[callsign.uppercased()] else {
            return nil
        }
        return Date().timeIntervalSince(last)
    }

    /// Remaining cooldown for `callsign` in seconds, or `nil` if it's free to spot.
    func cooldownRemaining(for callsign: String) -> TimeInterval? {
        guard let elapsed = elapsedSinceLastSpot(for: callsign) else {
            return nil
        }
        let remaining = cooldown - elapsed
        return remaining > 0 ? remaining : nil
    }

    /// Record that `callsign` was just spotted, starting its cooldown window.
    func recordSpot(_ callsign: String) {
        lastSpotByCallsign[callsign.uppercased()] = Date()
    }

    // MARK: Private

    private var lastSpotByCallsign: [String: Date] = [:]
}
