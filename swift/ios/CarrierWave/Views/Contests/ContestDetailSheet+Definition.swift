import CarrierWaveData
import SwiftUI

// MARK: - ContestDetailSheet+Definition

extension ContestDetailSheet {
    func definitionSourceCard(_ def: ContestDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let sponsor = def.sponsor?.name {
                HStack {
                    Text("Sponsor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(sponsor)
                        .font(.callout)
                }
            }
            if let urlStr = def.sponsor?.url, let url = URL(string: urlStr) {
                Link(destination: url) {
                    HStack {
                        Text("Rules & Info")
                            .font(.callout)
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func definitionExchangeCard(_ def: ContestDefinition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exchange")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if !def.exchange.sent.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Text(def.exchange.sent.map(\.label).joined(separator: " + "))
                        .font(.callout)
                }
            }
            if !def.exchange.received.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receive")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                    Text(def.exchange.received.map(\.label).joined(separator: " + "))
                        .font(.callout)
                }
            }
            ContestExchangeExampleView(exchange: def.exchange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func definitionScoringCard(_ def: ContestDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scoring")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ContestScoringPipelineView(scoring: def.scoring)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    func loadDefinition() async {
        if let templateId = contest.enrichment.matchedTemplateId {
            definition = await ContestDefinitions.definition(id: templateId)
            if definition != nil {
                return
            }
        }
        let allDefs = await ContestDefinitions.allDefinitions()
        let title = contest.title.lowercased()
        definition = allDefs.first { def in
            let defName = def.displayName.lowercased()
            return title.contains(defName) || defName.contains(title)
        }
    }
}
