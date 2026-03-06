import Foundation

/// A spot from the POTA spotting system
struct POTASpot: Decodable, Identifiable, Sendable {
    // MARK: Internal

    let spotId: Int64
    let activator: String
    let frequency: String
    let mode: String
    let reference: String
    let parkName: String?
    let spotTime: String
    let spotter: String
    let comments: String?
    let source: String?
    let name: String?
    let locationDesc: String?

    nonisolated var id: Int64 {
        spotId
    }

    /// Parse frequency string to kHz
    nonisolated var frequencyKHz: Double? {
        Double(frequency)
    }

    /// Parse spot time to Date.
    /// POTA API returns timestamps without timezone suffix (e.g., "2026-02-03T20:43:36").
    /// These are UTC times.
    nonisolated var timestamp: Date? {
        let formatter = ISO8601DateFormatter()

        // First try with full internet datetime (includes Z suffix)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: spotTime) {
            return date
        }

        // POTA API returns timestamps without Z suffix - parse as UTC
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let date = formatter.date(from: spotTime) {
            return date
        }

        // Try with fractional seconds but no Z
        formatter.formatOptions = [
            .withFullDate, .withTime, .withColonSeparatorInTime, .withFractionalSeconds,
        ]
        return formatter.date(from: spotTime)
    }

    /// Time ago string
    nonisolated var timeAgo: String {
        guard let timestamp else {
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

    /// Check if this is an automated spot (from RBN or similar)
    nonisolated var isAutomatedSpot: Bool {
        guard let source = source?.uppercased() else {
            return false
        }
        return source == "RBN"
    }

    /// Parse US state abbreviation from POTA locationDesc (e.g., "US-WY" → "WY")
    nonisolated static func parseState(from locationDesc: String?) -> String? {
        guard let desc = locationDesc else {
            return nil
        }
        let parts = desc.split(separator: "-")
        guard parts.count >= 2, parts[0] == "US" else {
            return nil
        }
        return String(parts[1])
    }

    /// Check if this spot is a self-spot for the given user callsign
    nonisolated func isSelfSpot(userCallsign: String) -> Bool {
        let normalizedUser = Self.normalizeCallsign(userCallsign)
        let normalizedSpot = Self.normalizeCallsign(activator)
        return normalizedUser == normalizedSpot
    }

    // MARK: Private

    /// Normalize callsign by removing portable suffixes and uppercasing
    nonisolated private static func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slashIndex = upper.firstIndex(of: "/") {
            return String(upper[..<slashIndex])
        }
        return upper
    }
}
