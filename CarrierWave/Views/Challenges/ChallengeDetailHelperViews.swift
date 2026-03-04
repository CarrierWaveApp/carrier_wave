import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ProgressRing

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 8)

            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    progress >= 1 ? Color.green : Color.accentColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.headline)
        }
    }
}

// MARK: - LeaderboardEntryRow

struct LeaderboardEntryRow: View {
    // MARK: Internal

    let entry: LeaderboardEntry
    var currentUserCallsign: String?
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(entry.rank)")
                .font(compact ? .subheadline : .headline)
                .fontWeight(.bold)
                .foregroundStyle(rankColor)
                .frame(width: compact ? 30 : 40)

            // Callsign
            Text(entry.callsign)
                .font(compact ? .subheadline : .body)
                .fontWeight(isCurrentUser ? .bold : .regular)

            if isCurrentUser {
                Text("(You)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Score/Progress
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.score)")
                    .font(compact ? .subheadline : .body)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, compact ? 4 : 8)
        .padding(.horizontal, compact ? 0 : 12)
        .background(isCurrentUser ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var isCurrentUser: Bool {
        guard let currentUserCallsign else {
            return false
        }
        return entry.callsign.uppercased() == currentUserCallsign.uppercased()
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1: .yellow
        case 2: .gray
        case 3: .orange
        default: .primary
        }
    }
}

// MARK: - TierProgressView

struct TierProgressView: View {
    // MARK: Internal

    let tiers: [ChallengeTier]
    let participation: ChallengeParticipation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tiers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(tiers) { tier in
                let isAchieved = isTierAchieved(tier)
                HStack {
                    Image(systemName: isAchieved ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isAchieved ? .green : .secondary)
                    Text(tier.name)
                        .font(.subheadline)
                        .foregroundStyle(isAchieved ? .primary : .secondary)
                    Spacer()
                    Text("\(tier.threshold)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Private

    private func isTierAchieved(_ tier: ChallengeTier) -> Bool {
        let currentValue =
            participation.challengeType == .collection
                ? participation.completedGoalsCount
                : participation.progress.currentValue
        return currentValue >= tier.threshold
    }
}

// MARK: - DrilldownRow

struct DrilldownRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(text)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - GoalListView

struct GoalListView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    let participation: ChallengeParticipation
    let showCompleted: Bool

    var goals: [ChallengeGoal] {
        guard let definition = participation.challengeDefinition else {
            return []
        }
        let completedIds = Set(participation.progress.completedGoals)

        return definition.goals.filter { goal in
            let isCompleted = completedIds.contains(goal.id)
            return showCompleted ? isCompleted : !isCompleted
        }
    }

    var filteredGoals: [ChallengeGoal] {
        if searchText.isEmpty {
            return goals
        }
        return goals.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if showCompleted {
                Section {
                    Button {
                        Task {
                            await loadFirstQSOs()
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text(firstQSOByGoal.isEmpty ? "Load First QSOs" : "Reload First QSOs")
                        }
                    }
                    .disabled(isLoading)
                }
            }

            ForEach(filteredGoals) { goal in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.name)
                            .font(.body)
                        Text(goal.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if showCompleted, let qso = firstQSOByGoal[goal.id] {
                            HStack(spacing: 4) {
                                Text(qso.callsign)
                                    .fontWeight(.medium)
                                Text("on")
                                Text(qso.timestamp, style: .date)
                            }
                            .font(.caption)
                            .foregroundStyle(.blue)
                        }
                    }

                    Spacer()

                    if showCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search goals")
        .navigationTitle(showCompleted ? "Completed" : "Remaining")
    }

    // MARK: Private

    @State private var searchText = ""
    @State private var firstQSOByGoal: [String: QSO] = [:]
    @State private var isLoading = false

    @MainActor
    private func loadFirstQSOs() async {
        guard let definition = participation.challengeDefinition else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        // Yield to allow UI to update with spinner
        await Task.yield()

        let qualifyingIds = participation.progress.qualifyingQSOIds
        let qualifyingIdSet = Set(qualifyingIds)

        // Fetch only non-hidden QSOs with a cap to avoid unbounded full-table scan
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate { !$0.isHidden },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        descriptor.fetchLimit = max(qualifyingIdSet.count * 2, 1_000)

        do {
            let candidateQSOs = try modelContext.fetch(descriptor)
            let qualifyingQSOs = candidateQSOs.filter { qualifyingIdSet.contains($0.id) }

            var result: [String: QSO] = [:]
            for qso in qualifyingQSOs {
                let matchedGoals = ChallengeQSOMatcher.findMatchedGoals(
                    qso: qso,
                    definition: definition
                )
                for goalId in matchedGoals where result[goalId] == nil {
                    result[goalId] = qso
                }
            }
            firstQSOByGoal = result
        } catch {
            print("Failed to load QSOs: \(error)")
        }
    }
}

// MARK: - QualifyingQSOsView

struct QualifyingQSOsView: View {
    // MARK: Internal

    let participation: ChallengeParticipation

    var body: some View {
        List {
            ForEach(qualifyingQSOs) { qso in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(qso.callsign)
                            .font(.headline)
                        Spacer()
                        Text(qso.timestamp, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(qso.band)
                        Text(qso.mode)
                        if let state = qso.state {
                            Text(state)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Qualifying QSOs")
        .task {
            await loadQualifyingQSOs()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    /// QSOs fetched by ID (not using @Query to avoid full table scan)
    @State private var qualifyingQSOs: [QSO] = []

    /// Load only the qualifying QSOs by their IDs
    private func loadQualifyingQSOs() async {
        let ids = participation.progress.qualifyingQSOIds

        // Fetch QSOs with matching IDs
        // SwiftData doesn't support IN queries well, so we fetch all non-hidden
        // with a limit and filter in memory. The qualifying IDs list is typically small.
        guard !ids.isEmpty else {
            qualifyingQSOs = []
            return
        }

        let idSet = Set(ids)

        // For small ID sets, fetch a reasonable batch and filter
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { !$0.isHidden })
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .reverse)]

        // Limit fetch to avoid loading entire database
        // Challenge qualifying QSOs are typically under 1000
        descriptor.fetchLimit = max(idSet.count * 2, 1_000)

        guard let fetched = try? modelContext.fetch(descriptor) else {
            qualifyingQSOs = []
            return
        }

        qualifyingQSOs = fetched.filter { idSet.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
