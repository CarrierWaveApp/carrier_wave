import SwiftData
import SwiftUI

// MARK: - ChallengeDetailView

struct ChallengeDetailView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    let participation: ChallengeParticipation

    var definition: ChallengeDefinition? {
        participation.challengeDefinition
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                progressSection
                if participation.isActive {
                    leaderboardSection
                }
                drilldownSection
                if participation.isActive {
                    actionsSection
                }
            }
            .padding()
        }
        .navigationTitle(participation.challengeName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if syncService == nil {
                syncService = ActivitiesSyncService(modelContext: modelContext)
            }
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
        .alert("Leave Challenge", isPresented: $showingLeaveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task { await leaveChallenge() }
            }
        } message: {
            Text(
                "Are you sure you want to leave this challenge? "
                    + "Your progress will be removed from the leaderboard."
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @State private var syncService: ActivitiesSyncService?
    @State private var leaderboardEntries: [LeaderboardEntry] = []
    @State private var isLoadingLeaderboard = false
    @State private var showingLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var isReevaluating = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var pollingTask: Task<Void, Never>?

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let definition {
                Text(definition.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label(definition.author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let timeRemaining = definition.timeRemaining {
                        TimeRemainingBadge(seconds: timeRemaining)
                    }
                }
            }

            if participation.isComplete {
                completedBanner
            }
        }
    }

    private var completedBanner: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("Completed")
                .fontWeight(.medium)
            if let completedAt = participation.completedAt {
                Text("on \(completedAt, style: .date)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)

            HStack(spacing: 24) {
                ProgressRing(progress: participation.progressPercentage / 100)
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 8) {
                    Text(participation.progressDisplayString)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(String(format: "%.1f%% complete", participation.progressPercentage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let tierName = participation.currentTierName {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(tierName)
                        }
                        .font(.subheadline)
                    }
                }

                Spacer()
            }

            if let tiers = definition?.sortedTiers, !tiers.isEmpty {
                TierProgressView(tiers: tiers, participation: participation)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Leaderboard Section

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Leaderboard")
                    .font(.headline)

                Spacer()

                if isLoadingLeaderboard {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                NavigationLink {
                    if let definition {
                        LeaderboardView(
                            definition: definition,
                            entries: leaderboardEntries,
                            currentUserCallsign: participation.userId
                        )
                    }
                } label: {
                    Text("View All")
                        .font(.subheadline)
                }
            }

            if leaderboardEntries.isEmpty {
                Text("No participants yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(leaderboardEntries.prefix(5)) { entry in
                    LeaderboardEntryRow(
                        entry: entry,
                        currentUserCallsign: participation.userId,
                        compact: true
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Drilldown Section

    private var drilldownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.headline)

            if let definition, definition.type == .collection {
                collectionDrilldownLinks
            }

            qualifyingQSOsLink
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var collectionDrilldownLinks: some View {
        Group {
            NavigationLink {
                GoalListView(participation: participation, showCompleted: true)
            } label: {
                DrilldownRow(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "Completed (\(participation.completedGoalsCount))"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                GoalListView(participation: participation, showCompleted: false)
            } label: {
                DrilldownRow(
                    icon: "circle",
                    iconColor: .secondary,
                    text: "Remaining (\(participation.remainingGoals))"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var qualifyingQSOsLink: some View {
        NavigationLink {
            QualifyingQSOsView(participation: participation)
        } label: {
            DrilldownRow(
                icon: "list.bullet",
                iconColor: Color.accentColor,
                text: "Qualifying QSOs (\(participation.progress.qualifyingQSOIds.count))"
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await reevaluateProgress() }
            } label: {
                HStack {
                    if isReevaluating {
                        ProgressView()
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Re-evaluate QSOs")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isReevaluating)

            Button(role: .destructive) {
                showingLeaveConfirmation = true
            } label: {
                HStack {
                    if isLeaving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "xmark.circle")
                    }
                    Text("Leave Challenge")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isLeaving)
        }
    }
}

// MARK: - ChallengeDetailView Actions

extension ChallengeDetailView {
    func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchLeaderboard()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func fetchLeaderboard() async {
        guard let syncService, let definition else {
            return
        }

        isLoadingLeaderboard = true
        defer { isLoadingLeaderboard = false }

        do {
            leaderboardEntries = try await syncService.fetchLeaderboard(for: definition)
        } catch {
            // Silently fail for leaderboard polling
        }
    }

    func leaveChallenge() async {
        guard let syncService else {
            return
        }

        isLeaving = true
        defer { isLeaving = false }

        do {
            try await syncService.leaveChallenge(participation)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    func reevaluateProgress() async {
        guard let syncService else {
            return
        }

        isReevaluating = true
        defer { isReevaluating = false }

        syncService.progressEngine.reevaluateAllQSOs(for: participation)

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    Text("ChallengeDetailView Preview")
}
