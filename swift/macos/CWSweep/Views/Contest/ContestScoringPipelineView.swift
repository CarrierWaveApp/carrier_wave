import CarrierWaveData
import SwiftUI

// MARK: - ContestScoringPipelineView

/// Visual pipeline of how a contest's score is computed, showing per-QSO
/// point rules, multiplier counts, and the final aggregate formula.
/// Each phase is rendered as a card with connecting arrows.
struct ContestScoringPipelineView: View {
    // MARK: Internal

    let scoring: ContestScoring

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(scoring.phases.enumerated()), id: \.offset) { index, phase in
                phaseCard(phase)
                if index < scoring.phases.count - 1 {
                    arrow
                }
            }
        }
    }

    // MARK: Private

    private var arrow: some View {
        HStack {
            Spacer()
            Image(systemName: "arrow.down")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(height: 20)
    }

    private func phaseCard(_ phase: ContestScoringPhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: phaseIcon(phase))
                    .foregroundStyle(phaseColor(phase))
                Text(phase.id)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(phaseTypeLabel(phase))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(phaseColor(phase).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(phaseColor(phase))
            }

            if let description = phase.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            phaseDetail(phase)
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(phaseColor(phase).opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func phaseDetail(_ phase: ContestScoringPhase) -> some View {
        switch phase {
        case let .perQSO(qso):
            perQSODetail(qso)
        case let .multiplierCount(mult):
            multiplierDetail(mult)
        case let .aggregate(agg):
            aggregateDetail(agg)
        }
    }

    private func perQSODetail(_ phase: ContestPerQSOPhase) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(phase.rules.enumerated()), id: \.offset) { _, rule in
                HStack(spacing: 6) {
                    Text("\(rule.value) pt")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.blue)
                        .frame(width: 40, alignment: .trailing)
                    if let desc = rule.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if rule.conditions.isEmpty {
                        Text("default")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(conditionsSummary(rule.conditions))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func multiplierDetail(_ phase: ContestMultiplierPhase) -> some View {
        HStack(spacing: 8) {
            Label(phase.source.replacingOccurrences(of: "_", with: " "), systemImage: "number")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("•")
                .foregroundStyle(.tertiary)
            Text(phase.scope == .perBand ? "per band" : "per contest")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func aggregateDetail(_ phase: ContestAggregatePhase) -> some View {
        Text(formatOp(phase.operation))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }

    private func phaseIcon(_ phase: ContestScoringPhase) -> String {
        switch phase {
        case .perQSO: "number.circle"
        case .multiplierCount: "xmark.circle"
        case .aggregate: "sum"
        }
    }

    private func phaseColor(_ phase: ContestScoringPhase) -> Color {
        switch phase {
        case .perQSO: .blue
        case .multiplierCount: .orange
        case .aggregate: .green
        }
    }

    private func phaseTypeLabel(_ phase: ContestScoringPhase) -> String {
        switch phase {
        case .perQSO: "per QSO"
        case .multiplierCount: "multiplier"
        case .aggregate: "aggregate"
        }
    }

    private func conditionsSummary(_ conditions: [ContestCondition]) -> String {
        conditions.map { condition in
            let field = condition.field.replacingOccurrences(of: "_", with: " ")
            let op = condition.op.rawValue
            if let value = condition.value {
                return "\(field) \(op) \(value.displayString)"
            }
            if let ref = condition.reference {
                return "\(field) \(op) \(ref)"
            }
            return field
        }.joined(separator: " & ")
    }

    private func formatOp(_ op: ContestAggregateOp) -> String {
        switch op {
        case let .reference(phase): phase
        case let .literal(value): "\(value)"
        case let .multiply(inputs): inputs.map { formatOp($0) }.joined(separator: " × ")
        case let .add(inputs): inputs.map { formatOp($0) }.joined(separator: " + ")
        case let .max(inputs): "max(\(inputs.map { formatOp($0) }.joined(separator: ", ")))"
        }
    }
}

// MARK: - JSONValue display helper

private extension JSONValue {
    var displayString: String {
        switch self {
        case let .string(str): str
        case let .int(num): "\(num)"
        case let .double(num): num.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(num))" : "\(num)"
        case let .bool(flag): flag ? "true" : "false"
        case let .array(items): "[\(items.map(\.displayString).joined(separator: ", "))]"
        case .null: "null"
        }
    }
}
