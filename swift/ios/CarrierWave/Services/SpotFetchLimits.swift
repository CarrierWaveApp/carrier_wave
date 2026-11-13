// Spot Fetch Limits
//
// Centralizes the user-configurable per-source spot fetch caps surfaced
// in Hunt and On Air settings. Each accessor reads the user's preference
// from `UserDefaults` and clamps to the allowed option range so that a
// stale or corrupted value can never exceed the upstream service maximum.

import UIKit

enum SpotFetchLimits {
    // MARK: Internal

    /// Allowed options for the hunter-mode RBN fetch cap.
    /// Bounded by the activities server (max 500).
    static let huntRBNOptions = [100, 250, 500]

    /// Allowed options for the hunter-mode SOTA fetch cap.
    /// Bounded by the SOTAwatch API (max 200).
    static let huntSOTAOptions = [50, 100, 200]

    /// Allowed options for the On Air SOTA fetch cap.
    /// Same upstream ceiling as the hunter SOTA fetch.
    static let onAirSOTAOptions = [50, 100, 200]

    static let huntRBNDefault = 500
    static let huntSOTADefault = 200
    static let onAirSOTADefault = 200

    static let huntRBNKey = "huntRBNFetchLimit"
    static let huntSOTAKey = "huntSOTAFetchLimit"
    static let onAirSOTAKey = "onAirSOTAFetchLimit"

    static var huntRBN: Int {
        resolve(key: huntRBNKey, options: huntRBNOptions, defaultValue: huntRBNDefault)
    }

    static var huntSOTA: Int {
        resolve(key: huntSOTAKey, options: huntSOTAOptions, defaultValue: huntSOTADefault)
    }

    static var onAirSOTA: Int {
        resolve(key: onAirSOTAKey, options: onAirSOTAOptions, defaultValue: onAirSOTADefault)
    }

    // MARK: Private

    private static func resolve(key: String, options: [Int], defaultValue: Int) -> Int {
        let stored = UserDefaults.standard.integer(forKey: key)
        guard stored > 0 else {
            return defaultValue
        }
        // Clamp to the largest allowed option so a hand-edited preference
        // can't exceed the upstream service ceiling.
        if let maxOption = options.max(), stored > maxOption {
            return maxOption
        }
        return stored
    }
}
