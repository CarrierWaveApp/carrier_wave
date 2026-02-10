import SwiftUI

// MARK: - ActivityLogSettingsView

/// Settings for the activity log feature.
/// Accessible from the gear icon on ActivityLogView and from main Settings.
struct ActivityLogSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            stationProfilesSection
            uploadSection
            dailyGoalSection
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { profileCount = StationProfileStorage.load().count }
    }

    // MARK: Private

    @AppStorage("activityLogDailyGoalEnabled") private var dailyGoalEnabled = false
    @AppStorage("activityLogDailyGoal") private var dailyGoal = 10
    @State private var profileCount = 0

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
