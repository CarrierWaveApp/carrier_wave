import CarrierWaveData
import SwiftUI

// MARK: - ActivityLogSettingsView

/// Settings for the activity log feature.
/// Accessible from the gear icon on ActivityLogView and from main Settings.
struct ActivityLogSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            SettingsHeroHeader(
                icon: "binoculars.fill",
                tint: .green,
                title: "Hunter Log",
                subtitle: "Spots, respots, and quick-log for hunting."
            )
            stationProfilesSection
            quickLogSection
            spotFilteringSection
            huntedSpotSection
            respotSection
            dailyGoalSection
        }
        .navigationTitle("Hunter Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profileCount = StationProfileStorage.load().count }
    }

    // MARK: Private

    private static let ageOptions = [5, 10, 12, 15, 20, 30]

    @AppStorage("hunterLogShowFields") private var showFields = false
    @AppStorage("huntedSpotBehavior") private var huntedSpotBehaviorRaw = HuntedSpotBehavior.crossOut.rawValue
    @AppStorage("activityLogDailyGoalEnabled") private var dailyGoalEnabled = false
    @AppStorage("activityLogDailyGoal") private var dailyGoal = 10
    @AppStorage("spotMaxAgeMinutes") private var spotMaxAgeMinutes = 12
    @AppStorage("spotRegionFilter") private var spotRegionFilterRaw = ""
    @AppStorage("potaHunterRespotEnabled") private var respotEnabled = true
    @AppStorage("potaHunterRespotCustomMessage") private var respotCustomMessage = false
    @AppStorage("potaHunterRespotDefaultMessage") private var respotDefaultMessage = "tnx"
    @State private var profileCount = 0

    private var selectedContinents: Set<SpotContinent> {
        SpotContinent.decode(spotRegionFilterRaw)
    }

    private var continentSummary: String {
        let continents = selectedContinents
        if continents == SpotContinent.allSet || continents.isEmpty {
            return "All"
        }
        return "\(continents.count) of \(SpotContinent.allCases.count)"
    }

    private var quickLogSection: some View {
        Section {
            Toggle("Show Extra Fields", isOn: $showFields)
        } header: {
            Text("Quick Log")
        } footer: {
            Text("Show RST, QTH, grid, park, and notes fields below the callsign entry.")
        }
    }

    private var spotFilteringSection: some View {
        Section {
            Picker("Max Spot Age", selection: $spotMaxAgeMinutes) {
                ForEach(Self.ageOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }

            NavigationLink {
                ContinentPickerView(
                    selectedContinents: Binding(
                        get: { SpotContinent.decode(spotRegionFilterRaw) },
                        set: { spotRegionFilterRaw = SpotContinent.encode($0) }
                    )
                )
            } label: {
                HStack {
                    Text("Continents")
                    Spacer()
                    Text(continentSummary)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Spots")
        } footer: {
            Text("Spots older than the max age are hidden. Continent filter controls which areas appear.")
        }
    }

    private var huntedSpotSection: some View {
        Section {
            Picker("Hunted Spots", selection: $huntedSpotBehaviorRaw) {
                ForEach(HuntedSpotBehavior.allCases, id: \.rawValue) { behavior in
                    Text(behavior.label).tag(behavior.rawValue)
                }
            }
        } footer: {
            Text(
                "When you work a spotted station on the same band, " +
                    "it can be crossed out or hidden from the list."
            )
        }
    }

    private var respotSection: some View {
        Section {
            Toggle("Auto-respot on POTA hunt", isOn: $respotEnabled)

            if respotEnabled {
                TextField("Default message", text: $respotDefaultMessage)
                    .autocorrectionDisabled()

                Toggle("Prompt for custom message", isOn: $respotCustomMessage)
            }
        } header: {
            Text("Hunter Respots")
        } footer: {
            Text(
                "Automatically respot an activator on POTA after logging from a spot. "
                    + "Requires POTA account credentials in Logbook Services."
            )
        }
    }

    private var stationProfilesSection: some View {
        Section("Station Profiles") {
            NavigationLink {
                StationProfileListView(onProfilesChanged: {
                    profileCount = StationProfileStorage.load().count
                })
            } label: {
                HStack {
                    Text("Manage Profiles")
                    Spacer()
                    Text("\(profileCount) profile\(profileCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var dailyGoalSection: some View {
        Section("Daily Goal") {
            Toggle("Enable Daily Goal", isOn: $dailyGoalEnabled)

            if dailyGoalEnabled {
                Stepper(
                    "Goal: \(dailyGoal) QSOs",
                    value: $dailyGoal,
                    in: 1 ... 100,
                    step: 5
                )
            }
        }
    }
}

// MARK: - ContinentPickerView

/// Multiselect picker for spot continents.
struct ContinentPickerView: View {
    // MARK: Internal

    @Binding var selectedContinents: Set<SpotContinent>

    var body: some View {
        List {
            Section {
                ForEach(SpotContinent.allCases, id: \.self) { cont in
                    Button {
                        toggleContinent(cont)
                    } label: {
                        HStack {
                            Text(cont.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedContinents.contains(cont) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } footer: {
                Text("Select which continents to show spots from. Tap to toggle.")
            }

            Section {
                Button("Select All") {
                    selectedContinents = SpotContinent.allSet
                }
                .disabled(selectedContinents == SpotContinent.allSet)

                Button("Deselect All") {
                    selectedContinents = []
                }
                .disabled(selectedContinents.isEmpty)
            }
        }
        .navigationTitle("Continents")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    private func toggleContinent(_ cont: SpotContinent) {
        if selectedContinents.contains(cont) {
            selectedContinents.remove(cont)
        } else {
            selectedContinents.insert(cont)
        }
    }
}

// MARK: - StationProfileListView

/// Full-screen list of station profiles for management.
struct StationProfileListView: View {
    // MARK: Internal

    var onProfilesChanged: (() -> Void)?

    var body: some View {
        List {
            if profiles.isEmpty {
                Text("No station profiles yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profiles) { profile in
                    profileRow(profile)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                StationProfileStorage.remove(profile.id)
                                reloadProfiles()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }

            Button {
                showingAddProfile = true
            } label: {
                Label("Add Station Profile", systemImage: "plus.circle")
            }
        }
        .navigationTitle("Station Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profiles = StationProfileStorage.load() }
        .sheet(isPresented: $showingAddProfile) {
            AddEditProfileSheet(
                profile: nil,
                onSave: { profile in
                    StationProfileStorage.add(profile)
                    reloadProfiles()
                }
            )
        }
        .sheet(item: $editingProfile) { profile in
            AddEditProfileSheet(
                profile: profile,
                onSave: { updated in
                    StationProfileStorage.update(updated)
                    reloadProfiles()
                }
            )
        }
    }

    // MARK: Private

    @State private var profiles: [StationProfile] = []
    @State private var showingAddProfile = false
    @State private var editingProfile: StationProfile?

    private func profileRow(_ profile: StationProfile) -> some View {
        Button {
            editingProfile = profile
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(profile.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if profile.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text(profile.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let grid = profile.grid, !grid.isEmpty {
                    Text(grid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reloadProfiles() {
        profiles = StationProfileStorage.load()
        onProfilesChanged?()
    }
}
