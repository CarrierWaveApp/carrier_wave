import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - EquipmentBrowserView

struct EquipmentBrowserView: View {
    // MARK: Internal

    var body: some View {
        List {
            if items.isEmpty {
                emptyState
            } else {
                filterSection
                equipmentSections
            }
        }
        .navigationTitle("My Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add equipment")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task {
                        await EquipmentCatalogService.shared.forceRefresh()
                        EquipmentMigration.resetAndClearItems(
                            container: modelContext.container
                        )
                        await loadItems()
                        showingMigrationSheet = true
                    }
                } label: {
                    Label(
                        "Re-run Migration",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
        .task {
            await loadItems()
            await loadUsageCounts()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEquipmentSheet { newItem in
                modelContext.insert(newItem)
                try? EntityWriteSink.commitUpsert(newItem, in: modelContext)
                syncCategoryToKVS(newItem.category)
                Task {
                    await loadItems()
                    await loadUsageCounts()
                }
            }
        }
        .sheet(isPresented: $showingMigrationSheet) {
            EquipmentMigrationSheet {
                showingMigrationSheet = false
                Task {
                    await loadItems()
                    await loadUsageCounts()
                }
            }
        }
    }

    // MARK: Fileprivate

    @Environment(\.modelContext) fileprivate var modelContext

    @State fileprivate var items: [EquipmentInventorySnapshot] = []
    @State fileprivate var usageCounts: [String: Int] = [:]
    @State fileprivate var categoryFilter: CarrierWaveData.EquipmentCategory?
    @State fileprivate var showRetired = false
    @State fileprivate var showingAddSheet = false
    @State fileprivate var showingMigrationSheet = false
}

// MARK: - Computed Data

private extension EquipmentBrowserView {
    var filteredItems: [EquipmentInventorySnapshot] {
        items.filter { item in
            if let filter = categoryFilter, item.category != filter {
                return false
            }
            if !showRetired, item.isRetired {
                return false
            }
            return true
        }
    }

    var retiredCount: Int {
        items.filter(\.isRetired).count
    }

    var usedCategories: [CarrierWaveData.EquipmentCategory] {
        let used = Set(items.map(\.category))
        return CarrierWaveData.EquipmentCategory.allCases
            .filter { used.contains($0) }
    }

    /// Categories to display as sections, in canonical order.
    var visibleCategories: [CarrierWaveData.EquipmentCategory] {
        let present = Set(filteredItems.map(\.category))
        return CarrierWaveData.EquipmentCategory.allCases
            .filter { present.contains($0) }
    }
}

// MARK: - Sections

private extension EquipmentBrowserView {
    var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "radio")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("No Equipment")
                    .font(.headline)
                Text(
                    "Add your radios, antennas, keys, and "
                        + "accessories to track what you use."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Equipment", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    var filterSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", isSelected: categoryFilter == nil) {
                        categoryFilter = nil
                    }
                    ForEach(usedCategories, id: \.self) { category in
                        filterChip(
                            category.displayName,
                            isSelected: categoryFilter == category
                        ) {
                            categoryFilter = category
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(
                top: 8, leading: 16, bottom: 8, trailing: 16
            ))

            if retiredCount > 0 {
                Toggle("Show Retired", isOn: $showRetired)
            }
        }
    }

    var equipmentSections: some View {
        ForEach(visibleCategories, id: \.self) { category in
            categorySection(category)
        }
    }

    func categorySection(
        _ category: CarrierWaveData.EquipmentCategory
    ) -> some View {
        let sectionItems = filteredItems
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                let lhsUses = usageCounts[lhs.displayName] ?? 0
                let rhsUses = usageCounts[rhs.displayName] ?? 0
                if lhsUses != rhsUses {
                    return lhsUses > rhsUses
                }
                return lhs.dateAdded > rhs.dateAdded
            }
        return Section {
            ForEach(sectionItems) { item in
                NavigationLink {
                    EquipmentItemDetailView(
                        itemId: item.id,
                        onUpdate: {
                            Task {
                                await loadItems()
                                await loadUsageCounts()
                            }
                        }
                    )
                } label: {
                    equipmentRow(item)
                }
            }
        } header: {
            HStack {
                Label(category.displayName, systemImage: category.icon)
                    .labelStyle(.titleAndIcon)
                Spacer()
                Text(
                    "\(sectionItems.count) "
                        + "item\(sectionItems.count == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Row Rendering

private extension EquipmentBrowserView {
    static let dateAddedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    func equipmentRow(
        _ item: EquipmentInventorySnapshot
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                equipmentRowHeader(item)
                equipmentRowMetadata(item)
                equipmentRowUsageLine(item)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    func equipmentRowHeader(
        _ item: EquipmentInventorySnapshot
    ) -> some View {
        HStack(spacing: 6) {
            Text(item.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            if item.isRetired {
                metadataTag("Retired", color: .gray)
            }
            if item.isCustom {
                metadataTag("Custom", color: .orange)
            }
        }
    }

    func equipmentRowMetadata(
        _ item: EquipmentInventorySnapshot
    ) -> some View {
        FlowLayout(spacing: 4) {
            if !item.manufacturer.isEmpty {
                metadataLabel(item.manufacturer, icon: "building.2")
            }
            if let power = item.maxPowerWatts {
                metadataLabel("\(power)W", icon: "bolt")
            }
            metadataLabel(
                item.portability.displayName,
                icon: "scalemass"
            )
        }
    }

    func equipmentRowUsageLine(
        _ item: EquipmentInventorySnapshot
    ) -> some View {
        let uses = usageCounts[item.displayName] ?? 0
        let usesLabel = "\(uses) session\(uses == 1 ? "" : "s")"
        let added = Self.dateAddedFormatter.string(from: item.dateAdded)
        return HStack(spacing: 10) {
            Label(usesLabel, systemImage: "waveform.path")
                .accessibilityLabel("Used in \(usesLabel)")
            Label("Added \(added)", systemImage: "calendar")
                .accessibilityLabel("Added \(added)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    func metadataLabel(
        _ text: String,
        icon: String
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    func metadataTag(
        _ text: String,
        color: Color
    ) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    func filterChip(
        _ label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : Color(.systemGray5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data Loading

private extension EquipmentBrowserView {
    func loadItems() async {
        var descriptor = FetchDescriptor<EquipmentItem>(
            sortBy: [SortDescriptor(\.catalogName)]
        )
        descriptor.fetchLimit = 200
        guard let fetched = try? modelContext.fetch(descriptor) else {
            return
        }
        items = fetched.map { EquipmentInventorySnapshot(item: $0) }
    }

    func loadUsageCounts() async {
        let container = modelContext.container
        let actor = EquipmentStatsActor()
        guard let stats = try? await actor.computeStats(
            container: container
        ) else {
            return
        }
        var counts: [String: Int] = [:]
        for stat in stats.allItems {
            // If the same display name is used across categories (rare), keep
            // the larger count so at least one row reflects full usage.
            counts[stat.name] = max(counts[stat.name] ?? 0, stat.sessionCount)
        }
        usageCounts = counts
    }

    func syncCategoryToKVS(
        _ category: CarrierWaveData.EquipmentCategory
    ) {
        let categoryRaw = category.rawValue
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 200
        descriptor.predicate = #Predicate<EquipmentItem> { item in
            item.categoryRawValue == categoryRaw
        }
        guard let fetched = try? modelContext.fetch(descriptor) else {
            return
        }
        EquipmentInventorySync.pushToKVS(
            category: category, items: fetched
        )
    }
}
