import CarrierWaveData
import SwiftUI

// MARK: - EquipmentMigrationSheet Row Views

extension EquipmentMigrationSheet {
    func candidateRow(
        _ candidate: Binding<MigrationCandidate>
    ) -> some View {
        let item = candidate.wrappedValue
        return Button {
            if let idx = candidates.firstIndex(where: {
                $0.id == item.id
            }) {
                searchingIndex = idx
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.category.icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.originalName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    matchStatusLine(item)
                }

                Spacer()

                matchTrailingIndicator(item)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if item.match != nil {
                Button {
                    candidate.wrappedValue.match = nil
                    candidate.wrappedValue.confidence = 0
                } label: {
                    Label("Custom", systemImage: "xmark")
                }
                .tint(.orange)
            }
        }
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityHint("Tap to change match")
    }

    @ViewBuilder
    func matchStatusLine(
        _ item: MigrationCandidate
    ) -> some View {
        if let match = item.match {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                Text(match.fullName)
                    .font(.caption)
                confidenceBadge(item.confidence)
            }
            .foregroundStyle(confidenceColor(item.confidence))
        } else {
            Text("Custom Hardware")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    func matchTrailingIndicator(
        _ item: MigrationCandidate
    ) -> some View {
        if item.match != nil, item.confidence >= 0.8 {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
        } else if item.match != nil {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
                .font(.body)
        } else {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    func confidenceBadge(_ confidence: Double) -> some View {
        Group {
            if confidence >= 0.8 {
                EmptyView()
            } else if confidence >= 0.6 {
                Text("Likely")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Text("Uncertain")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        }
        return .red
    }

    func catalogSearchSheet(for index: Int) -> some View {
        let candidate = candidates[index]
        return MigrationCatalogSearchSheet(
            originalName: candidate.originalName,
            category: candidate.category,
            onSelect: { selectedEntry in
                candidates[index].match = selectedEntry
                candidates[index].confidence = 1.0
                searchingIndex = nil
            },
            onKeepCustom: {
                candidates[index].match = nil
                candidates[index].confidence = 0
                searchingIndex = nil
            }
        )
    }

    private func accessibilityLabel(
        for item: MigrationCandidate
    ) -> String {
        if let match = item.match {
            "\(item.originalName) matched to \(match.fullName)"
        } else {
            "\(item.originalName), custom hardware"
        }
    }
}
