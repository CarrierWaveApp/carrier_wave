import SwiftUI

// MARK: - ActivityView+Sections

extension ActivityView {
    // MARK: - Friend Requests Banner

    @ViewBuilder
    var friendRequestsBanner: some View {
        if !incomingRequests.isEmpty {
            NavigationLink {
                FriendsListView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            incomingRequests.count == 1
                                ? "1 Friend Request"
                                : "\(incomingRequests.count) Friend Requests"
                        )
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                        Text(friendRequestSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private var friendRequestSubtitle: String {
        let callsigns = incomingRequests.map(\.friendCallsign)
        if callsigns.count == 1 {
            return "\(callsigns[0]) wants to connect"
        } else if callsigns.count == 2 {
            return "\(callsigns[0]) and \(callsigns[1]) want to connect"
        } else {
            return "\(callsigns[0]) and \(callsigns.count - 1) others want to connect"
        }
    }

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
