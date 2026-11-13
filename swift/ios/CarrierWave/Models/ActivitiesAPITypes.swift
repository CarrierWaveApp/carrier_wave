import Foundation

// MARK: - RegisterRequestBody

struct RegisterRequestBody: Codable {
    var callsign: String
    var deviceName: String?
}

// MARK: - RegisterResponseDTO

struct RegisterResponseDTO: Codable {
    var userId: String
    /// Present only when registration created a NEW participant. The server omits
    /// it for an already-registered callsign (CAR-304) so an unauthenticated
    /// `/v1/register` can't hand back an existing operator's token. A lost token
    /// is recovered via magic-link sign-in, not by re-registering — so this must
    /// stay optional or decoding an "already registered" response would throw.
    var deviceToken: String?
}

// MARK: - APIResponse

struct APIResponse<T: Codable>: Codable {
    var data: T
}

// MARK: - APIError

struct APIError: Codable {
    var code: String
    var message: String
    var details: [String: String]?
}

// MARK: - APIErrorResponse

struct APIErrorResponse: Codable {
    var error: APIError
}

// MARK: - ChangeCallsignRequest

struct ChangeCallsignRequest: Codable {
    var newCallsign: String
}

// MARK: - ChangeCallsignResponse

struct ChangeCallsignResponse: Codable {
    var callsign: String
}

// MARK: - ClaimPreviousRequest

struct ClaimPreviousRequest: Codable {
    var previousCallsign: String
}

// MARK: - ClaimPreviousResponse

struct ClaimPreviousResponse: Codable {
    var merged: Bool
    var previousCallsign: String
}
