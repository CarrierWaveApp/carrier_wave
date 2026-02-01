//
//  QuickEntryParser.swift
//  CarrierWave
//

import Foundation

// MARK: - QuickEntryResult

/// Result of parsing a quick entry string
struct QuickEntryResult: Equatable {
    let callsign: String
    var rstSent: String?
    var rstReceived: String?
    var state: String?
    var theirPark: String?
    var theirGrid: String?
    var notes: String?
}

// MARK: - QuickEntryParser

/// Parses quick entry strings like "AJ7CM 579 WA US-0189" into structured data
enum QuickEntryParser {
    // MARK: Internal

    // MARK: - Public API

    /// Parse a quick entry string into structured result
    /// Returns nil if input is not valid quick entry (single callsign or command)
    static func parse(_ input: String) -> QuickEntryResult? {
        let tokens = input.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        // Need at least 2 tokens for quick entry
        guard tokens.count >= 2 else {
            return nil
        }

        // First token must be a callsign
        guard isCallsign(tokens[0]) else {
            return nil
        }

        // Don't trigger quick entry if first token looks like a command
        if LoggerCommand.parse(tokens[0]) != nil {
            return nil
        }

        return QuickEntryResult(callsign: tokens[0])
    }

    /// Check if a string looks like a valid amateur radio callsign
    static func isCallsign(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Handle callsigns with modifiers (prefix/suffix)
        let parts = upper.split(separator: "/").map(String.init)
        let primaryPart = parts.count == 1 ? upper : extractPrimaryCallsign(parts)

        return isBasicCallsign(primaryPart)
    }

    // MARK: Private

    // MARK: - Private Helpers

    /// Check if string matches basic callsign pattern (no modifiers)
    /// Pattern: optional digit/letters prefix + digit + 1-4 letter suffix
    private static func isBasicCallsign(_ string: String) -> Bool {
        // Callsign regex: optional prefix (1-3 chars), required digit, 1-4 letter suffix
        // Examples: W1AW, K3LR, VE3ABC, JA1ABC, G4ABC, DL1ABC, 9A1A, 3DA0ABC
        let pattern = #"^[A-Z0-9]{1,3}[0-9][A-Z]{1,4}$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }

        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    /// Extract the primary callsign from parts split by "/"
    private static func extractPrimaryCallsign(_ parts: [String]) -> String {
        let knownSuffixes: Set<String> = ["P", "M", "MM", "AM", "QRP", "R", "A", "B"]

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix or very short, first is primary
            if knownSuffixes.contains(second) || second.count <= 2 {
                return first
            }
            // If first is very short, it's likely a country prefix
            if first.count <= 2 {
                return second
            }
            // Return the longer one
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is primary
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? parts[0]
    }
}
