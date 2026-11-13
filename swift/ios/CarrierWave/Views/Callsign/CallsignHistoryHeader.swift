import CarrierWaveData
import SwiftUI

// MARK: - CallsignHistoryHeader

/// Identity hero for any callsign — delegates to the canonical IdentityCard.
struct CallsignHistoryHeader: View {
    let callsign: String
    let callsignInfo: CallsignInfo?
    let friendship: Friendship?
    var isLookingUp: Bool = false
    var clubs: [String] = []
    var ownProfile: UserProfile?

    var body: some View {
        IdentityCard(
            content: .fromLookup(
                callsign: callsign,
                info: callsignInfo,
                friendship: friendship,
                isLookingUp: isLookingUp,
                clubs: clubs,
                ownProfile: ownProfile
            )
        )
    }
}
