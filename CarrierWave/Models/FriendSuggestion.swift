import Foundation
import SwiftData

// MARK: - DismissedSuggestion

/// Persists dismissed friend suggestions so they don't reappear.
@Model
nonisolated final class DismissedSuggestion {
    // MARK: Lifecycle

    init(callsign: String, dismissedAt: Date = Date()) {
        self.callsign = callsign.uppercased()
        self.dismissedAt = dismissedAt
    }

    // MARK: Internal

    var callsign = ""
    var dismissedAt = Date()
}

// MARK: - FriendSuggestion

/// Ephemeral suggestion for display — not persisted in SwiftData.
struct FriendSuggestion: Identifiable, Sendable {
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
