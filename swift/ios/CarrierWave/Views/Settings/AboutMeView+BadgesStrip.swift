import CarrierWaveData
import SwiftUI

// MARK: - AboutMeView + Badges Card

extension AboutMeView {
    /// Earned-badges strip — delegates to the canonical BadgesStripCard.
    func badgesCard(_ profile: UserProfile) -> some View {
        BadgesStripCard(callsign: profile.callsign)
    }
}
