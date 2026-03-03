import SwiftData
import SwiftUI

// MARK: - ClubDetailView

struct ClubDetailView: View {
    // MARK: Internal

    let club: Club

    var body: some View {
        List {
            if let description = club.clubDescription, !description.isEmpty {
                Section("About") {
                    Text(description)
                        .font(.body)
                }
            }

            Section("Members (\(club.memberCount))") {
                if club.members.isEmpty {
                    Text("No members loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(club.members, id: \.callsign) { member in
                        MemberRow(member: member)
                    }
                }
            }
        }
        .navigationTitle(club.name)
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
            try await service.syncClubDetails(
                clubId: club.serverId,
                sourceURL: sourceURL
            )
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - MemberRow

struct MemberRow: View {
    let member: ClubMember

    var body: some View {
        HStack {
            Text(member.callsign)
                .font(.body)
                .fontWeight(.medium)
            Spacer()
            if member.role != "member" {
                Text(member.role.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubDetailView(
            club: Club(
                serverId: UUID(),
                name: "Pacific Northwest DX Club",
                clubDescription: "A club for DXers in the Pacific Northwest"
            )
        )
    }
    .modelContainer(for: [Club.self, ClubMember.self], inMemory: true)
}
