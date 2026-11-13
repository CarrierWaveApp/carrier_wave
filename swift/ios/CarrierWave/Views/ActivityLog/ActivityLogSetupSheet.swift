import CarrierWaveData
import SwiftUI

// MARK: - ActivityLogSetupSheet

/// Sheet for initial activity log setup. Collects name and callsign,
/// then creates the activity log.
struct ActivityLogSetupSheet: View {
    // MARK: Internal

    let manager: ActivityLogManager?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Log Name", text: $logName)
                        .textInputAutocapitalization(.words)

                    TextField("Your Callsign", text: $callsign)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Hunter Log")
                } footer: {
                    Text("Give your log a name like \"Home CW Hunting\" or \"Daily Log\".")
                }

                Section("Station Profile (Optional)") {
                    TextField("Profile Name", text: $profileName)
                        .textInputAutocapitalization(.words)

                    HStack {
                        Text("Radio")
                        Spacer()
                        Button(selectedRig ?? "None") {
                            activePickerCategory = .radio
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Power")
                        Spacer()
                        TextField("W", text: $powerText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Antenna")
                        Spacer()
                        Button(selectedAntenna ?? "None") {
                            activePickerCategory = .antenna
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Key")
                        Spacer()
                        Button(selectedKey ?? "None") {
                            activePickerCategory = .key
                        }
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Microphone")
                        Spacer()
                        Button(selectedMic ?? "None") {
                            activePickerCategory = .microphone
                        }
                        .foregroundStyle(.secondary)
                    }

                    Toggle("Use Current Location", isOn: $useCurrentLocation)

                    if useCurrentLocation {
                        HStack {
                            Label {
                                if manager?.locationService.isMonitoring == true,
                                   manager?.locationService.currentGrid == nil
                                {
                                    Text("Locating...")
                                        .foregroundStyle(.secondary)
                                } else if let gpsGrid = manager?.locationService.currentGrid {
                                    Text(gpsGrid)
                                        .font(.body.monospaced())
                                } else if manager?.locationService.locationError != nil {
                                    Text("Location unavailable")
                                        .foregroundStyle(.orange)
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
            }
            .navigationTitle("Set Up Hunter Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createLog() }
                        .disabled(!isValid)
                }
            }
            .onChange(of: useCurrentLocation) { _, isOn in
                if isOn {
                    manager?.locationService.start()
                } else {
                    manager?.locationService.stop()
                }
            }
            .onDisappear {
                if useCurrentLocation {
                    manager?.locationService.stop()
                }
            }
            .sheet(item: $activePickerCategory) { category in
                InventoryPickerSheet(
                    category: category,
                    selection: equipmentBinding(for: category)
                )
            }
            .onAppear { loadDefaults() }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var logName = "Daily Log"
    @State private var callsign = ""
    @State private var profileName = "QTH"
    @State private var selectedRig: String?
    @State private var powerText = ""
    @State private var selectedAntenna: String?
    @State private var selectedKey: String?
    @State private var selectedMic: String?
    @State private var grid = ""
    @State private var useCurrentLocation = false
    @State private var activePickerCategory: EquipmentCategory?

    private var isValid: Bool {
        !callsign.trimmingCharacters(in: .whitespaces).isEmpty
            && !logName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadDefaults() {
        // Pre-fill callsign from user profile if available
        if let saved = UserDefaults.standard.string(forKey: "userCallsign"),
           !saved.isEmpty
        {
            callsign = saved
        }

        // Pre-fill grid from user profile
        if let saved = UserDefaults.standard.string(forKey: "userGrid"),
           !saved.isEmpty
        {
            grid = saved
        }

        // Pre-fill radio from saved list or last session default
        let radios = RadioStorage.load()
        if !radios.isEmpty {
            selectedRig = radios.first
        }

        // Pre-fill power from session defaults
        let savedPower = UserDefaults.standard.string(
            forKey: "loggerDefaultPower"
        ) ?? ""
        if !savedPower.isEmpty {
            powerText = savedPower
        }
    }

    private func createLog() {
        // Create station profile if any fields were filled
        var profileId: UUID?
        if !profileName.trimmingCharacters(in: .whitespaces).isEmpty {
            let profile = StationProfile(
                name: profileName.trimmingCharacters(in: .whitespaces),
                power: Int(powerText),
                rig: selectedRig,
                antenna: selectedAntenna,
                key: selectedKey,
                mic: selectedMic,
                grid: useCurrentLocation
                    ? nil
                    : (grid.isEmpty ? nil : grid.uppercased()),
                useCurrentLocation: useCurrentLocation,
                isDefault: true
            )
            StationProfileStorage.add(profile)
            profileId = profile.id
        }

        manager?.createLog(
            name: logName.trimmingCharacters(in: .whitespaces),
            myCallsign: callsign.uppercased()
                .trimmingCharacters(in: .whitespaces),
            profileId: profileId
        )

        dismiss()
    }

    private func equipmentBinding(
        for category: EquipmentCategory
    ) -> Binding<String?> {
        switch category {
        case .radio: $selectedRig
        case .antenna: $selectedAntenna
        case .key: $selectedKey
        case .microphone: $selectedMic
        case .accessory: .constant(nil)
        }
    }
}
