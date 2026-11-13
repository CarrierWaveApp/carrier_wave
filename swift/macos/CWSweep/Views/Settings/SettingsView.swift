import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - SettingsView

/// Tab-based settings view
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            CarrierWaveSyncSettingsTab()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            KeyerSettingsTab()
                .tabItem { Label("Keyer", systemImage: "waveform.path") }

            AccountsSettingsTab()
                .tabItem { Label("Accounts", systemImage: "person.circle") }

            CallsignNotesSettingsTab()
                .tabItem { Label("Notes", systemImage: "note.text") }

            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "externaldrive") }

            POTASettingsTab()
                .tabItem { Label("POTA", systemImage: "tree") }

            RemoteSettingsTab()
                .tabItem { Label("Remote", systemImage: "iphone.radiowaves.left.and.right") }

            SatLogSettingsTab()
                .tabItem { Label("S.A.T.", systemImage: "antenna.radiowaves.left.and.right") }
            TrackersSettingsTab()
                .tabItem { Label("Trackers", systemImage: "dot.radiowaves.up.forward") }
            WsjtxSettingsTab()
                .tabItem { Label("WSJT-X", systemImage: "dot.radiowaves.left.and.right") }
            JttySettingsTab()
                .tabItem { Label("JTTY", systemImage: "keyboard") }

            SDRSettingsTab()
                .tabItem { Label("SDR", systemImage: "waveform.badge.magnifyingglass") }

            VimModeSettingsTab()
                .tabItem { Label("Vim Mode", systemImage: "keyboard") }

            MacrosLibrarySettingsTab()
                .tabItem { Label("Macros", systemImage: "wand.and.stars") }
        }
        .frame(minWidth: 750, maxWidth: 750, minHeight: 500)
    }
}

// MARK: - GeneralSettingsTab

struct GeneralSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Station") {
                TextField("My Callsign", text: $myCallsign)
                    .autocorrectionDisabled()
                    .focused($callsignFieldFocused)
                    .onSubmit { commitCallsign() }
                    .onChange(of: callsignFieldFocused) { _, focused in
                        if !focused {
                            commitCallsign()
                        }
                    }
                HStack {
                    TextField("My Grid Square", text: $myGrid)
                    Button {
                        Task {
                            isResolvingLocation = true
                            defer { isResolvingLocation = false }
                            if let grid = await locationResolver.resolveGrid() {
                                myGrid = grid
                            }
                        }
                    } label: {
                        if isResolvingLocation {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "location")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isResolvingLocation)
                    .help("Use current location to determine grid square")
                }
            }

            Section("Server") {
                TextField(
                    "Activities Server URL",
                    text: $activitiesServerURL,
                    prompt: Text(ContestDefinitions.defaultURL)
                )
                .autocorrectionDisabled()
                Text(
                    activitiesServerURL.isEmpty
                        ? "Using default: \(ContestDefinitions.defaultURL)"
                        : "Override active — clear to use default"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Display") {
                Picker("Distance Units", selection: $useMetricUnits) {
                    Text("Imperial (mi)").tag(false)
                    Text("Metric (km)").tag(true)
                }
            }

            Section("Defaults") {
                Picker("Default Mode", selection: $defaultMode) {
                    Text("CW").tag("CW")
                    Text("SSB").tag("SSB")
                    Text("FT8").tag("FT8")
                    Text("FT4").tag("FT4")
                    Text("RTTY").tag("RTTY")
                    Text("JTTY").tag("JTTY")
                    Text("AM").tag("AM")
                    Text("FM").tag("FM")
                }
                TextField("Default RST", text: $defaultRST)
                    .frame(width: 80)
                Stepper("Default Power: \(defaultPower)W", value: $defaultPower, in: 1 ... 1_500, step: 5)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Always load callsign from keychain (source of truth)
            let keychainValue = (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.currentCallsign
            )) ?? ""
            if !keychainValue.isEmpty {
                myCallsign = keychainValue
            }
        }
    }

    // MARK: Private

    @AppStorage("useMetricUnits") private var useMetricUnits = Locale.current.measurementSystem != .us
    @AppStorage("myCallsign") private var myCallsign = ""
    @AppStorage("myGrid") private var myGrid = ""
    @AppStorage("defaultMode") private var defaultMode = "CW"
    @AppStorage("defaultRST") private var defaultRST = "599"
    @AppStorage("defaultPower") private var defaultPower = 100
    @AppStorage("activitiesServerURLOverride") private var activitiesServerURL = ""

    @FocusState private var callsignFieldFocused: Bool

    @State private var isResolvingLocation = false
    @State private var locationResolver = LocationGridResolver()

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// Commit the callsign to the shared Keychain only on submit or focus
    /// loss — never per keystroke. The item is iCloud-synchronized, so a
    /// debounced mid-typing write persists half-typed callsigns that then
    /// resurrect on every Carrier Wave: Field launch (CAR-287).
    private func commitCallsign() {
        let normalized = myCallsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            return
        }
        myCallsign = normalized
        let existing = try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.currentCallsign
        )
        if existing != normalized {
            try? KeychainHelper.shared.save(
                normalized,
                for: KeychainHelper.Keys.currentCallsign
            )
        }
    }
}

// MARK: - AccountsSettingsTab

struct AccountsSettingsTab: View {
    // MARK: Internal

    @Environment(\.modelContext) var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CarrierWaveAccountSection()
                Divider()
                qrzSection
                Divider()
                AMTAccountSection()
            }
            .padding()
        }
        .onAppear {
            loadCredentials()
        }
    }

    // MARK: Private

    @State private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var qrzSaveStatus: String?

    private var qrzSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QRZ.com Callbook")
                .font(.headline)

            LabeledContent("Username") {
                TextField("", text: $qrzUsername)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            LabeledContent("Password") {
                SecureField("", text: $qrzPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            HStack {
                Button("Save") {
                    let userOk = saveCredential(
                        qrzUsername,
                        key: KeychainHelper.Keys.qrzCallbookUsername
                    )
                    let passOk = saveCredential(
                        qrzPassword,
                        key: KeychainHelper.Keys.qrzCallbookPassword
                    )
                    qrzSaveStatus = userOk && passOk
                        ? "Saved" : "Failed to save"
                }
                if let status = qrzSaveStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status == "Saved" ? .green : .red)
                }
            }
        }
    }

    private func loadCredentials() {
        qrzUsername = (try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.qrzCallbookUsername
        )) ?? ""
        qrzPassword = (try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.qrzCallbookPassword
        )) ?? ""
    }

    @discardableResult
    private func saveCredential(_ value: String, key: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        do {
            try KeychainHelper.shared.save(value, for: key)
            return true
        } catch {
            return false
        }
    }
}
