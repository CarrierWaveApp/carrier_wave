import SwiftData
import SwiftUI

// MARK: - LeaderboardView

struct LeaderboardView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    let definition: ChallengeDefinition
    let entries: [LeaderboardEntry]
    var currentUserCallsign: String?

    var displayedEntries: [LeaderboardEntry] {
        liveEntries.isEmpty ? entries : liveEntries
    }

    var body: some View {
        List {
            if displayedEntries.isEmpty {
                ContentUnavailableView(
                    "No Participants",
                    systemImage: "person.3",
                    description: Text("Be the first to join this challenge!")
                )
            } else {
                ForEach(displayedEntries) { entry in
                    LeaderboardRow(entry: entry, currentUserCallsign: currentUserCallsign)
                }
            }
        }
        .navigationTitle("Leaderboard")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isRefreshing {
                    ProgressView()
                }
            }
        }
        .onAppear {
            if syncService == nil {
                syncService = ActivitiesSyncService(modelContext: modelContext)
            }
            liveEntries = entries
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: Private

    @State private var syncService: ActivitiesSyncService?
    @State private var liveEntries: [LeaderboardEntry] = []
    @State private var isRefreshing = false
    @State private var pollingTask: Task<Void, Never>?

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refresh() async {
        guard let syncService else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            liveEntries = try await syncService.fetchLeaderboard(for: definition)
        } catch {
            // Silently fail for polling
        }
    }
}

// MARK: - LeaderboardRow

struct LeaderboardRow: View {
    // MARK: Internal

    let entry: LeaderboardEntry
    var currentUserCallsign: String?

    var body: some View {
        HStack(spacing: 16) {
            // Rank with medal for top 3
            ZStack {
                if entry.rank <= 3 {
                    Circle()
                        .fill(medalColor)
                        .frame(width: 36, height: 36)
                }

                Text("\(entry.rank)")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(entry.rank <= 3 ? .white : .primary)
            }
            .frame(width: 44)

            // Callsign and tier
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.callsign)
                        .font(.body)
                        .fontWeight(isCurrentUser ? .bold : .regular)

                    if isCurrentUser {
                        Text("You")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                if let tier = entry.currentTier {
                    Text(tier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Score
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.score)")
                    .font(.headline)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isCurrentUser ? Color.accentColor.opacity(0.1) : nil)
    }

    // MARK: Private

    private var isCurrentUser: Bool {
        guard let currentUserCallsign else {
            return false
        }
        return entry.callsign.uppercased() == currentUserCallsign.uppercased()
    }

    private var medalColor: Color {
        switch entry.rank {
        case 1: .yellow
        case 2: Color(white: 0.75)
        case 3: .orange
        default: .clear
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LeaderboardView(
            definition: ChallengeDefinition(
                sourceURL: "https://example.com",
                name: "Test Challenge",
                descriptionText: "A test challenge",
                author: "Test",
                type: .collection,
                configurationData: Data()
            ),
            entries: [
                LeaderboardEntry(
                    rank: 1,
                    callsign: "W1AW",
                    score: 48,
                    currentTier: "Expert",
                    completedAt: nil
                ),
                LeaderboardEntry(
                    rank: 2,
                    callsign: "K2ABC",
                    score: 45,
                    currentTier: "Advanced",
                    completedAt: nil
                ),
                LeaderboardEntry(
                    rank: 3,
                    callsign: "N3XYZ",
                    score: 42,
                    currentTier: "Advanced",
                    completedAt: nil
                ),
            ]
        )
    }
}
