import CarrierWaveCwFfi
import Foundation

// MARK: - SOTASpot

/// A spot from the SOTAwatch API representing an active SOTA activator.
///
/// Decoding the bare-array JSON response lives in the shared Rust core
/// (`cw_net::sota`); use ``decodeResponse(_:)`` rather than `JSONDecoder`.
/// The `Codable` conformance is preserved for the existing parity-test suite
/// which decodes spots directly via `JSONDecoder`.
public struct SOTASpot: Codable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: Int,
        userID: Int,
        activatorCallsign: String,
        activatorName: String,
        spotterCallsign: String,
        associationCode: String,
        summitCode: String,
        summitDetails: String,
        frequency: String,
        mode: String,
        comments: String?,
        highlightColor: String?,
        timeStamp: String
    ) {
        self.id = id
        self.userID = userID
        self.activatorCallsign = activatorCallsign
        self.activatorName = activatorName
        self.spotterCallsign = spotterCallsign
        self.associationCode = associationCode
        self.summitCode = summitCode
        self.summitDetails = summitDetails
        self.frequency = frequency
        self.mode = mode
        self.comments = comments
        self.highlightColor = highlightColor
        self.timeStamp = timeStamp
    }

    /// Build a spot from the Rust-decoded FFI record.
    init(ffi: FfiSotaSpot) {
        self.init(
            id: Int(ffi.id),
            userID: Int(ffi.userId),
            activatorCallsign: ffi.activatorCallsign,
            activatorName: ffi.activatorName,
            spotterCallsign: ffi.spotterCallsign,
            associationCode: ffi.associationCode,
            summitCode: ffi.summitCode,
            summitDetails: ffi.summitDetails,
            frequency: ffi.frequency,
            mode: ffi.mode,
            comments: ffi.comments,
            highlightColor: ffi.highlightColor,
            timeStamp: ffi.timeStamp
        )
    }

    // MARK: Public

    public let id: Int
    public let userID: Int
    public let activatorCallsign: String
    public let activatorName: String
    public let spotterCallsign: String
    public let associationCode: String // e.g. "W4C"
    public let summitCode: String // e.g. "SE-029" (local code within association)
    public let summitDetails: String // e.g. "Mount Mitchell, 2037m, 10 points"
    public let frequency: String // MHz as a string, e.g. "14.062"
    public let mode: String // "CW", "SSB", "FM", etc.
    public let comments: String?
    public let highlightColor: String?
    public let timeStamp: String // ISO-8601 without timezone, UTC, e.g. "2026-02-26T17:51:41"

    // MARK: - Computed

    /// Frequency in MHz, parsed from the API string.
    nonisolated public var frequencyMHz: Double? {
        Double(frequency)
    }

    /// Frequency in kHz for band derivation.
    nonisolated public var frequencyKHz: Double? {
        guard let mhz = frequencyMHz else {
            return nil
        }
        return mhz * 1_000
    }

    /// Parsed timestamp. SOTAwatch returns UTC without a timezone suffix.
    nonisolated public var parsedTimestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timeStamp) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: timeStamp) {
            return date
        }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: timeStamp)
    }

    /// Human-readable age string (e.g. "3m ago").
    nonisolated public var timeAgo: String {
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
    nonisolated public var fullSummitReference: String {
        "\(associationCode)/\(summitCode)"
    }

    /// Points value extracted from summitDetails (e.g. "Mount Mitchell, 2037m, 10 points" -> 10).
    nonisolated public var points: Int {
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
    nonisolated public var summitName: String {
        summitDetails.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? summitDetails
    }

    /// Normalize callsign by removing portable suffixes and uppercasing.
    /// Mirrors `POTASpot.normalizeCallsign` so S2S/P2P matching is consistent.
    nonisolated public static func normalizeCallsign(_ callsign: String) -> String {
        let upper = callsign.uppercased()
        if let slash = upper.firstIndex(of: "/") {
            return String(upper[..<slash])
        }
        return upper
    }

    /// Decode a SOTAwatch spots response body (bare JSON array) via the shared
    /// Rust core. Returns `nil` if the payload is not a valid SOTA spot array.
    public static func decodeResponse(_ json: String) -> [SOTASpot]? {
        decodeSotaResponse(json: json).map { $0.map(SOTASpot.init(ffi:)) }
    }

    // MARK: Internal

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
}
