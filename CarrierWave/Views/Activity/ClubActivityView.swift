import SwiftUI

// MARK: - ClubActivityView

struct ClubActivityView: View {
    // MARK: Internal

    let club: Club

    var body: some View {
        Group {
            if activities.isEmpty, !isLoading {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        "Club member activity will appear here"
                    )
                )
            } else {
                List {
                    ForEach(activities, id: \.id) { item in
                        ClubActivityRow(item: item)
                    }
                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await loadMore() }
                    }
                }
            }
        }
        .task { await loadInitial() }
    }

    // MARK: Private

    @State private var activities: [FeedItemDTO] = []
    @State private var isLoading = false
    @State private var cursor: UUID?
    @State private var hasMore = true

    private let pageSize = 20
    private let sourceURL = "https://activities.carrierwave.app"

    private func loadInitial() async {
        guard !isLoading else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        let client = ActivitiesClient()
        guard let authToken = await client.ensureAuthToken()
        else {
            hasMore = false
            return
        }

        do {
            let items = try await client.fetchClubActivity(
                clubId: club.serverId,
                sourceURL: sourceURL,
                authToken: authToken,
                limit: pageSize
            )
            activities = items
            hasMore = items.count >= pageSize
            cursor = items.last?.id
        } catch {
            hasMore = false
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore, let cursor else {
            return
        }
        isLoading = true
        defer { isLoading = false }

        let client = ActivitiesClient()
        guard let authToken = await client.ensureAuthToken()
        else {
            hasMore = false
            return
        }

        do {
            let items = try await client.fetchClubActivity(
                clubId: club.serverId,
                sourceURL: sourceURL,
                authToken: authToken,
                cursor: cursor,
                limit: pageSize
            )
            activities.append(contentsOf: items)
            hasMore = items.count >= pageSize
            self.cursor = items.last?.id
        } catch {
            hasMore = false
        }
    }
}

// MARK: - ClubActivityRow

struct ClubActivityRow: View {
    // MARK: Internal

    let item: FeedItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.callsign)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(item.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(formatActivityType(item.activityType))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private func formatActivityType(_ type: String) -> String {
        type
            .replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubActivityView(
            club: Club(
                serverId: UUID(),
                name: "Preview Club"
            )
        )
    }
    .modelContainer(
        for: [Club.self, ClubMember.self],
        inMemory: true
    )
}
