import Foundation
import SwiftData

// MARK: - ActivityLog

/// A persistent activity log for the "hunter" workflow.
/// Unlike LoggingSession (which has start/end), activity logs stay open across app launches
/// and track daily QSO tallies, station profiles, and location changes.
@Model
nonisolated final class ActivityLog {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        name: String,
        myCallsign: String,
        createdAt: Date = Date(),
        stationProfileId: UUID? = nil,
        currentGrid: String? = nil,
        locationLabel: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.myCallsign = myCallsign
        self.createdAt = createdAt
        self.stationProfileId = stationProfileId
        self.currentGrid = currentGrid
        self.locationLabel = locationLabel
        self.isActive = isActive
    }

    // MARK: Internal

    var id = UUID()
    var name = ""
    var myCallsign = ""
    var createdAt = Date()

    /// ID of the currently selected StationProfile (stored in UserDefaults)
    var stationProfileId: UUID?

    /// Current grid square (updated on location change)
    var currentGrid: String?

    /// Human-readable location label (e.g., "Home", "Mobile - I-95")
    var locationLabel: String?

    /// Whether this is the currently active activity log
    var isActive: Bool = true

    /// Cloud sync
    var cloudDirtyFlag = false
}
