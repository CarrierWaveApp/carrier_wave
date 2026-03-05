import Foundation

// MARK: - CallsignFlagHelper

/// Shared country flag lookup from callsign prefix
enum CallsignFlagHelper {
    // MARK: Internal

    static func countryFlag(for callsign: String) -> String? {
        let cs = callsign.uppercased()
        for (prefix, flag) in prefixFlags where cs.hasPrefix(prefix) {
            return flag
        }
        return nil
    }

    // MARK: Private

    /// Ordered longest prefix first so 2-char prefixes match before 1-char
    private static let prefixFlags: [(prefix: String, flag: String)] = [
        ("VE", "🇨🇦"), ("VA", "🇨🇦"),
        ("DL", "🇩🇪"), ("DA", "🇩🇪"), ("DB", "🇩🇪"), ("DC", "🇩🇪"),
        ("JA", "🇯🇵"), ("JH", "🇯🇵"), ("JR", "🇯🇵"),
        ("VK", "🇦🇺"), ("ZL", "🇳🇿"), ("EA", "🇪🇸"),
        ("PA", "🇳🇱"), ("PD", "🇳🇱"), ("PE", "🇳🇱"),
        ("ON", "🇧🇪"), ("OZ", "🇩🇰"),
        ("SM", "🇸🇪"), ("SA", "🇸🇪"),
        ("LA", "🇳🇴"), ("OH", "🇫🇮"),
        ("W", "🇺🇸"), ("K", "🇺🇸"), ("N", "🇺🇸"), ("A", "🇺🇸"),
        ("G", "🇬🇧"), ("M", "🇬🇧"),
        ("F", "🇫🇷"), ("I", "🇮🇹"),
    ]
}
