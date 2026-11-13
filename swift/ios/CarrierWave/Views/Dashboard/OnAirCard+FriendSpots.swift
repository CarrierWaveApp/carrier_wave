import CarrierWaveCore
import CarrierWaveCwFfi
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Friend Spot Data Loading

/// Friend spots feed the card's one-line summary row and the On Air sheet's
/// full section. The card-side inline rows were removed when the glance
/// surface condensed to counts (ux-north-star.md §9 — one hero per screen).
extension OnAirCard {
    /// Filter the engine's POTA snapshot to accepted friends. The caller
    /// (`loadAllData`) has already polled the engine.
    func loadFriendSpots(
        friendCallsigns: Set<String>
    ) -> [(callsign: String, spot: POTASpot)] {
        guard !friendCallsigns.isEmpty,
              let engine = SpotEngineProvider.shared.engine()
        else {
            return []
        }
        return engine.snapshot(filter: nil, worked: nil).spots
            .compactMap(\.appPotaSpot)
            .filter { friendCallsigns.contains($0.activator.uppercased()) }
            .map { (callsign: $0.activator.uppercased(), spot: $0) }
    }
}
