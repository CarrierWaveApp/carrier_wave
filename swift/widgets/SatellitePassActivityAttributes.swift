import ActivityKit
import Foundation

// MARK: - SatellitePassAttributes

/// ActivityKit attributes for the satellite pass-countdown Live Activity.
/// Mirror of CarrierWave/Services/SatellitePassActivityAttributes.swift —
/// keep in sync.
///
/// The countdown is self-driving (`Text(_:style:.timer)` over the fixed
/// AOS/LOS dates), so `ContentState` never needs mid-pass updates.
///
/// `nonisolated` opts out of the target's default MainActor isolation: ActivityKit
/// uses this conformance off the main actor, which Swift rejects for a
/// MainActor-isolated conformance (Xcode 27+).
nonisolated struct SatellitePassAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var updatedAt: Date
    }

    /// Short OSCAR designator ("AO-91").
    var satelliteName: String
    var noradID: Int
    var aos: Date
    var los: Date
    var peakElevationDeg: Double
    var aosAzimuthDeg: Double
    var losAzimuthDeg: Double
    /// 10–20° peak — above the floor, below the handheld recommendation.
    var isMarginal: Bool
}
