import CarrierWaveData
import Foundation

// MARK: - SOTASpot

/// A spot from the SOTAwatch API representing an active SOTA activator.
struct SOTASpot: Codable, Sendable, Identifiable {
    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case userID
        case activatorCallsign
        case activatorName
        case spotterCallsign = "callsign"
        case associationCode
        case summitCode
        case summitDetails
        case frequency
        case mode
        case comments
        case highlightColor
        case timeStamp
    }

    let id: Int
    let userID: Int
    let activatorCallsign: String
    let activatorName: String
    let spotterCallsign: String
    let associationCode: String // e.g. "W4C"
    let summitCode: String // e.g. "SE-029" (local code within association)
    let summitDetails: String // e.g. "Mount Mitchell, 2037m, 10 points"
    let frequency: String // MHz as a string, e.g. "14.062"
    let mode: String // "CW", "SSB", "FM", etc.
    let comments: String?
    let highlightColor: String?
    let timeStamp: String // ISO-8601 without timezone, UTC, e.g. "2026-02-26T17:51:41"

    // MARK: - Computed

    /// Frequency in MHz, parsed from the API string.
    nonisolated var frequencyMHz: Double? {
        Double(frequency)
    }

    /// Frequency in kHz for band derivation.
    nonisolated var frequencyKHz: Double? {
        guard let mhz = frequencyMHz else {
            return nil
        }
        return mhz * 1_000
    }

    /// Parsed timestamp. SOTAwatch returns UTC without a timezone suffix.
    nonisolated var parsedTimestamp: Date? {
        // Try full internet datetime first (handles any future Z-suffixed responses)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timeStamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timeStamp) {
            return date
        }

        // SOTAwatch returns timestamps without a Z suffix — parse as UTC
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: timeStamp)
    }

    /// Human-readable age string (e.g. "3m ago").
    nonisolated var timeAgo: String {
        guard let timestamp = parsedTimestamp else {
            return ""
        }
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }

    /// Full summit reference combining association and summit codes (e.g. "W4C/CM-001").
    nonisolated var fullSummitReference: String {
        "\(associationCode)/\(summitCode)"
    }

    /// Points value extracted from summitDetails (e.g. "Mount Mitchell, 2037m, 10 points" → 10).
    nonisolated var points: Int {
        // Parse "N points" pattern from summitDetails
        let parts = summitDetails.components(separatedBy: ",")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.hasSuffix("points") || trimmed.hasSuffix("point") {
                let digits = trimmed.components(separatedBy: .whitespaces).first ?? ""
                return Int(digits) ?? 0
            }
        }
        return 0
    }

    /// Summit name extracted from summitDetails (text before first comma).
    nonisolated var summitName: String {
        summitDetails.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? summitDetails
    }
}
