import SwiftUI

// MARK: - StationProfilePicker

/// Sheet for selecting a station profile from the user's saved list.
/// Follows the RadioPickerSheet pattern.
struct StationProfilePicker: View {
    // MARK: Internal

    @Binding var selectedProfileId: UUID?

    var body: some View {
        NavigationStack {
            List {
                if profiles.isEmpty {
                    emptyState
                } else {
                    profilesList
                }

                addProfileSection
            }
            .navigationTitle("Station Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { profiles = StationProfileStorage.load() }
            .sheet(isPresented: $showingAddProfile) {
                AddEditProfileSheet(
                    profile: nil,
                    onSave: { profile in
                        StationProfileStorage.add(profile)
                        profiles = StationProfileStorage.load()
                        selectedProfileId = profile.id
                    }
                )
            }
            .sheet(item: $editingProfile) { profile in
                AddEditProfileSheet(
                    profile: profile,
                    onSave: { updated in
                        StationProfileStorage.update(updated)
                        profiles = StationProfileStorage.load()
                    }
                )
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var profiles: [StationProfile] = []
    @State private var showingAddProfile = false
    @State private var editingProfile: StationProfile?

    private var emptyState: some View {
        Section {
            Text("No profiles yet. Add one to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var profilesList: some View {
        Section {
            ForEach(profiles) { profile in
                Button {
                    selectedProfileId = profile.id
                    dismiss()
                } label: {
                    profileRow(profile)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteProfile(profile)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        editingProfile = profile
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private var addProfileSection: some View {
        Section {
            Button {
                showingAddProfile = true
            } label: {
                Label("Add Station Profile", systemImage: "plus.circle")
            }
        }
    }

    private func profileRow(_ profile: StationProfile) -> some View {
        HStack {
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

            Spacer()

            if selectedProfileId == profile.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func deleteProfile(_ profile: StationProfile) {
        StationProfileStorage.remove(profile.id)
        profiles = StationProfileStorage.load()
        if selectedProfileId == profile.id {
            selectedProfileId = profiles.first?.id
        }
    }
}
