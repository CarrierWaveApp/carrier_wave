import CarrierWaveData
import Foundation

enum ActivitiesError: Error, LocalizedError {
    case notAuthenticated
    case invalidServerURL
    case networkError(Error)
    case invalidResponse(String)
    case serverError(Int, String?)

    // API error codes from spec
    case invalidToken // INVALID_TOKEN (401)
    case rateLimited // RATE_LIMITED (429)
    case validationError(String?) // VALIDATION_ERROR (400)
    case callsignTaken(String) // CALLSIGN_TAKEN (409)
    case userNotFound // USER_NOT_FOUND (404)

    // MARK: Internal

    /// API error code string for this error
    var apiErrorCode: String? {
        switch self {
        case .invalidToken: "INVALID_TOKEN"
        case .rateLimited: "RATE_LIMITED"
        case .validationError: "VALIDATION_ERROR"
        case .callsignTaken: "CALLSIGN_TAKEN"
        case .userNotFound: "USER_NOT_FOUND"
        default: nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Please set your callsign in Settings"
        case .invalidServerURL:
            "Invalid server URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from server: \(details)"
        case let .serverError(code, message):
            if let message {
                "Server error (\(code)): \(message)"
            } else {
                "Server error: \(code)"
            }
        case .invalidToken:
            "Invalid or expired authentication token"
        case .rateLimited:
            "Too many requests, please try again later"
        case let .validationError(message):
            message ?? "Invalid request"
        case let .callsignTaken(callsign):
            "The callsign \(callsign) is already taken"
        case .userNotFound:
            "User not found"
        }
    }

    /// Create error from API error code
    static func from(apiCode: String, message: String?) -> ActivitiesError {
        switch apiCode {
        case "INVALID_TOKEN": .invalidToken
        case "RATE_LIMITED": .rateLimited
        case "VALIDATION_ERROR": .validationError(message)
        case "CALLSIGN_TAKEN": .callsignTaken(message ?? "")
        case "USER_NOT_FOUND": .userNotFound
        default: .serverError(0, message ?? apiCode)
        }
    }
}
