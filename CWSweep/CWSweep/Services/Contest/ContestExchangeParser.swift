import CarrierWaveData
import Foundation

// MARK: - ContestParseResult

struct ContestParseResult: Sendable {
    var fields: [String: String] = [:]
    var serialReceived: Int?
    var unmatchedTokens: [String] = []
}

// MARK: - ContestExchangeParser

/// Contest-mode overlay that classifies remaining tokens after QuickEntryParser.
/// Matches unrecognized tokens against the contest definition's exchange fields.
enum ContestExchangeParser {
    // MARK: Internal

    static let arrlSections: Set<String> = [
        // Atlantic
        "CT", "EMA", "ME", "NH", "RI", "VT", "WMA", "ENY", "NLI", "NNJ", "NNY", "SNJ", "WNY",
        // Central
        "IL", "IN", "WI",
        // Dakota
        "MN", "ND", "SD",
        // Delta
        "AR", "LA", "MS", "TN",
        // Great Lakes
        "MI", "OH", "WV",
        // Hudson
        "EPA", "MDC", "WPA",
        // Midwest
        "IA", "KS", "MO", "NE",
        // New England
        // Northwestern
        "AK", "EWA", "ID", "MT", "OR", "WWA", "WY",
        // Pacific
        "EB", "LAX", "ORG", "PAC", "SB", "SCV", "SDG", "SF", "SJV", "SV",
        // Roanoke
        "NC", "SC", "VA",
        // Rocky Mountain
        "CO", "NM", "UT",
        // Southeastern
        "AL", "GA", "KY", "NFL", "PR", "SFL", "TN", "VI", "WCF",
        // Southwestern
        "AZ", "EWA", "NV", "SV",
        // West Gulf
        "NTX", "OK", "STX", "WTX",
        // Canada
        "AB", "BC", "GH", "MAR", "MB", "NL", "NT", "ONE", "ONN", "ONS", "PE", "QC", "SK", "TER",
    ]

    static func parse(tokens: [String], definition: ContestDefinition) -> ContestParseResult {
        var result = ContestParseResult()
        var remaining = tokens

        for field in definition.exchange.fields {
            guard !remaining.isEmpty else {
                break
            }

            switch field.type {
            case .rst:
                // RST is typically already parsed by QuickEntryParser
                if let idx = remaining.firstIndex(where: { isRST($0) }) {
                    result.fields[field.id] = remaining[idx]
                    remaining.remove(at: idx)
                }

            case .cqZone:
                if let idx = remaining.firstIndex(where: { isCQZone($0) }) {
                    result.fields[field.id] = remaining[idx]
                    remaining.remove(at: idx)
                }

            case .ituZone:
                if let idx = remaining.firstIndex(where: { isITUZone($0) }) {
                    result.fields[field.id] = remaining[idx]
                    remaining.remove(at: idx)
                }

            case .state:
                if let idx = remaining.firstIndex(where: { isStateOrProvince($0) }) {
                    result.fields[field.id] = remaining[idx].uppercased()
                    remaining.remove(at: idx)
                }

            case .arrlSection:
                if let idx = remaining.firstIndex(where: { isARRLSection($0) }) {
                    result.fields[field.id] = remaining[idx].uppercased()
                    remaining.remove(at: idx)
                }

            case .serialNumber:
                if let idx = remaining.firstIndex(where: { isInteger($0) }) {
                    let value = remaining[idx]
                    result.fields[field.id] = value
                    result.serialReceived = Int(value)
                    remaining.remove(at: idx)
                }

            case .county:
                // County abbreviations are 3+ letters
                if let idx = remaining.firstIndex(where: { $0.count >= 3 && $0.allSatisfy(\.isLetter) }) {
                    result.fields[field.id] = remaining[idx].uppercased()
                    remaining.remove(at: idx)
                }

            case .power:
                if let idx = remaining.firstIndex(where: { isPower($0) }) {
                    result.fields[field.id] = remaining[idx].uppercased()
                    remaining.remove(at: idx)
                }

            case .name:
                // Name is typically a single word token that isn't a number or code
                if let idx = remaining.firstIndex(where: { $0.allSatisfy(\.isLetter) && $0.count >= 2 }) {
                    result.fields[field.id] = remaining[idx]
                    remaining.remove(at: idx)
                }

            case .precedence:
                // Single letter: A, B, M, Q, S, U
                if let idx = remaining.firstIndex(where: { isPrecedence($0) }) {
                    result.fields[field.id] = remaining[idx].uppercased()
                    remaining.remove(at: idx)
                }

            case .check:
                // Two-digit year check (e.g., "72", "85")
                if let idx = remaining.firstIndex(where: { isCheck($0) }) {
                    result.fields[field.id] = remaining[idx]
                    remaining.remove(at: idx)
                }

            case .classField:
                // Field Day class: e.g., "2A", "1B", "3F"
                if let idx = remaining.firstIndex(where: { isFieldDayClass($0) }) {
                    result.fields[field.id] = remaining[idx].uppercased()
                    remaining.remove(at: idx)
                }

            case .opaque:
                // Any remaining token
                if let first = remaining.first {
                    result.fields[field.id] = first
                    remaining.removeFirst()
                }
            }
        }

        result.unmatchedTokens = remaining
        return result
    }

    // MARK: Private

    // MARK: - State / Province / ARRL Section Data

    private static let usStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        "DC",
    ]

    private static let caProvinces: Set<String> = [
        "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT",
    ]

    // MARK: - Token Matchers

    private static func isRST(_ token: String) -> Bool {
        guard token.allSatisfy(\.isNumber) else {
            return false
        }
        return token.count == 2 || token.count == 3
    }

    private static func isCQZone(_ token: String) -> Bool {
        guard let zone = Int(token) else {
            return false
        }
        return zone >= 1 && zone <= 40
    }

    private static func isITUZone(_ token: String) -> Bool {
        guard let zone = Int(token) else {
            return false
        }
        return zone >= 1 && zone <= 90
    }

    private static func isInteger(_ token: String) -> Bool {
        Int(token) != nil
    }

    private static func isPower(_ token: String) -> Bool {
        let upper = token.uppercased()
        return ["H", "L", "Q", "HIGH", "LOW", "QRP"].contains(upper)
    }

    private static func isPrecedence(_ token: String) -> Bool {
        guard token.count == 1 else {
            return false
        }
        return "ABMQSU".contains(token.uppercased())
    }

    private static func isCheck(_ token: String) -> Bool {
        guard token.count == 2, let val = Int(token) else {
            return false
        }
        return val >= 0 && val <= 99
    }

    private static func isFieldDayClass(_ token: String) -> Bool {
        guard token.count >= 2 else {
            return false
        }
        let upper = token.uppercased()
        guard upper.last?.isLetter == true else {
            return false
        }
        let numberPart = upper.dropLast()
        return numberPart.allSatisfy(\.isNumber)
    }

    private static func isStateOrProvince(_ token: String) -> Bool {
        let upper = token.uppercased()
        return usStates.contains(upper) || caProvinces.contains(upper)
    }

    private static func isARRLSection(_ token: String) -> Bool {
        arrlSections.contains(token.uppercased())
    }
}
