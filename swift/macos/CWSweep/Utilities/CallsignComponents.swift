import CarrierWaveCore
import Foundation

// MARK: - CallsignModifier

/// A prefix or suffix modifier on a callsign (e.g., VP5/ or /P).
struct CallsignModifier: Equatable {
    let raw: String
    let meaning: String
}

// MARK: - CallsignComponents

/// Parsed callsign broken into base call, optional prefix modifier, and optional suffix modifier.
/// The base call is what should be looked up in QRZ/HamDB/SCP.
struct CallsignComponents: Equatable {
    let fullCallsign: String
    let baseCallsign: String
    let prefix: CallsignModifier?
    let suffix: CallsignModifier?

    /// True when the callsign has a modifier that changes identity or location.
    var hasModifiers: Bool {
        prefix != nil || suffix != nil
    }
}

// MARK: - CallsignComponentsParser

enum CallsignComponentsParser {
    // MARK: Internal

    /// Parse a callsign into its components with human-readable modifier meanings.
    /// Uses the DXCC lookup service to resolve prefix modifiers to entity names.
    @MainActor
    static func parse(
        _ callsign: String,
        dxccLookup: DXCCLookupService? = nil
    ) -> CallsignComponents {
        let upper = callsign.uppercased()
            .trimmingCharacters(in: .whitespaces)

        let parts = upper.components(separatedBy: "/")

        guard parts.count >= 2 else {
            return CallsignComponents(
                fullCallsign: upper,
                baseCallsign: upper,
                prefix: nil,
                suffix: nil
            )
        }

        if parts.count == 2 {
            return parseTwoPart(
                parts[0], parts[1],
                full: upper,
                dxccLookup: dxccLookup
            )
        }

        // Three-part: PREFIX/BASE/SUFFIX (e.g., VP5/W6JY/P)
        if parts.count == 3 {
            let prefixMod = resolvePrefix(
                parts[0], dxccLookup: dxccLookup
            )
            let suffixMod = resolveSuffix(parts[2])
            return CallsignComponents(
                fullCallsign: upper,
                baseCallsign: parts[1],
                prefix: prefixMod,
                suffix: suffixMod
            )
        }

        // Unusual — just use longest part as base
        let base = parts.max(by: { $0.count < $1.count }) ?? upper
        return CallsignComponents(
            fullCallsign: upper,
            baseCallsign: base,
            prefix: nil,
            suffix: nil
        )
    }

    // MARK: Private

    /// Known operating suffixes and their meanings.
    private static let knownSuffixes: [String: String] = [
        "P": "Portable",
        "M": "Mobile",
        "MM": "Maritime Mobile",
        "AM": "Aeronautical Mobile",
        "QRP": "QRP (Low Power)",
        "A": "Alternative address",
        "B": "Beacon",
        "R": "Repeater",
        "LH": "Lighthouse",
    ]

    /// Numeric suffixes indicate call area (e.g., W6JY/4 = operating in 4th call area).
    private static func isNumericSuffix(_ str: String) -> Bool {
        str.count <= 2 && str.allSatisfy(\.isNumber)
    }

    /// A full callsign has letters after the digit (e.g., W6JY, KL7ABC).
    /// A bare prefix like KL7, VP5 has no trailing letters after the last digit.
    private static func isLikelyFullCallsign(_ str: String) -> Bool {
        guard let lastDigitIndex = str.lastIndex(where: \.isNumber) else {
            return false
        }
        let afterDigit = str[str.index(after: lastDigitIndex)...]
        return afterDigit.count >= 2
    }

    @MainActor
    private static func parseTwoPart(
        _ left: String,
        _ right: String,
        full: String,
        dxccLookup: DXCCLookupService?
    ) -> CallsignComponents {
        // Check if right side is a known suffix
        if let meaning = knownSuffixes[right] {
            return CallsignComponents(
                fullCallsign: full,
                baseCallsign: left,
                prefix: nil,
                suffix: CallsignModifier(raw: right, meaning: meaning)
            )
        }

        // Numeric suffix = call area
        if isNumericSuffix(right) {
            return CallsignComponents(
                fullCallsign: full,
                baseCallsign: left,
                prefix: nil,
                suffix: CallsignModifier(
                    raw: right,
                    meaning: "Operating in call area \(right)"
                )
            )
        }

        // Use DXCC resolution to determine base vs location modifier
        return resolveBaseAndModifier(
            left: left, right: right,
            full: full, dxccLookup: dxccLookup
        )
    }

    /// Determine which part is the base callsign vs location modifier.
    /// Convention: CALL/PREFIX (W2A/KL7) or PREFIX/CALL (VP5/W6JY).
    @MainActor
    private static func resolveBaseAndModifier(
        left: String,
        right: String,
        full: String,
        dxccLookup: DXCCLookupService?
    ) -> CallsignComponents {
        // If right resolves to a DXCC prefix, left is base (e.g., W2A/KL7)
        if dxccLookup?.lookup(right) != nil, !isLikelyFullCallsign(right) {
            return CallsignComponents(
                fullCallsign: full,
                baseCallsign: left,
                prefix: nil,
                suffix: resolvePrefix(right, dxccLookup: dxccLookup)
            )
        }

        // If left resolves and looks like a short prefix, right is base (e.g., VP5/W6JY)
        if dxccLookup?.lookup(left) != nil, !isLikelyFullCallsign(left) {
            return CallsignComponents(
                fullCallsign: full,
                baseCallsign: right,
                prefix: resolvePrefix(left, dxccLookup: dxccLookup),
                suffix: nil
            )
        }

        // Fallback: longer part is the base callsign
        if left.count <= right.count {
            return CallsignComponents(
                fullCallsign: full,
                baseCallsign: right,
                prefix: resolvePrefix(left, dxccLookup: dxccLookup),
                suffix: nil
            )
        } else {
            return CallsignComponents(
                fullCallsign: full,
                baseCallsign: left,
                prefix: nil,
                suffix: resolvePrefix(right, dxccLookup: dxccLookup)
            )
        }
    }

    @MainActor
    private static func resolvePrefix(
        _ prefix: String,
        dxccLookup: DXCCLookupService?
    ) -> CallsignModifier? {
        guard !prefix.isEmpty else {
            return nil
        }

        // Try DXCC entity resolution
        if let entity = dxccLookup?.lookup(prefix) {
            return CallsignModifier(
                raw: prefix,
                meaning: "Operating from \(entity.name)"
            )
        }

        return CallsignModifier(
            raw: prefix,
            meaning: "Prefix: \(prefix)"
        )
    }

    private static func resolveSuffix(
        _ suffix: String
    ) -> CallsignModifier? {
        guard !suffix.isEmpty else {
            return nil
        }

        if let meaning = knownSuffixes[suffix] {
            return CallsignModifier(raw: suffix, meaning: meaning)
        }

        if isNumericSuffix(suffix) {
            return CallsignModifier(
                raw: suffix,
                meaning: "Operating in call area \(suffix)"
            )
        }

        return CallsignModifier(raw: suffix, meaning: "Suffix: \(suffix)")
    }
}
