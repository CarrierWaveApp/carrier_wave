import SwiftUI

// MARK: - ActivityView+Sections

extension ActivityView {
    // MARK: - Challenges Section

    var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Challenges")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    BrowseChallengesView()
                } label: {
                    Text("Browse")
                        .font(.subheadline)
                }
            }

            if activeParticipations.isEmpty, completedParticipations.isEmpty {
                challengesEmptyState
            } else {
                if !activeParticipations.isEmpty {
                    ForEach(activeParticipations) { participation in
                        NavigationLink {
                            ChallengeDetailView(participation: participation)
                        } label: {
                            ChallengeProgressCard(participation: participation)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !completedParticipations.isEmpty {
                    DisclosureGroup("Completed (\(completedParticipations.count))") {
                        ForEach(completedParticipations) { participation in
                            NavigationLink {
                                ChallengeDetailView(participation: participation)
                            } label: {
                                CompletedChallengeCard(participation: participation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    var challengesEmptyState: some View {
        VStack(spacing: 8) {
            Text("No active challenges")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                BrowseChallengesView()
            } label: {
                Text("Browse Challenges")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Activity Feed Section

    var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            FilterBar(selectedFilter: $selectedFilter, clubs: clubs)

            if filteredActivityItems.isEmpty {
                activityEmptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredActivityItems) { item in
                        ActivityItemRow(
                            item: item,
                            onShare: { shareActivity(item) },
                            onCallsignTap: { callsign in
                                navigateToProfile(callsign: callsign)
                            }
                        )
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showingFriendProfile) {
            if let callsign = selectedCallsign {
                FriendProfileView(
                    callsign: callsign,
                    friendship: friendshipFor(callsign: callsign)
                )
            }
        }
    }

    var activityEmptyState: some View {
        ContentUnavailableView(
            "No Activity Yet",
            systemImage: "person.2",
            description: Text("Activity from friends and clubs will appear here.")
        )
        .padding(.vertical, 24)
    }

    // MARK: - Helper Functions

    func navigateToProfile(callsign: String) {
        selectedCallsign = callsign
        showingFriendProfile = true
    }

    func friendshipFor(callsign: String) -> Friendship? {
        acceptedFriends.first { $0.friendCallsign.uppercased() == callsign.uppercased() }
    }

    func shareActivity(_ item: ActivityItem) {
        itemToShare = item
        showingShareSheet = true
    }
}
