//
//  ModeEquivalence.swift
//  CarrierWaveCore
//
//  Mode family classification and equivalence checking for deduplication.
//  Delegates to `cw-domain::mode::ModeEquivalence` via the UniFFI surface.
//

import CarrierWaveCwFfi
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
    // MARK: Public

    /// Generic mode names that should be replaced by specific modes when merging
    public static let genericModes: Set<String> = Set(modeGenericModes())

    /// Phone mode family - all considered equivalent for deduplication
    public static let phoneModes: Set<String> = Set(modePhoneModes())

    /// Digital mode family - all considered equivalent for deduplication
    public static let digitalModes: Set<String> = Set(modeDigitalModes())

    /// CW mode (standalone, not grouped with others)
    public static let cwModes: Set<String> = Set(modeCwModes())

    /// Get the mode family for a given mode string
    public static func family(for mode: String) -> ModeFamily {
        liftModeFamily(modeFamily(mode: mode))
    }

    /// Check if two modes are equivalent (handles PHONE/SSB/USB/LSB aliases and digital modes)
    public static func areEquivalent(_ mode1: String, _ mode2: String) -> Bool {
        modesAreEquivalent(mode1: mode1, mode2: mode2)
    }

    /// Returns the more specific of two equivalent modes (prefers SSB over PHONE, FT8 over DATA)
    public static func moreSpecific(_ mode1: String, _ mode2: String) -> String {
        modeMoreSpecific(mode1: mode1, mode2: mode2)
    }

    /// Check if a mode is generic (should be replaced when a more specific mode is available)
    public static func isGeneric(_ mode: String) -> Bool {
        modeIsGeneric(mode: mode)
    }

    /// Returns a canonical display name for a mode, normalizing generic modes
    /// to their preferred specific form (e.g., PHONE → SSB, DATA → DATA).
    /// Specific modes (USB, LSB, FT8, etc.) are kept as-is.
    public static func canonicalName(_ mode: String) -> String {
        modeCanonicalName(mode: mode)
    }

    /// Returns a canonical name for deduplication key construction.
    /// All phone-family modes (PHONE, USB, LSB, AM, FM, DV) normalize to "SSB"
    /// so that dedup keys match across services (POTA returns "SSB" for all phone contacts).
    public static func canonicalNameForDedup(_ mode: String) -> String {
        modeCanonicalNameForDedup(mode: mode)
    }

    /// ADIF parent mode and optional submode for a given mode string.
    /// USB/LSB → (SSB, USB/LSB), PSK31 → (PSK, PSK31), FT8 → (FT8, nil), etc.
    public static func adifModeSubmode(_ mode: String) -> (mode: String, submode: String?) {
        let result = modeAdifModeSubmode(mode: mode)
        return (result.mode, result.submode)
    }

    /// Normalizes a mode string for strict ADIF-compliant services (e.g., POTA).
    /// Maps generic modes that aren't in the ADIF spec to valid parent modes:
    /// PHONE → SSB, DATA → RTTY. Then applies the standard mode/submode split.
    /// Services like QRZ tolerate generic names; POTA does not.
    public static func normalizeForStrictADIF(
        _ mode: String
    ) -> (mode: String, submode: String?) {
        let result = modeNormalizeForStrictAdif(mode: mode)
        return (result.mode, result.submode)
    }

    /// Deduplicates a collection of mode strings by mode family,
    /// preferring specific modes over generic ones.
    /// e.g., ["PHONE", "SSB", "CW"] → ["SSB", "CW"]
    public static func deduplicatedModes(_ modes: [String]) -> [String] {
        modesDeduplicated(modes: modes)
    }

    // MARK: Private

    private static func liftModeFamily(_ ffi: FfiModeFamily) -> ModeFamily {
        switch ffi {
        case .phone: .phone
        case .cw: .cw
        case .digital: .digital
        case .other: .other
        }
    }
}
