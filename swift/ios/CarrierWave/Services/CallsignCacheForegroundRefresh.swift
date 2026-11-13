// Callsign Cache Foreground Refresh
//
// Re-checks staleness of the callsign notes / enrichment / QRQ Crew member
// caches when the app returns to the foreground. These caches otherwise only
// refresh at cold launch, and iOS keeps the app resident for days, so a
// roster change (e.g. a member's new callsign) never appeared until the
// process died. Each call is a cheap no-op while the caches are fresh.

import SwiftData
import UIKit

enum CallsignCacheForegroundRefresh {
    @MainActor
    static func run(container: ModelContainer) async {
        let sources = NotesSourceInfo.fetchAll(modelContext: container.mainContext)
        await CallsignNotesCache.shared.refreshIfNeeded(sources: sources)
        await CallsignEnrichmentCache.shared.refreshIfNeeded()
        await QRQCrewMemberCache.shared.refreshIfNeeded()
    }
}
