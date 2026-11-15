import UIKit

// MARK: - POTAAutoUploadPolicy

/// Rules that keep automatic POTA uploads from generating work for POTA's
/// volunteers (see docs/investigations/2026-04-22-pota-upload-volunteer-load.md).
/// Sync only uploads an activation once it has settled, and paces its attempts.
/// The "Upload to POTA" buttons are not subject to any of this.
enum POTAAutoUploadPolicy {
    /// Why sync left an activation for later, or for a manual upload.
    enum Hold: Equatable {
        /// The logging session it belongs to is still open.
        case sessionActive
        /// A QSO was logged too recently; the activation may still be going.
        case stillSettling
        /// Too old to upload unprompted; use the upload button.
        case tooOld
    }

    /// Time since the last QSO before an activation counts as finished, so one
    /// activation becomes one upload job instead of one per sync tick.
    static let quietPeriod: TimeInterval = 30 * 60

    /// Activations older than this are left for a manual upload, so re-enabling
    /// automatic uploads never backfills an old log without being asked.
    static let maxActivationAge: TimeInterval = 14 * 24 * 60 * 60

    /// Minimum spacing between automatic upload passes.
    static let minInterval: TimeInterval = 10 * 60

    /// Longest wait between passes after repeated failures.
    static let maxBackoff: TimeInterval = 6 * 60 * 60

    /// Decide whether one activation (a park on one UTC day) may upload now.
    /// Returns nil when it may.
    static func hold(
        newestQSO: Date, inActiveSession: Bool, now: Date = Date()
    ) -> Hold? {
        if inActiveSession {
            return .sessionActive
        }
        let age = now.timeIntervalSince(newestQSO)
        if age < quietPeriod {
            return .stillSettling
        }
        if age > maxActivationAge {
            return .tooOld
        }
        return nil
    }

    /// How long to wait after an attempt before the next one: `minInterval`,
    /// doubled for every consecutive failed pass, capped at `maxBackoff`.
    static func waitAfterAttempt(consecutiveFailures: Int) -> TimeInterval {
        let doublings = min(max(consecutiveFailures, 0), 10)
        return min(minInterval * pow(2, Double(doublings)), maxBackoff)
    }

    /// Seconds until the next automatic pass is allowed (0 when allowed now).
    static func secondsUntilNextAttempt(
        lastAttempt: Date?, consecutiveFailures: Int, now: Date = Date()
    ) -> TimeInterval {
        guard let lastAttempt else {
            return 0
        }
        let elapsed = now.timeIntervalSince(lastAttempt)
        // A clock that moved backwards must not block uploads indefinitely.
        guard elapsed >= 0 else {
            return 0
        }
        return max(0, waitAfterAttempt(consecutiveFailures: consecutiveFailures) - elapsed)
    }
}

// MARK: - POTAAutoUploadThrottle

/// Persisted pacing state for automatic POTA uploads.
struct POTAAutoUploadThrottle {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Internal

    static let lastAttemptKey = "potaAutoUpload.lastAttempt"
    static let failuresKey = "potaAutoUpload.consecutiveFailures"

    var lastAttempt: Date? {
        defaults.object(forKey: Self.lastAttemptKey) as? Date
    }

    var consecutiveFailures: Int {
        defaults.integer(forKey: Self.failuresKey)
    }

    func secondsUntilNextAttempt(now: Date = Date()) -> TimeInterval {
        POTAAutoUploadPolicy.secondsUntilNextAttempt(
            lastAttempt: lastAttempt, consecutiveFailures: consecutiveFailures, now: now
        )
    }

    /// Record a finished pass. A pass with any failed activation backs off.
    func recordAttempt(failed: Bool, now: Date = Date()) {
        defaults.set(now, forKey: Self.lastAttemptKey)
        defaults.set(failed ? consecutiveFailures + 1 : 0, forKey: Self.failuresKey)
    }

    // MARK: Private

    private let defaults: UserDefaults
}
