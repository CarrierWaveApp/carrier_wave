import SwiftUI

// MARK: - HuntSettingsView

/// Persistent preferences for HUNT and P2P spot panels.
/// Band/mode filters are session-scoped (set dynamically from the filter sheet).
struct HuntSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            SettingsHeroHeader(
                icon: "scope",
                tint: .orange,
                title: "Hunt & P2P",
                subtitle: "Spot sources and filters for Hunt & P2P."
            )
            ageSection
            fetchLimitSection
            activitySection
            clusterSection
            clubSection
            friendSection
        }
        .navigationTitle("Hunt & P2P")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: clusterHost) { _, _ in
            SpotEngineProvider.shared.applyClusterConnection()
        }
        .onChange(of: clusterPort) { _, _ in
            SpotEngineProvider.shared.applyClusterConnection()
        }
    }

    // MARK: Private

    /// Well-known telnet cluster nodes (mirrors Sweep's `ClusterNode.presets`).
    private struct ClusterPreset {
        let name: String
        let host: String
        let port: Int
    }

    private static let clusterPresets = [
        ClusterPreset(name: "W3LPL", host: "w3lpl.net", port: 7_373),
        ClusterPreset(name: "VE7CC", host: "dxc.ve7cc.net", port: 23),
        ClusterPreset(name: "N1MM", host: "n1mm.net", port: 7_300),
        ClusterPreset(name: "AB5K", host: "dxc.ab5k.net", port: 7_300),
        ClusterPreset(name: "K1TTT", host: "k1ttt.net", port: 7_373),
    ]

    private static let ageOptions = [5, 10, 15, 20, 30, 60]

    @AppStorage(SpotEngineProvider.clusterHostKey)
    private var clusterHost = SpotEngineProvider.defaultClusterHost
    @AppStorage(SpotEngineProvider.clusterPortKey)
    private var clusterPort = SpotEngineProvider.defaultClusterPort
    @AppStorage("huntSpotMaxAgeMinutes") private var spotMaxAgeMinutes = 30
    @AppStorage(SpotFetchLimits.huntRBNKey)
    private var rbnFetchLimit = SpotFetchLimits.huntRBNDefault
    @AppStorage(SpotFetchLimits.huntSOTAKey)
    private var sotaFetchLimit = SpotFetchLimits.huntSOTADefault
    @AppStorage("huntShowPOTA") private var showPOTA = true
    @AppStorage("huntShowSOTA") private var showSOTA = true
    @AppStorage("huntShowClubSection") private var showClubSection = true
    @AppStorage("huntClubFilter") private var clubFilterRaw = ""
    @AppStorage("huntShowFriends") private var showFriends = true

    private var selectedClubs: Set<String> {
        OnAirSpotFilter.decodeSet(from: clubFilterRaw)
    }

    private var availableClubs: [String] {
        ClubsSyncService.shared.callsignsByClub.keys.sorted()
    }

    private var presetName: String? {
        Self.clusterPresets
            .first { $0.host == clusterHost && $0.port == clusterPort }?
            .name
    }

    // MARK: - Sections

    private var ageSection: some View {
        Section {
            Picker("Max Spot Age", selection: $spotMaxAgeMinutes) {
                ForEach(Self.ageOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
        } footer: {
            Text("Hide spots older than this in Hunt and P2P panels.")
        }
    }

    private var fetchLimitSection: some View {
        Section {
            Picker("Max RBN Spots", selection: $rbnFetchLimit) {
                ForEach(SpotFetchLimits.huntRBNOptions, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
            Picker("Max SOTA Spots", selection: $sotaFetchLimit) {
                ForEach(SpotFetchLimits.huntSOTAOptions, id: \.self) { limit in
                    Text("\(limit)").tag(limit)
                }
            }
        } header: {
            Text("Fetch Limits")
        } footer: {
            Text(
                "How many spots to pull from each source per refresh. "
                    + "Higher values show more activity but use more data."
            )
        }
    }

    private var activitySection: some View {
        Section {
            Toggle(isOn: $showPOTA) {
                Label("POTA Spots", systemImage: "leaf.fill")
            }
            Toggle(isOn: $showSOTA) {
                Label("SOTA Spots", systemImage: "mountain.2.fill")
            }
        } header: {
            Text("Activities")
        } footer: {
            Text("Choose which activity types appear in Hunt spots.")
        }
    }

    private var clubSection: some View {
        Section {
            Toggle(isOn: $showClubSection) {
                Label("Club Members", systemImage: "person.3.fill")
            }

            if showClubSection, !availableClubs.isEmpty {
                ForEach(availableClubs, id: \.self) { club in
                    let isSelected = selectedClubs.contains(club)
                    Button {
                        toggleClub(club)
                    } label: {
                        HStack {
                            Text(club)
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
            }
        } header: {
            Text("Clubs")
        } footer: {
            if !showClubSection {
                Text("Club member section is hidden in Hunt spots.")
            } else if selectedClubs.isEmpty {
                Text(
                    "Showing all clubs. "
                        + "Tap a club to filter to specific clubs."
                )
            } else {
                Text("Showing \(selectedClubs.count) club(s).")
            }
        }
    }

    private var clusterSection: some View {
        Section {
            Menu {
                ForEach(Self.clusterPresets, id: \.name) { preset in
                    Button("\(preset.name) — \(preset.host)") {
                        clusterHost = preset.host
                        clusterPort = preset.port
                    }
                }
            } label: {
                HStack {
                    Label("Node Presets", systemImage: "server.rack")
                    Spacer()
                    Text(presetName ?? "Custom")
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Host", text: $clusterHost)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField("Port", value: $clusterPort, format: .number.grouping(.never))
                .keyboardType(.numberPad)
        } header: {
            Text("DX Cluster")
        } footer: {
            Text(
                "Used when the Cluster source is enabled in the Hunt spot "
                    + "filter. Logs in with your callsign."
            )
        }
    }

    private var friendSection: some View {
        Section {
            Toggle(isOn: $showFriends) {
                Label("Highlight Friends", systemImage: "person.2.fill")
            }
        } header: {
            Text("Friends")
        } footer: {
            Text(
                showFriends
                    ? "Friend callsigns are highlighted in Hunt spots."
                    : "Friend highlighting is disabled."
            )
        }
    }

    // MARK: - Helpers

    private func toggleClub(_ club: String) {
        var clubs = selectedClubs
        if clubs.contains(club) {
            clubs.remove(club)
        } else {
            clubs.insert(club)
        }
        clubFilterRaw = OnAirSpotFilter.encodeSet(clubs)
    }
}
