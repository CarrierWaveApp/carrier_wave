// Custom Need
//
// SwiftData model for user-defined needs (Phase 3).
// Persists callsign patterns, entity codes, park references, etc.
// that the operator wants to watch for in the spot feed.

import Foundation
import SwiftData

// MARK: - CustomNeed

@Model
final class CustomNeed {
    // MARK: Lifecycle

    init(
        pattern: String,
        patternTypeRaw: String,
        label: String
    ) {
        id = UUID()
        self.pattern = pattern
        self.patternTypeRaw = patternTypeRaw
        self.label = label
        createdAt = Date()
        isActive = true
    }

    // MARK: Internal

    var id = UUID()

    /// The match pattern (e.g., "VK9*", "WY", "K-1234").
    var pattern = ""

    /// Pattern type raw value: "callsign", "entity", "state", "parkRef".
    var patternTypeRaw = "callsign"

    /// User-provided description (e.g., "Christmas Island").
    var label = ""

    var createdAt = Date()

    /// Whether this need is actively monitored.
    var isActive = true

    /// When this need was fulfilled (QSO logged matching pattern).
    var fulfilledAt: Date?

    /// UUID of the QSO that fulfilled this need.
    var fulfilledByQSOId: UUID?
}
