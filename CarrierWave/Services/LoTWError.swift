import CarrierWaveData
import Foundation

// MARK: - URLError Transient Classification

extension URLError {
    /// Whether this error is transient and worth retrying.
    /// Covers SSL certificate failures, connection resets, and network interruptions.
    var isTransient: Bool {
        switch code {
        case .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot,
             .secureConnectionFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .timedOut:
            true
        default:
            false
        }
    }
}

// MARK: - LoTWError

enum LoTWError: Error, LocalizedError {
    case authenticationFailed
    case serviceError(String)
    case invalidResponse(String)
    case noCredentials

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            "LoTW authentication failed. Check your username and password."
        case let .serviceError(message):
            "LoTW service error: \(message)"
        case let .invalidResponse(details):
            "Invalid response from LoTW: \(details)"
        case .noCredentials:
            "LoTW credentials not configured"
        }
    }
}
