import CarrierWaveData
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
                        "You're not a member of any clubs yet. "
                            + "Club membership is managed by club administrators."
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
        .task {
            await refreshQuietly()
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @Query(sort: \Club.name)
    private var clubs: [Club]

    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private let sourceURL = "https://activities.carrierwave.app"

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await ClubsSyncService.shared.syncClubs(sourceURL: sourceURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    /// Sync clubs on appear without showing errors (background refresh)
    private func refreshQuietly() async {
        try? await ClubsSyncService.shared.syncClubs(sourceURL: sourceURL)
    }
}

// MARK: - ClubRow

struct ClubRow: View {
    let club: Club

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(club.name)
                    .font(.body)
                    .fontWeight(.medium)
                if let callsign = club.callsign {
                    Text(callsign)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
