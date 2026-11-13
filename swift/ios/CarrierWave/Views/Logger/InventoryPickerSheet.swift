import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - InventoryPickerSheet

/// Unified equipment picker that shows the user's inventory and local catalog search.
/// Replaces both RadioPickerSheet and EquipmentPickerSheet.
struct InventoryPickerSheet: View {
    // MARK: Internal

    let category: EquipmentCategory

    @Binding var selection: String?

    /// Optional callback delivering the chosen item's snapshot.
    /// Fires with nil when the user picks "None" or types a free-form
    /// name that doesn't match inventory. Used by the session start
    /// sheet to capture `radioItemID` for auto-connect.
    var onItemSelected: ((EquipmentInventorySnapshot?) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                noneRow
                if !inventoryItems.isEmpty {
                    inventorySection
                }
                if searchText.count >= 2 {
                    catalogSection
                }
                addCustomFooter
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search \(category.displayName.lowercased())s\u{2026}"
            )
            .navigationTitle("Select \(category.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { loadInventory() }
            .onChange(of: searchText) { _, newValue in
                updateCatalogResults(query: newValue)
            }
            .sheet(isPresented: $showAddSheet) {
                AddEquipmentSheet { newItem in
                    modelContext.insert(newItem)
                    try? EntityWriteSink.commitUpsert(newItem, in: modelContext)
                    syncCategoryToKVS()
                    selection = newItem.displayName
                    onItemSelected?(EquipmentInventorySnapshot(item: newItem))
                    loadInventory()
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var inventoryItems: [EquipmentInventorySnapshot] = []
    @State private var searchText = ""
    @State private var catalogResults: [CatalogSearchResult] = []
    @State private var showAddSheet = false

    // MARK: - Inventory Section

    private var filteredInventory: [EquipmentInventorySnapshot] {
        if searchText.isEmpty {
            return inventoryItems
        }
        let query = searchText.lowercased()
        return inventoryItems.filter {
            $0.displayName.lowercased().contains(query)
                || $0.manufacturer.lowercased().contains(query)
        }
    }

    // MARK: - Catalog Section

    /// Filter out catalog results that are already in inventory.
    private var filteredCatalogResults: [CatalogSearchResult] {
        let ownedIds = Set(inventoryItems.map(\.catalogId))
        return catalogResults.filter { !ownedIds.contains($0.entry.id) }
    }

    // MARK: - None Row

    private var noneRow: some View {
        Button {
            selection = nil
            onItemSelected?(nil)
            dismiss()
        } label: {
            HStack {
                Text("None")
                    .foregroundStyle(.primary)
                Spacer()
                if selection == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var inventorySection: some View {
        Section("My \(category.displayName)s") {
            ForEach(filteredInventory) { item in
                Button {
                    selection = item.displayName
                    onItemSelected?(item)
                    dismiss()
                } label: {
                    inventoryRow(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var catalogSection: some View {
        if !filteredCatalogResults.isEmpty {
            Section("From Catalog") {
                ForEach(filteredCatalogResults, id: \.entry.id) { result in
                    Button {
                        addFromCatalogAndSelect(result.entry)
                    } label: {
                        catalogRow(result.entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Add Custom Footer

    private var addCustomFooter: some View {
        Section {
            Button {
                showAddSheet = true
            } label: {
                Label(
                    "Add custom \(category.displayName.lowercased())",
                    systemImage: "plus.circle"
                )
                .font(.subheadline)
            }
        }
    }

    private func inventoryRow(
        _ item: EquipmentInventorySnapshot
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if !item.manufacturer.isEmpty {
                    Text(item.manufacturer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if selection == item.displayName {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    private func catalogRow(_ entry: CatalogEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fullName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let power = entry.maxPowerWatts {
                        Text("\(power)W")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.bands.isEmpty {
                        Text(bandSummary(entry.bands))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Text("Add")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func loadInventory() {
        let categoryRaw = category.rawValue
        var descriptor = FetchDescriptor<EquipmentItem>()
        descriptor.fetchLimit = 200
        descriptor.predicate = #Predicate<EquipmentItem> { item in
            item.categoryRawValue == categoryRaw && !item.isRetired
        }
        descriptor.sortBy = [SortDescriptor(\.catalogName)]
        guard let fetched = try? modelContext.fetch(descriptor) else {
            return
        }
        inventoryItems = fetched.map {
            EquipmentInventorySnapshot(item: $0)
        }
    }

    private func updateCatalogResults(query: String) {
        guard query.count >= 2 else {
            catalogResults = []
            return
        }
        catalogResults = CatalogMatcher.search(
            query: query,
            in: EquipmentCatalogService.shared.catalog,
            category: category,
            limit: 5
        )
    }

    private func addFromCatalogAndSelect(_ entry: CatalogEntry) {
        let item = EquipmentItem(
            catalogId: entry.id,
            catalogName: entry.name,
            category: category,
            bands: entry.bands,
            modes: entry.modes.map(\.rawValue),
            maxPowerWatts: entry.maxPowerWatts,
            portability: entry.portability,
            manufacturer: entry.manufacturer
        )
        seedConnectorFromCatalog(entry)
        modelContext.insert(item)
        try? EntityWriteSink.commitUpsert(item, in: modelContext)
        syncCategoryToKVS()
        selection = item.displayName
        onItemSelected?(EquipmentInventorySnapshot(item: item))
        loadInventory()
        dismiss()
    }

    private func seedConnectorFromCatalog(_ entry: CatalogEntry) {
        if let connector = entry.antennaConnector,
           let type = ConnectorType(rawValue: connector),
           GearConnectorStorage.connector(for: entry.name) == nil
        {
            GearConnectorStorage.setConnector(type, for: entry.name)
        }
    }

    private func syncCategoryToKVS() {
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

    private func bandSummary(_ bands: [String]) -> String {
        if bands.count <= 3 {
            return bands.joined(separator: ", ")
        }
        return "\(bands.first ?? "") \u{2013} \(bands.last ?? "")"
    }
}
