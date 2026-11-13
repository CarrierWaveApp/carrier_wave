import CarrierWaveCore
import SwiftUI

// MARK: - CallsignPrefixSheet

/// Sheet for selecting a callsign prefix when operating from a foreign location.
///
/// Shows three options:
/// 1. GPS-suggested prefix (if location detected and different from home country)
/// 2. Country browser with search
/// 3. Custom prefix entry
struct CallsignPrefixSheet: View {
    // MARK: Lifecycle

    init(
        currentPrefix: String,
        homeCallsign: String,
        currentGrid: String?,
        onSelect: @escaping (String) -> Void
    ) {
        self.currentPrefix = currentPrefix
        self.homeCallsign = homeCallsign
        self.currentGrid = currentGrid
        self.onSelect = onSelect
        _customPrefix = State(initialValue: currentPrefix)
    }

    // MARK: Internal

    @Environment(\.dismiss) var dismiss

    let currentPrefix: String
    let homeCallsign: String
    let currentGrid: String?
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                clearSection
                gpsSuggestionSection
                customPrefixSection
                countryListSection
            }
            .searchable(text: $searchText, prompt: "Search country or prefix")
            .navigationTitle("Operating Prefix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @State private var searchText = ""
    @State private var customPrefix = ""

    private var homeCountry: PrefixCountry? {
        LocationPrefixLookup.entity(forCallsign: homeCallsign)
    }

    private var gpsSuggestion: PrefixCountry? {
        guard let grid = currentGrid,
              let nearest = LocationPrefixLookup.nearest(grid: grid)
        else {
            return nil
        }
        // Only suggest if different from home country
        if let home = homeCountry, home.id == nearest.id {
            return nil
        }
        return nearest
    }

    private var filteredCountries: [PrefixCountry] {
        LocationPrefixLookup.search(searchText)
    }

    // MARK: - Sections

    @ViewBuilder
    private var clearSection: some View {
        if !currentPrefix.isEmpty {
            Section {
                Button {
                    onSelect("")
                    dismiss()
                } label: {
                    HStack {
                        Label("No Prefix", systemImage: "xmark.circle")
                        Spacer()
                        Text("Use home callsign")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Remove prefix to operate under your home callsign.")
            }
        }
    }

    @ViewBuilder
    private var gpsSuggestionSection: some View {
        if searchText.isEmpty, let suggestion = gpsSuggestion {
            Section {
                Button {
                    onSelect(suggestion.prefix)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.name)
                                .foregroundStyle(.primary)
                            Text(suggestion.prefix)
                                .font(.subheadline.monospaced().bold())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if currentPrefix.uppercased() == suggestion.prefix.uppercased() {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            } header: {
                Text("Based on Your Location")
            } footer: {
                let formatted = portableCallsign(with: suggestion.prefix)
                Text("You would sign as **\(formatted)**")
            }
        }
    }

    private var customPrefixSection: some View {
        Section {
            HStack {
                TextField("e.g. VE3, I, F", text: $customPrefix)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.subheadline.monospaced())
                if !customPrefix.isEmpty {
                    Button("Use") {
                        onSelect(customPrefix.trimmingCharacters(in: .whitespaces).uppercased())
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Custom Prefix")
        } footer: {
            if !customPrefix.isEmpty {
                let formatted = portableCallsign(with: customPrefix)
                Text("You would sign as **\(formatted)**")
            } else {
                Text("Enter any prefix, even if not in the list below.")
            }
        }
    }

    private var countryListSection: some View {
        Section {
            ForEach(filteredCountries) { country in
                Button {
                    onSelect(country.prefix)
                    dismiss()
                } label: {
                    countryRow(country)
                }
            }
        } header: {
            if searchText.isEmpty {
                Text("All Countries")
            } else {
                Text("Results")
            }
        }
    }

    private func countryRow(_ country: PrefixCountry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(country.name)
                    .foregroundStyle(.primary)
                Text(country.prefix)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if currentPrefix.uppercased() == country.prefix.uppercased() {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func portableCallsign(with prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmed.isEmpty else {
            return homeCallsign.uppercased()
        }
        return "\(trimmed)/\(homeCallsign.uppercased())"
    }
}
