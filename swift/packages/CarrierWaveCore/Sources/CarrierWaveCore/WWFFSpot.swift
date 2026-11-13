import CarrierWaveCwFfi
import Foundation

// MARK: - WWFFSpot

/// A spot from the WWFF Spotline service representing an active WWFF activator.
/// Parsed from the HTML table at `https://spots.wwff.co/spots` via the shared
/// Rust core (`cw_net::wwff`); use ``decodeResponse(_:)`` rather than the
/// legacy Swift HTML parser.
public struct WWFFSpot: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: Int,
        activator: String,
        reference: String,
        referenceInfo: String?,
        spotter: String,
        frequency: String,
        mode: String,
        comments: String?,
        source: String?,
        time: String
    ) {
        self.id = id
        self.activator = activator
        self.reference = reference
        self.referenceInfo = referenceInfo
        self.spotter = spotter
        self.frequency = frequency
        self.mode = mode
        self.comments = comments
        self.source = source
        self.time = time
    }

    /// Build a spot from the Rust-decoded FFI record.
    init(ffi: FfiWwffSpot) {
        self.init(
            id: Int(ffi.id),
            activator: ffi.activator,
            reference: ffi.reference,
            referenceInfo: ffi.referenceInfo,
            spotter: ffi.spotter,
            frequency: ffi.frequency,
            mode: ffi.mode,
            comments: ffi.comments,
            source: ffi.source,
            time: ffi.time
        )
    }

    // MARK: Public

    public let id: Int
    public let activator: String // Activator callsign
    public let reference: String // WWFF reference, e.g. "KFF-1234"
    public let referenceInfo: String? // Location name / area details
    public let spotter: String // Who spotted it
    public let frequency: String // MHz as string, e.g. "14.244"
    public let mode: String // "CW", "SSB", "FT8", etc.
    public let comments: String?
    public let source: String? // "RBN" for automated, nil/other for human

    /// ISO-8601 UTC timestamp built from the Spotline "HH:MM" time column.
    public let time: String

    // MARK: - Computed

    /// Frequency in kHz for band derivation.
    nonisolated public var frequencyKHz: Double? {
        guard let mhz = Double(frequency) else {
            return nil
        }
        return mhz * 1_000
    }

    /// Parsed timestamp. Spotline returns UTC ISO-8601 timestamps.
    nonisolated public var parsedTimestamp: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: time) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: time) {
            return date
        }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: time)
    }

    /// Location name extracted from referenceInfo.
    nonisolated public var locationName: String? {
        referenceInfo?.trimmingCharacters(in: .whitespaces)
    }

    /// Parse a WWFF Spotline HTML payload via the shared Rust core.
    /// Always returns a (possibly empty) list — the HTML scraper never hard-fails.
    public static func decodeResponse(_ html: String) -> [WWFFSpot] {
        decodeWwffSpotsHtml(html: html).map(WWFFSpot.init(ffi:))
    }
}
