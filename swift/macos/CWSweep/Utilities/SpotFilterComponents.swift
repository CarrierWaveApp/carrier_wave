import SwiftUI

// MARK: - SpotFilterConstants

/// Shared constants for spot filtering across views
enum SpotFilterConstants {
    /// Standard HF + 6m amateur bands used in filter pickers
    static let commonBands = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m",
    ]
}

// MARK: - BandFilterPicker

/// Reusable band filter picker with "All" option + common amateur bands
struct BandFilterPicker: View {
    @Binding var selectedBand: String

    var body: some View {
        Picker("Band", selection: $selectedBand) {
            Text("All").tag("All")
            ForEach(SpotFilterConstants.commonBands, id: \.self) { band in
                Text(band).tag(band)
            }
        }
        .labelsHidden()
        .frame(width: 75)
    }
}

// MARK: - ModeFilterPicker

/// Reusable mode filter picker (CW/Phone/Digital/All) as a segmented control
struct ModeFilterPicker: View {
    @Binding var selectedMode: SpotModeFilter

    var body: some View {
        Picker(selection: $selectedMode) {
            ForEach(SpotModeFilter.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }
}

// MARK: - CompactSpotFilterBar

/// Compact filter bar using labeled multi-select dropdown menus.
/// Designed for space-constrained layouts like the activator bottom pane.
struct CompactSpotFilterBar: View {
    @Binding var selectedSources: Set<SpotSourceFilter>
    @Binding var selectedBands: Set<String>
    @Binding var selectedModes: Set<SpotModeFilter>
    @Binding var filterText: String

    var selectedContinents: Binding<Set<SpotContinent>>?
    var selectedRegions: Binding<Set<SpotRegionGroup>>?

    var body: some View {
        HStack(spacing: 6) {
            MultiSelectDropdown(
                title: "Source",
                options: SpotSourceFilter.allCases.filter { $0 != .all }
                    .map { ($0.displayName, $0) },
                selection: $selectedSources
            )
            MultiSelectDropdown(
                title: "Band",
                options: SpotFilterConstants.commonBands.map { ($0, $0) },
                selection: $selectedBands
            )
            MultiSelectDropdown(
                title: "Mode",
                options: SpotModeFilter.allCases.filter { $0 != .all }
                    .map { ($0.displayName, $0) },
                selection: $selectedModes
            )
            if let continents = selectedContinents, let regions = selectedRegions {
                GeographicFilterDropdowns(
                    selectedContinents: continents,
                    selectedRegions: regions
                )
            }
            SpotSearchField(text: $filterText, showClearButton: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - MultiSelectDropdown

/// Labeled multi-select dropdown menu with consistent compact styling.
struct MultiSelectDropdown<T: Hashable>: View {
    // MARK: Internal

    let title: String
    let options: [(String, T)]

    @Binding var selection: Set<T>

    var body: some View {
        Menu {
            Button {
                selection.removeAll()
            } label: {
                if selection.isEmpty {
                    Label("All", systemImage: "checkmark")
                } else {
                    Text("All")
                }
            }
            Divider()
            ForEach(options, id: \.1) { name, value in
                Button {
                    if selection.contains(value) {
                        selection.remove(value)
                    } else {
                        selection.insert(value)
                    }
                } label: {
                    if selection.contains(value) {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(summaryLabel)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: Private

    private var summaryLabel: String {
        if selection.isEmpty {
            return "All"
        }
        if selection.count == 1, let first = options.first(where: { selection.contains($0.1) }) {
            return first.0
        }
        return "\(selection.count) selected"
    }
}

// MARK: - GeographicFilterDropdowns

/// Compact multi-select dropdowns for continent and region filtering.
/// Empty selection = "All" (no filtering). Region options are scoped to
/// selected continents when any are active.
struct GeographicFilterDropdowns: View {
    // MARK: Internal

    @Binding var selectedContinents: Set<SpotContinent>
    @Binding var selectedRegions: Set<SpotRegionGroup>

    var body: some View {
        MultiSelectDropdown(
            title: "Continent",
            options: SpotContinent.allCases.map { ($0.displayName, $0) },
            selection: $selectedContinents
        )
        MultiSelectDropdown(
            title: "Region",
            options: availableRegionOptions,
            selection: $selectedRegions
        )
    }

    // MARK: Private

    private var availableRegionOptions: [(String, SpotRegionGroup)] {
        SpotRegionGroup.allCases
            .filter { group in
                selectedContinents.isEmpty || selectedContinents.contains(group.continent)
            }
            .map { ($0.rawValue, $0) }
    }
}

// MARK: - SpotSearchField

/// Reusable search/filter text field with magnifying glass icon
struct SpotSearchField: View {
    @Binding var text: String

    var showClearButton = false
    var width: CGFloat?

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter...", text: $text)
                .textFieldStyle(.plain)
            if showClearButton, !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .frame(minWidth: width ?? 100, idealWidth: width, maxWidth: width)
    }
}
