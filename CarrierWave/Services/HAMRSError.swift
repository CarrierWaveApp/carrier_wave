import CarrierWaveData
import Foundation

enum HAMRSError: Error, LocalizedError {
    case notConfigured
    case invalidApiKey
    case subscriptionInactive
    case networkError(Error)
    case invalidResponse(String)
    case decodingError(Error)
    case invalidCouchDBURL

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "HAMRS is not configured. Please enter your API key."
        case .invalidApiKey:
            "Invalid API key. Check your HAMRS Pro settings at hamrs.app"
        case .subscriptionInactive:
            "HAMRS Pro subscription is inactive. Visit hamrs.app to resubscribe."
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(msg):
            "Invalid response: \(msg)"
        case let .decodingError(error):
            "Failed to decode response: \(error.localizedDescription)"
        case .invalidCouchDBURL:
            "Invalid CouchDB URL received from HAMRS"
        }
    }
}
