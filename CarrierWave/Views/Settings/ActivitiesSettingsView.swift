import SwiftData
import SwiftUI

// MARK: - ActivitiesSettingsView

struct ActivitiesSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                Toggle("Enable community features", isOn: $activitiesEnabled)
                    .onChange(of: activitiesEnabled) { _, enabled in
                        handleActivitiesToggle(enabled: enabled)
                    }
            } header: {
                Text("Community")
            } footer: {
                Text(
                    "When enabled, your callsign is discoverable in friend search "
                        + "and you can participate in challenges and clubs."
                )
            }

            Section {
                HStack {
                    Text("Callsign")
                    Spacer()
                    Text(stationCallsign.isEmpty ? "Not Set" : stationCallsign)
                        .foregroundStyle(stationCallsign.isEmpty ? .secondary : .primary)
                }
            } header: {
                Text("Your Station")
            } footer: {
                Text("Uses your station callsign from Logger settings.")
            }

            Section {
                ForEach(sources) { source in
                    if source.isOfficial {
                        sourceRow(source)
                    } else {
                        Button {
                            editingSource = source
                        } label: {
                            sourceRow(source)
                        }
                        .tint(.primary)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteSource(source)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    showingAddSource = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            } header: {
                Text("Activity Servers")
            } footer: {
                Text("Activity servers host competitions and track leaderboards.")
            }
        }
        .navigationTitle("Activities")
        .onAppear {
            if syncService == nil {
                syncService = ActivitiesSyncService(modelContext: modelContext)
            }
            Task {
                await ensureOfficialSource()
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddChallengeServerSheet(syncService: syncService)
        }
        .sheet(item: $editingSource) { source in
            EditChallengeServerSheet(source: source)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @AppStorage("loggerDefaultCallsign") private var stationCallsign = ""
    @AppStorage("activitiesServerEnabled") private var activitiesEnabled = false

    @Query(sort: \ChallengeSource.name) private var sources: [ChallengeSource]

    @State private var syncService: ActivitiesSyncService?
    @State private var showingAddSource = false
    @State private var editingSource: ChallengeSource?
    @State private var showingError = false
    @State private var errorMessage = ""

    private let activitiesSourceURL = "https://activities.carrierwave.app"

    private func sourceRow(_ source: ChallengeSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(source.name)
                        .font(.body)

                    if source.isOfficial {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Text(source.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let error = source.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            } else if source.lastFetched != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func deleteSource(_ source: ChallengeSource) {
        guard !source.isOfficial else {
            errorMessage = "Cannot remove the official activity server"
            showingError = true
            return
        }
        modelContext.delete(source)
        try? modelContext.save()
    }

    private func ensureOfficialSource() async {
        guard let syncService else {
            return
        }

        do {
            _ = try syncService.getOrCreateOfficialSource()
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func handleActivitiesToggle(enabled: Bool) {
        if enabled {
            let client = ActivitiesClient()
            guard !client.hasAuthToken(), !stationCallsign.isEmpty else {
                return
            }
            Task {
                do {
                    _ = try await client.register(
                        callsign: stationCallsign.uppercased(),
                        deviceName: UIDevice.current.name,
                        sourceURL: activitiesSourceURL
                    )
                } catch {
                    errorMessage = "Registration failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        } else {
            ActivitiesClient().clearAuthToken()
        }
    }
}

// MARK: - AddChallengeServerSheet

struct AddChallengeServerSheet: View {
    // MARK: Internal

    let syncService: ActivitiesSyncService?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $url)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Display Name", text: $name)
                } footer: {
                    Text("Enter the URL of a community activity server.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSource()
                    }
                    .disabled(url.isEmpty || name.isEmpty || isAdding)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var name = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    private func addSource() {
        guard let syncService else {
            return
        }

        isAdding = true
        errorMessage = nil

        do {
            _ = try syncService.addCommunitySource(url: url, name: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
        }
    }
}

// MARK: - EditChallengeServerSheet

struct EditChallengeServerSheet: View {
    // MARK: Internal

    let source: ChallengeSource

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $url)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Display Name", text: $name)
                } footer: {
                    Text("Update the server URL or display name.")
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete Server")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(url.isEmpty || name.isEmpty)
                }
            }
            .onAppear {
                url = source.url
                name = source.name
            }
            .alert("Delete Server", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(source)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(source.name)\"? This cannot be undone.")
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var url = ""
    @State private var name = ""
    @State private var showingDeleteConfirmation = false

    private func saveChanges() {
        source.url = url
        source.name = name
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ActivitiesSettingsView()
    }
    .modelContainer(for: ChallengeSource.self, inMemory: true)
}
