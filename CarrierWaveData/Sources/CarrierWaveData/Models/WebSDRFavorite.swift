import Foundation
import SwiftData

// MARK: - WebSDRFavorite

/// A favorited KiwiSDR receiver, synced via iCloud.
/// Small table (~20 items max), so @Query is fine.
@Model
nonisolated public final class WebSDRFavorite {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public var hostPort = ""
    public var displayName = ""
    public var location = ""
    public var antenna: String?
    public var addedDate = Date()

    public var host: String {
        let parts = hostPort.components(separatedBy: ":")
        return parts[0]
    }

    public var port: Int {
        let parts = hostPort.components(separatedBy: ":")
        return parts.count > 1 ? Int(parts[1]) ?? 8_073 : 8_073
    }
}
