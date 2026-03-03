// Callsign Notes Settings View
//
// Allows users to manage callsign notes file sources.
// Sources are URLs to Polo-style notes files that get fetched and cached.

import SwiftData
import SwiftUI

// MARK: - RecommendedClubNotes

private struct RecommendedClubNotes: Identifiable {
    let club: Club
    let notesURL: String
    let notesTitle: String

    var id: UUID {
        club.serverId
    }
}

// MARK: - CallsignNotesSettingsView

struct CallsignNotesSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if !recommendedClubs.isEmpty {
                recommendedSection
            }

            if sources.isEmpty {
                emptySection
            } else {
                sourcesSection
            }

            addSection
        }
        .task {
            loadRecommendations()
        }
        .navigationTitle("Callsign Notes")
        .sheet(isPresented: $showAddSheet) {
            AddCallsignNotesSourceSheet { title, url in
                addSource(title: title, url: url)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CallsignNotesSource.title) private var sources: [CallsignNotesSource]

    @State private var showAddSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isRefreshing = false
    @State private var recommendedClubs: [RecommendedClubNotes] = []

    // MARK: - Sections

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.title)
                    .foregroundStyle(.secondary)

                Text("No Notes Sources")
                    .font(.headline)

                Text("Add URLs to Polo-style notes files to see callsign info during logging.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var sourcesSection: some View {
        Section {
            ForEach(sources) { source in
                sourceRow(source)
            }
            .onDelete(perform: deleteSources)
        } header: {
            Text("Sources")
        } footer: {
            Text("Sources are refreshed automatically every 24 hours.")
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showAddSheet = true
            } label: {
                Label("Add Source", systemImage: "plus.circle")
            }

            if !sources.isEmpty {
                Button {
                    Task { await refreshAllSources() }
                } label: {
                    HStack {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isRefreshing)
            }
        }
    }

    // MARK: - Recommended Section

    private var recommendedSection: some View {
        Section {
            ForEach(recommendedClubs) { rec in
                recommendedRow(rec)
            }
        } header: {
            Text("Recommended")
        }
    }

    private func recommendedRow(_ rec: RecommendedClubNotes) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.notesTitle)
                    .font(.body)
                if rec.notesTitle != rec.club.name {
                    Text(rec.club.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Add") {
                addSource(title: rec.notesTitle, url: rec.notesURL)
                recommendedClubs.removeAll { $0.id == rec.id }
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }

    // MARK: - Source Row

    private func sourceRow(_ source: CallsignNotesSource) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sourceHeaderRow(source)

            Text(source.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            sourceStatusRow(source)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                deleteSource(source)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                Task { await refreshSource(source) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(.blue)
        }
    }

    private func sourceHeaderRow(_ source: CallsignNotesSource) -> some View {
        HStack {
            Text(source.title)
                .font(.body)

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { source.isEnabled },
                    set: { newValue in
                        source.isEnabled = newValue
                        try? modelContext.save()
                        CallsignNotesSourceSync.mirrorToDefaults(
                            modelContext: modelContext
                        )
                    }
                )
            )
            .labelsHidden()
        }
    }

    private func sourceStatusRow(_ source: CallsignNotesSource) -> some View {
        HStack(spacing: 8) {
            if let error = source.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if source.entryCount > 0 {
                Text("\(source.entryCount) callsigns")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }

            if let lastFetched = source.lastFetchedDescription {
                Text("Updated \(lastFetched)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadRecommendations() {
        let descriptor = FetchDescriptor<Club>(
            predicate: #Predicate<Club> { $0.notesURL != nil }
        )
        guard let clubs = try? modelContext.fetch(descriptor) else {
            return
        }

        let existingURLs = Set(sources.map(\.url))
        recommendedClubs = clubs.compactMap { club in
            guard let url = club.notesURL, !existingURLs.contains(url) else {
                return nil
            }
            let title = club.notesTitle ?? club.name
            return RecommendedClubNotes(club: club, notesURL: url, notesTitle: title)
        }
    }

    private func addSource(title: String, url: String) {
        let source = CallsignNotesSource(title: title, url: url)
        modelContext.insert(source)

        do {
            try modelContext.save()
            CallsignNotesSourceSync.mirrorToDefaults(modelContext: modelContext)
            // Trigger initial fetch
            Task { await refreshSource(source) }
        } catch {
            errorMessage = "Failed to save source: \(error.localizedDescription)"
            showError = true
        }
    }

    private func deleteSource(_ source: CallsignNotesSource) {
        modelContext.delete(source)
        try? modelContext.save()
        CallsignNotesSourceSync.mirrorToDefaults(modelContext: modelContext)
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sources[index])
        }
        try? modelContext.save()
        CallsignNotesSourceSync.mirrorToDefaults(modelContext: modelContext)
    }

    private func refreshSource(_ source: CallsignNotesSource) async {
        guard let url = URL(string: source.url) else {
            await MainActor.run {
                source.lastError = "Invalid URL"
                try? modelContext.save()
            }
            return
        }

        do {
            let entries = try await PoloNotesParser.load(from: url)

            await MainActor.run {
                source.entryCount = entries.count
                source.lastFetched = Date()
                source.lastError = nil
                try? modelContext.save()
            }
        } catch {
            await MainActor.run {
                source.lastError = error.localizedDescription
                try? modelContext.save()
            }
        }
    }

    private func refreshAllSources() async {
        isRefreshing = true
        defer { isRefreshing = false }

        for source in sources where source.isEnabled {
            await refreshSource(source)
        }

        // Force the in-memory/disk cache to re-download and re-parse
        let notesSources = NotesSourceInfo.fetchAll(modelContext: modelContext)
        try? await CallsignNotesCache.shared.forceRefresh(sources: notesSources)
    }
}

// MARK: - AddCallsignNotesSourceSheet

struct AddCallsignNotesSourceSheet: View {
    // MARK: Internal

    let onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)

                    TextField("URL", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text(
                        "Enter a URL to a Polo-style notes file. "
                            + "Each line should have a callsign followed by optional emoji and note text."
                    )
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(
                            title.trimmingCharacters(in: .whitespaces),
                            url.trimmingCharacters(in: .whitespaces)
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .landscapeAdaptiveDetents(portrait: [.medium])
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var url = ""

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !url.trimmingCharacters(in: .whitespaces).isEmpty
            && URL(string: url.trimmingCharacters(in: .whitespaces)) != nil
    }
}

#Preview {
    NavigationStack {
        CallsignNotesSettingsView()
    }
    .modelContainer(for: CallsignNotesSource.self, inMemory: true)
}
