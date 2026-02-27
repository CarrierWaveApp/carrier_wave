import SwiftData
import SwiftUI

// MARK: - ChallengesView

struct ChallengesView: View {
    // MARK: Internal

    let tourState: TourState

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if activeParticipations.isEmpty, completedParticipations.isEmpty {
                        emptyState
                    } else {
                        if !activeParticipations.isEmpty {
                            activeChallengesSection
                        }

                        if !completedParticipations.isEmpty {
                            completedChallengesSection
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refreshChallenges() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh challenges")
                }
            }
            .onAppear {
                if syncService == nil {
                    syncService = ActivitiesSyncService(modelContext: modelContext)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { showingError = false }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .sheet(isPresented: $showingInviteSheet) {
                if let invite = pendingInvite {
                    InviteJoinSheet(
                        invite: invite,
                        syncService: syncService,
                        isJoining: $isJoiningFromInvite,
                        onComplete: { success in
                            showingInviteSheet = false
                            pendingInvite = nil
                            if !success {
                                errorMessage = "Failed to join challenge"
                                showingError = true
                            }
                        }
                    )
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveChallengeInvite)
            ) { notification in
                handleInviteNotification(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didSyncQSOs)
            ) { _ in
                Task { await evaluateNewQSOs() }
            }
            .miniTour(.challenges, tourState: tourState)
        }
    }

    // MARK: Private

    @Query(sort: \ChallengeParticipation.joinedAt, order: .reverse)
    private var allParticipations: [ChallengeParticipation]

    @State private var syncService: ActivitiesSyncService?
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var showingError = false

    // Invite handling
    @State private var pendingInvite: PendingChallengeInvite?
    @State private var showingInviteSheet = false
    @State private var isJoiningFromInvite = false

    private var activeParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .active }
    }

    private var completedParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .completed }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.2.crossed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Active Challenges")
                .font(.headline)

            Text(
                "Browse available challenges to start tracking your progress toward awards and goals."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            NavigationLink {
                BrowseChallengesView()
            } label: {
                Text("Browse Challenges")
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 48)
    }

    // MARK: - Active Challenges Section

    private var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Challenges")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    BrowseChallengesView()
                } label: {
                    Text("Browse")
                        .font(.subheadline)
                }
            }

            ForEach(activeParticipations) { participation in
                NavigationLink {
                    ChallengeDetailView(participation: participation)
                } label: {
                    ChallengeProgressCard(participation: participation)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Completed Challenges Section

    private var completedChallengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed")
                .font(.headline)

            ForEach(completedParticipations) { participation in
                NavigationLink {
                    ChallengeDetailView(participation: participation)
                } label: {
                    CompletedChallengeCard(participation: participation)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func handleInviteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let source = userInfo["source"] as? String,
              let challengeId = userInfo["challengeId"] as? UUID
        else {
            return
        }

        let token = userInfo["token"] as? String

        pendingInvite = PendingChallengeInvite(
            sourceURL: source,
            challengeId: challengeId,
            token: token
        )
        showingInviteSheet = true
    }

    private func refreshChallenges() async {
        guard let syncService else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // Force update to ensure local data matches server (source of truth)
            try await syncService.refreshChallenges(forceUpdate: true)

            // Re-evaluate all QSOs against active participations
            // This ensures DXCC lookups and other progress calculations are current
            for participation in activeParticipations {
                syncService.progressEngine.reevaluateAllQSOs(for: participation)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func evaluateNewQSOs() async {
        // Use a fresh progress engine with current modelContext to avoid stale context issues
        // (e.g., after device sleep the cached syncService.progressEngine may have an invalid context)
        let engine = ChallengeProgressEngine(modelContext: modelContext)

        // Fetch all QSOs and evaluate against active challenges
        // The progress engine will handle deduplication internally
        var descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100

        do {
            let recentQSOs = try modelContext.fetch(descriptor)
            for qso in recentQSOs {
                engine.evaluateQSO(qso, notificationsEnabled: false)
            }
            try modelContext.save()
        } catch {
            // Silently fail - this is a background operation
        }
    }
}

// MARK: - CompletedChallengeCard

struct CompletedChallengeCard: View {
    let participation: ChallengeParticipation

    var body: some View {
        HStack(spacing: 12) {
            // Badge/Trophy icon
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text(participation.challengeName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let completedAt = participation.completedAt {
                    Text("Completed \(completedAt, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let tierName = participation.currentTierName {
                Text(tierName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - PendingChallengeInvite

struct PendingChallengeInvite {
    let sourceURL: String
    let challengeId: UUID
    let token: String?
}

// MARK: - InviteJoinSheet

struct InviteJoinSheet: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    let invite: PendingChallengeInvite
    let syncService: ActivitiesSyncService?
    @Binding var isJoining: Bool

    let onComplete: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading challenge...")
                } else if let error = loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("Failed to load challenge")
                            .font(.headline)

                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let dto = challengeDTO {
                    challengePreview(dto)
                }
            }
            .navigationTitle("Join Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete(false)
                    }
                }
            }
            .task {
                await loadChallenge()
            }
        }
    }

    // MARK: Private

    @State private var challengeDTO: ChallengeDefinitionDTO?
    @State private var isLoading = true
    @State private var loadError: String?

    private func challengePreview(_ dto: ChallengeDefinitionDTO) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(dto.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(dto.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(dto.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ChallengeTypeBadge(type: dto.type)

                if let items = dto.configuration.goals.items, !items.isEmpty {
                    Label(
                        "\(items.count) items",
                        systemImage: "square.grid.2x2"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await joinChallenge() }
            } label: {
                HStack {
                    if isJoining {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Join Challenge")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isJoining)
        }
        .padding()
    }

    private func loadChallenge() async {
        guard let syncService else {
            loadError = "Service not available"
            isLoading = false
            return
        }

        do {
            challengeDTO = try await syncService.client.fetchChallenge(
                id: invite.challengeId,
                from: invite.sourceURL
            )
            isLoading = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
        }
    }

    private func joinChallenge() async {
        guard let syncService, let dto = challengeDTO else {
            return
        }

        isJoining = true
        defer { isJoining = false }

        do {
            // First ensure we have a source for this URL
            let sources = try syncService.fetchEnabledSources()
            var source = sources.first { $0.url == invite.sourceURL }

            if source == nil {
                // Create an invite source
                let newSource = ChallengeSource(
                    type: .invite,
                    url: invite.sourceURL,
                    name: "Invite: \(dto.name)"
                )
                modelContext.insert(newSource)
                source = newSource
            }

            // Create the definition locally
            let definition = try ChallengeDefinition.from(dto: dto, source: source)
            modelContext.insert(definition)

            // Join via the sync service
            try await syncService.joinChallenge(definition, inviteToken: invite.token)

            onComplete(true)
        } catch {
            onComplete(false)
        }
    }
}

#Preview {
    ChallengesView(tourState: TourState())
        .modelContainer(
            for: [
                ChallengeSource.self,
                ChallengeDefinition.self,
                ChallengeParticipation.self,
            ], inMemory: true
        )
}
