import CarrierWaveCore
import SwiftUI

// MARK: - StatePickerSheet

/// Searchable picker for primary administrative subdivisions — US states,
/// Canadian provinces, or a free-form ADIF code for any other country
/// (Mexican states, German Länder, Japanese prefectures, etc.). The
/// section for the operator's own country, inferred from their callsign
/// prefix, is listed first.
struct StatePickerSheet: View {
    // MARK: Lifecycle

    init(
        currentCode: String,
        onSelect: @escaping (ADIFCatalog.StateProvince) -> Void,
        onSelectCustom: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.currentCode = currentCode.uppercased()
        self.onSelect = onSelect
        self.onSelectCustom = onSelectCustom
        self.onDismiss = onDismiss
    }

    // MARK: Internal

    let currentCode: String
    let onSelect: (ADIFCatalog.StateProvince) -> Void
    let onSelectCustom: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                customEntrySection

                ForEach(orderedCountries, id: \.self) { country in
                    let matches = filtered(for: country)
                    if !matches.isEmpty {
                        Section(country.rawValue) {
                            ForEach(matches, id: \.id) { entry in
                                stateRow(entry)
                            }
                        }
                    }
                }

                if allFilteredEmpty, !trimmedSearch.isEmpty {
                    ContentUnavailableView.search(text: trimmedSearch)
                        .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Code or name")
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .navigationTitle("Subdivision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    // MARK: Private

    @State private var searchText = ""
    @State private var customText = ""

    /// Countries ordered so the operator's own country appears first.
    /// Falls back to ADIFCatalog's declaration order (USA, Canada) when
    /// the callsign can't be resolved.
    private var orderedCountries: [ADIFCatalog.Country] {
        let all = ADIFCatalog.Country.allCases
        let callsign = UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? ""
        guard !callsign.isEmpty,
              let entity = LocationPrefixLookup.entity(forCallsign: callsign)
        else {
            return all
        }
        let name = entity.name.lowercased()
        let preferred: ADIFCatalog.Country? = if name
            .contains("united states") || name == "alaska" || name == "hawaii"
        {
            .usa
        } else if name == "canada" {
            .canada
        } else {
            nil
        }
        guard let primary = preferred else {
            return all
        }
        return [primary] + all.filter { $0 != primary }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var allFilteredEmpty: Bool {
        ADIFCatalog.Country.allCases.allSatisfy { filtered(for: $0).isEmpty }
    }

    private var customEntrySection: some View {
        Section {
            HStack {
                TextField("Code", text: $customText)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button("Use") {
                    commitCustomEntry()
                }
                .disabled(customText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Other Country")
        } footer: {
            Text(
                "Enter the ADIF subdivision code used by your country " +
                    "(e.g. DL-BY for Bavaria, XE-JAL for Jalisco, " +
                    "JA-13 for Tokyo)."
            )
        }
    }

    private func stateRow(_ entry: ADIFCatalog.StateProvince) -> some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(spacing: 12) {
                Text(entry.code)
                    .font(.body.monospaced().weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 36, alignment: .leading)

                Text(entry.name)
                    .foregroundStyle(.primary)

                Spacer()

                if entry.code.uppercased() == currentCode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func filtered(for country: ADIFCatalog.Country) -> [ADIFCatalog.StateProvince] {
        let query = trimmedSearch.lowercased()
        return ADIFCatalog.stateProvinces
            .filter { $0.country == country }
            .filter { entry in
                guard !query.isEmpty else {
                    return true
                }
                return entry.code.lowercased().contains(query)
                    || entry.name.lowercased().contains(query)
            }
    }

    private func commitCustomEntry() {
        let trimmed = customText.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return
        }
        onSelectCustom(trimmed)
    }
}

#Preview {
    StatePickerSheet(
        currentCode: "CA",
        onSelect: { print("Selected: \($0.code)") },
        onSelectCustom: { print("Custom: \($0)") },
        onDismiss: {}
    )
}
