import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - ScopeSpot mapping & sample

extension ScopeSpot {
    /// Map a live on-air station into a scope row. Tier is derived from the
    /// source (RBN skimmer vs program spot); needed/club tiers require the
    /// goal profile and aren't inferred here.
    init(station: ActiveStation) {
        let tier: SpotTier =
            switch station.source {
            case .rbn: .rbn
            default: .pota
            }
        self.init(
            frequencyHz: Int((station.frequencyMHz * 1_000_000).rounded()),
            callsign: station.callsign,
            tier: tier,
            mode: station.mode,
            wpm: nil,
            ageSeconds: max(0, Int(Date().timeIntervalSince(station.timestamp)))
        )
    }

    /// Sample 20 m picture used by the preview so the Swift renders like the
    /// design mock. Production feeds live spots. Includes sub-kHz frequencies
    /// and a same-frequency pileup.
    static let sample20m: [ScopeSpot] = [
        ScopeSpot(frequencyHz: 14_035_300, callsign: "K7CW", tier: .rbn, mode: "CW", wpm: 24, ageSeconds: 30),
        ScopeSpot(frequencyHz: 14_042_100, callsign: "W1POT", tier: .pota, mode: "CW", wpm: nil, ageSeconds: 55),
        ScopeSpot(frequencyHz: 14_205_400, callsign: "W1AW", tier: .pota, mode: "SSB", wpm: nil, ageSeconds: 150),
        ScopeSpot(frequencyHz: 14_243_000, callsign: "N0DX", tier: .needed, mode: "SSB", wpm: nil, ageSeconds: 60),
        ScopeSpot(frequencyHz: 14_243_150, callsign: "K4POT", tier: .pota, mode: "SSB", wpm: nil, ageSeconds: 90),
        ScopeSpot(frequencyHz: 14_252_600, callsign: "AC2XX", tier: .club, mode: "SSB", wpm: nil, ageSeconds: 480),
        ScopeSpot(frequencyHz: 14_263_200, callsign: "VE3ABC", tier: .pota, mode: "SSB", wpm: nil, ageSeconds: 120),
        ScopeSpot(frequencyHz: 14_285_500, callsign: "K9POT", tier: .pota, mode: "SSB", wpm: nil, ageSeconds: 300),
    ]
}
