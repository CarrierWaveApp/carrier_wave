import Foundation
import SwiftData

// MARK: - WebSDRFavorite

/// A favorited KiwiSDR receiver, synced via iCloud.
/// Small table (~20 items max), so @Query is fine.
@Model
final class WebSDRFavorite {
    // MARK: Lifecycle

    init(
        hostPort: String,
        displayName: String,
        location: String,
        antenna: String? = nil,
        addedDate: Date = Date()
    ) {
        self.hostPort = hostPort
        self.displayName = displayName
        self.location = location
        self.antenna = antenna
        self.addedDate = addedDate
    }

    // MARK: Internal

    /// Stable identifier: "host:port"
    var hostPort: String
    var displayName: String
    var location: String
    var antenna: String?
    var addedDate: Date

    var host: String {
        let parts = hostPort.components(separatedBy: ":")
        return parts[0]
    }

    var port: Int {
        let parts = hostPort.components(separatedBy: ":")
        return parts.count > 1 ? Int(parts[1]) ?? 8_073 : 8_073
    }
}
