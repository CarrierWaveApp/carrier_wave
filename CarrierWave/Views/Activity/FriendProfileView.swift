import SwiftData
import SwiftUI

// MARK: - FriendProfileView

/// Displays a friend's profile or the user's own profile with recent activity
struct FriendProfileView: View {
    // MARK: Internal

    let callsign: String
    let friendship: Friendship?
    var isOwnProfile: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeader
                statsSection
                recentActivitySection
            }
            .padding()
        }
        .navigationTitle(isOwnProfile ? "My Profile" : callsign)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadActivity()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var friendActivity: [ActivityItem] = []
    @State private var isLoading = true

    private var activitiesThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return friendActivity.filter { $0.timestamp >= weekAgo }.count
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Avatar placeholder
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Text(callsign.prefix(2).uppercased())
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
            }

            Text(callsign)
                .font(.title2)
                .fontWeight(.bold)

            if isOwnProfile {
                Text("Your Activity Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let friendship, friendship.isAccepted {
                let dateText =
                    friendship.acceptedAt?
                        .formatted(date: .abbreviated, time: .omitted) ?? "recently"
                Label("Friends since \(dateText)", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity Stats")
                .font(.headline)

            if friendActivity.isEmpty, !isLoading {
                Text("No activity stats available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(
                        title: "Activities",
                        value: "\(friendActivity.count)",
                        icon: "chart.bar.fill"
                    )

                    StatCard(
                        title: "This Week",
                        value: "\(activitiesThisWeek)",
                        icon: "calendar"
                    )
                }
            }
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if friendActivity.isEmpty {
                ContentUnavailableView(
                    "No Recent Activity",
                    systemImage: isOwnProfile
                        ? "sparkles" : "person.crop.circle.badge.questionmark",
                    description: Text(
                        isOwnProfile
                            ? "Your notable activities will appear here as you make QSOs."
                            : "Activity from \(callsign) will appear here."
                    )
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(friendActivity.prefix(10)) { item in
                        ActivityItemRow(item: item)
                    }
                }
            }
        }
    }

    private func loadActivity() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch activity items for this callsign from local database
        let targetCallsign = callsign.uppercased()
        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { item in
                item.callsign == targetCallsign
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        do {
            friendActivity = try modelContext.fetch(descriptor)
        } catch {
            friendActivity = []
        }
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview("Friend Profile") {
    NavigationStack {
        FriendProfileView(
            callsign: "W1ABC",
            friendship: Friendship(
                friendCallsign: "W1ABC",
                friendUserId: "usr_123",
                status: .accepted,
                acceptedAt: Date().addingTimeInterval(-86_400 * 30),
                isOutgoing: false
            )
        )
    }
    .modelContainer(for: [ActivityItem.self, Friendship.self], inMemory: true)
}

#Preview("Own Profile") {
    NavigationStack {
        FriendProfileView(
            callsign: "N0CALL",
            friendship: nil,
            isOwnProfile: true
        )
    }
    .modelContainer(for: [ActivityItem.self, Friendship.self], inMemory: true)
}
