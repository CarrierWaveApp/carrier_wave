// Callsign Notes Source Model
//
// SwiftData model for user-configured callsign notes file sources.
// These are URLs to Polo-style notes files that get fetched and cached.

import Foundation
import SwiftData

// MARK: - CallsignNotesSource

@Model
nonisolated final class CallsignNotesSource {
    // MARK: Lifecycle

    init(title: String, url: String) {
        id = UUID()
        self.title = title
        self.url = url
        isEnabled = true
        lastFetched = nil
        entryCount = 0
        lastError = nil
    }

    // MARK: Internal

    /// Unique identifier
    var id = UUID()

    /// Display name for this source (e.g., "POTA Activators")
    var title = ""

    /// URL to the notes file
    var url = ""

    /// Whether this source is enabled for lookups
    var isEnabled: Bool = true

    /// When this source was last successfully fetched
    var lastFetched: Date?

    /// Number of callsign entries parsed from this source
    var entryCount: Int = 0

    /// Last error message (if fetch failed)
    var lastError: String?

    /// Whether the source needs refresh (older than 1 day)
    var needsRefresh: Bool {
        guard let lastFetched else {
            return true
        }
        let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        return lastFetched < oneDayAgo
    }

    /// Formatted last fetched string
    var lastFetchedDescription: String? {
        guard let lastFetched else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastFetched, relativeTo: Date())
    }
}
