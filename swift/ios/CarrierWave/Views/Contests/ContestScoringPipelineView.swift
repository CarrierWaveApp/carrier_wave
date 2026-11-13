import CarrierWaveData
import SwiftUI

// MARK: - ContestScoringPipelineView

/// Visual pipeline showing how a contest's score is computed: per-QSO
/// point rules, multiplier counts, and the final aggregate formula.
struct ContestScoringPipelineView: View {
    // MARK: Internal

    let scoring: ContestScoring

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(scoring.phases.enumerated()), id: \.offset) { idx, phase in
                phaseCard(phase, index: idx)
                if idx < scoring.phases.count - 1 {
                    pipelineConnector
                }
            }
        }
    }

    // MARK: Private

    private var pipelineConnector: some View {
        HStack(spacing: 6) {
            Spacer()
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1, height: 8)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func phaseCard(
        _ phase: ContestScoringPhase,
        index: Int
    ) -> some View {
        switch phase {
        case let .perQSO(qso):
            perQSOCard(qso, index: index)
        case let .multiplierCount(mult):
            multiplierCard(mult, index: index)
        case let .aggregate(agg):
            aggregateCard(agg, index: index)
        }
    }

    private func perQSOCard(
        _ phase: ContestPerQSOPhase,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            phaseHeader(
                label: phase.id,
                icon: "number.circle.fill",
                color: .blue,
                description: phase.description
            )
            ForEach(Array(phase.rules.enumerated()), id: \.offset) { _, rule in
                ruleRow(rule)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func multiplierCard(
        _ phase: ContestMultiplierPhase,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            phaseHeader(
                label: phase.id,
                icon: "multiply.circle.fill",
                color: .orange,
                description: phase.description
            )
            HStack {
                Text("Source:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(phase.source.replacingOccurrences(of: "_", with: " "))
                    .font(.caption)
            }
            HStack {
                Text("Scope:")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(phase.scope == .perBand ? "per band" : "per contest")
                    .font(.caption)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func aggregateCard(
        _ phase: ContestAggregatePhase,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            phaseHeader(
                label: phase.id,
                icon: "sum",
                color: .green,
                description: phase.description
            )
            Text(formulaString(phase.operation))
                .font(.callout.monospaced())
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func phaseHeader(
        label: String,
        icon: String,
        color: Color,
        description: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label.replacingOccurrences(of: "_", with: " "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            if let desc = description {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ruleRow(_ rule: ContestScoringRule) -> some View {
        HStack {
            if let desc = rule.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.primary)
            } else if rule.conditions.isEmpty {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(conditionsSummary(rule.conditions))
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("\(rule.value) pt\(rule.value == 1 ? "" : "s")")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(.blue)
        }
    }

    private func conditionsSummary(_ conditions: [ContestCondition]) -> String {
        conditions.map { cond in
            let field = cond.field.replacingOccurrences(of: "_", with: " ")
            let op = cond.op.rawValue
            if let val = cond.value {
                return "\(field) \(op) \(jsonValueString(val))"
            }
            if let ref = cond.reference {
                return "\(field) \(op) \(ref)"
            }
            return field
        }.joined(separator: " & ")
    }

    private func jsonValueString(_ val: JSONValue) -> String {
        switch val {
        case let .string(str): str
        case let .int(num): "\(num)"
        case let .double(num): "\(num)"
        case let .bool(flag): flag ? "true" : "false"
        case let .array(items): items.map { jsonValueString($0) }.joined(separator: ", ")
        case .null: "null"
        }
    }

    private func formulaString(_ op: ContestAggregateOp) -> String {
        switch op {
        case let .reference(phase):
            phase
        case let .literal(val):
            "\(val)"
        case let .add(ops):
            ops.map { formulaString($0) }.joined(separator: " + ")
        case let .multiply(ops):
            ops.map { formulaString($0) }.joined(separator: " \u{00D7} ")
        case let .max(ops):
            "max(\(ops.map { formulaString($0) }.joined(separator: ", ")))"
        }
    }
}
