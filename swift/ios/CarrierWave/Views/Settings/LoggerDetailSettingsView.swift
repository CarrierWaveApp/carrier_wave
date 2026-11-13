import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - LoggerDetailSettingsView

struct LoggerDetailSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "square.and.pencil",
                tint: .blue,
                title: "Logger",
                subtitle: "How the logger looks and behaves during a session."
            )
            modeInputSection
            displaySection
            behaviorSection
            gridPrecisionSection
            fieldsSection
            scpSection
            contestSection
            conditionsSection
            bragSheetSection
            webSDRSection
            activityLogSection
        }
        .navigationTitle("Logger")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            userProfile = UserProfileService.shared.getProfile()
        }
    }

    // MARK: Private

    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerSimpleMode") private var loggerSimpleMode = false
    @AppStorage("rstParseOrder") private var rstParseOrder = RSTOrder.receivedFirst.rawValue
    @AppStorage("loggerShowActivityPanel") private var showActivityPanel = true
    @AppStorage("loggerShowLicenseWarnings") private var showLicenseWarnings = true
    @AppStorage("loggerKeepScreenOn") private var keepScreenOn = true
    @AppStorage("shareSessionOnEnd") private var shareSessionOnEnd = true
    @AppStorage("loggerAutoModeSwitch") private var autoModeSwitch = true
    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"

    @AppStorage("keyboardRowShowNumbers") private var keyboardRowShowNumbers = true
    @AppStorage("keyboardRowSymbols") private var keyboardRowSymbols = "/"
    @AppStorage("prefixRowEnabled") private var prefixRowEnabled = true
    @AppStorage("commandRowEnabled") private var commandRowEnabled = false

    @AppStorage("loggerKeepLookupAfterLog") private var keepLookupAfterLog = true
    @AppStorage("contestAutoFillExchange") private var contestAutoFillExchange = true
    @AppStorage("loggerHideFieldEntryForm") private var hideFieldEntryForm = false
    @AppStorage("loggerShowTheirGrid") private var showTheirGrid = false
    @AppStorage("loggerShowTheirPark") private var showTheirPark = false
    @AppStorage("loggerShowOperator") private var showOperator = false

    @AppStorage("scpEnabled") private var scpEnabled = true
    @AppStorage("scpWarningEnabled") private var scpWarningEnabled = false
    @AppStorage("loggerShowPhonetics") private var showPhonetics = false

    @AppStorage(GridPrecisionPreference.key) private var gridPrecisionRaw = 6

    @AppStorage("autoRecordConditions") private var autoRecordConditions = true
    @AppStorage("solarPollingEnabled") private var solarPollingEnabled = true
    @AppStorage(DONKIPollingService.settingsKey) private var spaceWeatherAlertsEnabled = true
    @AppStorage("shareCardIncludeEquipment") private var shareCardIncludeEquipment = true
    @AppStorage("statisticianMode") private var statisticianMode = false

    @State private var userProfile: UserProfile?

    private var keyboardRowsSummary: String {
        var count = 0
        if keyboardRowShowNumbers || !keyboardRowSymbols.isEmpty {
            count += 1
        }
        if prefixRowEnabled {
            count += 1
        }
        if commandRowEnabled {
            count += 1
        }
        return "\(count) row\(count == 1 ? "" : "s")"
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

            Picker("RST Parse Order", selection: $rstParseOrder) {
                ForEach(RSTOrder.allCases, id: \.rawValue) { order in
                    Text(order.label).tag(order.rawValue)
                }
            }

            NavigationLink {
                KeyboardRowsSettingsView()
            } label: {
                HStack {
                    Text("Keyboard Rows")
                    Spacer()
                    Text(keyboardRowsSummary)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Mode & Input")
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Simple Logging Mode", isOn: $loggerSimpleMode)
            Toggle("Show frequency activity", isOn: $showActivityPanel)

            Picker("Notes display", selection: $notesDisplayMode) {
                Text("Emoji").tag("emoji")
                Text("Source names").tag("sources")
            }
        } header: {
            Text("Display")
        } footer: {
            Text(
                "Simple mode hides situational chips — duration, equipment, "
                    + "space weather, SDR/radio status, and operating shift — "
                    + "from the in-session header."
            )
        }
    }

    private var behaviorSection: some View {
        Section {
            Toggle("Keep screen on", isOn: $keepScreenOn)
            Toggle("Auto-switch mode for frequency", isOn: $autoModeSwitch)
            Toggle("Keep lookup info after logging", isOn: $keepLookupAfterLog)
            Toggle("Hide field entry form", isOn: $hideFieldEntryForm)
            Toggle("Share to activity feed on end", isOn: $shareSessionOnEnd)
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

    private var gridPrecisionSection: some View {
        Section {
            Picker("Grid precision", selection: $gridPrecisionRaw) {
                Text("4-character (FN31)").tag(4)
                Text("6-character (FN31pr)").tag(6)
                Text("8-character (FN31pr12)").tag(8)
            }
        } header: {
            Text("Grid Square")
        } footer: {
            Text(
                "Precision used when deriving your grid from GPS. "
                    + "6-character is the HF default; 8-character is "
                    + "useful for VHF/UHF and grid-square contests."
            )
        }
    }

    private var scpSection: some View {
        Section {
            Toggle("Callsign Suggestions", isOn: $scpEnabled)
            Toggle("Warn on Unknown Callsign", isOn: $scpWarningEnabled)
            Toggle("Show NATO Phonetics", isOn: $showPhonetics)
        } header: {
            Text("Callsign Assistance")
        } footer: {
            Text(
                "Suggestions show callsign completions while typing, "
                    + "combining the SCP database with active spots. "
                    + "Unknown callsign warnings prompt before logging "
                    + "a callsign not found in the database. "
                    + "NATO phonetics shows the phonetic spelling "
                    + "on the callsign lookup card for readback."
            )
        }
    }

    private var contestSection: some View {
        Section {
            Toggle(
                "Auto-fill exchange from member lists",
                isOn: $contestAutoFillExchange
            )
        } header: {
            Text("Contests")
        } footer: {
            Text(
                "When logging a contest like CWT, prefill the exchange "
                    + "(name and member number) from the server's "
                    + "callsign enrichment data. Only fills empty fields, "
                    + "so anything you've typed stays put."
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
            Toggle("Space weather alerts", isOn: $spaceWeatherAlertsEnabled)
                .onChange(of: spaceWeatherAlertsEnabled) {
                    DONKIPollingService.shared.startIfEnabled()
                }
        } header: {
            Text("Conditions")
        } footer: {
            Text(
                "Records current solar and weather conditions when starting a session. "
                    + "Hourly polling captures solar conditions in the background "
                    + "for a continuous conditions history graph. "
                    + "Space weather alerts notify you of geomagnetic storms, "
                    + "solar flares, and CMEs that may degrade HF propagation."
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
}
