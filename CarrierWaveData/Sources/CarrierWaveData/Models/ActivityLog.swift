import Foundation
import SwiftData

@Model
nonisolated public final class ActivityLog {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public var id = UUID()
    public var name = ""
    public var myCallsign = ""
    public var createdAt = Date()
    public var stationProfileId: UUID?
    public var currentGrid: String?
    public var locationLabel: String?
    public var isActive: Bool = true
    public var cloudDirtyFlag = false
}
