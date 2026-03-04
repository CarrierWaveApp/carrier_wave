import SwiftUI

// MARK: - AboutMeView

/// View for displaying and editing the user's profile information
struct AboutMeView: View {
    // MARK: Internal

    var onRequestOnboarding: (() -> Void)?

    var body: some View {
        Form {
            if let profile {
                profileSection(profile)
                editSection
                actionsSection
            } else {
                noProfileSection
            }
        }
        .navigationTitle("About Me")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadProfile() }
        .alert("Profile Updated", isPresented: $showSaveSuccess) {
            Button("OK") {}
        } message: {
            Text("Your profile has been updated.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Refresh Profile?", isPresented: $showRefreshConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Refresh") {
                Task { await refreshProfile() }
            }
        } message: {
            Text("This will look up your information from HamDB and update your profile.")
        }
    }

    // MARK: Private

    @State private var profile: UserProfile?
    @State private var editedFirstName = ""
    @State private var editedLastName = ""
    @State private var editedCity = ""
    @State private var editedState = ""
    @State private var editedGrid = ""
    @State private var editedLicenseClass = "Extra"

    @State private var isRefreshing = false
    @State private var showSaveSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showRefreshConfirmation = false
    @State private var callsignChangeNote: String?

    private let profileService = UserProfileService.shared

    private var editSection: some View {
        Section {
            TextField("First Name", text: $editedFirstName)
            TextField("Last Name", text: $editedLastName)
            TextField("City", text: $editedCity)
            TextField("State", text: $editedState)
            TextField("Grid Square", text: $editedGrid)
                .autocapitalization(.allCharacters)

            Picker("License Class", selection: $editedLicenseClass) {
                Text("Technician").tag("Technician")
                Text("General").tag("General")
                Text("Extra").tag("Extra")
            }

            Button("Save Changes") {
                saveProfile()
            }
        } header: {
            Text("Edit")
        } footer: {
            Text("Changes are saved locally and used throughout the app.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showRefreshConfirmation = true
            } label: {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Refreshing...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh from HamDB")
                    }
                }
            }
            .disabled(isRefreshing)

            Button {
                onRequestOnboarding?()
            } label: {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text("Change Callsign")
                }
            }
        } header: {
            Text("Actions")
        } footer: {
            Text(
                "Refresh re-fetches your information from HamDB.org. "
                    + "Change Callsign lets you set up a different callsign."
            )
        }
    }

    private var noProfileSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("No Profile Set Up")
                    .font(.headline)

                Text(
                    "Your profile will be set up automatically during onboarding, or you can set it up manually."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Button("Set Up Profile") {
                    onRequestOnboarding?()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func profileSection(_ profile: UserProfile) -> some View {
        Section {
            HStack {
                Text(profile.callsign)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .monospaced()
                Spacer()
                if let licenseClass = profile.licenseClass {
                    Text(licenseClass.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }

            if let name = profile.fullName {
                HStack {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                    Text(name)
                }
            }

            if let location = profile.fullLocation {
                HStack {
                    Image(systemName: "location")
                        .foregroundStyle(.secondary)
                    Text(location)
                }
            }

            if let grid = profile.grid {
                HStack {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(.secondary)
                    Text(grid)
                }
            }

            if let expires = profile.licenseExpires {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("License expires: \(expires)")
                }
            }

            if let changeNote = callsignChangeNote {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                    Text(changeNote)
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
        } header: {
            Text("Profile")
        }
    }

    private func loadProfile() {
        profile = profileService.getProfile()

        if let profile {
            editedFirstName = profile.firstName ?? ""
            editedLastName = profile.lastName ?? ""
            editedCity = profile.city ?? ""
            editedState = profile.state ?? ""
            editedGrid = profile.grid ?? ""
            editedLicenseClass = profile.licenseClass?.rawValue ?? "Extra"
        }
    }

    private func saveProfile() {
        guard let existingProfile = profile else {
            return
        }

        let licenseClass = LicenseClass(rawValue: editedLicenseClass)

        let updatedProfile = UserProfile(
            callsign: existingProfile.callsign,
            firstName: editedFirstName.isEmpty ? nil : editedFirstName,
            lastName: editedLastName.isEmpty ? nil : editedLastName,
            city: editedCity.isEmpty ? nil : editedCity,
            state: editedState.isEmpty ? nil : editedState,
            country: existingProfile.country,
            grid: editedGrid.isEmpty ? nil : editedGrid,
            licenseClass: licenseClass,
            licenseExpires: existingProfile.licenseExpires
        )

        do {
            try profileService.saveProfile(updatedProfile)
            profile = updatedProfile
            showSaveSuccess = true
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
            showError = true
        }
    }

    private func refreshProfile() async {
        guard let existingProfile = profile else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let result = try await profileService.lookupAndCreateProfileWithChangeDetection(
                callsign: existingProfile.callsign
            )

            if let newProfile = result.profile {
                try profileService.saveProfile(newProfile)

                await MainActor.run {
                    profile = newProfile
                    callsignChangeNote = result.callsignChangeNote
                    loadProfile()
                    showSaveSuccess = true
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to refresh profile: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AboutMeView()
    }
}
