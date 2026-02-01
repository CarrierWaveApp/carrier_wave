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

        var result = QuickEntryResult(callsign: tokens[0])
        var unrecognized: [String] = []

        // Process remaining tokens
        for token in tokens.dropFirst() {
            if isRST(token) {
                if result.rstReceived == nil {
                    result.rstReceived = token
                } else if result.rstSent == nil {
                    // Shift: first RST was actually sent, this one is received
                    result.rstSent = result.rstReceived
                    result.rstReceived = token
                } else {
                    // Already have both RSTs, treat as notes
                    unrecognized.append(token)
                }
            } else if isParkReference(token) {
                result.theirPark = token
            } else {
                unrecognized.append(token)
            }
        }

        // Unrecognized tokens become notes
        if !unrecognized.isEmpty {
            result.notes = unrecognized.joined(separator: " ")
        }

        return result
    }

    /// Check if a string is a valid RST report
    /// Phone: [1-5][1-9], CW/Digital: [1-5][1-9][1-9]
    static func isRST(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Must be 2 or 3 digits
        guard upper.count == 2 || upper.count == 3,
              upper.allSatisfy(\.isNumber)
        else {
            return false
        }

        let digits = upper.map { Int(String($0))! }

        // R (readability): 1-5
        guard digits[0] >= 1, digits[0] <= 5 else {
            return false
        }

        // S (strength): 1-9
        guard digits[1] >= 1, digits[1] <= 9 else {
            return false
        }

        // T (tone) for CW: 1-9 (if present)
        if digits.count == 3 {
            guard digits[2] >= 1, digits[2] <= 9 else {
                return false
            }
        }

        return true
    }

    /// Check if a string looks like a valid amateur radio callsign
    static func isCallsign(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Handle callsigns with modifiers (prefix/suffix)
        let parts = upper.split(separator: "/").map(String.init)
        let primaryPart = parts.count == 1 ? upper : extractPrimaryCallsign(parts)

        return isBasicCallsign(primaryPart)
    }

    /// Check if a string is a valid POTA/WWFF park reference
    /// Pattern: 1-2 letter country code, dash, 4-5 digits
    static func isParkReference(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Pattern: XX-#### or XX-#####
        let pattern = #"^[A-Z]{1,2}-[0-9]{4,5}$"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }

        let range = NSRange(upper.startIndex..., in: upper)
        return regex.firstMatch(in: upper, options: [], range: range) != nil
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
