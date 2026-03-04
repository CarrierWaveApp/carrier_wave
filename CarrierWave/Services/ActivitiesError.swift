import CarrierWaveData
import Foundation

enum ActivitiesError: Error, LocalizedError {
    case notAuthenticated
    case invalidServerURL
    case networkError(Error)
    case invalidResponse(String)
    case serverError(Int, String?)

    // API error codes from spec
    case challengeNotFound // CHALLENGE_NOT_FOUND (404)
    case alreadyJoined // ALREADY_JOINED (409)
    case notParticipating // NOT_PARTICIPATING (403)
    case inviteRequired // INVITE_REQUIRED (403)
    case inviteExpired // INVITE_EXPIRED (403)
    case inviteExhausted // INVITE_EXHAUSTED (403)
    case maxParticipants // MAX_PARTICIPANTS (403)
    case challengeEnded // CHALLENGE_ENDED (400)
    case invalidToken // INVALID_TOKEN (401)
    case rateLimited // RATE_LIMITED (429)
    case validationError(String?) // VALIDATION_ERROR (400)

    // MARK: Internal

    /// API error code string for this error
    var apiErrorCode: String? {
        switch self {
        case .challengeNotFound: "CHALLENGE_NOT_FOUND"
        case .alreadyJoined: "ALREADY_JOINED"
        case .notParticipating: "NOT_PARTICIPATING"
        case .inviteRequired: "INVITE_REQUIRED"
        case .inviteExpired: "INVITE_EXPIRED"
        case .inviteExhausted: "INVITE_EXHAUSTED"
        case .maxParticipants: "MAX_PARTICIPANTS"
        case .challengeEnded: "CHALLENGE_ENDED"
        case .invalidToken: "INVALID_TOKEN"
        case .rateLimited: "RATE_LIMITED"
        case .validationError: "VALIDATION_ERROR"
        default: nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Please set your callsign in Settings before joining challenges"
        case .invalidServerURL:
            "Invalid challenge server URL"
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
        case .challengeNotFound:
            "Challenge not found"
        case .alreadyJoined:
            "Already participating in this challenge"
        case .notParticipating:
            "Not participating in this challenge"
        case .inviteRequired:
            "This challenge requires an invite"
        case .inviteExpired:
            "This invite link has expired"
        case .inviteExhausted:
            "This invite has reached its maximum uses"
        case .maxParticipants:
            "This challenge has reached its participant limit"
        case .challengeEnded:
            "This challenge has ended"
        case .invalidToken:
            "Invalid or expired authentication token"
        case .rateLimited:
            "Too many requests, please try again later"
        case let .validationError(message):
            message ?? "Invalid request"
        }
    }

    /// Create error from API error code
    static func from(apiCode: String, message: String?) -> ActivitiesError {
        switch apiCode {
        case "CHALLENGE_NOT_FOUND": .challengeNotFound
        case "ALREADY_JOINED": .alreadyJoined
        case "NOT_PARTICIPATING": .notParticipating
        case "INVITE_REQUIRED": .inviteRequired
        case "INVITE_EXPIRED": .inviteExpired
        case "INVITE_EXHAUSTED": .inviteExhausted
        case "MAX_PARTICIPANTS": .maxParticipants
        case "CHALLENGE_ENDED": .challengeEnded
        case "INVALID_TOKEN": .invalidToken
        case "RATE_LIMITED": .rateLimited
        case "VALIDATION_ERROR": .validationError(message)
        default: .serverError(0, message ?? apiCode)
        }
    }
}
