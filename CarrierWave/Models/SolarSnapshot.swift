import Foundation
import SwiftData

/// Hourly solar conditions snapshot captured by background polling.
/// Stores solar-only readings (no weather — that requires location).
@Model
final class SolarSnapshot {
    // MARK: Lifecycle

    init(
        timestamp: Date,
        kIndex: Double?,
        aIndex: Int?,
        solarFlux: Double?,
        sunspots: Int?,
        propagationRating: String?,
        bandConditions: String?
    ) {
        self.timestamp = timestamp
        self.kIndex = kIndex
        self.aIndex = aIndex
        self.solarFlux = solarFlux
        self.sunspots = sunspots
        self.propagationRating = propagationRating
        self.bandConditions = bandConditions
    }

    // MARK: Internal

    var timestamp = Date()
    var kIndex: Double?
    var aIndex: Int?
    var solarFlux: Double?
    var sunspots: Int?
    var propagationRating: String?
    var bandConditions: String?

    /// Whether this snapshot has any meaningful solar data
    var hasSolarData: Bool {
        kIndex != nil || solarFlux != nil || sunspots != nil
    }
}
