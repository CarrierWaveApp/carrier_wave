import Foundation

// MARK: - KiwiSDRMode

/// Radio modes supported by KiwiSDR, mapped from amateur radio modes.
/// Explicitly nonisolated — pure value type used across actor boundaries.
nonisolated enum KiwiSDRMode: Sendable {
    case cw
    case usb
    case lsb
    case am
    case nbfm

    // MARK: Internal

    /// KiwiSDR protocol name for this mode
    var kiwiName: String {
        switch self {
        case .cw: "cw"
        case .usb: "usb"
        case .lsb: "lsb"
        case .am: "am"
        case .nbfm: "nbfm"
        }
    }

    /// Human-readable mode name
    var displayName: String {
        switch self {
        case .cw: "CW"
        case .usb: "USB"
        case .lsb: "LSB"
        case .am: "AM"
        case .nbfm: "NBFM"
        }
    }

    /// Low frequency cut in Hz
    var lowCut: Int {
        switch self {
        case .cw: 300
        case .usb: 300
        case .lsb: -2_700
        case .am: -5_000
        case .nbfm: -6_000
        }
    }

    /// High frequency cut in Hz
    var highCut: Int {
        switch self {
        case .cw: 800
        case .usb: 2_700
        case .lsb: -300
        case .am: 5_000
        case .nbfm: 6_000
        }
    }

    /// Offset in kHz to subtract from operating frequency to get the
    /// KiwiSDR carrier frequency. For CW, the operating frequency is
    /// the signal frequency; the receiver must tune below it so the
    /// signal lands in the center of the audio passband.
    var carrierOffsetKHz: Double {
        switch self {
        case .cw:
            // Center of CW passband: (300 + 800) / 2 = 550 Hz = 0.550 kHz
            Double(lowCut + highCut) / 2.0 / 1_000.0
        case .usb,
             .lsb,
             .am,
             .nbfm:
            0
        }
    }

    /// Bandwidth in Hz
    var bandwidthHz: Int {
        highCut - lowCut
    }

    /// Human-readable bandwidth description
    var bandwidthDescription: String {
        let bw = bandwidthHz
        if bw >= 1_000 {
            return String(format: "%.1f kHz", Double(bw) / 1_000.0)
        }
        return "\(bw) Hz"
    }

    /// Map from Carrier Wave mode string to KiwiSDR mode
    static func from(carrierWaveMode: String, frequencyMHz: Double?) -> KiwiSDRMode {
        switch carrierWaveMode.uppercased() {
        case "CW":
            return .cw
        case "SSB":
            // SSB → USB above 10 MHz, LSB below
            if let freq = frequencyMHz, freq < 10.0 {
                return .lsb
            }
            return .usb
        case "USB":
            return .usb
        case "LSB":
            return .lsb
        case "FT8",
             "FT4",
             "RTTY",
             "DATA",
             "DIGITAL",
             "PSK31",
             "PSK",
             "JT65",
             "JT9",
             "WSPR":
            return .usb
        case "AM":
            return .am
        case "FM":
            return .nbfm
        default:
            return .usb
        }
    }
}

// MARK: - KiwiSDRError

nonisolated enum KiwiSDRError: Error, LocalizedError {
    case invalidURL
    case notConnected
    case alreadyConnected
    case handshakeFailed(String)
    case connectionLost
    case authenticationFailed
    case tooBusy(Int)
    case serverDown
    case serverRedirect(String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid KiwiSDR URL"
        case .notConnected:
            "Not connected to KiwiSDR"
        case .alreadyConnected:
            "Already connected to a KiwiSDR"
        case let .handshakeFailed(reason):
            "KiwiSDR handshake failed: \(reason)"
        case .connectionLost:
            "Connection to KiwiSDR lost"
        case .authenticationFailed:
            "KiwiSDR authentication failed (bad password)"
        case let .tooBusy(slots):
            "KiwiSDR is full (\(slots) channels in use)"
        case .serverDown:
            "KiwiSDR server is down"
        case let .serverRedirect(url):
            "KiwiSDR redirected to \(url)"
        }
    }
}
