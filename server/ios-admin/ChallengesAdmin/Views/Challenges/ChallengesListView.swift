import SwiftUI

// MARK: - ChallengesListView

struct ChallengesListView: View {
    // MARK: Internal

    enum ChallengeFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case inactive = "Inactive"
    }

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(ChallengeFilter.allCases, id: \.self) { filterCase in
                        Text(filterCase.rawValue).tag(filterCase)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    if let error {
                        ErrorBanner(message: error)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    ForEach(filteredChallenges) { challenge in
                        ChallengeRow(challenge: challenge)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    challengeToDelete = challenge
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Challenges (\(total))")
            .refreshable { await loadChallenges() }
            .task { await loadChallenges() }
            .overlay {
                if isLoading, challenges.isEmpty {
                    ProgressView()
                } else if challenges.isEmpty, error == nil {
                    ContentUnavailableView(
                        "No Challenges",
                        systemImage: "trophy",
                        description: Text("No challenges found on this server.")
                    )
                }
            }
            .alert("Delete Challenge?", isPresented: .init(
                get: { challengeToDelete != nil },
                set: {
                    if !$0 {
                        challengeToDelete = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) { challengeToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let challenge = challengeToDelete {
                        Task { await deleteChallenge(challenge) }
                    }
                }
            } message: {
                if let challenge = challengeToDelete {
                    Text(
                        "This will permanently delete \"\(challenge.name)\" and all associated data."
                    )
                }
            }
        }
    }

    // MARK: Private

    @State private var challenges: [ChallengeListItem] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var error: String?
    @State private var filter: ChallengeFilter = .all
    @State private var challengeToDelete: ChallengeListItem?

    private var api: APIClient {
        APIClient(config: config)
    }

    private var filteredChallenges: [ChallengeListItem] {
        switch filter {
        case .all: challenges
        case .active: challenges.filter(\.isActive)
        case .inactive: challenges.filter { !$0.isActive }
        }
    }

    private func loadChallenges() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.getChallenges()
            challenges = response.challenges
            total = response.total
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteChallenge(_ challenge: ChallengeListItem) async {
        do {
            try await api.deleteChallenge(id: challenge.id)
            challenges.removeAll { $0.id == challenge.id }
            total = max(0, total - 1)
        } catch {
            self.error = error.localizedDescription
        }
        challengeToDelete = nil
    }
}

// MARK: - ChallengeRow

struct ChallengeRow: View {
    let challenge: ChallengeListItem

    var categoryColor: Color {
        switch challenge.category {
        case "award": .orange
        case "event": .blue
        case "club": .purple
        case "personal": .green
        default: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(challenge.name)
                    .font(.headline)
                Spacer()
                if challenge.isActive {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                }
            }

            HStack(spacing: 8) {
                Text(challenge.category.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.15))
                    .foregroundStyle(categoryColor)
                    .clipShape(Capsule())

                Text(challenge.type)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label("\(challenge.participantCount)", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let desc = challenge.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
