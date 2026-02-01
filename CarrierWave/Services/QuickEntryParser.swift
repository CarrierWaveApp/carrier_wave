//
//  QuickEntryParser.swift
//  CarrierWave
//

import Foundation

// MARK: - TokenType

/// Token types for quick entry color coding
enum TokenType: Equatable {
    case callsign
    case rstSent
    case rstReceived
    case state
    case park
    case grid
    case notes
}

// MARK: - ParsedToken

/// A parsed token with its text and type for UI preview
struct ParsedToken: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let type: TokenType

    static func == (lhs: ParsedToken, rhs: ParsedToken) -> Bool {
        lhs.text == rhs.text && lhs.type == rhs.type
    }
}

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
            } else if isGridSquare(token) {
                result.theirGrid = token.uppercased()
            } else if isStateOrRegion(token) {
                result.state = token
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

    /// Parse a quick entry string into tokens with types for UI preview (color-coding)
    /// Returns empty array if input is not valid quick entry (single callsign or command)
    static func parseTokens(_ input: String) -> [ParsedToken] {
        let tokens = input.uppercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)

        // Need at least 2 tokens for quick entry
        guard tokens.count >= 2 else {
            return []
        }

        // First token must be a callsign
        guard isCallsign(tokens[0]) else {
            return []
        }

        // Don't trigger quick entry if first token looks like a command
        if LoggerCommand.parse(tokens[0]) != nil {
            return []
        }

        var result: [ParsedToken] = []
        var rstTokens: [(text: String, index: Int)] = []

        // Add callsign token
        result.append(ParsedToken(text: tokens[0], type: .callsign))

        // First pass: identify all tokens and track RST positions
        for (index, token) in tokens.dropFirst().enumerated() {
            if isRST(token) {
                // Track RST tokens for second pass
                rstTokens.append((text: token, index: index + 1))
            } else if isParkReference(token) {
                result.append(ParsedToken(text: token, type: .park))
            } else if isGridSquare(token) {
                result.append(ParsedToken(text: token.uppercased(), type: .grid))
            } else if isStateOrRegion(token) {
                result.append(ParsedToken(text: token, type: .state))
            } else {
                result.append(ParsedToken(text: token, type: .notes))
            }
        }

        // Second pass: assign RST types based on count
        // If one RST: it's received. If two RSTs: first is sent, second is received
        if rstTokens.count == 1 {
            result.insert(ParsedToken(text: rstTokens[0].text, type: .rstReceived), at: 1)
        } else if rstTokens.count >= 2 {
            // First two RSTs: sent then received. Additional RSTs become notes.
            result.insert(ParsedToken(text: rstTokens[0].text, type: .rstSent), at: 1)
            result.insert(ParsedToken(text: rstTokens[1].text, type: .rstReceived), at: 2)
            // Any additional RSTs become notes
            for rst in rstTokens.dropFirst(2) {
                result.append(ParsedToken(text: rst.text, type: .notes))
            }
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

    /// Check if a string is a valid Maidenhead grid square
    /// 4-char: [A-R][A-R][0-9][0-9], 6-char: adds [a-x][a-x]
    static func isGridSquare(_ string: String) -> Bool {
        let upper = string.uppercased()

        // Must be 4 or 6 characters
        guard upper.count == 4 || upper.count == 6 else {
            return false
        }

        let chars = Array(upper)

        // First two: A-R (field)
        guard chars[0] >= "A", chars[0] <= "R",
              chars[1] >= "A", chars[1] <= "R"
        else {
            return false
        }

        // Next two: 0-9 (square)
        guard chars[2].isNumber, chars[3].isNumber else {
            return false
        }

        // If 6 chars, last two: A-X (subsquare)
        if upper.count == 6 {
            guard chars[4] >= "A", chars[4] <= "X",
                  chars[5] >= "A", chars[5] <= "X"
            else {
                return false
            }
        }

        return true
    }

    /// Check if a string is a valid US state, Canadian province, or DX region code
    static func isStateOrRegion(_ string: String) -> Bool {
        let upper = string.uppercased()
        return knownRegions.contains(upper)
    }

    // MARK: Private

    /// Known state/province/region codes
    private static let knownRegions: Set<String> = {
        // US States + DC
        let usStates: Set<String> = [
            "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
            "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
            "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
            "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
            "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
            "DC",
        ]

        // Canadian Provinces/Territories
        let canada: Set<String> = [
            "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT",
        ]

        // Common DX Region codes (country prefixes used as region identifiers)
        let dxRegions: Set<String> = [
            "DL", "EA", "EI", "CT", "HA", "HB", "LU", "LZ", "OE", "OH",
            "OK", "OM", "OZ", "PA", "SM", "SP", "UA", "UR", "VK", "ZL",
            "ZS", "JA", "HL", "BV", "BY", "YB", "HS", "VU", "UK",
        ]

        return usStates.union(canada).union(dxRegions)
    }()

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
