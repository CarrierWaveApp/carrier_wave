import CarrierWaveCore
import SwiftData
import SwiftUI
import UIKit

// swiftlint:disable file_length

// MARK: - SettingsMainView

// swiftlint:disable:next type_body_length
struct SettingsMainView: View {
    // MARK: Internal

    @ObservedObject var potaAuth: POTAAuthService
    @Binding var destination: SettingsDestination?

    let tourState: TourState
    var syncService: SyncService?

    /// When true, the view is already inside a navigation context (e.g., "More" tab)
    /// and should not add its own NavigationStack
    var isInNavigationContext: Bool = false

    var body: some View {
        if isInNavigationContext {
            settingsContent
        } else {
            NavigationStack(path: $navigationPath) {
                settingsContent
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var navigationPath = NavigationPath()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingClearAllConfirmation = false
    @State private var isClearingQSOs = false
    @State private var dedupeTimeWindow = 5
    @State private var isDeduplicating = false
    @State private var showingDedupeResult = false
    @State private var dedupeResultMessage = ""
    @State private var isExportingDatabase = false
    @State private var exportedFile: ExportedFile?
    @State private var showingBugReport = false
    @State private var showIntroTour = false
    @State private var showOnboarding = false

    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("readOnlyMode") private var readOnlyMode = false
    @AppStorage("bypassPOTAMaintenance") private var bypassPOTAMaintenance = false

    /// Appearance
    @AppStorage("appearanceMode") private var appearanceMode = "system"

    // Logger settings
    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerShowActivityPanel") private var showActivityPanel = true
    @AppStorage("loggerShowLicenseWarnings") private var showLicenseWarnings = true
    @AppStorage("loggerKeepScreenOn") private var keepScreenOn = true

    @AppStorage("potaAutoSpotEnabled") private var potaAutoSpotEnabled = false
    @AppStorage("potaQSYSpotEnabled") private var potaQSYSpotEnabled = true
    @AppStorage("potaQRTSpotEnabled") private var potaQRTSpotEnabled = true
    @AppStorage("autoRecordConditions") private var autoRecordConditions = true
    @AppStorage("shareCardIncludeEquipment") private var shareCardIncludeEquipment = true
    @AppStorage("statisticianMode") private var statisticianMode = false
    @AppStorage("loggerAutoModeSwitch") private var autoModeSwitch = true
    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"
    @AppStorage("useMetricUnits") private var useMetricUnits = false

    // Keyboard row settings
    @AppStorage("keyboardRowShowNumbers") private var keyboardRowShowNumbers = true
    @AppStorage("keyboardRowSymbols") private var keyboardRowSymbols = "/"

    // Command row settings
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandRowCommands =
        "rbn,solar,weather,spot,pota,p2p"

    // Logger visible fields
    @AppStorage("loggerShowTheirGrid") private var showTheirGrid = false
    @AppStorage("loggerShowTheirPark") private var showTheirPark = false
    @AppStorage("loggerShowOperator") private var showOperator = false

    @StateObject private var iCloudMonitor = ICloudMonitor()
    @State private var qrzIsConfigured = false
    @State private var qrzCallsign: String?

    @State private var qrzCallbookIsConfigured = false

    @State private var lotwIsConfigured = false
    @State private var lotwUsername: String?

    @State private var userProfile: UserProfile?

    @Query(sort: \ChallengeSource.name) private var challengeSources: [ChallengeSource]

    private let lofiClient = LoFiClient.appDefault()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()

    /// Summary text for keyboard row settings
    private var keyboardRowSummary: String {
        var parts: [String] = []
        if keyboardRowShowNumbers {
            parts.append("0-9")
        }
        let symbols = keyboardRowSymbols.components(separatedBy: ",").filter { !$0.isEmpty }
        if !symbols.isEmpty {
            parts.append(symbols.joined())
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " ")
    }

    /// Summary text for command row settings
    private var commandRowSummary: String {
        guard commandRowEnabled else {
            return "Off"
        }
        let commands = commandRowCommands.components(separatedBy: ",").filter { !$0.isEmpty }
        if commands.isEmpty {
            return "None"
        }
        return "\(commands.count) commands"
    }

    private var settingsContent: some View {
        List {
            profileSection
            tabsSection
            loggerSection
            activityLogSection
            potaSection
            SyncSourcesSection(
                potaAuth: potaAuth,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                iCloudMonitor: iCloudMonitor,
                qrzIsConfigured: qrzIsConfigured,
                qrzCallsign: qrzCallsign,
                lotwIsConfigured: lotwIsConfigured,
                lotwUsername: lotwUsername,
                challengeSources: challengeSources,
                tourState: tourState
            )
            deduplicationSection
            developerSection
            dataSection
            aboutSection
        }
        .navigationDestination(for: SettingsDestination.self) { dest in
            switch dest {
            case .qrz:
                QRZSettingsView(syncService: syncService)
            case .pota:
                POTASettingsView(potaAuth: potaAuth, tourState: tourState, syncService: syncService)
            case .lofi:
                LoFiSettingsView(tourState: tourState, syncService: syncService)
            case .hamrs:
                HAMRSSettingsView(syncService: syncService)
            case .lotw:
                LoTWSettingsView(syncService: syncService)
            case .icloud:
                ICloudSettingsView()
            }
        }
        .onAppear {
            loadServiceStatus()
        }
        .task(id: destination) {
            // Handle deep link - task restarts when destination changes
            guard let dest = destination else {
                return
            }
            // Small delay to ensure NavigationStack is ready after tab switch
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            navigationPath.append(dest)
            destination = nil
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Clear All QSOs?", isPresented: $showingClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                Task { await clearAllQSOs() }
            }
        } message: {
            Text(
                "This will permanently delete all QSOs from this device. This cannot be undone."
            )
        }
        .alert("Deduplication Complete", isPresented: $showingDedupeResult) {
            Button("OK") {}
        } message: {
            Text(dedupeResultMessage)
        }
        .sheet(
            item: $exportedFile,
            onDismiss: { isExportingDatabase = false },
            content: { file in ShareSheet(activityItems: [file.url]) }
        )
        .sheet(isPresented: $showingBugReport) {
            BugReportView(
                syncService: syncService,
                potaAuth: potaAuth,
                iCloudMonitor: iCloudMonitor
            )
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState, potaAuth: potaAuth)
        }
        .onChange(of: showOnboarding) { _, isShowing in
            // Reload profile after onboarding completes
            if !isShowing {
                userProfile = UserProfileService.shared.getProfile()
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            NavigationLink {
                AboutMeView {
                    showOnboarding = true
                }
            } label: {
                HStack {
                    if let profile = userProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.callsign)
                                .font(.headline)
                                .monospaced()
                            if let name = profile.fullName {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let licenseClass = profile.licenseClass {
                            Text(licenseClass.abbreviation)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    } else {
                        Label("Set Up Profile", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        } header: {
            Text("My Profile")
        }
    }

    private var tabsSection: some View {
        let isIPad = horizontalSizeClass == .regular
        return Section {
            NavigationLink {
                TabConfigurationView()
            } label: {
                HStack {
                    Label(
                        isIPad ? "Sidebar" : "Tab Bar",
                        systemImage: isIPad ? "sidebar.left" : "square.grid.2x2"
                    )
                    Spacer()
                    let visibleCount = TabConfiguration.visibleTabs().filter { $0 != .more }.count
                    Text(isIPad ? "\(visibleCount) visible" : "\(visibleCount) in tab bar")
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                DashboardMetricsSettingsView()
            } label: {
                Label("Dashboard Metrics", systemImage: "gauge.with.dots.needle.33percent")
            }

            Picker("Appearance", selection: $appearanceMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("Sunlight").tag("sunlight")
            }

            Picker("Units", selection: $useMetricUnits) {
                Text("Imperial (mi, \u{00B0}F, mph)").tag(false)
                Text("Metric (km, \u{00B0}C, km/h)").tag(true)
            }
        } header: {
            Text("Navigation")
        } footer: {
            if appearanceMode == "sunlight" {
                Text(
                    "Sunlight mode uses a bright theme with boosted contrast for "
                        + "outdoor visibility. Best for use in direct sunlight."
                )
            } else if isIPad {
                Text("Choose which tabs appear in the sidebar.")
            } else {
                Text(
                    "Choose which tabs appear in the tab bar. Hidden tabs are accessible from More."
                )
            }
        }
    }

    private var loggerSection: some View {
        Section {
            // License class (read-only, from profile)
            if let profile = userProfile, let licenseClass = profile.licenseClass {
                HStack {
                    Text("License Class")
                    Spacer()
                    Text(licenseClass.displayName)
                        .foregroundStyle(.secondary)
                }

                Toggle("Show band privilege warnings", isOn: $showLicenseWarnings)
            }

            Picker("Default Mode", selection: $defaultMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }

            NavigationLink {
                KeyboardRowSettingsView()
            } label: {
                HStack {
                    Text("Keyboard Row")
                    Spacer()
                    Text(keyboardRowSummary)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                CommandRowSettingsView()
            } label: {
                HStack {
                    Text("Command Row")
                    Spacer()
                    Text(commandRowSummary)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Show frequency activity", isOn: $showActivityPanel)
            Toggle("Keep screen on", isOn: $keepScreenOn)
            Toggle("Auto-switch mode for frequency", isOn: $autoModeSwitch)
            Picker("Notes display", selection: $notesDisplayMode) {
                Text("Emoji").tag("emoji")
                Text("Source names").tag("sources")
            }

            NavigationLink {
                WebSDRRecordingsView()
            } label: {
                Label("WebSDR Recordings", systemImage: "waveform.circle")
            }

            DisclosureGroup("Always visible fields") {
                Toggle("Their Grid", isOn: $showTheirGrid)
                Toggle("Their Park", isOn: $showTheirPark)
                Toggle("Operator", isOn: $showOperator)
            }
        } header: {
            Text("Logger")
        } footer: {
            Text(
                "Keep screen on prevents device sleep during sessions. "
                    + "Notes and RST are always visible. Other fields appear without tapping \"More Fields\"."
            )
        }
    }

    private var activityLogSection: some View {
        Section("Activity Log") {
            NavigationLink {
                ActivityLogSettingsView()
            } label: {
                HStack {
                    Text("Activity Log Settings")
                    Spacer()
                    let count = StationProfileStorage.load().count
                    Text("\(count) profile\(count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var potaSection: some View {
        Section {
            Toggle("Auto-spot every 10 minutes", isOn: $potaAutoSpotEnabled)
            Toggle("Prompt for QSY spots", isOn: $potaQSYSpotEnabled)
            Toggle("Post QRT when ending session", isOn: $potaQRTSpotEnabled)
            Toggle("Record solar & weather at start", isOn: $autoRecordConditions)
            Toggle("Include equipment on brag sheet", isOn: $shareCardIncludeEquipment)
            Toggle("Professional Statistician Mode", isOn: $statisticianMode)
        } header: {
            Text("POTA Activations")
        } footer: {
            Text(
                "Auto-spot posts your frequency to POTA every 10 minutes. "
                    + "QSY spots prompt after frequency or mode changes. "
                    + "QRT spot notifies hunters when you end your activation. "
                    + "Solar & weather records current conditions when starting a session. "
                    + "Equipment on brag sheet shows radio, antenna, key, and other gear. "
                    + "Statistician mode adds charts to activation details "
                    + "and extra stats to brag sheets."
            )
        }
    }

    private var deduplicationSection: some View {
        Section {
            Stepper(
                "Time window: \(dedupeTimeWindow) min", value: $dedupeTimeWindow, in: 1 ... 15
            )

            Button {
                Task { await runDeduplication() }
            } label: {
                if isDeduplicating {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Scanning...")
                    }
                } else {
                    Text("Find & Merge Duplicates")
                }
            }
            .disabled(isDeduplicating)
        } header: {
            Text("Deduplication")
        } footer: {
            Text(
                """
                Find QSOs with same callsign, band, and mode within \(dedupeTimeWindow) min \
                and merge. Mode families are treated as equivalent (e.g., PHONE/SSB/USB, \
                DATA/FT8/PSK31).
                """
            )
        }
    }

    private var developerSection: some View {
        Section {
            Toggle("Debug Mode", isOn: $debugMode)

            if debugMode {
                Toggle("Read-Only Mode", isOn: $readOnlyMode)
                Toggle("Bypass POTA Maintenance", isOn: $bypassPOTAMaintenance)

                NavigationLink {
                    SyncDebugView(potaAuth: potaAuth)
                } label: {
                    Label("Sync Debug Log", systemImage: "doc.text.magnifyingglass")
                }

                NavigationLink {
                    AllHiddenQSOsView()
                } label: {
                    Label("Hidden QSOs", systemImage: "eye.slash")
                }

                Button(role: .destructive) {
                    showingClearAllConfirmation = true
                } label: {
                    if isClearingQSOs {
                        HStack {
                            ProgressView()
                            Text("Clearing...")
                        }
                    } else {
                        Text("Clear All QSOs")
                    }
                }
                .disabled(isClearingQSOs)
            }
        } header: {
            Text("Developer")
        } footer: {
            if debugMode, bypassPOTAMaintenance {
                Text("POTA maintenance window bypass enabled. Uploads allowed 24/7.")
            } else if debugMode, readOnlyMode {
                Text(
                    "Read-only mode: uploads disabled. Downloads and local changes still work."
                )
            } else {
                Text("Shows individual sync buttons on service cards and debug tools")
            }
        }
    }

    private var dataSection: some View {
        Section {
            // QRZ Callbook (for callsign lookups)
            NavigationLink {
                QRZCallbookSettingsView()
            } label: {
                HStack {
                    Label("QRZ Callbook", systemImage: "magnifyingglass")
                    Spacer()
                    if qrzCallbookIsConfigured {
                        if let username = try? KeychainHelper.shared.readString(
                            for: KeychainHelper.Keys.qrzCallbookUsername
                        ) {
                            Text(username)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            NavigationLink {
                CallsignNotesSettingsView()
            } label: {
                Label("Callsign Notes", systemImage: "note.text")
            }

            NavigationLink {
                ExternalDataView()
            } label: {
                Label("External Data", systemImage: "arrow.down.circle")
            }

            Button {
                isExportingDatabase = true
                Task { await exportDatabase() }
            } label: {
                if isExportingDatabase {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Exporting...")
                    }
                } else {
                    Label("Export SQLite Database", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExportingDatabase)
        } header: {
            Text("Data")
        } footer: {
            Text(
                "QRZ Callbook enables callsign lookups (requires QRZ XML subscription). "
                    + "Export creates a backup of the QSO database."
            )
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.32.0")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://discord.gg/PqubUxWW62")!) {
                Label("Join Discord", systemImage: "bubble.left.and.bubble.right")
            }

            Button {
                showingBugReport = true
            } label: {
                Label("Report a Bug", systemImage: "ant")
            }

            Button {
                tourState.resetForTesting()
                showIntroTour = true
            } label: {
                Label("Show App Tour", systemImage: "questionmark.circle")
            }

            Link(destination: URL(string: "https://discord.gg/ksNb2jAeTR")!) {
                Label("Request a Feature", systemImage: "lightbulb")
            }

            NavigationLink {
                AttributionsView()
            } label: {
                Label("Attributions", systemImage: "heart")
            }
        } header: {
            Text("About")
        }
    }

    @MainActor
    private func exportDatabase() async {
        do {
            try modelContext.save()
            let exportURL = try await DatabaseExporter.export(from: modelContext.container)
            exportedFile = ExportedFile(url: exportURL)
        } catch {
            isExportingDatabase = false
            errorMessage = "Failed to export database: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func clearAllQSOs() async {
        isClearingQSOs = true
        defer { isClearingQSOs = false }

        do {
            // Use batch deletion - cascade delete rule handles ServicePresence
            try modelContext.delete(model: QSO.self)
            try modelContext.save()

            // Reset LoFi sync timestamp so QSOs can be re-downloaded
            lofiClient.resetSyncTimestamp()

            // Notify dashboard to reset stats
            NotificationCenter.default.post(name: .didClearQSOs, object: nil)
        } catch {
            errorMessage = "Failed to clear QSOs: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func runDeduplication() async {
        isDeduplicating = true
        defer { isDeduplicating = false }

        do {
            let service = DeduplicationService(modelContext: modelContext)
            let result = try service.findAndMergeDuplicates(
                timeWindowMinutes: dedupeTimeWindow
            )

            if result.duplicateGroupsFound == 0 {
                dedupeResultMessage = "No duplicates found."
            } else {
                dedupeResultMessage = """
                Found \(result.duplicateGroupsFound) duplicate groups.
                Merged \(result.qsosMerged) QSOs, removed \(result.qsosRemoved) duplicates.
                """
            }
            showingDedupeResult = true
        } catch {
            errorMessage = "Deduplication failed: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func loadServiceStatus() {
        qrzIsConfigured = qrzClient.hasApiKey()
        qrzCallsign = qrzClient.getCallsign()

        qrzCallbookIsConfigured = checkQRZCallbookAuth()

        lotwIsConfigured = lotwClient.hasCredentials()
        if lotwIsConfigured {
            if let creds = try? lotwClient.getCredentials() {
                lotwUsername = creds.username
            }
        }

        userProfile = UserProfileService.shared.getProfile()
    }

    private func checkQRZCallbookAuth() -> Bool {
        (try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.qrzCallbookUsername
        )) != nil
            && (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )) != nil
    }
}

// MARK: - ExportedFile

// QRZApiKeySheet, QRZSettingsView, POTASettingsView are in ServiceSettingsViews.swift
// ICloudSettingsView, LoFiSettingsView are in CloudSettingsViews.swift

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - DatabaseExporter

enum DatabaseExporter {
    enum ExportError: LocalizedError {
        case storeNotFound

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .storeNotFound:
                "Could not locate the database file."
            }
        }
    }

    static func export(from container: ModelContainer) async throws -> URL {
        guard let config = container.configurations.first else {
            throw ExportError.storeNotFound
        }
        let storeURL = config.url

        return try await Task.detached(priority: .userInitiated) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let exportFilename = "CarrierWave_QSO_Export_\(timestamp).sqlite"

            let tempDir = FileManager.default.temporaryDirectory
            let exportURL = tempDir.appendingPathComponent(exportFilename)

            if FileManager.default.fileExists(atPath: exportURL.path) {
                try FileManager.default.removeItem(at: exportURL)
            }

            try FileManager.default.copyItem(at: storeURL, to: exportURL)

            // Copy WAL and SHM files if they exist for complete export
            for ext in ["wal", "shm"] {
                let sourceURL = storeURL.appendingPathExtension(ext)
                let destURL = exportURL.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }

            return exportURL
        }.value
    }
}

// MARK: - TabConfigurationView

struct TabConfigurationView: View {
    // MARK: Internal

    var body: some View {
        List {
            // Visible tabs section
            Section {
                ForEach(tabBarTabs, id: \.self) { tab in
                    tabRow(tab, inTabBar: true)
                }
                .onMove(perform: moveTabBarTab)
            } header: {
                Text(isIPad ? "Sidebar" : "Tab Bar")
            } footer: {
                if isIPad {
                    Text("Drag to reorder. Tap to hide.")
                } else if tabBarTabs.count >= maxVisibleTabs {
                    Text("Maximum \(maxVisibleTabs) tabs. Drag to reorder.")
                } else {
                    Text("Drag to reorder. Tap to move to More.")
                }
            }

            // Hidden tabs section
            Section {
                if moreTabs.isEmpty {
                    Text("No hidden tabs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(moreTabs, id: \.self) { tab in
                        tabRow(tab, inTabBar: false)
                    }
                    .onMove(perform: moveMoreTab)
                }
            } header: {
                Text("Hidden")
            } footer: {
                if isIPad {
                    Text("Hidden tabs won't appear in the sidebar.")
                } else {
                    Text("These tabs are accessible from the More tab.")
                }
            }

            Section {
                Button("Reset to Defaults") {
                    TabConfiguration.reset()
                    refreshTabs()
                    notifyChange()
                }
            }
        }
        .navigationTitle(isIPad ? "Sidebar" : "Tab Bar")
        .environment(\.editMode, .constant(.active))
        .onAppear {
            refreshTabs()
        }
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var tabBarTabs: [AppTab] = []
    @State private var moreTabs: [AppTab] = []

    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }

    /// Maximum tabs visible in tab bar (excluding More).
    /// iPad has no limit since the sidebar can hold all tabs.
    private var maxVisibleTabs: Int {
        isIPad ? AppTab.configurableTabs.count : 4
    }

    private func tabRow(_ tab: AppTab, inTabBar: Bool) -> some View {
        let canMoveToTabBar = !inTabBar && tabBarTabs.count < maxVisibleTabs

        return Button {
            toggleTab(tab, inTabBar: inTabBar)
        } label: {
            HStack {
                Image(systemName: tab.icon)
                    .foregroundStyle(
                        inTabBar || canMoveToTabBar ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .foregroundStyle(inTabBar || canMoveToTabBar ? .primary : .secondary)
                    Text(tab.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Show action hint
                if inTabBar {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if canMoveToTabBar {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inTabBar && !canMoveToTabBar)
    }

    private func refreshTabs() {
        let order = TabConfiguration.tabOrder()
        let hidden = TabConfiguration.hiddenTabs()

        tabBarTabs = order.filter { $0 != .more && !hidden.contains($0) }
        moreTabs = order.filter { $0 != .more && hidden.contains($0) }
    }

    private func toggleTab(_ tab: AppTab, inTabBar: Bool) {
        var hidden = TabConfiguration.hiddenTabs()

        if inTabBar {
            // Move from tab bar to more
            hidden.insert(tab)
        } else {
            // Move from more to tab bar (only if under limit)
            if tabBarTabs.count < maxVisibleTabs {
                hidden.remove(tab)
            }
        }

        TabConfiguration.saveHidden(hidden)
        refreshTabs()
        notifyChange()
    }

    private func moveTabBarTab(from source: IndexSet, to destination: Int) {
        tabBarTabs.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    private func moveMoreTab(from source: IndexSet, to destination: Int) {
        moreTabs.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    private func saveTabOrder() {
        // Combine tab bar tabs + more tabs + .more at end
        let newOrder = tabBarTabs + moreTabs + [.more]
        TabConfiguration.saveOrder(newOrder)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .tabConfigurationChanged, object: nil)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - AllHiddenQSOsView

/// View showing all hidden (deleted) QSOs across the app with option to restore
struct AllHiddenQSOsView: View {
    // MARK: Internal

    var body: some View {
        Group {
            if hiddenQSOs.isEmpty, !isLoading {
                ContentUnavailableView(
                    "No Hidden QSOs",
                    systemImage: "checkmark.circle",
                    description: Text("All QSOs are visible")
                )
            } else {
                List {
                    Section {
                        ForEach(hiddenQSOs) { qso in
                            AllHiddenQSORow(qso: qso) {
                                restoreQSO(qso)
                            }
                        }

                        // Load more button if there are more hidden QSOs
                        if hasMoreQSOs {
                            HStack {
                                Spacer()
                                Button {
                                    Task { await loadMoreHiddenQSOs() }
                                } label: {
                                    if isLoadingMore {
                                        ProgressView()
                                            .padding(.vertical, 8)
                                    } else {
                                        Text(
                                            "Load More (\(totalCount - hiddenQSOs.count) remaining)"
                                        )
                                        .foregroundStyle(.blue)
                                    }
                                }
                                .disabled(isLoadingMore)
                                Spacer()
                            }
                        }
                    } header: {
                        Text("\(totalCount) hidden QSO\(totalCount == 1 ? "" : "s")")
                    } footer: {
                        Text(
                            "Hidden QSOs are excluded from sync and statistics. "
                                + "Restore them to include them again."
                        )
                    }

                    if !hiddenQSOs.isEmpty {
                        Section {
                            Button("Restore All") {
                                showRestoreAllConfirmation = true
                            }

                            Button("Permanently Delete All", role: .destructive) {
                                showDeleteAllConfirmation = true
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Hidden QSOs")
        .task {
            await loadHiddenQSOs()
        }
        .alert("Restore All?", isPresented: $showRestoreAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore All") {
                Task { await restoreAllQSOs() }
            }
        } message: {
            Text("This will restore \(totalCount) hidden QSO(s) and include them in sync.")
        }
        .alert("Permanently Delete All?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task { await permanentlyDeleteAllQSOs() }
            }
        } message: {
            Text(
                "This will permanently delete \(totalCount) hidden QSO(s). "
                    + "This cannot be undone."
            )
        }
    }

    // MARK: Private

    private static let batchSize = 100

    @Environment(\.modelContext) private var modelContext

    /// Hidden QSOs loaded on demand (not using @Query to avoid full table scan)
    @State private var hiddenQSOs: [QSO] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var showRestoreAllConfirmation = false
    @State private var showDeleteAllConfirmation = false

    private var hasMoreQSOs: Bool {
        hiddenQSOs.count < totalCount
    }

    private func loadHiddenQSOs() async {
        isLoading = true
        defer { isLoading = false }

        // Get total count
        let countDescriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.isHidden })
        totalCount = (try? modelContext.fetchCount(countDescriptor)) ?? 0

        // Fetch initial batch
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.isHidden })
        descriptor.sortBy = [SortDescriptor(\QSO.timestamp, order: .reverse)]
        descriptor.fetchLimit = Self.batchSize

        if let fetched = try? modelContext.fetch(descriptor) {
            hiddenQSOs = fetched
        }
    }

    private func loadMoreHiddenQSOs() async {
        guard !isLoadingMore, hasMoreQSOs else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.isHidden })
        descriptor.sortBy = [SortDescriptor(\QSO.timestamp, order: .reverse)]
        descriptor.fetchOffset = hiddenQSOs.count
        descriptor.fetchLimit = Self.batchSize

        if let fetched = try? modelContext.fetch(descriptor) {
            hiddenQSOs.append(contentsOf: fetched)
        }
    }

    private func restoreQSO(_ qso: QSO) {
        qso.isHidden = false
        try? modelContext.save()
        // Refresh list
        Task { await loadHiddenQSOs() }
    }

    private func restoreAllQSOs() async {
        // Process in batches to avoid memory issues with large datasets
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.isHidden })
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }
            if batch.isEmpty {
                break
            }

            for qso in batch {
                qso.isHidden = false
            }
            offset += Self.batchSize
            await Task.yield()
        }
        try? modelContext.save()

        // Refresh list
        await loadHiddenQSOs()
    }

    private func permanentlyDeleteAllQSOs() async {
        // Process in batches to avoid memory issues with large datasets
        var deletedCount = 0
        while true {
            // Always fetch from offset 0 since we're deleting
            var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.isHidden })
            descriptor.fetchLimit = Self.batchSize

            guard let batch = try? modelContext.fetch(descriptor) else {
                break
            }
            if batch.isEmpty {
                break
            }

            for qso in batch {
                modelContext.delete(qso)
                deletedCount += 1
            }
            await Task.yield()
        }
        try? modelContext.save()

        // Refresh list
        await loadHiddenQSOs()
    }
}

// MARK: - AllHiddenQSORow

/// A row displaying a hidden QSO with restore button
struct AllHiddenQSORow: View {
    // MARK: Internal

    let qso: QSO
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(qso.callsign)
                    .font(.headline.monospaced())

                HStack(spacing: 8) {
                    Text(qso.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(qso.band)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())

                    Text(qso.mode)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }

                if let park = qso.parkReference {
                    Text(park)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            Button {
                onRestore()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    // MARK: Private

    /// Shared date formatter for performance
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()
}
