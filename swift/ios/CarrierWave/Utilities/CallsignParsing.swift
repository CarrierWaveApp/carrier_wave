import UIKit

// MARK: - CallsignParsing

/// Shared callsign string parsing (promoted from LoggerView so the Band
/// Scope peek sheet and any other lookup surface resolve prefixed/suffixed
/// calls exactly like the session logger).
enum CallsignParsing {
    /// Extract the primary callsign from a potentially prefixed/suffixed
    /// callsign, e.g. "I/W6JY/P" → "W6JY", "VE3/W6JY" → "W6JY",
    /// "W6JY/M" → "W6JY".
    static func primaryCallsign(from callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        // Common suffixes that indicate the primary is before them
        let knownSuffixes = Set(["P", "M", "MM", "AM", "QRP", "R", "A", "B"])

        // For 2 parts: check if second part is a known suffix or very short
        // (1-2 chars). If so, first part is primary. Otherwise, longer part
        // is likely primary.
        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix, first is primary
            if knownSuffixes.contains(second.uppercased()) {
                return first
            }

            // If second is very short (1-2 chars), it's likely a suffix
            if second.count <= 2 {
                return first
            }

            // If first is very short (1-2 chars), it's likely a country prefix
            if first.count <= 2 {
                return second
            }

            // Otherwise, return the longer one (more likely the full callsign)
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is primary
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }
}
