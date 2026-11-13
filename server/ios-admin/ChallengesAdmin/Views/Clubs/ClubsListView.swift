import SwiftUI

// MARK: - ClubsListView

struct ClubsListView: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    ErrorBanner(message: error)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                ForEach(clubs) { club in
                    NavigationLink(destination: ClubDetailView(club: club)) {
                        ClubRow(club: club)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            clubToDelete = club
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Clubs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await loadClubs() }
            .task { await loadClubs() }
            .overlay {
                if isLoading, clubs.isEmpty {
                    ProgressView()
                } else if clubs.isEmpty, error == nil {
                    ContentUnavailableView(
                        "No Clubs",
                        systemImage: "person.3",
                        description: Text("Create a club to get started.")
                    )
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                CreateClubSheet { await loadClubs() }
            }
            .alert("Delete Club?", isPresented: .init(
                get: { clubToDelete != nil },
                set: {
                    if !$0 {
                        clubToDelete = nil
                    }
                }
            )) {
                Button("Cancel", role: .cancel) { clubToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let club = clubToDelete {
                        Task { await deleteClub(club) }
                    }
                }
            } message: {
                if let club = clubToDelete {
                    Text("This will permanently delete \"\(club.name)\" and remove all members.")
                }
            }
        }
    }

    // MARK: Private

    @State private var clubs: [ClubAdminResponse] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingCreateSheet = false
    @State private var clubToDelete: ClubAdminResponse?

    private var api: APIClient {
        APIClient(config: config)
    }

    private func loadClubs() async {
        isLoading = true
        error = nil
        do {
            clubs = try await api.getClubs()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteClub(_ club: ClubAdminResponse) async {
        do {
            try await api.deleteClub(id: club.id)
            clubs.removeAll { $0.id == club.id }
        } catch {
            self.error = error.localizedDescription
        }
        clubToDelete = nil
    }
}

// MARK: - ClubRow

struct ClubRow: View {
    let club: ClubAdminResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(club.name)
                    .font(.headline)
                Spacer()
                Label("\(club.memberCount)", systemImage: "person.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let callsign = club.callsign, !callsign.isEmpty {
                Text(callsign)
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                    .fontDesign(.monospaced)
            }
            if let desc = club.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - CreateClubSheet

struct CreateClubSheet: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let onCreated: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Club Name", text: $name)
                    TextField("Callsign (optional)", text: $callsign)
                        .textInputAutocapitalization(.characters)
                        .fontDesign(.monospaced)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("New Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createClub() }
                    }
                    .disabled(name.isEmpty || isSubmitting)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var callsign = ""
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private func createClub() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        let request = CreateClubRequest(
            name: name,
            callsign: callsign.isEmpty ? nil : callsign,
            description: description.isEmpty ? nil : description
        )
        do {
            _ = try await api.createClub(request)
            await onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
