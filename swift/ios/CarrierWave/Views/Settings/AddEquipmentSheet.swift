import CarrierWaveData
import SwiftUI

// MARK: - AddEquipmentSheet

struct AddEquipmentSheet: View {
    // MARK: Internal

    var onAdd: (EquipmentItem) -> Void

    var body: some View {
        NavigationStack {
            List {
                searchSection
                if !searchText.isEmpty {
                    searchResultsSection
                }
                if showManualEntry {
                    manualEntrySection
                }
            }
            .navigationTitle("Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [CatalogSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var showManualEntry = false

    // Manual entry state
    @State private var manualName = ""
    @State private var manualManufacturer = ""
    @State private var manualCategory: CarrierWaveData.EquipmentCategory = .radio
    @State private var manualPortability: PortabilityClass = .portable
    @State private var manualMaxPower = ""
    @State private var manualBands: Set<String> = []
    @State private var manualModes: Set<String> = []

    private var portabilityOptions: [PortabilityClass] {
        [.pocket, .backpack, .portable, .mobile, .base]
    }

    // MARK: - Search Section

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Search radios, antennas, keys\u{2026}",
                    text: $searchText
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    debouncedSearch(newValue)
                }
                if isSearching {
                    ProgressView()
                } else if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            Text("Search the equipment catalog or add custom gear.")
        }
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        Section {
            if searchResults.isEmpty, !isSearching {
                noResultsView
            } else {
                ForEach(searchResults, id: \.entry.id) { result in
                    Button { addFromCatalog(result.entry) } label: {
                        catalogResultRow(result.entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            if !searchResults.isEmpty {
                Text("Catalog Results")
            }
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 8) {
            Text("No matches found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                manualName = searchText
                showManualEntry = true
            } label: {
                Label(
                    "Add \"\(searchText)\" manually",
                    systemImage: "plus.circle"
                )
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Manual Entry

    @ViewBuilder
    private var manualEntrySection: some View {
        Section("Manual Entry") {
            TextField("Equipment name", text: $manualName)
                .textInputAutocapitalization(.words)
            TextField("Manufacturer", text: $manualManufacturer)
                .textInputAutocapitalization(.words)
        }
        Section("Category") {
            Picker("Type", selection: $manualCategory) {
                ForEach(EquipmentCategory.allCases, id: \.self) { cat in
                    Label(cat.displayName, systemImage: cat.icon)
                        .tag(cat)
                }
            }
            .pickerStyle(.menu)
            Picker("Portability", selection: $manualPortability) {
                ForEach(portabilityOptions, id: \.self) { opt in
                    Text(opt.displayName).tag(opt)
                }
            }
            .pickerStyle(.menu)
        }
        if manualCategory == .radio {
            Section("Power") {
                TextField("Max watts", text: $manualMaxPower)
                    .keyboardType(.numberPad)
            }
        }
        Section {
            Button {
                addManualItem()
            } label: {
                Label("Add Equipment", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .disabled(
                manualName.trimmingCharacters(in: .whitespaces)
                    .isEmpty
            )
        }
    }

    private func catalogResultRow(
        _ entry: CatalogEntry
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fullName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                detailLine(entry)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func detailLine(
        _ entry: CatalogEntry
    ) -> some View {
        HStack(spacing: 6) {
            Text(entry.category.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func bandSummary(_ bands: [String]) -> String {
        if bands.count <= 3 {
            return bands.joined(separator: ", ")
        }
        return "\(bands.first ?? "") \u{2013} \(bands.last ?? "")"
    }

    private func debouncedSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            let results = CatalogMatcher.search(
                query: query,
                in: EquipmentCatalogService.shared.catalog,
                limit: 10
            )
            guard !Task.isCancelled else {
                return
            }
            searchResults = results
            isSearching = false
        }
    }

    private func addFromCatalog(_ entry: CatalogEntry) {
        let item = EquipmentItem(
            catalogId: entry.id,
            catalogName: entry.name,
            category: entry.category,
            bands: entry.bands,
            modes: entry.modes.map(\.rawValue),
            maxPowerWatts: entry.maxPowerWatts,
            portability: entry.portability,
            manufacturer: entry.manufacturer,
            weightOunces: entry.weightGrams.map(EquipmentWeight.gramsToOunces)
        )
        seedConnectorFromCatalog(entry)
        onAdd(item)
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

    private func addManualItem() {
        let trimmed = manualName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }

        let item = EquipmentItem.custom(
            name: trimmed,
            category: manualCategory,
            maxPowerWatts: Int(manualMaxPower),
            portability: manualPortability
        )
        item.manufacturer = manualManufacturer.trimmingCharacters(
            in: .whitespaces
        )
        CustomEquipmentSubmitter.shared.submitIfNeeded(item)
        onAdd(item)
        dismiss()
    }
}
