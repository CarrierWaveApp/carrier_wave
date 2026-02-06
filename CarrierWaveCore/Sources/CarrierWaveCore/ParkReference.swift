//
//  ParkReference.swift
//  CarrierWaveCore
//
//  Park reference parsing and validation for POTA/WWFF activations.
//

import Foundation

/// Utilities for park reference handling
public enum ParkReference: Sendable {
    /// Split a comma-separated park reference string into individual parks
    /// e.g., "US-1044, US-3791" -> ["US-1044", "US-3791"]
    public static func split(_ parkRef: String) -> [String] {
        parkRef.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
    }

    /// Check if park reference contains multiple parks (two-fer, three-fer, etc.)
    public static func isMultiPark(_ parkRef: String) -> Bool {
        parkRef.contains(",")
    }

    /// Check if a string is a valid POTA/WWFF park reference
    /// Pattern: 1-2 letter country code, dash, 4-5 digits (e.g., "K-1234", "US-0189")
    public static func isValid(_ parkRef: String) -> Bool {
        let upper = parkRef.trimmingCharacters(in: .whitespaces).uppercased()

        // Pattern: XX-#### or XX-#####
        let pattern = #"^[A-Z]{1,2}-[0-9]{4,5}$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }

        let range = NSRange(upper.startIndex..., in: upper)
        return regex.firstMatch(in: upper, options: [], range: range) != nil
    }

    /// Normalize a park reference (uppercase, trimmed)
    public static func normalize(_ parkRef: String) -> String {
        parkRef.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Sanitize a park reference by fixing common malformations from upstream APIs.
    /// - "US1849" -> "US-1849" (missing dash)
    /// - "3687" -> nil (bare number with no country prefix — ambiguous)
    /// Returns nil if the input can't be salvaged into a valid ref.
    public static func sanitize(_ parkRef: String) -> String? {
        let trimmed = parkRef.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return nil
        }

        // Already valid
        if isValid(trimmed) {
            return trimmed
        }

        // Missing dash: "US1849" -> "US-1849"
        let missingDash = #"^([A-Z]{1,2})(\d{4,5})$"#
        if let regex = try? NSRegularExpression(pattern: missingDash),
           let match = regex.firstMatch(
               in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)
           )
        {
            let prefix = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]) }
            let digits = Range(match.range(at: 2), in: trimmed).map { String(trimmed[$0]) }
            if let prefix, let digits {
                let fixed = "\(prefix)-\(digits)"
                return isValid(fixed) ? fixed : nil
            }
        }

        // Bare number "3687" — can't determine country prefix, return nil
        return nil
    }

    /// Sanitize a potentially multi-park reference, fixing each individual park.
    /// Drops parks that can't be sanitized.
    public static func sanitizeMulti(_ parkRef: String) -> String? {
        let sanitized = split(parkRef).compactMap { sanitize($0) }
        return sanitized.isEmpty ? nil : sanitized.joined(separator: ", ")
    }

    /// Normalize a potentially multi-park reference (sorts parks for consistent comparison)
    public static func normalizeMulti(_ parkRef: String) -> String {
        split(parkRef).sorted().joined(separator: ", ")
    }

    /// Check if one park reference is a subset of another
    /// e.g., "US-1044" is a subset of "US-1044, US-3791"
    public static func isSubset(_ subset: String, of superset: String) -> Bool {
        let subsetParks = Set(split(subset))
        let supersetParks = Set(split(superset))
        return subsetParks.isSubset(of: supersetParks)
    }

    /// Check if two park references have any parks in common
    public static func hasOverlap(_ parkRef1: String, _ parkRef2: String) -> Bool {
        let parks1 = Set(split(parkRef1))
        let parks2 = Set(split(parkRef2))
        return !parks1.isDisjoint(with: parks2)
    }
}
