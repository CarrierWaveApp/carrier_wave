import CarrierWaveData
import SwiftUI

// MARK: - AddEditProfileSheet

/// Sheet for adding or editing a station profile.
/// Reuses RadioPickerSheet for radio selection.
struct AddEditProfileSheet: View {
    // MARK: Lifecycle

    init(profile: StationProfile?, onSave: @escaping (StationProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave

        let existing = profile
        profileId = existing?.id ?? UUID()
        _name = State(initialValue: existing?.name ?? "")
        _rig = State(initialValue: existing?.rig)
        _powerText = State(initialValue: existing?.power.map { "\($0)" } ?? "")
        _antenna = State(initialValue: existing?.antenna)
        _key = State(initialValue: existing?.key)
        _mic = State(initialValue: existing?.mic)
        _grid = State(initialValue: existing?.grid ?? "")
        _useCurrentLocation = State(initialValue: existing?.useCurrentLocation ?? false)
        _isDefault = State(initialValue: existing?.isDefault ?? false)
    }

    // MARK: Internal

    /// Pass nil to create a new profile, or an existing profile to edit
    let profile: StationProfile?
    let onSave: (StationProfile) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Equipment") {
                    HStack {
                        Text("Radio")
                        Spacer()
                        Button(rig ?? "None") {
                            showingRadioPicker = true
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Power (W)")
                        Spacer()
                        TextField("Watts", text: $powerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Antenna")
                        Spacer()
                        Button(antenna ?? "None") {
                            showingAntennaPicker = true
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Key")
                        Spacer()
                        Button(key ?? "None") {
                            showingKeyPicker = true
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Microphone")
                        Spacer()
                        Button(mic ?? "None") {
                            showingMicPicker = true
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    Toggle("Use Current Location", isOn: $useCurrentLocation)

                    if useCurrentLocation {
                        HStack {
                            Label {
                                if locationService.isLocating {
                                    Text("Locating...")
                                        .foregroundStyle(.secondary)
                                } else if let gpsGrid = locationService.currentGrid {
                                    Text(gpsGrid)
                                        .font(.body.monospaced())
                                } else {
                                    Text("Waiting for GPS")
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "location.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    } else {
                        TextField("Grid Square", text: $grid)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Toggle("Set as Default", isOn: $isDefault)
                }
            }
            .navigationTitle(isEditing ? "Edit Profile" : "New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespaces).isEmpty
                        )
                }
            }
            .task {
                if useCurrentLocation {
                    locationService.requestGrid()
                }
            }
            .onChange(of: useCurrentLocation) { _, isOn in
                if isOn {
                    locationService.requestGrid()
                }
            }
            .sheet(isPresented: $showingRadioPicker) {
                RadioPickerSheet(selection: $rig)
            }
            .sheet(isPresented: $showingAntennaPicker) {
                EquipmentPickerSheet(
                    equipmentType: .antenna,
                    selection: $antenna
                )
            }
            .sheet(isPresented: $showingKeyPicker) {
                EquipmentPickerSheet(
                    equipmentType: .key,
                    selection: $key
                )
            }
            .sheet(isPresented: $showingMicPicker) {
                EquipmentPickerSheet(
                    equipmentType: .mic,
                    selection: $mic
                )
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var rig: String?
    @State private var powerText: String
    @State private var antenna: String?
    @State private var key: String?
    @State private var mic: String?
    @State private var grid: String
    @State private var useCurrentLocation: Bool
    @State private var isDefault: Bool
    @State private var showingRadioPicker = false
    @State private var showingAntennaPicker = false
    @State private var showingKeyPicker = false
    @State private var showingMicPicker = false
    @State private var locationService = GridLocationService()

    private let profileId: UUID

    private var isEditing: Bool {
        profile != nil
    }

    private func save() {
        let saved = StationProfile(
            id: profileId,
            name: name.trimmingCharacters(in: .whitespaces),
            power: Int(powerText),
            rig: rig,
            antenna: antenna,
            key: key,
            mic: mic,
            grid: useCurrentLocation
                ? nil
                : (grid.isEmpty ? nil : grid.uppercased()),
            useCurrentLocation: useCurrentLocation,
            isDefault: isDefault
        )
        onSave(saved)
        dismiss()
    }
}
