import CarrierWaveData
import Foundation
import SwiftData

// MARK: - ChallengeProgressEngine

@MainActor
final class ChallengeProgressEngine {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    /// Evaluate a single QSO against all active challenge participations
    func evaluateQSO(_ qso: QSO, notificationsEnabled: Bool = true) {
        let participations = fetchActiveParticipations()

        for participation in participations {
            evaluateQSO(qso, against: participation, notificationsEnabled: notificationsEnabled)
        }
    }

    /// Evaluate a QSO against a specific participation
    func evaluateQSO(
        _ qso: QSO,
        against participation: ChallengeParticipation,
        notificationsEnabled: Bool = true
    ) {
        guard let definition = participation.challengeDefinition else {
            return
        }
        guard participation.isActive else {
            return
        }

        // Check if historical QSOs are allowed
        if !definition.historicalQSOsAllowed, qso.timestamp < participation.joinedAt {
            return
        }

        // Check qualification criteria
        guard ChallengeQSOMatcher.qsoMatchesCriteria(qso, criteria: definition.criteria) else {
            return
        }

        // Check time constraints
        guard
            ChallengeQSOMatcher.qsoWithinTimeConstraints(
                qso,
                constraints: definition.timeConstraints
            )
        else {
            return
        }

        // Apply match rules to find matched goals
        let matchedGoals = ChallengeQSOMatcher.findMatchedGoals(qso: qso, definition: definition)

        guard !matchedGoals.isEmpty else {
            return
        }

        // Update progress
        let (updatedProgress, newMatches) = applyMatchedGoals(
            matchedGoals,
            qso: qso,
            participation: participation,
            definition: definition
        )
        participation.progress = updatedProgress

        // Check tier advancement
        let previousTier = participation.currentTier
        evaluateTierAdvancement(participation)

        // Check for completion
        if isComplete(participation: participation, definition: definition) {
            participation.status = .completed
            participation.completedAt = Date()
        }

        // Trigger notifications if enabled
        if notificationsEnabled, !newMatches.isEmpty {
            notifyProgress(
                participation: participation,
                newMatches: newMatches,
                tierAdvanced: participation.currentTier != previousTier
            )
        }
    }

    /// Evaluate all historical QSOs for a newly joined participation
    func evaluateHistoricalQSOs(for participation: ChallengeParticipation) {
        guard let definition = participation.challengeDefinition else {
            return
        }
        guard definition.historicalQSOsAllowed else {
            return
        }

        let qsos = fetchAllQSOs()

        for qso in qsos {
            evaluateQSO(qso, against: participation, notificationsEnabled: false)
        }

        // Send a single summary notification
        if !participation.progress.completedGoals.isEmpty {
            notifyHistoricalEvaluation(participation)
        }
    }

    /// Re-evaluate all QSOs for a participation (e.g., after challenge update)
    func reevaluateAllQSOs(for participation: ChallengeParticipation) {
        // Reset progress
        var progress = ChallengeProgress()
        progress.lastUpdated = Date()
        participation.progress = progress
        participation.currentTier = nil
        participation.status = .active
        participation.completedAt = nil

        // Re-evaluate all qualifying QSOs
        evaluateHistoricalQSOs(for: participation)
    }

    // MARK: Private

    private let modelContext: ModelContext

    private func applyMatchedGoals(
        _ matchedGoals: [String],
        qso: QSO,
        participation: ChallengeParticipation,
        definition: ChallengeDefinition
    ) -> (ChallengeProgress, [String]) {
        var progress = participation.progress
        var newMatches: [String] = []

        for goalId in matchedGoals where !progress.completedGoals.contains(goalId) {
            progress.completedGoals.append(goalId)
            newMatches.append(goalId)
        }

        if definition.type == .cumulative || definition.type == .timeBounded {
            progress.currentValue += 1
        }

        if !progress.qualifyingQSOIds.contains(qso.id) {
            progress.qualifyingQSOIds.append(qso.id)
        }

        progress = updateProgressMetrics(progress, for: definition)
        progress.lastUpdated = Date()

        return (progress, newMatches)
    }

    // MARK: - Progress Metrics

    private func updateProgressMetrics(
        _ progress: ChallengeProgress,
        for definition: ChallengeDefinition
    ) -> ChallengeProgress {
        var updated = progress

        switch definition.type {
        case .collection:
            let total = definition.totalGoals
            updated.percentage =
                total > 0
                    ? Double(progress.completedGoals.count) / Double(total) * 100
                    : 0
            updated.score = progress.completedGoals.count

        case .cumulative:
            if let target = definition.targetValue, target > 0 {
                updated.percentage = Double(progress.currentValue) / Double(target) * 100
            }
            updated.score = progress.currentValue

        case .timeBounded:
            updated.score = progress.currentValue
            if let target = definition.targetValue, target > 0 {
                updated.percentage = Double(progress.currentValue) / Double(target) * 100
            }
        }

        return updated
    }

    private func evaluateTierAdvancement(_ participation: ChallengeParticipation) {
        guard let tiers = participation.challengeDefinition?.sortedTiers else {
            return
        }

        let currentValue =
            participation.challengeType == .collection
                ? participation.completedGoalsCount
                : participation.progress.currentValue

        // Find highest achieved tier
        var highestTier: ChallengeTier?
        for tier in tiers {
            if currentValue >= tier.threshold {
                highestTier = tier
            } else {
                break
            }
        }

        participation.currentTier = highestTier?.id
    }

    private func isComplete(
        participation: ChallengeParticipation,
        definition: ChallengeDefinition
    ) -> Bool {
        switch definition.type {
        case .collection:
            return participation.completedGoalsCount >= definition.totalGoals

        case .cumulative:
            guard let target = definition.targetValue else {
                return false
            }
            return participation.progress.currentValue >= target

        case .timeBounded:
            if definition.hasEnded {
                return true
            }
            if let target = definition.targetValue {
                return participation.progress.currentValue >= target
            }
            return false
        }
    }

    // MARK: - Data Fetching

    private func fetchActiveParticipations() -> [ChallengeParticipation] {
        let activeRaw = ParticipationStatus.active.rawValue
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.statusRawValue == activeRaw }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchAllQSOs() -> [QSO] {
        let descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Notifications

    private func notifyProgress(
        participation: ChallengeParticipation,
        newMatches: [String],
        tierAdvanced: Bool
    ) {
        NotificationCenter.default.post(
            name: .challengeProgressUpdated,
            object: nil,
            userInfo: [
                "participationId": participation.id,
                "newMatches": newMatches,
                "tierAdvanced": tierAdvanced,
            ]
        )

        if tierAdvanced {
            scheduleTierAdvancementNotification(participation)
        } else if participation.isComplete {
            scheduleChallengeCompletionNotification(participation)
        } else {
            scheduleProgressNotification(participation, newMatches: newMatches)
        }
    }

    private func notifyHistoricalEvaluation(_ participation: ChallengeParticipation) {
        NotificationCenter.default.post(
            name: .challengeProgressUpdated,
            object: nil,
            userInfo: [
                "participationId": participation.id,
                "historical": true,
            ]
        )
    }

    private func scheduleProgressNotification(_: ChallengeParticipation, newMatches _: [String]) {
        // Placeholder for UNUserNotificationCenter implementation
    }

    private func scheduleTierAdvancementNotification(_: ChallengeParticipation) {
        // Placeholder for UNUserNotificationCenter implementation
    }

    private func scheduleChallengeCompletionNotification(_: ChallengeParticipation) {
        // Placeholder for UNUserNotificationCenter implementation
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let challengeProgressUpdated = Notification.Name("challengeProgressUpdated")
}
