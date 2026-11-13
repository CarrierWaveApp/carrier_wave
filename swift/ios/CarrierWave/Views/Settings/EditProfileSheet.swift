import CarrierWaveData
import SwiftUI

// MARK: - EditProfileSheet

/// Modal editor for the local UserProfile fields. Presented from the
/// AboutMe page so the read view stays clean and dense.
struct EditProfileSheet: View {
    // MARK: Lifecycle

    init(profile: UserProfile, onSave: @escaping (UserProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _firstName = State(initialValue: profile.firstName ?? "")
        _lastName = State(initialValue: profile.lastName ?? "")
        _city = State(initialValue: profile.city ?? "")
        _state = State(initialValue: profile.state ?? "")
        _grid = State(initialValue: profile.grid ?? "")
        _licenseClass = State(initialValue: profile.licenseClass?.rawValue ?? "Extra")
    }

    // MARK: Internal

    let profile: UserProfile
    let onSave: (UserProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                } header: {
                    Text("Name")
                }

                Section {
                    TextField("City", text: $city)
                    TextField("State", text: $state)
                    TextField("Grid Square", text: $grid)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Location")
                }

                Section {
                    Picker("License Class", selection: $licenseClass) {
                        Text("Technician").tag("Technician")
                        Text("General").tag("General")
                        Text("Extra").tag("Extra")
                    }
                } header: {
                    Text("License")
                } footer: {
                    Text("Changes are saved locally and used throughout the app.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var city: String
    @State private var state: String
    @State private var grid: String
    @State private var licenseClass: String

    private func save() {
        let updated = UserProfile(
            callsign: profile.callsign,
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            country: profile.country,
            grid: grid.isEmpty ? nil : grid,
            licenseClass: LicenseClass(rawValue: licenseClass),
            licenseExpires: profile.licenseExpires
        )
        onSave(updated)
        dismiss()
    }
}
