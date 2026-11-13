import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionStartSheet

/// Session setup wizard for starting a new logging session
struct SessionStartSheet: View {
    var sessionManager: LoggingSessionManager?
    var onDismiss: () -> Void
    var onSessionStarted: (() -> Void)?

    @AppStorage("loggerDefaultCallsign") var defaultCallsign = ""
    @AppStorage("loggerDefaultMode") var defaultMode = "CW"
    @AppStorage("loggerDefaultGrid") var defaultGrid = ""
    @State var selectedMode = "CW"
    @State var frequency = ""
    @State var selectedPrograms: Set<String> = []
    @State var parkReference = ""
    @State var sotaReference = ""
    @State var missionReference = ""
    @State var wwffReference = ""
    @State var isRove = false
    @State var myGrid = ""
    @State var powerText = ""
    @State var selectedRadio: String?
    @State var selectedRadioItemID: UUID?

    // Callsign prefix/suffix
    @State var callsignPrefix = ""
    @State var selectedSuffix: CallsignSuffix = .none
    @State var customSuffix = ""

    // Club station
    @State var isClubStation = false
    @State var clubCallsignInput = ""

    @State var showPrefixSuffix = false
    @State var showPrefixPicker = false

    // Loadouts (Rust-backed, surfaced in the Gear section)
    @State var loadouts: [Loadout] = []
    @State var appliedLoadoutId: UUID?

    // Gear section UI state
    @State var gearExpanded = false
    @State var inventoryModel = EquipmentInventoryModel()
    @State var showNewLoadoutDialog = false
    @State var showSaveLoadoutDialog = false
    @State var showRenameLoadoutDialog = false
    @State var loadoutNameField = ""

    /// Track whether the user manually edited the grid. Once true, the
    /// background GPS handler stops auto-overwriting myGrid so manual
    /// corrections stick.
    @State var gridManuallyEdited = false

    // Equipment
    @State var selectedAntenna: String?
    @State var selectedKey: String?
    @State var selectedMic: String?
    @State var attendeesText = ""
    @State var additionalOperators: [String] = []
    @State var operatorInput = ""
    @State var sessionNotes = ""

    // Gear reminders
    @State var radioConnector: ConnectorType?
    @State var antennaConnector: ConnectorType?
    @State var checkedReminderIds: Set<String> = []
    @State var showGearReminders = false

    @AppStorage("loggerDefaultPrograms") var defaultPrograms = ""
    @AppStorage("loggerDefaultParkReference") var defaultParkReference = ""
    @AppStorage("loggerDefaultPower") var defaultPower = ""
    @AppStorage("loggerDefaultRadio") var defaultRadio = ""
    @AppStorage("loggerDefaultAntenna") var defaultAntenna = ""
    @AppStorage("loggerDefaultKey") var defaultKey = ""
    @AppStorage("loggerDefaultMic") var defaultMic = ""
    @AppStorage("loggerDefaultContestId") var defaultContestId = ""

    // SDR auto-start
    @AppStorage("sdrAutoStart") var sdrAutoStart = false
    @AppStorage("sdrLastReceiverHostPort") var sdrLastReceiverHostPort = ""
    @AppStorage("sdrLastReceiverName") var sdrLastReceiverName = ""
    @State var showSDRPicker = false

    // Contest
    @State var showContestPicker = false
    @State var selectedContest: ContestDefinition?
    @State var contestCategory = ""
    @State var contestOverlayCategory = ""
    @State var contestPowerClass = "HIGH"
    @State var contestBands = "ALL"

    /// Template to pre-fill from (set externally before presenting)
    var initialTemplate: SavedSessionTemplate?

    /// Pre-fill programs and references (e.g. from map park/summit selection)
    var initialPrograms: Set<String>?
    var initialParkReference: String?
    var initialSotaReference: String?

    /// Contest-intent entry. `""` = auto-present picker. Non-nil id = pre-load.
    /// See `applyContestIntentIfNeeded()`.
    var initialContestId: String?

    /// Which tailored wizard to present. Defaults to the full-featured
    /// `.activation` layout so generic entry points (logger "+", map park
    /// selection) keep their existing behaviour. See `SessionOperationType`.
    var operationType: SessionOperationType = .activation

    /// UI state
    @State var showSavedConfirmation = false
    @State var showBandPlanSheet = false
    @State var bandDetail: BandSuggestion?
    @State var showBandSuggestions = false

    /// Frequency the wizard auto-suggested (most-activated band × radio
    /// capability). Tracks our own fill so re-suggestion never clobbers a
    /// value the operator typed or a band pill they tapped.
    @State var autoFilledFrequency: String?
    @State var frequencyOverridden = false
    @State var frequencySuggestionNote: String?
    @State var scopeSpots: [ScopeSpot] = []
    /// True while the async POTA/SOTA/RBN spot fetch is in flight, so the
    /// callout can show a spinner describing what it's doing.
    @State var frequencySuggestionLoading = false

