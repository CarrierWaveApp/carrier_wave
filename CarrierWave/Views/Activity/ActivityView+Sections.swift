import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ActivityView+Sections

extension ActivityView {
    // MARK: - Community Section

    var communitySection: some View {
        VStack(spacing: 0) {
            communityRow(
                icon: "person.circle",
                iconColor: .blue,
                title: currentCallsign,
                subtitle: "My Profile",
                destination: AnyView(
                    FriendProfileView(
                        callsign: currentCallsign,
                        friendship: nil,
                        isOwnProfile: true
                    )
                )
            )

            Divider().padding(.leading, 48)

            communityRow(
                icon: "person.2",
                iconColor: .green,
                title: "Friends",
                subtitle: friendsSummary,
                badge: incomingRequests.count,
                destination: AnyView(FriendsListView())
            )

            Divider().padding(.leading, 48)

            communityRow(
                icon: "person.3",
                iconColor: .purple,
                title: "Clubs",
                subtitle: clubs.isEmpty
                    ? "No clubs yet"
                    : clubs.map(\.name).joined(separator: ", "),
                destination: AnyView(ClubsListView())
            )
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var friendsSummary: String {
        if !incomingRequests.isEmpty {
            let count = incomingRequests.count
            return "\(count) pending request\(count == 1 ? "" : "s")"
        }
        let count = acceptedFriends.count
        if count == 0 {
            return "No friends yet"
        }
        return "\(count) friend\(count == 1 ? "" : "s")"
    }

    private func communityRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        badge: Int = 0,
        destination: AnyView
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
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

            FilterBar(selectedFilter: $selectedFilter, clubs: [])

            if filteredActivityItems.isEmpty {
                activityEmptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredActivityItems) { item in
                        ActivityItemRow(
                            item: item,
                            onShare: { shareActivity(item) },
                            onHide: { hideActivity(item) },
                            onDeleteFromServer: item.isOwn && item.serverId != nil
                                ? { deleteActivityFromServer(item) }
                                : nil,
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

    func hideActivity(_ item: ActivityItem) {
        withAnimation {
            item.isHidden = true
            try? modelContext.save()
            allActivityItems.removeAll { $0.id == item.id }
        }
    }

    func deleteActivityFromServer(_ item: ActivityItem) {
        guard let serverId = item.serverId else {
            return
        }
        withAnimation {
            item.isHidden = true
            try? modelContext.save()
            allActivityItems.removeAll { $0.id == item.id }
        }
        Task {
            let reporter = ActivityReporter()
            try? await reporter.deleteActivity(
                serverId: serverId,
                sourceURL: "https://activities.carrierwave.app"
            )
        }
    }
}
