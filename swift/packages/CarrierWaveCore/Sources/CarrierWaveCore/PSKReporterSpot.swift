import CarrierWaveCwFfi
import Foundation

// MARK: - PSKReporterSpot

/// A reception report from PSK Reporter.
///
/// Parsing the XML response lives in the shared Rust core
/// (`cw_net::pskreporter`); use ``decodeResponse(_:)`` rather than the
/// legacy Swift XML parser.
public struct PSKReporterSpot: Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        senderCallsign: String,
        senderLocator: String?,
        receiverCallsign: String,
        receiverLocator: String?,
        frequency: Int,
        mode: String,
        snr: Int?,
        flowStartSeconds: Int
    ) {
        self.senderCallsign = senderCallsign
        self.senderLocator = senderLocator
        self.receiverCallsign = receiverCallsign
        self.receiverLocator = receiverLocator
        self.frequency = frequency
        self.mode = mode
        self.snr = snr
        self.flowStartSeconds = flowStartSeconds
    }

    /// Build a spot from the Rust-decoded FFI record.
    init(ffi: FfiPskReporterSpot) {
        self.init(
            senderCallsign: ffi.senderCallsign,
            senderLocator: ffi.senderLocator,
            receiverCallsign: ffi.receiverCallsign,
            receiverLocator: ffi.receiverLocator,
            frequency: Int(ffi.frequency),
            mode: ffi.mode,
            snr: ffi.snr.map(Int.init),
            flowStartSeconds: Int(ffi.flowStartSeconds)
        )
    }

    // MARK: Public

    public let senderCallsign: String
    public let senderLocator: String? // Maidenhead grid
    public let receiverCallsign: String
    public let receiverLocator: String? // Maidenhead grid
    public let frequency: Int // Hz
    public let mode: String
    public let snr: Int?
    public let flowStartSeconds: Int // Unix timestamp

    public var id: String {
        "\(senderCallsign)-\(receiverCallsign)-\(frequency)-\(flowStartSeconds)"
    }

    /// Frequency in kHz.
    nonisolated public var frequencyKHz: Double {
        Double(frequency) / 1_000.0
    }

    /// Timestamp derived from flowStartSeconds.
    nonisolated public var timestamp: Date {
        Date(timeIntervalSince1970: Double(flowStartSeconds))
    }

    /// Band derived from frequency.
    nonisolated public var band: String {
        BandUtilities.deriveBand(from: frequencyKHz) ?? ""
    }

    /// Parse a PSK Reporter XML payload via the shared Rust core.
    /// Returns `nil` on XML parse failure (caller should throw an error);
    /// returns an empty array for valid XML with no reception reports.
    public static func decodeResponse(_ xml: String) -> [PSKReporterSpot]? {
        decodePskReporterXml(xml: xml).map { $0.map(PSKReporterSpot.init(ffi:)) }
    }
}
