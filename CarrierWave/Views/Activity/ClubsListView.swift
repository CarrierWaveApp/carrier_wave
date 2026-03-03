import SwiftData
import SwiftUI

// MARK: - ClubsListView

struct ClubsListView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if clubs.isEmpty {
                ContentUnavailableView(
                    "No Clubs",
                    systemImage: "person.3",
                    description: Text(
                        "Club membership is based on Ham2K Polo callsign notes lists. "
                            + "Ask a club admin to add your callsign."
                    )
                )
            } else {
                List(clubs) { club in
                    NavigationLink {
                        ClubDetailView(club: club)
                    } label: {
                        ClubRow(club: club)
                    }
                }
            }
        }
        .navigationTitle("Clubs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .onAppear {
            if clubsSyncService == nil {
                clubsSyncService = ClubsSyncService(modelContext: modelContext)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Club.name)
    private var clubs: [Club]

    @State private var clubsSyncService: ClubsSyncService?
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private let sourceURL = "https://activities.carrierwave.app"

    private func refresh() async {
        guard let service = clubsSyncService else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await service.syncClubs(sourceURL: sourceURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - ClubRow

struct ClubRow: View {
    let club: Club

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(club.name)
                .font(.body)
                .fontWeight(.medium)

            Text("\(club.memberCount) members")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubsListView()
    }
    .modelContainer(for: [Club.self, ClubMember.self], inMemory: true)
}
