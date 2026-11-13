import CarrierWaveCwFfi
import Foundation

// MARK: - RBNSpot

/// A spot from the Reverse Beacon Network.
///
/// Decoding the three response shapes lives in the shared Rust core
/// (`cw_net::rbn`); use ``decodeResponse(_:)`` rather than `JSONDecoder`.
public struct RBNSpot: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        id: Int,
        callsign: String,
        frequency: Double,
        mode: String,
        timestamp: Date,
        snr: Int,
        wpm: Int?,
        spotter: String,
        spotterGrid: String?
    ) {
        self.id = id
        self.callsign = callsign
        self.frequency = frequency
        self.mode = mode
        self.timestamp = timestamp
        self.snr = snr
        self.wpm = wpm
        self.spotter = spotter
        self.spotterGrid = spotterGrid
    }

    /// Build a spot from the Rust-decoded FFI record.
    init(ffi: FfiRbnSpot) {
        self.init(
            id: Int(ffi.id),
            callsign: ffi.callsign,
            frequency: ffi.frequency,
            mode: ffi.mode,
            timestamp: ffi.timestampEpochSeconds.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            snr: Int(ffi.snr),
            wpm: ffi.wpm.map(Int.init),
            spotter: ffi.spotter,
            spotterGrid: ffi.spotterGrid
        )
    }

    // MARK: Public

    public let id: Int
    public let callsign: String
    public let frequency: Double // in kHz
    public let mode: String
    public let timestamp: Date
    public let snr: Int
    public let wpm: Int?
    public let spotter: String
    public let spotterGrid: String?

    /// Frequency in MHz.
    nonisolated public var frequencyMHz: Double {
        frequency / 1_000.0
    }

    /// Band derived from frequency.
    nonisolated public var band: String {
        BandUtilities.deriveBand(from: frequency) ?? ""
    }

    /// Formatted frequency string.
    nonisolated public var formattedFrequency: String {
        String(format: "%.1f kHz", frequency)
    }

    /// Time ago string.
    nonisolated public var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }

    /// Decode an RBN response body (callsign-echo, total-count, or bare array)
    /// via the shared Rust core. Returns `nil` if the payload matches none of
    /// the shapes.
    public static func decodeResponse(_ json: String) -> [RBNSpot]? {
        decodeRbnResponse(json: json).map { $0.map(RBNSpot.init(ffi:)) }
    }
}
