import CarrierWaveData
import SwiftUI

// MARK: - AboutMeView + Identity Card

extension AboutMeView {
    /// Operator identity card — delegates to the canonical IdentityCard.
    /// Club memberships come from the same SwiftData fetch the Club
    /// Numbers card uses (`myClubMembers`), so the pill row is always in
    /// sync with what's listed below.
    func identityCard(_ profile: UserProfile) -> some View {
        let clubNames = myClubMembers.compactMap { ClubsSyncService.shared.club(id: $0.clubId)?.name }
        return IdentityCard(
            content: .fromOwnProfile(
                profile,
                info: callsignInfo,
                changeNote: callsignChangeNote,
                clubs: clubNames
            )
        )
    }

    var noProfileCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No Profile Set Up")
                .font(.headline)
            Text(
                "Your profile will be set up automatically during onboarding, "
                    + "or you can set it up manually."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Set Up Profile") {
                onRequestOnboarding?()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
