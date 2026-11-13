import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - Custom Equipment Enrichment

extension EquipmentItemDetailView {
    /// Editable spec fields for custom equipment not linked to the catalog.
    func customSpecsSection(_ item: EquipmentItem) -> some View {
        Section("Specifications") {
            manufacturerField(item)
            portabilityPicker(item)
            if item.category == .radio {
                powerField(item)
            }
            customWeightField(item)
        }
    }

    /// "Is this a...?" recommendation banner for custom items.
    @ViewBuilder
    func catalogSuggestionBanner(_ item: EquipmentItem) -> some View {
        if !isDismissedSuggestion(item),
           let suggestion = bestCatalogMatch(for: item)
        {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.orange)
                        Text("Is this a \(suggestion.fullName)?")
                            .font(.subheadline.weight(.medium))
                    }

                    HStack(spacing: 8) {
                        Button {
                            relinkToCatalog(item, entry: suggestion)
                        } label: {
                            Label("Yes, link it", systemImage: "checkmark")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            dismissSuggestion(item)
                        } label: {
                            Label(
                                "No, it\u{2019}s custom",
                                systemImage: "xmark"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Similar catalog entries for manual linking.
    func similarInCatalogSection(_ item: EquipmentItem) -> some View {
        let matches = CatalogMatcher.search(
            query: item.catalogName,
            in: EquipmentCatalogService.shared.catalog,
            category: item.category,
            limit: 3
        )
        return Group {
            if !matches.isEmpty {
                Section("Similar in Catalog") {
                    ForEach(matches, id: \.entry.id) { result in
                        Button {
                            relinkToCatalog(item, entry: result.entry)
                        } label: {
                            catalogMatchRow(result.entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Spec Fields

    var portabilityOptions: [PortabilityClass] {
        [.pocket, .backpack, .portable, .mobile, .base]
    }

    private func manufacturerField(_ item: EquipmentItem) -> some View {
        TextField("Manufacturer", text: Binding(
            get: { item.manufacturer },
            set: {
                item.manufacturer = $0
                saveAndNotify()
            }
        ))
        .textInputAutocapitalization(.words)
    }

    private func portabilityPicker(_ item: EquipmentItem) -> some View {
        Picker("Portability", selection: Binding(
            get: { item.portability },
            set: {
                item.portabilityRawValue = $0.rawValue
                saveAndNotify()
            }
        )) {
            ForEach(portabilityOptions, id: \.self) { opt in
                Text(opt.displayName).tag(opt)
            }
        }
        .pickerStyle(.menu)
    }

    private func powerField(_ item: EquipmentItem) -> some View {
        HStack {
            Text("Max Power")
            Spacer()
            TextField("W", text: Binding(
                get: { item.maxPowerWatts.map { String($0) } ?? "" },
                set: {
                    item.maxPowerWatts = Int($0)
                    saveAndNotify()
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            Text("W").foregroundStyle(.secondary)
        }
    }

    private func customWeightField(_ item: EquipmentItem) -> some View {
        HStack {
            Text("Weight")
            Spacer()
            TextField("oz", text: Binding(
                get: { item.weightOunces.map { String($0) } ?? "" },
                set: {
                    item.weightOunces = Int($0)
                    saveAndNotify()
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            Text("oz").foregroundStyle(.secondary)
        }
    }

    private func catalogMatchRow(
        _ entry: CatalogEntry
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fullName)
                    .font(.subheadline)
                if let pw = entry.maxPowerWatts {
                    Text("\(pw)W")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("Link")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Helpers

    func relinkToCatalog(
        _ item: EquipmentItem, entry: CatalogEntry
    ) {
        item.catalogId = entry.id
        item.catalogName = entry.name
        item.manufacturer = entry.manufacturer
        item.bandsJSON = (try? JSONEncoder().encode(entry.bands)) ?? Data()
        item.modesJSON = (
            try? JSONEncoder().encode(entry.modes.map(\.rawValue))
        ) ?? Data()
        item.maxPowerWatts = entry.maxPowerWatts
        item.portabilityRawValue = entry.portability.rawValue
        if let grams = entry.weightGrams, item.weightOunces == nil {
            item.weightOunces = EquipmentWeight.gramsToOunces(grams)
        }
        if let connector = entry.antennaConnector,
           let type = ConnectorType(rawValue: connector),
           GearConnectorStorage.connector(for: entry.name) == nil
        {
            GearConnectorStorage.setConnector(type, for: entry.name)
        }
        saveAndNotify()
    }

    func bestCatalogMatch(for item: EquipmentItem) -> CatalogEntry? {
        CatalogMatcher.bestMatch(
            for: item.catalogName,
            in: EquipmentCatalogService.shared.catalog,
            category: item.category,
            threshold: 0.6
        )?.entry
    }

    func isDismissedSuggestion(_ item: EquipmentItem) -> Bool {
        UserDefaults.standard.bool(
            forKey: "dismissedCatalogSuggestion.\(item.catalogId)"
        )
    }

    func dismissSuggestion(_ item: EquipmentItem) {
        UserDefaults.standard.set(
            true,
            forKey: "dismissedCatalogSuggestion.\(item.catalogId)"
        )
    }
}
