import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SyncSourcesSettingsView

struct SyncSourcesSettingsView: View {
    // MARK: Internal

    var potaAuth: POTAAuthService

    let tourState: TourState
    var syncService: SyncService?

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "arrow.triangle.2.circlepath",
                tint: .blue,
                title: "Logbook Services",
                subtitle: "Sync your QSOs with third-party logbooks."
            )
            SyncNowSection(syncService: syncService)

            AutoSyncSection()

            PendingUploadsNavigationSection()

            SyncDirectionSection()

            SyncSourcesSection(
                potaAuth: potaAuth,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                clublogClient: clublogClient,
                eqslClient: eqslClient,
                qrzIsConfigured: qrzIsConfigured,
                qrzCallsign: qrzCallsign,
                qrzLogbookMismatch: qrzLogbookMismatch,
                lotwIsConfigured: lotwIsConfigured,
                lotwUsername: lotwUsername,
                tourState: tourState
            )
        }
        .navigationTitle("Logbook Services")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadServiceStatus()
        }
    }

    // MARK: Private

    @State private var qrzIsConfigured = false
    @State private var qrzCallsign: String?
    @State private var qrzLogbookMismatch: QRZLogbookCallsignMismatch?
    @State private var lotwIsConfigured = false
    @State private var lotwUsername: String?

    private let lofiClient = LoFiClient.appDefault()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()
    private let clublogClient = ClubLogClient()
    private let eqslClient = EQSLClient()

    private func loadServiceStatus() {
        qrzIsConfigured = qrzClient.hasApiKey()
        qrzCallsign = qrzClient.getCallsign()
        qrzLogbookMismatch = qrzClient.logbookMismatch()

        lotwIsConfigured = lotwClient.hasCredentials()
        if lotwIsConfigured {
            if let creds = try? lotwClient.getCredentials() {
                lotwUsername = creds.username
            }
        }
    }
}

// MARK: - SyncDirectionSection

private struct SyncDirectionSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            SyncModePicker(service: .qrz, mode: $qrzMode)
            SyncModePicker(service: .pota, mode: $potaMode)
            SyncModePicker(service: .hamrs, mode: $hamrsMode)
            SyncModePicker(service: .eqsl, mode: $eqslMode)
            FixedSyncModeRow(service: .lofi, mode: .downloadOnly)
            FixedSyncModeRow(service: .lotw, mode: .downloadOnly)
        } header: {
            Text("Sync Direction")
        } footer: {
            Text("Controls whether each service uploads, downloads, or both.")
        }
    }

    // MARK: Private

    @State private var qrzMode = CarrierWaveData.ServiceConfiguration.syncMode(for: .qrz)
    @State private var potaMode = CarrierWaveData.ServiceConfiguration.syncMode(for: .pota)
    @State private var hamrsMode = CarrierWaveData.ServiceConfiguration.syncMode(for: .hamrs)
    @State private var eqslMode = CarrierWaveData.ServiceConfiguration.syncMode(for: .eqsl)
}

// MARK: - SyncModePicker

private struct SyncModePicker: View {
    let service: ServiceType

    @Binding var mode: SyncMode

    var body: some View {
        Picker(service.displayName, selection: $mode) {
            ForEach(SyncMode.allCases, id: \.self) { syncMode in
                Text(syncMode.displayName).tag(syncMode)
            }
        }
        .onChange(of: mode) {
            CarrierWaveData.ServiceConfiguration.setSyncMode(mode, for: service)
        }
    }
}

// MARK: - FixedSyncModeRow

private struct FixedSyncModeRow: View {
    let service: ServiceType
    let mode: SyncMode

    var body: some View {
        HStack {
            Text(service.displayName)
            Spacer()
            Text(mode.displayName)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AutoSyncSection

private struct AutoSyncSection: View {
    // MARK: Internal

    var body: some View {
        Section {
            Toggle("Sync automatically", isOn: $autoSyncEnabled)
                .onChange(of: autoSyncEnabled) {
                    AutoSyncService.shared.settingsDidChange()
                }

            if autoSyncEnabled {
                Picker("Every", selection: $intervalMinutes) {
                    ForEach(AutoSyncService.intervalOptions, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }
                .onChange(of: intervalMinutes) {
                    AutoSyncService.shared.settingsDidChange()
                }
            }
        } header: {
            Text("Auto-Sync")
        } footer: {
            Text("Automatically syncs with all configured services while the app is open.")
        }
    }

    // MARK: Private

    @AppStorage(AutoSyncService.enabledKey) private var autoSyncEnabled = false
    @AppStorage(AutoSyncService.intervalKey) private var intervalMinutes =
        AutoSyncService.defaultIntervalMinutes

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }
        return "\(minutes / 60) hour"
    }
}

// MARK: - SyncNowSection

private struct SyncNowSection: View {
    // MARK: Internal

    var syncService: SyncService?

    var body: some View {
        Section {
            Button {
                Task {
                    guard let syncService else {
                        return
                    }
                    lastError = nil
                    do {
                        let result = try await syncService.syncAll()
                        if !result.errors.isEmpty {
                            lastError = result.errors.joined(separator: "\n")
                        }
                    } catch {
                        lastError = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if syncService?.isSyncing == true {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing…")
                    } else {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            .disabled(syncService == nil || syncService?.isSyncing == true)

            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: Private

    @State private var lastError: String?
}
