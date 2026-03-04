import CarrierWaveData
import SwiftUI

// MARK: - ChallengeProgressCard

struct ChallengeProgressCard: View {
    // MARK: Internal

    let participation: ChallengeParticipation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(participation.challengeName)
                        .font(.headline)

                    if let definition = participation.challengeDefinition {
                        Text(challengeTypeLabel(definition.type))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Time remaining for time-bounded challenges
                if let timeRemaining = participation.challengeDefinition?.timeRemaining {
                    TimeRemainingBadge(seconds: timeRemaining)
                }
            }

            // Progress bar
            ProgressView(value: participation.progressPercentage, total: 100)
                .tint(progressColor)

            // Stats row
            HStack {
                // Progress text
                Text(participation.progressDisplayString)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // Percentage
                Text(String(format: "%.0f%%", participation.progressPercentage))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Tier progress (if applicable)
            if let nextTier = participation.nextTier {
                HStack(spacing: 8) {
                    if let currentTierName = participation.currentTierName {
                        Text(currentTierName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(nextTier.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(remainingForNextTier) to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private var progressColor: Color {
        if participation.progressPercentage >= 100 {
            .green
        } else if participation.progressPercentage >= 75 {
            .blue
        } else if participation.progressPercentage >= 50 {
            .orange
        } else {
            .accentColor
        }
    }

    private var remainingForNextTier: Int {
        guard let nextTier = participation.nextTier else {
            return 0
        }

        let currentValue =
            participation.challengeType == .collection
                ? participation.completedGoalsCount
                : participation.progress.currentValue

        return max(0, nextTier.threshold - currentValue)
    }

    private func challengeTypeLabel(_ type: ChallengeType) -> String {
        switch type {
        case .collection:
            "Collection"
        case .cumulative:
            "Cumulative"
        case .timeBounded:
            "Time-Limited"
        }
    }
}

// MARK: - TimeRemainingBadge

struct TimeRemainingBadge: View {
    // MARK: Internal

    let seconds: TimeInterval

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)

            Text(formattedTime)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(urgencyColor.opacity(0.2))
        .foregroundStyle(urgencyColor)
        .clipShape(Capsule())
    }

    // MARK: Private

    private var formattedTime: String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60

        if hours >= 24 {
            let days = hours / 24
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private var urgencyColor: Color {
        if seconds < 3_600 { // Less than 1 hour
            .red
        } else if seconds < 86_400 { // Less than 1 day
            .orange
        } else {
            .secondary
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        // Would need sample data for preview
        Text("ChallengeProgressCard Preview")
    }
    .padding()
}
