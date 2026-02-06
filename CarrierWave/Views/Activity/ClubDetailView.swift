import SwiftData
import SwiftUI

// MARK: - ClubDetailView

struct ClubDetailView: View {
    // MARK: Internal

    let club: Club

    var body: some View {
        List {
            if let description = club.descriptionText, !description.isEmpty {
                Section("About") {
                    Text(description)
                        .font(.body)
                }
            }

            Section("Members (\(club.memberCount))") {
                if club.memberCallsigns.isEmpty {
                    Text("No members loaded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(club.memberCallsigns, id: \.self) { callsign in
                        MemberRow(callsign: callsign)
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
            try await service.syncClubDetails(clubId: club.id, sourceURL: sourceURL)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - MemberRow

struct MemberRow: View {
    let callsign: String

    var body: some View {
        HStack {
            Text(callsign)
                .font(.body)
                .fontWeight(.medium)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClubDetailView(
            club: Club(
                name: "Pacific Northwest DX Club",
                poloNotesListURL: "https://example.com",
                descriptionText: "A club for DXers in the Pacific Northwest"
            )
        )
    }
    .modelContainer(for: [Club.self], inMemory: true)
}
