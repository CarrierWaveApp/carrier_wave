import CarrierWaveData
import SwiftUI

// MARK: - SettingsView

/// Tab-based settings view
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            RadioSettingsTab()
                .tabItem { Label("Radio", systemImage: "antenna.radiowaves.left.and.right") }

            SyncSettingsTab()
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }

            KeyerSettingsTab()
                .tabItem { Label("Keyer", systemImage: "waveform.path") }

            WinKeyerSettingsTab()
                .tabItem { Label("WinKeyer", systemImage: "pianokeys") }

            InteropSettingsTab()
                .tabItem { Label("Interop", systemImage: "arrow.left.arrow.right") }

            AccountsSettingsTab()
                .tabItem { Label("Accounts", systemImage: "person.circle") }

            SDRSettingsTab()
                .tabItem { Label("SDR", systemImage: "antenna.radiowaves.left.and.right.circle") }
        }
        .frame(minWidth: 450, idealWidth: 500, minHeight: 400, idealHeight: 500)
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
                    .onChange(of: myCallsign) { _, newValue in
                        // Debounce keychain writes
                        keychainSaveTask?.cancel()
                        keychainSaveTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else {
                                return
                            }
                            try? KeychainHelper.shared.save(
                                newValue,
                                for: KeychainHelper.Keys.currentCallsign
                            )
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

            Section("Defaults") {
                Picker("Default Mode", selection: $defaultMode) {
                    Text("CW").tag("CW")
                    Text("SSB").tag("SSB")
                    Text("FT8").tag("FT8")
                    Text("FT4").tag("FT4")
                    Text("RTTY").tag("RTTY")
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
            // Load callsign from keychain if AppStorage is empty
            if myCallsign.isEmpty {
                myCallsign = (try? KeychainHelper.shared.readString(
                    for: KeychainHelper.Keys.currentCallsign
                )) ?? ""
            }
        }
    }

    // MARK: Private

    @AppStorage("myCallsign") private var myCallsign = ""
    @AppStorage("myGrid") private var myGrid = ""
    @AppStorage("defaultMode") private var defaultMode = "CW"
    @AppStorage("defaultRST") private var defaultRST = "599"
    @AppStorage("defaultPower") private var defaultPower = 100

    @State private var keychainSaveTask: Task<Void, Never>?
    @State private var isResolvingLocation = false
    @State private var locationResolver = LocationGridResolver()
}

// MARK: - RadioSettingsTab

struct RadioSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("Default Radio") {
                Picker("Radio Model", selection: $defaultRadioModel) {
                    ForEach(RadioModel.knownModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }

                Picker("Baud Rate", selection: $defaultBaudRate) {
                    Text("4800").tag(4_800)
                    Text("9600").tag(9_600)
                    Text("19200").tag(19_200)
                    Text("38400").tag(38_400)
                    Text("57600").tag(57_600)
                    Text("115200").tag(115_200)
                }
            }

            Section("Connection") {
                Toggle("Auto-connect on launch", isOn: $autoConnect)
                Stepper("Poll interval: \(pollIntervalMs)ms", value: $pollIntervalMs, in: 50 ... 1_000, step: 50)
            }

            Section("Auto-XIT") {
                Toggle("Enable auto-XIT when tuning spots", isOn: $autoXITEnabled)
                if autoXITEnabled {
                    Stepper("Offset: \(autoXITOffsetHz) Hz",
                            value: $autoXITOffsetHz, in: -9_999 ... 9_999, step: 10)
                    Text("Transmit frequency will be offset from receive when tuning to a spot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    @AppStorage("defaultRadioModel") private var defaultRadioModel = "ic7300"
    @AppStorage("defaultBaudRate") private var defaultBaudRate = 19_200
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("pollIntervalMs") private var pollIntervalMs = 100
    @AppStorage("autoXITEnabled") private var autoXITEnabled = false
    @AppStorage("autoXITOffsetHz") private var autoXITOffsetHz = 0
}

// MARK: - SyncSettingsTab

struct SyncSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("iCloud") {
                Toggle("Enable iCloud Sync", isOn: Binding(
                    get: { syncService.isEnabled },
                    set: { newValue in
                        Task { await syncService.setEnabled(newValue) }
                    }
                ))
                Text("Container: iCloud.com.jsvana.FullDuplex")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if syncService.isEnabled {
                    HStack {
                        Text("Status")
                        Spacer()
                        Image(systemName: syncService.syncStatus.iconName)
                        Text(syncService.syncStatus.displayText)
                            .foregroundStyle(.secondary)
                    }

                    if syncService.counts.totalDirty > 0 {
                        HStack {
                            Text("Pending upload")
                            Spacer()
                            Text("\(syncService.counts.totalDirty) records")
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack {
                        Text("Synced records")
                        Spacer()
                        Text("\(syncService.counts.totalSynced)")
                            .foregroundStyle(.secondary)
                    }

                    if syncService.counts.totalDirty > 0 {
                        Button("Sync Now") {
                            Task { await syncService.syncPending() }
                        }
                    }

                    Button("Force Full Sync") {
                        Task { await syncService.forceFullSync() }
                    }
                }

                if let error = syncService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Info") {
                Text(
                    "QSOs, sessions, and settings sync automatically between CW Sweep (macOS) and Carrier Wave (iOS/iPadOS)."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await syncService.refreshCounts()
        }
    }

    // MARK: Private

    private var syncService = CloudSyncService.shared
}

// MARK: - AccountsSettingsTab

struct AccountsSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("QRZ.com") {
                TextField("Username", text: $qrzUsername)
                SecureField("Password", text: $qrzPassword)
                Button("Save QRZ Credentials") {
                    saveCredential(qrzUsername, key: KeychainHelper.Keys.qrzCallbookUsername)
                    saveCredential(qrzPassword, key: KeychainHelper.Keys.qrzCallbookPassword)
                }
            }

            Section("Logbook of The World (LoTW)") {
                TextField("Username", text: $lotwUsername)
                SecureField("Password", text: $lotwPassword)
                Button("Save LoTW Credentials") {
                    saveCredential(lotwUsername, key: KeychainHelper.Keys.lotwUsername)
                    saveCredential(lotwPassword, key: KeychainHelper.Keys.lotwPassword)
                }
            }

            Section("Club Log") {
                TextField("Email", text: $clubLogEmail)
                SecureField("Password", text: $clubLogPassword)
                TextField("Callsign", text: $clubLogCallsign)
                Button("Save Club Log Credentials") {
                    saveCredential(clubLogEmail, key: KeychainHelper.Keys.clublogEmail)
                    saveCredential(clubLogPassword, key: KeychainHelper.Keys.clublogPassword)
                    saveCredential(clubLogCallsign, key: KeychainHelper.Keys.clublogCallsign)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadCredentials()
        }
    }

    // MARK: Private

    @State private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var lotwUsername = ""
    @State private var lotwPassword = ""
    @State private var clubLogEmail = ""
    @State private var clubLogPassword = ""
    @State private var clubLogCallsign = ""

    private func loadCredentials() {
        qrzUsername = (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.qrzCallbookUsername)) ?? ""
        lotwUsername = (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.lotwUsername)) ?? ""
        clubLogEmail = (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.clublogEmail)) ?? ""
        clubLogCallsign = (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.clublogCallsign)) ?? ""
        // Don't load passwords — show empty, only overwrite if user types
    }

    private func saveCredential(_ value: String, key: String) {
        guard !value.isEmpty else {
            return
        }
        try? KeychainHelper.shared.save(value, for: key)
    }
}
