import CarrierWaveData
import SwiftUI

// MARK: - EquipmentSortMode

enum EquipmentSortMode: String, CaseIterable {
    case sessions
    case totalQSOs
    case avgQSOs
    case lastUsed

    // MARK: Internal

    var label: String {
        switch self {
        case .sessions: "Sessions"
        case .totalQSOs: "Total QSOs"
        case .avgQSOs: "Avg QSOs"
        case .lastUsed: "Last Used"
        }
    }
}

// MARK: - EquipmentDetailView

struct EquipmentDetailView: View {
    // MARK: Internal

    let equipmentStats: AsyncEquipmentStats
    let initialSort: EquipmentSortMode

    var body: some View {
        List {
            if !sortedItems.isEmpty {
                equipmentSection
            }

            if !equipmentStats.comboRanking.isEmpty, categoryFilter == nil {
                comboSection
            }
        }
        .navigationTitle("Equipment Usage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
        .onAppear {
            sortMode = initialSort
        }
    }

    // MARK: Private

    @State private var sortMode: EquipmentSortMode = .sessions
    @State private var categoryFilter: EquipmentCategory?

    private var availableCategories: [EquipmentCategory] {
        let used = Set(equipmentStats.allItems.map(\.category))
        return EquipmentCategory.allCases.filter { used.contains($0) }
    }

    private var sortedItems: [EquipmentItemStat] {
        let filtered = categoryFilter == nil
            ? equipmentStats.allItems
            : equipmentStats.allItems.filter { $0.category == categoryFilter }

        switch sortMode {
        case .sessions:
            return filtered.sorted { $0.sessionCount > $1.sessionCount }
        case .totalQSOs:
            return filtered.sorted { $0.totalQSOs > $1.totalQSOs }
        case .avgQSOs:
            return filtered.sorted { $0.avgQSOsPerSession > $1.avgQSOsPerSession }
        case .lastUsed:
            return filtered.sorted { $0.lastUsed > $1.lastUsed }
        }
    }

    // MARK: - Sections

    private var equipmentSection: some View {
        Section {
            ForEach(sortedItems) { item in
                EquipmentDetailRow(item: item, highlightedMetric: sortMode)
            }
        } header: {
            categoryPicker
        }
    }

    private var comboSection: some View {
        Section("Radio + Antenna Combos") {
            ForEach(equipmentStats.comboRanking) { combo in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(combo.description)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(combo.totalQSOs) QSOs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(combo.sessionCount)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sort & Filter

    private var sortMenu: some View {
        Menu {
            ForEach(EquipmentSortMode.allCases, id: \.self) { mode in
                Button {
                    sortMode = mode
                } label: {
                    if mode == sortMode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort equipment")
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(availableCategories, id: \.self) { category in
                    filterChip(category.displayName, isSelected: categoryFilter == category) {
                        categoryFilter = category
                    }
                }
            }
        }
        .textCase(nil)
    }

    private func filterChip(
        _ label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EquipmentDetailRow

private struct EquipmentDetailRow: View {
    // MARK: Internal

    let item: EquipmentItemStat
    let highlightedMetric: EquipmentSortMode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    metricPill("\(item.sessionCount) sess", highlighted: highlightedMetric == .sessions)
                    metricPill("\(item.totalQSOs) QSOs", highlighted: highlightedMetric == .totalQSOs)
                    metricPill(
                        "\(Int(item.avgQSOsPerSession.rounded())) avg",
                        highlighted: highlightedMetric == .avgQSOs
                    )
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.dateFormatter.string(from: item.lastUsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func metricPill(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(highlighted ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(highlighted ? Color.blue.opacity(0.2) : Color(.systemGray5))
            .clipShape(Capsule())
    }
}
