import CarrierWaveData
import SwiftUI

// MARK: - ActivityLogSettingsView

/// Settings for the activity log feature.
/// Accessible from the gear icon on ActivityLogView and from main Settings.
struct ActivityLogSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            stationProfilesSection
            quickLogSection
            spotFilteringSection
            huntedSpotSection
            respotSection
            uploadSection
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

    @State private var qrzConnected = false
    @State private var lofiConnected = false

    private let qrzClient = QRZClient()
    private let lofiClient = LoFiClient.appDefault()

    private var selectedRegions: Set<SpotRegionGroup> {
        SpotRegionGroup.decode(spotRegionFilterRaw)
    }

    private var regionSummary: String {
        let regions = selectedRegions
        if regions == SpotRegionGroup.allSet || regions.isEmpty {
            return "All"
        }
        return "\(regions.count) of \(SpotRegionGroup.allCases.count)"
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
                RegionPickerView(
                    selectedRegions: Binding(
                        get: { SpotRegionGroup.decode(spotRegionFilterRaw) },
                        set: { spotRegionFilterRaw = SpotRegionGroup.encode($0) }
                    )
                )
            } label: {
                HStack {
                    Text("Spot Regions")
                    Spacer()
                    Text(regionSummary)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Spots")
        } footer: {
            Text("Spots older than the max age are hidden. Region filter controls which areas appear.")
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
                    + "Requires POTA account credentials in Sync Sources."
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

    private var uploadSection: some View {
        Section {
            NavigationLink {
                QRZSettingsView()
            } label: {
                HStack {
                    Text("QRZ Logbook")
                    Spacer()
                    if qrzConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            NavigationLink {
                LoFiSettingsView(tourState: TourState())
            } label: {
                HStack {
                    Text("Ham2K LoFi")
                    Spacer()
                    if lofiConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack {
                Text("POTA")
                Spacer()
                Text("Not applicable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Upload Services")
        } footer: {
            Text(
                "Hunter log QSOs upload to QRZ and LoFi. " +
                    "POTA upload requires an activation session with a park reference."
            )
        }
        .task {
            qrzConnected = qrzClient.hasApiKey()
            lofiConnected = lofiClient.isConfigured
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

// MARK: - RegionPickerView

/// Multiselect picker for spot region groups.
struct RegionPickerView: View {
    // MARK: Internal

    @Binding var selectedRegions: Set<SpotRegionGroup>

    var body: some View {
        List {
            Section {
                ForEach(SpotRegionGroup.allCases, id: \.self) { region in
                    Button {
                        toggleRegion(region)
                    } label: {
                        HStack {
                            Text(region.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedRegions.contains(region) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } footer: {
                Text("Select which regions to show spots from. Tap to toggle.")
            }

            Section {
                Button("Select All") {
                    selectedRegions = SpotRegionGroup.allSet
                }
                .disabled(selectedRegions == SpotRegionGroup.allSet)

                Button("Deselect All") {
                    selectedRegions = []
                }
                .disabled(selectedRegions.isEmpty)
            }
        }
        .navigationTitle("Spot Regions")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    private func toggleRegion(_ region: SpotRegionGroup) {
        if selectedRegions.contains(region) {
            selectedRegions.remove(region)
        } else {
            selectedRegions.insert(region)
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
