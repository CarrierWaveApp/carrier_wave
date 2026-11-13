import CarrierWaveData
import SwiftUI

// MARK: - Contest UI Components

extension LoggerView {
    /// Whether the current session is a contest session
    var isContestSession: Bool {
        sessionManager?.activeSession?.isContest == true
    }

    /// Contest exchange fields that appear below the callsign row
    @ViewBuilder
    var contestExchangeSection: some View {
        if isContestSession, let definition = contestManager?.definition {
            VStack(spacing: 8) {
                clubNumberReminder
                contestDupeIndicator
                contestExchangeFields(definition: definition)
                contestScoreBar
                contestConstraintBadges
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Dismissible reminder listing the operator's saved club numbers so
    /// they can include them in the contest exchange. Appears only when
    /// the user has at least one number on file and hasn't dismissed the
    /// banner for the current contest.
    @ViewBuilder
    var clubNumberReminder: some View {
        if let session = sessionManager?.activeSession,
           let contestId = session.contestId
        {
            ClubNumberReminderBanner(
                contestId: contestId,
                myCallsign: session.contestOperator ?? session.myCallsign
            )
        }
    }

    /// Dynamic exchange fields based on contest definition
    @ViewBuilder
    private func contestExchangeFields(
        definition: ContestDefinition
    ) -> some View {
        let receivedFields = definition.exchange.received.filter {
            $0.type != .signalReport
        }

        if !receivedFields.isEmpty {
            HStack(spacing: 8) {
                ForEach(receivedFields) { field in
                    contestFieldInput(field)
                }
            }
        }

        if definition.exchange.sent.contains(where: { $0.type == .serialNumber }) {
            HStack {
                Text("My Serial")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("#\(contestManager?.currentSerial ?? 1)")
                    .font(.subheadline.monospaced().bold())
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Individual contest field input
    private func contestFieldInput(
        _ field: ContestExchangeField
    ) -> some View {
        VStack(spacing: 2) {
            Text(field.label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField(
                field.defaultValue?.stringValue ?? field.label,
                text: contestExchangeBinding(for: field.name)
            )
            .font(.subheadline.monospaced())
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(keyboardType(for: field.type))
            .frame(height: fieldHeight)
            .padding(.horizontal, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Keyboard type appropriate for the field type
    private func keyboardType(
        for type: ContestExchangeFieldType
    ) -> UIKeyboardType {
        switch type {
        case .serialNumber,
             .cqZone,
             .ituZone,
             .age,
             .signalReport:
            .numberPad
        default:
            .default
        }
    }

    /// Binding into the contestExchangeValues dictionary
    private func contestExchangeBinding(
        for fieldName: String
    ) -> Binding<String> {
        Binding(
            get: { contestExchangeValues[fieldName] ?? "" },
            set: { contestExchangeValues[fieldName] = $0 }
        )
    }

    /// Dupe indicator badge
    @ViewBuilder
    var contestDupeIndicator: some View {
        if let status = contestManager?.lastDupeStatus {
            HStack {
                switch status {
                case .dupe:
                    Label("DUPE", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.red)
                case let .newMultiplier(phaseID, value):
                    Label(
                        "NEW MULT: \(value) (\(phaseID))",
                        systemImage: "star.fill"
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                case .newStation:
                    EmptyView()
                }
                Spacer()
            }
        }
    }

    /// Score bar showing QSOs | Points | Mults | Score
    @ViewBuilder
    var contestScoreBar: some View {
        if let manager = contestManager, manager.isActive {
            let sc = manager.score
            HStack(spacing: 0) {
                scoreCell(label: "QSOs", value: "\(sc.totalQSOs)")
                Divider().frame(height: 24)
                scoreCell(label: "Points", value: "\(sc.totalPoints)")
                Divider().frame(height: 24)
                scoreCell(label: "Mults", value: "\(sc.multiplierCount)")
                Divider().frame(height: 24)
                scoreCell(
                    label: "Score",
                    value: formatScore(sc.finalScore)
                )
            }
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Off-time + band-change constraint badges
    @ViewBuilder
    var contestConstraintBadges: some View {
        if let manager = contestManager, manager.isActive {
            let offTime = manager.offTimeSummary
            let bandChange = manager.bandChangeSummary
            if let remaining = offTime.remainingOnAirSeconds,
               manager.definition?.operatingConstraints?.offTime != nil
            {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("On-air left: \(formatDuration(remaining))")
                        .font(.caption2)
                    Spacer()
                    if !offTime.violations.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }
            if !bandChange.violations.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("\(bandChange.violations.count) band-change violation(s)")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private func scoreCell(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.subheadline.monospaced().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatScore(_ score: Int) -> String {
        if score >= 1_000_000 {
            return String(format: "%.1fM", Double(score) / 1_000_000)
        } else if score >= 1_000 {
            return String(format: "%.1fK", Double(score) / 1_000)
        }
        return "\(score)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
