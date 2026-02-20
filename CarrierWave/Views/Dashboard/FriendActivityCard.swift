import SwiftData
import SwiftUI

// MARK: - FriendActivityCard

/// Dashboard card showing recent friend activity feed items.
struct FriendActivityCard: View {
    // MARK: Internal

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(alignment: .leading, spacing: 12) {
                header
                if friendActivities.isEmpty {
                    emptyState
                } else {
                    activityRows
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .task(id: acceptedFriends.count) {
            loadActivities()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didDetectActivities)
        ) { _ in
            loadActivities()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didSyncQSOs)
        ) { _ in
            loadActivities()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var friendActivities: [ActivityItem] = []

    private var friendCallsigns: Set<String> {
        Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.2.wave.2.fill")
                .foregroundStyle(.blue)
            Text("Friend Activity")
                .font(.headline)
            Spacer()
        }
    }

    private var emptyState: some View {
        Text("No recent friend activity")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var activityRows: some View {
        VStack(spacing: 8) {
            ForEach(friendActivities.prefix(3)) { item in
                compactActivityRow(item)
            }
        }
    }

    private func compactActivityRow(_ item: ActivityItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.activityType.icon)
                .font(.caption)
                .foregroundStyle(iconColor(for: item.activityType))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                Text(item.activityType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(relativeTime(item.timestamp))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func iconColor(for type: ActivityType) -> Color {
        switch type {
        case .challengeTierUnlock,
             .challengeCompletion: .yellow
        case .newDXCCEntity,
             .dxContact: .blue
        case .potaActivation: .green
        case .sotaActivation: .brown
        case .dailyStreak,
             .potaDailyStreak: .orange
        case .personalBest: .purple
        case .workedFriend: .pink
        case .newBand,
             .newMode: .teal
        case .sessionCompleted: .green
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        } else if interval < 3_600 {
            let mins = Int(interval / 60)
            return "\(mins)m"
        } else if interval < 86_400 {
            let hours = Int(interval / 3_600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86_400)
            return "\(days)d"
        }
    }

    // MARK: - Data Loading

    private func loadActivities() {
        guard !friendCallsigns.isEmpty else {
            friendActivities = []
            return
        }

        var descriptor = FetchDescriptor<ActivityItem>(
            predicate: #Predicate { !$0.isOwn },
            sortBy: [SortDescriptor(\ActivityItem.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        let all = (try? modelContext.fetch(descriptor)) ?? []
        friendActivities = Array(
            all.filter { friendCallsigns.contains($0.callsign.uppercased()) }
                .prefix(3)
        )
    }
}
