import SwiftUI

// MARK: - ActivityLogSettingsView

/// Settings for the activity log feature.
/// Accessible from the gear icon on ActivityLogView and from main Settings.
struct ActivityLogSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            stationProfilesSection
            spotFilteringSection
            uploadSection
            dailyGoalSection
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profileCount = StationProfileStorage.load().count }
    }

    // MARK: Private

    private static let ageOptions = [5, 10, 12, 15, 20, 30]
    private static let radiusOptions = [100, 250, 500, 1_000, 1_500, 2_000]

    @AppStorage("activityLogDailyGoalEnabled") private var dailyGoalEnabled = false
    @AppStorage("activityLogDailyGoal") private var dailyGoal = 10
    @AppStorage("spotMaxAgeMinutes") private var spotMaxAgeMinutes = 12
    @AppStorage("spotProximityRadiusMiles") private var proximityRadiusMiles = 500
    @State private var profileCount = 0

    private var spotFilteringSection: some View {
        Section {
            Picker("Max Spot Age", selection: $spotMaxAgeMinutes) {
                ForEach(Self.ageOptions, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }

            Picker("Proximity Radius", selection: $proximityRadiusMiles) {
                ForEach(Self.radiusOptions, id: \.self) { miles in
                    Text("\(miles) mi").tag(miles)
                }
            }
        } header: {
            Text("Spots")
        } footer: {
            Text(
                "Spots older than the max age are hidden. " +
                    "Proximity radius applies when \"Heard Nearby\" is enabled in the spot filter."
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
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("QRZ Logbook")
                Spacer()
                Text("Enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ham2K LoFi")
                Spacer()
                Text("Enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
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
                "Activity log QSOs upload to QRZ and LoFi. " +
                    "POTA upload requires an activation session with a park reference."
            )
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
