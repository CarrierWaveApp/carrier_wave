import SwiftUI

// MARK: - ClubDetailView

struct ClubDetailView: View {
    // MARK: Lifecycle

    init(club: ClubAdminResponse) {
        _club = State(initialValue: club)
    }

    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    var body: some View {
        List {
            clubInfoSection
            membersSection
        }
        .navigationTitle(club.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Club", systemImage: "pencil")
                    }
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                    }
                    if club.notesUrl != nil {
                        Button {
                            Task { await importFromNotes() }
                        } label: {
                            Label("Import from Notes", systemImage: "square.and.arrow.down")
                        }
                        .disabled(isImporting)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .refreshable { await loadMembers() }
        .task { await loadMembers() }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(clubId: club.id) { await loadMembers() }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditClubSheet(club: club) { updated in
                club = updated
            }
        }
        .alert("Import Notes", isPresented: .init(
            get: { importResult != nil },
            set: {
                if !$0 {
                    importResult = nil
                }
            }
        )) {
            Button("OK") { importResult = nil }
        } message: {
            if let result = importResult {
                Text(result)
            }
        }
    }

    // MARK: Private

    @State private var club: ClubAdminResponse

    @State private var members: [ClubMemberAdminResponse] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingAddMember = false
    @State private var showingEditSheet = false
    @State private var isImporting = false
    @State private var importResult: String?

    private var api: APIClient {
        APIClient(config: config)
    }

    private var clubInfoSection: some View {
        Section("Details") {
            if let callsign = club.callsign, !callsign.isEmpty {
                LabeledContent("Callsign") {
                    Text(callsign)
                        .fontDesign(.monospaced)
                }
            }
            if let desc = club.description, !desc.isEmpty {
                LabeledContent("Description") {
                    Text(desc)
                }
            }
            LabeledContent("Members") {
                Text("\(club.memberCount)")
                    .fontDesign(.monospaced)
            }
            if let createdAt = club.createdAt {
                LabeledContent("Created") {
                    Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if let notesUrl = club.notesUrl, !notesUrl.isEmpty {
                LabeledContent("Notes") {
                    Text(club.notesTitle ?? notesUrl)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private var membersSection: some View {
        Section("Members (\(members.count))") {
            if isLoading, members.isEmpty {
                ProgressView()
            }

            ForEach(members) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.callsign)
                            .font(.headline)
                            .fontDesign(.monospaced)
                        Text("Joined \(member.joinedAt.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    RoleBadge(role: member.role)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await removeMember(member) }
                    } label: {
                        Label("Remove", systemImage: "person.badge.minus")
                    }
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func loadMembers() async {
        isLoading = true
        do {
            members = try await api.getClubMembers(clubId: club.id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func importFromNotes() async {
        isImporting = true
        do {
            let result = try await api.importNotesMembers(clubId: club.id)
            if result.imported > 0 {
                let plural = result.imported == 1 ? "" : "s"
                importResult = "Imported \(result.imported) member\(plural) (\(result.skipped) already existed)"
                await loadMembers()
            } else {
                importResult = "No new members to import (\(result.skipped) already existed)"
            }
        } catch {
            self.error = error.localizedDescription
        }
        isImporting = false
    }

    private func removeMember(_ member: ClubMemberAdminResponse) async {
        do {
            try await api.removeClubMember(clubId: club.id, callsign: member.callsign)
            members.removeAll { $0.callsign == member.callsign }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - RoleBadge

struct RoleBadge: View {
    let role: String

    var color: Color {
        switch role.lowercased() {
        case "admin": .red
        case "moderator": .orange
        default: .secondary
        }
    }

    var body: some View {
        Text(role.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - AddMemberSheet

struct AddMemberSheet: View {
    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let clubId: String
    let onAdded: () async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Callsign", text: $callsign)
                        .textInputAutocapitalization(.characters)
                        .fontDesign(.monospaced)

                    Picker("Role", selection: $role) {
                        Text("Member").tag("member")
                        Text("Admin").tag("admin")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await addMember() }
                    }
                    .disabled(callsign.isEmpty || isSubmitting)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var callsign = ""
    @State private var role = "member"
    @State private var isSubmitting = false
    @State private var error: String?

    private func addMember() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        do {
            try await api.addClubMembers(
                clubId: clubId,
                members: [AddMemberEntry(callsign: callsign.uppercased(), role: role)]
            )
            await onAdded()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - EditClubSheet

struct EditClubSheet: View {
    // MARK: Lifecycle

    init(club: ClubAdminResponse, onSaved: @escaping (ClubAdminResponse) -> Void) {
        self.club = club
        self.onSaved = onSaved
        _name = State(initialValue: club.name)
        _callsign = State(initialValue: club.callsign ?? "")
        _description = State(initialValue: club.description ?? "")
        _notesUrl = State(initialValue: club.notesUrl ?? "")
        _notesTitle = State(initialValue: club.notesTitle ?? "")
    }

    // MARK: Internal

    @EnvironmentObject var config: ServerConfig

    let club: ClubAdminResponse
    let onSaved: (ClubAdminResponse) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Callsign", text: $callsign)
                        .textInputAutocapitalization(.characters)
                        .fontDesign(.monospaced)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                Section("Notes") {
                    TextField("Notes URL", text: $notesUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    TextField("Notes Title", text: $notesTitle)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Edit Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.isEmpty || isSubmitting)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var callsign: String
    @State private var description: String
    @State private var notesUrl: String
    @State private var notesTitle: String
    @State private var isSubmitting = false
    @State private var error: String?

    private func save() async {
        isSubmitting = true
        error = nil
        let api = APIClient(config: config)
        let request = UpdateClubRequest(
            name: name,
            callsign: callsign.isEmpty ? .null : .value(callsign),
            description: description.isEmpty ? .null : .value(description),
            notesUrl: notesUrl.isEmpty ? .null : .value(notesUrl),
            notesTitle: notesTitle.isEmpty ? .null : .value(notesTitle)
        )
        do {
            let updated = try await api.updateClub(id: club.id, request)
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
