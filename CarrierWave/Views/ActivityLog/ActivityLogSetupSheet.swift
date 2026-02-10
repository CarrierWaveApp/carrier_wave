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
                    Text("Activity Log")
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
                            showingRadioPicker = true
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

                    TextField("Antenna", text: $antenna)
                        .textInputAutocapitalization(.words)

                    TextField("Grid Square", text: $grid)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Set Up Activity Log")
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
            .sheet(isPresented: $showingRadioPicker) {
                RadioPickerSheet(selection: $selectedRig)
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
    @State private var antenna = ""
    @State private var grid = ""
    @State private var showingRadioPicker = false

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
    }

    private func createLog() {
        // Create station profile if any fields were filled
        var profileId: UUID?
        if !profileName.trimmingCharacters(in: .whitespaces).isEmpty {
            let profile = StationProfile(
                name: profileName.trimmingCharacters(in: .whitespaces),
                power: Int(powerText),
                rig: selectedRig,
                antenna: antenna.isEmpty ? nil : antenna,
                grid: grid.isEmpty ? nil : grid.uppercased(),
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
}
