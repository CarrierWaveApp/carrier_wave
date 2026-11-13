import CarrierWaveData
import Foundation

// MARK: - KiwiSDRError

/// Errors thrown by the Swift wrapper around the Rust KiwiSDR client. The
/// protocol-level errors (auth, too-busy, redirects, handshake) surface from
/// the Rust core as `CwError`; mode/passband tables live in Rust too and are
/// reachable via `kiwiModeInfo(mode:frequencyMhz:)`.
nonisolated enum KiwiSDRError: Error, LocalizedError {
    case notConnected
    case alreadyConnected

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Not connected to KiwiSDR"
        case .alreadyConnected:
            "Already connected to a KiwiSDR"
        }
    }
}