    /// Collapsed-by-default tail of the wizard (station, people, contest
    /// add-on, WebSDR, pack checklist, notes). The essentials — identity,
    /// what, radio — are always visible; everything else expands on demand.
    @State var showMoreOptions = false

    /// Park reference this sheet auto-filled (closest / most-frequent). Lets
    /// the prefill replace its own suggestion when the GPS fix lands without
    /// ever clobbering a park the user typed or picked.
    @State var autoFilledPark: String?

    @Environment(\.modelContext) var modelContext

    @State var hasLoadedDefaults = false
    @State var startedLocationForPreFill = false

    // TOTA fields (only consumed when "tota" is in selectedPrograms)
    @State var totaActivationLatitude: Double?
    @State var totaActivationLongitude: Double?
    @State var totaRecordTrack = true
    @State var totaWithPets = false
    @State var totaWithKids = false
    @State var totaWinlinkSent = false
    @State var totaAprsSent = false
    @State var totaVaracSent = false
    @State var totaAdaptiveSport = false
    @State var totaRuckWeightPounds: Double?
    @State var totaRuckWeightAutoFilled = false
    @State var totaCategory: TOTACategory = .standard // Standard hides bonus inputs.
    @State var totaWinterOverride: Bool? // nil = auto-detect by hemisphere/month.
    @State var totaPersonalEffortFactor: Int = 0 // Frozen at start.
    @AppStorage("totaPersonalEffortFactor") var totaProfilePEF: Int = 0

