import SwiftUI

// MARK: - OnAirSettingsView

/// Settings for which sections appear on the On Air Now card and sheet,
/// plus band/mode filters for operator spots.
struct OnAirSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "dot.radiowaves.left.and.right",
                tint: .red,
                title: "On Air Now",
                subtitle: "What appears on the On Air Now card."
            )
            sectionsToggleSection
            ageFilterSection
            fetchLimitSection
            bandFilterSection
            modeFilterSection
        }
        .navigationTitle("On Air Now")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    private static let selectableBands: [BandFilter] = BandFilter.allCases
        .filter { $0 != .all }

    private static let selectableModes: [ModeFilter] = ModeFilter.allCases
        .filter { $0 != .all }

    private static let ageOptions = [5, 10, 15, 20, 30, 60]

    @AppStorage("onAirShowConditions") private var showConditions = true
    @AppStorage("onAirShowDXpeditions") private var showDXpeditions = true
    @AppStorage("onAirShowContests") private var showContests = true
    @AppStorage("onAirShowFriendSpots") private var showFriendSpots = true
    @AppStorage("onAirShowPOTASpots") private var showPOTASpots = true
    @AppStorage("onAirShowSOTASpots") private var showSOTASpots = true

    @AppStorage("onAirSpotMaxAgeMinutes") private var spotMaxAgeMinutes = 30
    @AppStorage(SpotFetchLimits.onAirSOTAKey)
    private var sotaFetchLimit = SpotFetchLimits.onAirSOTADefault
    @AppStorage("onAirBandFilter") private var bandFilterRaw = ""
    @AppStorage("onAirModeFilter") private var modeFilterRaw = ""

    private var selectedBands: Set<String> {
        OnAirSpotFilter.decodeSet(from: bandFilterRaw)
    }

    private var selectedModes: Set<String> {
        OnAirSpotFilter.decodeSet(from: modeFilterRaw)
    }

    // MARK: - Sections

    private var sectionsToggleSection: some View {
        Section {
            Toggle(isOn: $showConditions) {
                Label("Solar Conditions", systemImage: "sun.max.fill")
            }
            Toggle(isOn: $showDXpeditions) {
                Label("DXpeditions", systemImage: "globe")
            }
            Toggle(isOn: $showContests) {
                Label("Contests", systemImage: "flag.2.crossed")
            }
            Toggle(isOn: $showFriendSpots) {
                Label("Friend Spots", systemImage: "person.2")
            }
            Toggle(isOn: $showPOTASpots) {
                Label("POTA Spots", systemImage: "leaf.fill")
            }
            Toggle(isOn: $showSOTASpots) {
                Label("SOTA Spots", systemImage: "mountain.2.fill")
            }
        } header: {
            Text("Visible Sections")
        } footer: {
            Text(
                "Choose which sections appear on the On Air Now "
                    + "card and expanded sheet."
            )
        }
    }

    private var ageFilterSection: some View {
        Section {
            Picker("Max Spot Age", selection: $spotMaxAgeMinutes) {
                ForEach(Self.ageOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
        } footer: {
            Text("Hide spots older than this.")
        }
    }

    private var fetchLimitSection: some View {
        Section {
            Picker("Max SOTA Spots", selection: $sotaFetchLimit) {
                ForEach(SpotFetchLimits.onAirSOTAOptions, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
        } header: {
            Text("Fetch Limit")
        } footer: {
            Text(
                "How many SOTA spots to pull per refresh. "
                    + "POTA spots are unlimited from the source."
            )
        }
    }

    private var bandFilterSection: some View {
        Section {
            ForEach(Self.selectableBands) { band in
                let isSelected = selectedBands.contains(band.rawValue)
                Button {
                    toggleBand(band.rawValue)
                } label: {
                    HStack {
                        Text(band.rawValue)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Bands")
        } footer: {
            if selectedBands.isEmpty {
                Text("Showing all bands. Tap to select specific bands.")
            } else {
                Text("Showing \(selectedBands.count) band(s). Tap to toggle.")
            }
        }
    }

    private var modeFilterSection: some View {
        Section {
            ForEach(Self.selectableModes) { mode in
                let isSelected = selectedModes.contains(mode.rawValue)
                Button {
                    toggleMode(mode.rawValue)
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Modes")
        } footer: {
            if selectedModes.isEmpty {
                Text("Showing all modes. Tap to select specific modes.")
            } else {
                Text("Showing \(selectedModes.count) mode(s). Tap to toggle.")
            }
        }
    }

    private func toggleBand(_ band: String) {
        var bands = selectedBands
        if bands.contains(band) {
            bands.remove(band)
        } else {
            bands.insert(band)
        }
        bandFilterRaw = OnAirSpotFilter.encodeSet(bands)
    }

    private func toggleMode(_ mode: String) {
        var modes = selectedModes
        if modes.contains(mode) {
            modes.remove(mode)
        } else {
            modes.insert(mode)
        }
        modeFilterRaw = OnAirSpotFilter.encodeSet(modes)
    }
}
