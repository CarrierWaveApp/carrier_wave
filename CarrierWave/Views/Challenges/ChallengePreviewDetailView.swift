import SwiftData
import SwiftUI

// MARK: - ChallengePreviewDetailView

struct ChallengePreviewDetailView: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    let challenge: ChallengeDefinition
    let syncService: ActivitiesSyncService?

    @Query var participations: [ChallengeParticipation]

    var isJoined: Bool {
        participations.contains {
            $0.challengeDefinition?.id == challenge.id && $0.status != .left
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                descriptionSection
                if challenge.type == .collection {
                    goalsSection
                }
                tiersSection
                criteriaSection
                joinSection
            }
            .padding()
        }
        .navigationTitle(challenge.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if localSyncService == nil {
                localSyncService = syncService ?? ActivitiesSyncService(modelContext: modelContext)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { showingError = false }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
    }

    // MARK: Private

    @State private var localSyncService: ActivitiesSyncService?
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var showingError = false

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ChallengeTypeBadge(type: challenge.type)

                Spacer()

                if let timeRemaining = challenge.timeRemaining {
                    TimeRemainingBadge(seconds: timeRemaining)
                }
            }

            Text(challenge.author)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)

            Text(challenge.descriptionText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var goalsSection: some View {
        let goals = challenge.goals
        if !goals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Goals (\(goals.count))")
                    .font(.headline)

                ForEach(goals.prefix(10), id: \.id) { goal in
                    HStack {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(goal.name)
                            .font(.subheadline)
                        Spacer()
                    }
                }

                if goals.count > 10 {
                    Text("And \(goals.count - 10) more...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var tiersSection: some View {
        let tiers = challenge.sortedTiers
        if !tiers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tiers")
                    .font(.headline)

                ForEach(tiers, id: \.id) { tier in
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(tier.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(tier.threshold)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var criteriaSection: some View {
        let modes = challenge.criteria?.modes ?? []
        let bands = challenge.criteria?.bands ?? []
        if !modes.isEmpty || !bands.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Requirements")
                    .font(.headline)

                if !modes.isEmpty {
                    HStack {
                        Text("Modes:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(modes.joined(separator: ", "))
                            .font(.subheadline)
                    }
                }

                if !bands.isEmpty {
                    HStack {
                        Text("Bands:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(bands.joined(separator: ", "))
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var joinSection: some View {
        Group {
            if isJoined {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("You've joined this challenge")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button(action: joinChallenge) {
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
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isJoining)
            }
        }
    }

    private func joinChallenge() {
        let service = localSyncService ?? ActivitiesSyncService(modelContext: modelContext)
        if localSyncService == nil {
            localSyncService = service
        }

        isJoining = true

        Task { @MainActor in
            do {
                try await service.joinChallenge(challenge)
            } catch ActivitiesError.alreadyJoined {
                // Server says already joined - create local participation if missing
                createLocalParticipationIfNeeded()
            } catch {
                errorMessage = String(describing: error)
                showingError = true
            }
            isJoining = false
        }
    }

    private func createLocalParticipationIfNeeded() {
        // Check if we already have a local participation
        let hasLocal = participations.contains {
            $0.challengeDefinition?.id == challenge.id && $0.status != .left
        }

        guard !hasLocal else {
            return
        }

        // Create local participation since server says we're joined
        let callsign = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        let participation = ChallengeParticipation.join(
            challenge: challenge,
            userId: callsign,
            serverParticipationId: nil
        )
        modelContext.insert(participation)

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save participation: \(error)"
            showingError = true
        }
    }
}

#Preview {
    NavigationStack {
        Text("ChallengePreviewDetailView Preview")
    }
}
