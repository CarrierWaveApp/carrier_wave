import CarrierWaveCwFfi
import Foundation

// MARK: - POTASpot

/// A spot from the POTA spotting system.
///
/// Decoding the bare-array JSON response lives in the shared Rust core
/// (`cw_net::pota`); use ``decodeResponse(_:)`` rather than `JSONDecoder`.
public struct POTASpot: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        spotId: Int64,
        activator: String,
        frequency: String,
        mode: String,
        reference: String,
        parkName: String?,
        spotTime: String,
        spotter: String,
        comments: String?,
        source: String?,
        name: String?,
        locationDesc: String?
    ) {
        self.spotId = spotId
        self.activator = activator
        self.frequency = frequency
        self.mode = mode
        self.reference = reference
        self.parkName = parkName
        self.spotTime = spotTime
        self.spotter = spotter
        self.comments = comments
        self.source = source
        self.name = name
        self.locationDesc = locationDesc
        timestamp = Self.parseSpotTime(spotTime)
    }

    /// Build a spot from the Rust-decoded FFI record.
    init(ffi: FfiPotaSpot) {
        spotId = ffi.spotId
        activator = ffi.activator
        frequency = ffi.frequency
        mode = ffi.mode
        reference = ffi.reference
        parkName = ffi.parkName
        spotTime = ffi.spotTime
        spotter = ffi.spotter
        comments = ffi.comments
        source = ffi.source
        name = ffi.name
        locationDesc = ffi.locationDesc
        timestamp = ffi.timestampEpochSeconds.map { Date(timeIntervalSince1970: $0) }
    }

    // MARK: Public

    public let spotId: Int64
    public let activator: String
    public let frequency: String
    public let mode: String
    public let reference: String
    public let parkName: String?
    public let spotTime: String
    public let spotter: String
    public let comments: String?
    public let source: String?
    public let name: String?
    public let locationDesc: String?

    /// Parsed spot time (UTC). `nil` if the timestamp string is unparseable.
    public let timestamp: Date?

    public var id: Int64 {
        spotId
    }

    /// Parse frequency string to kHz.
    nonisolated public var frequencyKHz: Double? {
        Double(frequency)
    }

    /// Time ago string.
    nonisolated public var timeAgo: String {
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

    /// Check if this is an automated spot (from RBN or similar).
    nonisolated public var isAutomatedSpot: Bool {
        guard let source = source?.uppercased() else {
            return false
        }
        return source == "RBN"
    }

    /// Check if this is a human-generated spot.
    nonisolated public var isHumanSpot: Bool {
        !isAutomatedSpot
    }

    /// Parse US state abbreviation from a POTA locationDesc (e.g., "US-WY" -> "WY").
    nonisolated public static func parseState(from locationDesc: String?) -> String? {
        guard let desc = locationDesc else {
            return nil
        }
        let parts = desc.split(separator: "-")
        guard parts.count >= 2, parts[0] == "US" else {
            return nil
        }
        return String(parts[1])
    }

    /// Normalize callsign by removing portable suffixes and uppercasing.
    nonisolated public static func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slashIndex = upper.firstIndex(of: "/") {
            return String(upper[..<slashIndex])
        }
        return upper
    }

    /// Decode a POTA spots response body (bare JSON array) via the shared Rust
    /// core. Returns `nil` if the payload is not a valid POTA spot array.
    public static func decodeResponse(_ json: String) -> [POTASpot]? {
        decodePotaResponse(json: json).map { $0.map(POTASpot.init(ffi:)) }
    }

    /// Check if this spot is a self-spot for the given user callsign.
    nonisolated public func isSelfSpot(userCallsign: String) -> Bool {
        let normalizedUser = Self.normalizeCallsign(userCallsign)
        let normalizedSpot = Self.normalizeCallsign(activator)
        return normalizedUser == normalizedSpot
    }

    // MARK: Private

    /// Parse a POTA spot-time string (UTC, ISO-8601 without Z suffix).
    private static func parseSpotTime(_ spotTime: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        if let date = formatter.date(from: spotTime) {
            return date
        }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withFractionalSeconds]
        return formatter.date(from: spotTime)
    }
}
