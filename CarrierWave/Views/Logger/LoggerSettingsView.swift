import SwiftUI

// MARK: - LoggerSettingsView

/// Settings for the logger feature
struct LoggerSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            licenseSection
            defaultsSection
            displaySection
            behaviorSection
            potaSection
        }
        .navigationTitle("Logger Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("License Lookup", isPresented: $showLookupResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lookupResultMessage)
        }
    }

    // MARK: Private

    @AppStorage("userLicenseClass") private var licenseClass = "Extra"
    @AppStorage("loggerDefaultCallsign") private var defaultCallsign = ""
    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerDefaultGrid") private var defaultGrid = ""
    @AppStorage("loggerSkipWizard") private var skipWizard = false
    @AppStorage("loggerShowActivityPanel") private var showActivityPanel = true
    @AppStorage("loggerShowLicenseWarnings") private var showLicenseWarnings = true
    @AppStorage("loggerKeepScreenOn") private var keepScreenOn = true
    @AppStorage("potaAutoSpotEnabled") private var potaAutoSpotEnabled = false

    @State private var isLookingUp = false
    @State private var showLookupResult = false
    @State private var lookupResultMessage = ""

    private var licenseSection: some View {
        Section {
            HStack {
                Picker("License Class", selection: $licenseClass) {
                    Text("Technician").tag("Technician")
                    Text("General").tag("General")
                    Text("Extra").tag("Extra")
                }
                .pickerStyle(.segmented)

                if isLookingUp {
                    ProgressView()
                        .padding(.leading, 8)
                } else {
                    Button {
                        lookupLicenseClass()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(defaultCallsign.isEmpty)
                    .padding(.leading, 8)
                }
            }

            Toggle("Show band privilege warnings", isOn: $showLicenseWarnings)
        } header: {
            Text("License Class")
        } footer: {
            if defaultCallsign.isEmpty {
                Text("Enter your callsign below to enable automatic license lookup")
            } else {
                Text("Tap the search icon to look up your license class from HamDB")
            }
        }
    }

    private var defaultsSection: some View {
        Section {
            HStack {
                Text("Callsign")
                Spacer()
                TextField("W1AW", text: $defaultCallsign)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
            }

            HStack {
                Text("Grid")
                Spacer()
                TextField("FN31", text: $defaultGrid)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
            }

            Picker("Default Mode", selection: $defaultMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }

            Toggle("Skip session wizard", isOn: $skipWizard)
        } header: {
            Text("Defaults")
        } footer: {
            Text("These values are pre-filled when starting a new session")
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Show frequency activity", isOn: $showActivityPanel)
        } header: {
            Text("Display")
        } footer: {
            Text("Show nearby activity on the frequency (from RBN, POTA, etc.)")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Keep screen on", isOn: $keepScreenOn)
        } header: {
            Text("Behavior")
        } footer: {
            Text("Keep screen on prevents device sleep during active sessions.")
        }
    }

    private var potaSection: some View {
        Section {
            Toggle("Auto-spot every 10 minutes", isOn: $potaAutoSpotEnabled)
        } header: {
            Text("POTA Activations")
        } footer: {
            Text(
                "When enabled, automatically posts a spot to POTA every 10 minutes "
                    + "during active POTA sessions."
            )
        }
    }

    private func lookupLicenseClass() {
        guard !defaultCallsign.isEmpty else {
            return
        }

        isLookingUp = true

        Task {
            do {
                let client = HamDBClient()
                if let foundClass = try await client.lookupLicenseClass(callsign: defaultCallsign) {
                    await MainActor.run {
                        licenseClass = foundClass.rawValue
                        lookupResultMessage = "License class set to \(foundClass.displayName)"
                        showLookupResult = true
                        isLookingUp = false
                    }
                } else {
                    await MainActor.run {
                        lookupResultMessage =
                            "Callsign \(defaultCallsign.uppercased()) not found in HamDB"
                        showLookupResult = true
                        isLookingUp = false
                    }
                }
            } catch {
                await MainActor.run {
                    lookupResultMessage = "Lookup failed: \(error.localizedDescription)"
                    showLookupResult = true
                    isLookingUp = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoggerSettingsView()
    }
}
