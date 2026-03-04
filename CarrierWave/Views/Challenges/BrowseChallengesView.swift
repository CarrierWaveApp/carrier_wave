import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - BrowseChallengesView

struct BrowseChallengesView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    @Query(sort: \ChallengeSource.name) var sources: [ChallengeSource]
    @Query(sort: \ChallengeDefinition.name) var allChallenges: [ChallengeDefinition]

    var displayedChallenges: [ChallengeDefinition] {
        if let selectedSource {
            return allChallenges.filter { $0.source?.id == selectedSource.id }
        }
        return allChallenges
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sourceSelector
                challengesList
            }
            .padding()
        }
        .navigationTitle("Browse Challenges")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddSource = true
                    } label: {
                        Label("Add Community Source", systemImage: "plus")
                    }

                    Button {
                        Task { await refreshAll() }
                    } label: {
                        Label("Refresh All", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if syncService == nil {
                syncService = ActivitiesSyncService(modelContext: modelContext)
            }
            Task {
                await ensureOfficialSource()
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceSheet(syncService: syncService)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @State private var syncService: ActivitiesSyncService?
    @State private var selectedSource: ChallengeSource?
    @State private var isRefreshing = false
    @State private var showingAddSource = false
    @State private var errorMessage: String?
    @State private var showingError = false

    // MARK: - Source Selector

    private var sourceSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                SourcePill(
                    name: "All",
                    isSelected: selectedSource == nil
                ) {
                    selectedSource = nil
                }

                ForEach(sources) { source in
                    SourcePill(
                        name: source.name,
                        isOfficial: source.isOfficial,
                        isSelected: selectedSource?.id == source.id
                    ) {
                        selectedSource = source
                    }
                }
            }
        }
    }

    // MARK: - Challenges List

    private var challengesList: some View {
        VStack(spacing: 12) {
            if displayedChallenges.isEmpty {
                emptyState
            } else {
                ForEach(displayedChallenges) { challenge in
                    NavigationLink {
                        ChallengePreviewDetailView(
                            challenge: challenge,
                            syncService: syncService
                        )
                    } label: {
                        ChallengePreviewCard(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No challenges found")
                .font(.headline)

            if isRefreshing {
                ProgressView("Loading...")
            } else {
                Button("Refresh") {
                    Task { await refreshAll() }
                }
            }
        }
        .padding(.vertical, 48)
    }

    private func ensureOfficialSource() async {
        guard let syncService else {
            return
        }

        do {
            _ = try syncService.getOrCreateOfficialSource()
            try modelContext.save()

            // Refresh if no challenges yet
            if allChallenges.isEmpty {
                await refreshAll()
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func refreshAll() async {
        guard let syncService else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // Force update to ensure local data matches server (source of truth)
            try await syncService.refreshChallenges(forceUpdate: true)
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - SourcePill

struct SourcePill: View {
    let name: String
    var isOfficial: Bool = false
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(name)
                if isOfficial {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

// MARK: - ChallengePreviewCard

struct ChallengePreviewCard: View {
    let challenge: ChallengeDefinition

    @Query var participations: [ChallengeParticipation]

    var isJoined: Bool {
        participations.contains {
            $0.challengeDefinition?.id == challenge.id && $0.status != .left
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.name)
                        .font(.headline)

                    Text(challenge.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ChallengeTypeBadge(type: challenge.type)
            }

            // Description
            Text(challenge.descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Stats row
            HStack {
                if challenge.type == .collection {
                    Label("\(challenge.totalGoals) items", systemImage: "square.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !challenge.tiers.isEmpty {
                    Label("\(challenge.tiers.count) tiers", systemImage: "star")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let timeRemaining = challenge.timeRemaining {
                    TimeRemainingBadge(seconds: timeRemaining)
                }

                Spacer()

                // Status indicator
                if isJoined {
                    Label("Joined", systemImage: "checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ChallengeTypeBadge

struct ChallengeTypeBadge: View {
    // MARK: Internal

    let type: ChallengeType

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: Private

    private var label: String {
        switch type {
        case .collection: "Collection"
        case .cumulative: "Cumulative"
        case .timeBounded: "Time-Limited"
        }
    }

    private var color: Color {
        switch type {
        case .collection: .blue
        case .cumulative: .purple
        case .timeBounded: .orange
        }
    }
}

// MARK: - AddSourceSheet

struct AddSourceSheet: View {
    // MARK: Internal

    @Environment(\.dismiss) var dismiss

    let syncService: ActivitiesSyncService?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Source URL", text: $url)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    TextField("Name", text: $name)
                } header: {
                    Text("Community Source")
                } footer: {
                    Text("Enter the URL of a community challenge server.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
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
                        addSource()
                    }
                    .disabled(url.isEmpty || name.isEmpty || isAdding)
                }
            }
        }
    }

    // MARK: Private

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

#Preview {
    NavigationStack {
        BrowseChallengesView()
    }
    .modelContainer(
        for: [
            ChallengeSource.self,
            ChallengeDefinition.self,
            ChallengeParticipation.self,
        ], inMemory: true
    )
}
