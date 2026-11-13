import CarrierWaveData
import Foundation

// MARK: - FriendSuggestion

/// Ephemeral suggestion for display — not persisted in SwiftData.
struct FriendSuggestion: Identifiable {
    let userId: String
    let callsign: String
    let qsoCount: Int

    var id: String {
        callsign
    }
}

// MARK: - FriendSuggestionDTO

/// Server response for validated friend suggestions.
struct FriendSuggestionDTO: Codable {
    let userId: String
    let callsign: String
}
