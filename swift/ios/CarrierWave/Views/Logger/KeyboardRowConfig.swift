// Keyboard Row Configuration
//
// Shared model for the logger's keyboard accessory rows: which rows
// exist, their user-configurable stacking order, and prefix-key helpers.

import Foundation

// MARK: - KeyboardRowKind

/// One row in the logger keyboard accessory stack.
enum KeyboardRowKind: String, CaseIterable, Identifiable {
    case numbers
    case prefixes
    case keyer
    case commands

    // MARK: Internal

    static let defaultOrder: [KeyboardRowKind] = [.numbers, .prefixes, .keyer, .commands]
    static let defaultOrderRaw = defaultOrder.map(\.rawValue).joined(separator: ",")

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .numbers: "Numbers & Symbols"
        case .prefixes: "Prefixes"
        case .keyer: "CW Keyer"
        case .commands: "Commands"
        }
    }

    /// Parses a stored order string, tolerating missing or unknown entries.
    /// Any known kind absent from the stored value is appended in default order.
    static func order(from raw: String) -> [KeyboardRowKind] {
        var parsed = raw.components(separatedBy: ",")
            .compactMap(KeyboardRowKind.init(rawValue:))
        for kind in defaultOrder where !parsed.contains(kind) {
            parsed.append(kind)
        }
        return parsed
    }
}

// MARK: - CallsignPrefixer

/// Applies a prefix hot key to the callsign entry field.
enum CallsignPrefixer {
    /// Smart replace: if the current text starts with any known prefix,
    /// swap it (keeping the suffix); otherwise prepend.
    static func apply(
        _ prefix: String,
        to text: String,
        knownPrefixes: [String]
    ) -> String {
        let upper = text.uppercased()
        let sorted = knownPrefixes.sorted { $0.count > $1.count }
        for known in sorted where upper.hasPrefix(known) && known != prefix {
            return prefix + upper.dropFirst(known.count)
        }
        if upper.hasPrefix(prefix) {
            return upper
        }
        return prefix + upper
    }

    /// Extracts the hot-key prefix from a callsign: everything through the
    /// first digit (e.g. "KN6ABC" -> "KN6", "VK3XYZ" -> "VK3").
    static func prefix(ofCallsign callsign: String) -> String? {
        let upper = callsign.uppercased()
        guard let digitIndex = upper.firstIndex(where: \.isNumber) else {
            return nil
        }
        let end = upper.index(after: digitIndex)
        let candidate = String(upper[..<end])
        guard candidate.count >= 2, candidate.count <= 4 else {
            return nil
        }
        return candidate
    }
}
