import CarrierWaveData
import Foundation

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
