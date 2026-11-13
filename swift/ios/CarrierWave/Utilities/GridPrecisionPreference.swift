import CarrierWaveCore
import UIKit

/// Reads the user's preferred Maidenhead grid precision (4 / 6 / 8 chars).
/// Stored in `UserDefaults` so reads are thread-safe from any context — used
/// by GPS-driven grid emitters that run on `CLLocationManagerDelegate`
/// callbacks before hopping to the main actor.
///
/// Settings UI binds to `UserDefaults.standard` via `@AppStorage(key)` directly;
/// this helper just centralizes the key + decoding.
nonisolated enum GridPrecisionPreference {
    /// `@AppStorage` key. Stored as the raw `Int` (4 / 6 / 8).
    static let key = "gridSquarePrecision"

    /// Default precision when nothing has been written yet. 6-char is the
    /// long-standing HF logging default.
    static let `default`: CarrierWaveCore.MaidenheadConverter.Precision = .six

    /// Current precision honoured by GPS-driven grid emitters. Safe to call
    /// from any context — `UserDefaults` is thread-safe.
    static var current: CarrierWaveCore.MaidenheadConverter.Precision {
        let raw = UserDefaults.standard.integer(forKey: key)
        return CarrierWaveCore.MaidenheadConverter.Precision(rawValue: raw) ?? `default`
    }
}
