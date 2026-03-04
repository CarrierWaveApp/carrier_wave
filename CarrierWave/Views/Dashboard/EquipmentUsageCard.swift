import CarrierWaveData
import SwiftUI

// MARK: - EquipmentUsageCard

struct EquipmentUsageCard: View {
    // MARK: Internal

    let equipmentStats: AsyncEquipmentStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Equipment")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(equipmentStats.topThree.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        rowDivider
                    }
                    NavigationLink {
                        EquipmentDetailView(
                            equipmentStats: equipmentStats,
                            initialSort: .sessions
                        )
                    } label: {
                        EquipmentUsageRow(
                            title: rankLabel(index, category: item.category),
                            icon: item.category.icon,
                            name: item.name,
                            detail: "\(item.sessionCount)"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let magnet = equipmentStats.qsoMagnet {
                    rowDivider
                    NavigationLink {
                        EquipmentDetailView(
                            equipmentStats: equipmentStats,
                            initialSort: .avgQSOs
                        )
                    } label: {
                        EquipmentUsageRow(
                            title: "QSO Magnet",
                            icon: "bolt.fill",
                            name: magnet.name,
                            detail: "\(Int(magnet.avgQSOsPerSession.rounded())) avg"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let combo = equipmentStats.bestCombo {
                    rowDivider
                    NavigationLink {
                        EquipmentDetailView(
                            equipmentStats: equipmentStats,
                            initialSort: .sessions
                        )
                    } label: {
                        EquipmentUsageRow(
                            title: "Best Combo",
                            icon: "link",
                            name: combo.description,
                            detail: "\(combo.sessionCount)"
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let dusty = equipmentStats.gatheringDust {
                    rowDivider
                    NavigationLink {
                        EquipmentDetailView(
                            equipmentStats: equipmentStats,
                            initialSort: .lastUsed
                        )
                    } label: {
                        EquipmentUsageRow(
                            title: "Gathering Dust",
                            icon: "clock.arrow.circlepath",
                            name: dusty.name,
                            detail: Self.relativeDate(dusty.lastUsed)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Helpers

    private var rowDivider: some View {
        Divider().padding(.leading, 44)
    }

    private static func relativeDate(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func rankLabel(_ index: Int, category: EquipmentCategory) -> String {
        let ordinal = index == 0 ? "Top" : (index == 1 ? "2nd" : "3rd")
        return "\(ordinal) \(category.displayName)"
    }
}

// MARK: - EquipmentUsageRow

private struct EquipmentUsageRow: View {
    let title: String
    let icon: String
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Spacer()

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}