    var parsedPower: Int? {
        guard !powerText.isEmpty,
              let watts = Int(powerText), watts > 0, watts <= 1_500
        else {
            return nil
        }
        return watts
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                wizardSections

                Section {} footer: {
                    Spacer()
                        .frame(height: 1)
                }
                .listSectionSeparator(.hidden)
            }
            .scrollContentBackground(.visible)
            .listSectionSpacing(24)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .task {
                loadDefaults()
                loadSavedLoadouts()
                inventoryModel.start()
                recomputeTOTARuckWeightIfNeeded()
                loadTOTAProfileDefaultsIfNeeded()
                // The parks cache hydrates lazily from the Rust store at app
                // launch; right after a (re)launch the wizard can open before
                // it finishes and the synchronous snapshot reads empty. Wait
                // for hydration before computing the park prefill.
                await POTAParksCache.shared.ensureLoaded()
                prefillParkIfNeeded()
                await refreshSuggestedFrequency()
                await applyContestIntentIfNeeded()
                // A pre-loaded contest add-on lives in the collapsed tail —
                // expand it so the user can see what they came for.
                if operationType == .activation, selectedContest != nil {
                    showMoreOptions = true
                }
            }
            .onDisappear {
                inventoryModel.stop()
                if startedLocationForPreFill {
                    sessionManager?.locationService.stop()
                }
            }
            .onChange(of: sessionManager?.locationService.currentGrid) { _, newGrid in
                // GPS overwrites the field unless the user has typed something
                // of their own. Empty -> pre-fill. Pre-fill from defaultGrid ->
                // still get replaced once GPS has a fix.
                if let newGrid, !gridManuallyEdited, newGrid != myGrid {
                    myGrid = newGrid
                    prefillParkIfNeeded()
                }
            }
            .onChange(of: selectedRadio) { _, _ in
                refreshConnectorForRadio()
                recomputeTOTARuckWeightIfNeeded()
                Task { await refreshSuggestedFrequency() }
            }
            .onChange(of: selectedRadioItemID) { _, _ in
                Task { await refreshSuggestedFrequency() }
            }
            .onChange(of: frequency) { _, newValue in
                // A value we didn't place means the operator typed or tapped
                // their own — retire the suggestion so we stop re-picking.
                if !newValue.isEmpty, newValue != autoFilledFrequency {
                    frequencyOverridden = true
                    frequencySuggestionNote = nil
                }
            }
            .onChange(of: selectedAntenna) { _, _ in
                refreshConnectorForAntenna()
                recomputeTOTARuckWeightIfNeeded()
            }
            .onChange(of: selectedPrograms) { _, _ in
                recomputeTOTARuckWeightIfNeeded()
                prefillParkIfNeeded()
            }
            .onChange(of: selectedKey) { _, _ in
                recomputeTOTARuckWeightIfNeeded()
            }
            .onChange(of: selectedMic) { _, _ in
                recomputeTOTARuckWeightIfNeeded()
            }
            .onChange(of: selectedMode) { oldMode, newMode in
                // Leaving FT8/FT4 for a free-form mode: drop the fixed digital
                // frequency so the suggestion re-picks for the new mode (unless
                // the operator pinned their own value).
                let ftModes: Set = ["FT8", "FT4"]
                let leavingFT = ftModes.contains(oldMode) && !ftModes.contains(newMode)
                if leavingFT, !frequencyOverridden {
                    frequency = ""
                    autoFilledFrequency = nil
                }
                Task { await refreshSuggestedFrequency() }
            }
            .overlay(alignment: .bottom) {
                // Pinned primary action. An overlay (not `.safeAreaInset`) so
                // it doesn't participate in safe-area layout on every body
                // re-eval — the previous banner variant caused scroll jitter
                // that way. `.contentMargins(.bottom, ...)` above reserves
                // room so the last fields aren't covered. The disabled reason
                // rides directly above the button instead of shouting from a
                // detached banner.
                startBar
            }
            .sheet(isPresented: $showBandPlanSheet) {
                BandPlanSheet(
                    selectedMode: selectedMode,
                    frequency: $frequency
                )
            }
            .sheet(item: $bandDetail) { band in
                BandActivitySheet(
                    suggestion: band,
                    onFrequencyPicked: { showBandSuggestions = false },
                    frequency: $frequency
                )
            }
            .sheet(isPresented: $showContestPicker) { contestPickerSheetContent }
            .onChange(of: selectedContest) { _, newValue in handleContestSelection(newValue) }
            .sheet(isPresented: $showPrefixPicker) {
                CallsignPrefixSheet(
                    currentPrefix: callsignPrefix,
                    homeCallsign: defaultCallsign,
                    currentGrid: myGrid.isEmpty ? nil : myGrid
                ) { prefix in
                    callsignPrefix = prefix
                    if !prefix.isEmpty {
                        showPrefixSuffix = true
                    }
                }
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
            .sheet(isPresented: $showSDRPicker) {
                WebSDRPickerSheet(
                    myGrid: myGrid.isEmpty ? defaultGrid : myGrid,
                    operatingBand: parsedFrequency.flatMap { BandUtilities.deriveBand(from: $0 * 1_000) }
                ) { receiver in
                    sdrLastReceiverHostPort = "\(receiver.host):\(receiver.port)"
                    sdrLastReceiverName = receiver.name
                    sdrAutoStart = true
                    showSDRPicker = false
                }
                .landscapeAdaptiveDetents(portrait: [.medium, .large])
            }
            .navigationTitle(operationType.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Start Bar

extension SessionStartSheet {
    /// Pinned bottom bar with the primary Start action. The disabled reason
    /// sits right above the button so cause and blocked action read together.
    var startBar: some View {
        VStack(spacing: 8) {
            if let reason = startDisabledReason {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Button {
                startSession()
            } label: {
                Text(operationType.startButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canStart)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Validation & Keyboard

extension SessionStartSheet {
    /// Dismiss the keyboard from any focused field. Wired to the keyboard
    /// toolbar's Done button and to the grid TextField's submit.
    func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    var validationInput: SessionStartInput {
        SessionStartInput(
            callsign: defaultCallsign,
            programs: selectedPrograms,
            parkReference: parkReference,
            sotaReference: sotaReference,
            missionReference: missionReference,
            wwffReference: wwffReference,
            frequency: parsedFrequency
        )
    }

    var canStart: Bool {
        if isClubStation, clubStationCallsign == nil {
            return false
        }
        return SessionStartValidation.canStart(validationInput)
    }

    var startDisabledReason: String? {
        if isClubStation, clubStationCallsign == nil {
            return "Enter a club callsign"
        }
        return SessionStartValidation.disabledReason(validationInput)
    }

    var parsedFrequency: Double? {
        FrequencyFormatter.parse(frequency)
    }
}

// MARK: - Computed Properties

extension SessionStartSheet {
    /// The full constructed callsign (prefix/base/suffix)
    /// In club station mode, this is the operator's unmodified callsign from settings.
    var fullCallsign: String {
        if isClubStation {
            return defaultCallsign.uppercased()
        }
        let prefix = callsignPrefix.trimmingCharacters(in: .whitespaces).uppercased()
        let suffix = effectiveSuffix
        let parts = [prefix, defaultCallsign.uppercased(), suffix].filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    /// The club station callsign with prefix/suffix applied (nil when not in club mode)
    var clubStationCallsign: String? {
        guard isClubStation else {
            return nil
        }
        let base = clubCallsignInput.trimmingCharacters(in: .whitespaces).uppercased()
        guard !base.isEmpty else {
            return nil
        }
        let prefix = callsignPrefix.trimmingCharacters(in: .whitespaces).uppercased()
        let suffix = effectiveSuffix
        let parts = [prefix, base, suffix].filter { !$0.isEmpty }
        return parts.joined(separator: "/")
    }

    /// The effective suffix based on selection
    var effectiveSuffix: String {
        switch selectedSuffix {
        case .none:
            ""
        case .portable:
            "P"
        case .mobile:
            "M"
        case .maritime:
            "MM"
        case .aeronautical:
            "AM"
        case .custom:
            customSuffix.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    var powerWarning: String? {
        guard !powerText.isEmpty else {
            return nil
        }
        guard let watts = Int(powerText) else {
            return "Enter a whole number"
        }
        if watts <= 0 {
            return "Power must be greater than 0"
        }
        if watts > 1_500 {
            return "US maximum is 1,500W"
        }
        return nil
    }
}

// MARK: - Preview

#Preview {
    SessionStartSheet(
        sessionManager: nil,
        onDismiss: {}
    )
}
