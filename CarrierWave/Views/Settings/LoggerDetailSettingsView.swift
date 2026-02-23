import SwiftUI

// MARK: - LoggerDetailSettingsView

struct LoggerDetailSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            modeInputSection
            displaySection
            behaviorSection
            fieldsSection
            conditionsSection
            bragSheetSection
            webSDRSection
            activityLogSection
        }
        .navigationTitle("Logger")
        .onAppear {
            userProfile = UserProfileService.shared.getProfile()
        }
    }

    // MARK: Private

    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerShowActivityPanel") private var showActivityPanel = true
    @AppStorage("loggerShowLicenseWarnings") private var showLicenseWarnings = true
    @AppStorage("loggerKeepScreenOn") private var keepScreenOn = true
    @AppStorage("loggerAutoModeSwitch") private var autoModeSwitch = true
    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"

    @AppStorage("keyboardRowShowNumbers") private var keyboardRowShowNumbers = true
    @AppStorage("keyboardRowSymbols") private var keyboardRowSymbols = "/"
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false
    @AppStorage("commandRowCommands") private var commandRowCommands =
        "rbn,solar,weather,spot,pota,p2p"

    @AppStorage("loggerKeepLookupAfterLog") private var keepLookupAfterLog = true
    @AppStorage("loggerHideFieldEntryForm") private var hideFieldEntryForm = false
    @AppStorage("loggerShowTheirGrid") private var showTheirGrid = false
    @AppStorage("loggerShowTheirPark") private var showTheirPark = false
    @AppStorage("loggerShowOperator") private var showOperator = false

    @AppStorage("autoRecordConditions") private var autoRecordConditions = true
    @AppStorage("solarPollingEnabled") private var solarPollingEnabled = true
    @AppStorage("shareCardIncludeEquipment") private var shareCardIncludeEquipment = true
    @AppStorage("statisticianMode") private var statisticianMode = false

    @State private var userProfile: UserProfile?

    private var keyboardRowSummary: String {
        var parts: [String] = []
        if keyboardRowShowNumbers {
            parts.append("0-9")
        }
        let symbols = keyboardRowSymbols.components(separatedBy: ",")
            .filter { !$0.isEmpty }
        if !symbols.isEmpty {
            parts.append(symbols.joined())
        }
        return parts.isEmpty ? "None" : parts.joined(separator: " ")
    }

    private var commandRowSummary: String {
        guard commandRowEnabled else {
            return "Off"
        }
        let commands = commandRowCommands.components(separatedBy: ",")
            .filter { !$0.isEmpty }
        if commands.isEmpty {
            return "None"
        }
        return "\(commands.count) commands"
    }

    private var modeInputSection: some View {
        Section {
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
        } header: {
            Text("Mode & Input")
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Show frequency activity", isOn: $showActivityPanel)

            Picker("Notes display", selection: $notesDisplayMode) {
                Text("Emoji").tag("emoji")
                Text("Source names").tag("sources")
            }
        } header: {
            Text("Display")
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Keep screen on", isOn: $keepScreenOn)
            Toggle("Auto-switch mode for frequency", isOn: $autoModeSwitch)
            Toggle("Keep lookup info after logging", isOn: $keepLookupAfterLog)
            Toggle("Hide field entry form", isOn: $hideFieldEntryForm)
        } header: {
            Text("Behavior")
        } footer: {
            Text(
                "Keep screen on prevents device sleep during sessions. "
                    + "Keep lookup info shows the callsign card after logging "
                    + "until you start typing a new callsign."
            )
        }
    }

    private var fieldsSection: some View {
        Section {
            Toggle("Their Grid", isOn: $showTheirGrid)
            Toggle("Their Park", isOn: $showTheirPark)
            Toggle("Operator", isOn: $showOperator)
        } header: {
            Text("Always Visible Fields")
        } footer: {
            Text(
                "Notes and RST are always visible. "
                    + "Other fields appear without tapping \"More Fields\"."
            )
        }
    }

    private var conditionsSection: some View {
        Section {
            Toggle(
                "Record solar & weather at start",
                isOn: $autoRecordConditions
            )
            Toggle("Poll solar conditions hourly", isOn: $solarPollingEnabled)
                .onChange(of: solarPollingEnabled) {
                    SolarPollingService.shared.startIfEnabled()
                }
        } header: {
            Text("Conditions")
        } footer: {
            Text(
                "Records current solar and weather conditions when starting a session. "
                    + "Hourly polling captures solar conditions in the background "
                    + "for a continuous conditions history graph."
            )
        }
    }

    private var bragSheetSection: some View {
        Section {
            Toggle(
                "Include equipment on brag sheet",
                isOn: $shareCardIncludeEquipment
            )
            Toggle("Professional Statistician Mode", isOn: $statisticianMode)
        } header: {
            Text("Brag Sheet & Stats")
        } footer: {
            Text(
                "Equipment on brag sheet shows radio, antenna, key, and other gear. "
                    + "Statistician mode adds charts to activation details "
                    + "and extra stats to brag sheets."
            )
        }
    }

    private var webSDRSection: some View {
        Section {
            NavigationLink {
                WebSDRRecordingsView()
            } label: {
                Text("Recordings")
            }

            NavigationLink {
                WebSDRFavoritesView()
            } label: {
                Text("Favorites")
            }
        } header: {
            Text("WebSDR")
        }
    }

    private var activityLogSection: some View {
        Section("Hunter Log") {
            NavigationLink {
                ActivityLogSettingsView()
            } label: {
                HStack {
                    Text("Hunter Log Settings")
                    Spacer()
                    let count = StationProfileStorage.load().count
                    Text("\(count) profile\(count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
