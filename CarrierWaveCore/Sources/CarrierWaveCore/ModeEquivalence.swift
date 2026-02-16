//
//  ModeEquivalence.swift
//  CarrierWaveCore
//
//  Mode family classification and equivalence checking for deduplication.
//

import Foundation

// MARK: - ModeFamily

/// Mode family classification for amateur radio modes
public enum ModeFamily: Sendable, Equatable {
    case phone
    case cw
    case digital
    case other
}

// MARK: - ModeEquivalence

/// Utilities for mode classification and equivalence checking
public enum ModeEquivalence: Sendable {
    /// Generic mode names that should be replaced by specific modes when merging
    public static let genericModes: Set<String> = ["PHONE", "DATA"]

    /// Phone mode family - all considered equivalent for deduplication
    public static let phoneModes: Set<String> = ["PHONE", "SSB", "USB", "LSB", "AM", "FM", "DV"]

    /// Digital mode family - all considered equivalent for deduplication
    public static let digitalModes: Set<String> = [
        "DATA", "FT8", "FT4", "PSK31", "PSK", "RTTY", "JT65", "JT9", "MFSK", "OLIVIA",
    ]

    /// CW mode (standalone, not grouped with others)
    public static let cwModes: Set<String> = ["CW"]

    /// Get the mode family for a given mode string
    public static func family(for mode: String) -> ModeFamily {
        let upper = mode.uppercased()
        if phoneModes.contains(upper) {
            return .phone
        }
        if digitalModes.contains(upper) {
            return .digital
        }
        if cwModes.contains(upper) {
            return .cw
        }
        return .other
    }

    /// Check if two modes are equivalent (handles PHONE/SSB/USB/LSB aliases and digital modes)
    public static func areEquivalent(_ mode1: String, _ mode2: String) -> Bool {
        let m1 = mode1.uppercased()
        let m2 = mode2.uppercased()

        // Direct match
        if m1 == m2 {
            return true
        }

        // Check if both are in the same mode family
        if phoneModes.contains(m1), phoneModes.contains(m2) {
            return true
        }
        if digitalModes.contains(m1), digitalModes.contains(m2) {
            return true
        }

        return false
    }

    /// Returns the more specific of two equivalent modes (prefers SSB over PHONE, FT8 over DATA)
    public static func moreSpecific(_ mode1: String, _ mode2: String) -> String {
        let m1 = mode1.uppercased()
        let m2 = mode2.uppercased()

        // If one is generic and the other isn't, prefer the specific one
        let m1IsGeneric = genericModes.contains(m1)
        let m2IsGeneric = genericModes.contains(m2)

        if m1IsGeneric, !m2IsGeneric {
            return mode2
        }
        if m2IsGeneric, !m1IsGeneric {
            return mode1
        }

        // Both specific or both generic - keep the first one
        return mode1
    }

    /// Check if a mode is generic (should be replaced when a more specific mode is available)
    public static func isGeneric(_ mode: String) -> Bool {
        genericModes.contains(mode.uppercased())
    }

    /// Returns a canonical display name for a mode, normalizing generic modes
    /// to their preferred specific form (e.g., PHONE → SSB, DATA → DATA).
    /// Specific modes (USB, LSB, FT8, etc.) are kept as-is.
    public static func canonicalName(_ mode: String) -> String {
        let upper = mode.uppercased()
        if upper == "PHONE" {
            return "SSB"
        }
        return mode
    }

    /// Deduplicates a collection of mode strings by mode family,
    /// preferring specific modes over generic ones.
    /// e.g., ["PHONE", "SSB", "CW"] → ["SSB", "CW"]
    public static func deduplicatedModes(_ modes: [String]) -> [String] {
        var familySeen: [ModeFamily: String] = [:]
        var otherModes: [String] = []

        for mode in modes {
            let fam = family(for: mode)
            if fam == .other {
                if !otherModes.contains(mode.uppercased()) {
                    otherModes.append(mode.uppercased())
                }
            } else if let existing = familySeen[fam] {
                familySeen[fam] = moreSpecific(existing, mode)
            } else {
                familySeen[fam] = canonicalName(mode)
            }
        }

        return familySeen.values.sorted() + otherModes.sorted()
    }
}
