// swiftlint:disable file_length type_body_length
import CarrierWaveCore
import SwiftData
import SwiftUI

// MARK: - LoggerView

/// Main logging view for QSO entry
struct LoggerView: View {
    // MARK: Lifecycle

    init(
        tourState: TourState,
        onSessionEnd: (() -> Void)? = nil,
        onSpotCommand: ((SpotCommandAction) -> Void)? = nil,
        pendingSpotSelection: Binding<SpotSelection?>? = nil
    ) {
        self.tourState = tourState
        self.onSessionEnd = onSessionEnd
        self.onSpotCommand = onSpotCommand
        _externalSpotSelection = pendingSpotSelection ?? .constant(nil)
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    sessionHeader

                    // WebSDR mini recording badge (visible when panel is closed)
                    if let manager = sessionManager,
                       !showWebSDRPanel,
                       manager.webSDRSession.state.isActive
                    {
                        webSDRMiniBadge(session: manager.webSDRSession)
                    }

                    // Spot monitoring summary (always visible when session active)
                    if let manager = sessionManager {
                        SpotSummaryView(monitoringService: manager.spotMonitoringService)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Frequency warning banner (license violations + activity warnings)
                    // Note: We pass cachedPOTASpots.count and callsignInput to force re-evaluation
                    FrequencyWarningBannerContainer(
                        warning: computeCurrentWarning(
                            spotCount: cachedPOTASpots.count,
                            inputText: callsignInput
                        ),
                        onDismiss: { message in
                            dismissedWarnings.insert(message)
                        }
                    )

                    ScrollView {
                        VStack(spacing: 12) {
                            UnderConstructionBanner()

                            // Only show QSO form when session is active
                            if sessionManager?.hasActiveSession == true {
                                callsignInputSection

                                // POTA duplicate/new band warning
                                if let status = potaDuplicateStatus {
                                    POTAStatusBanner(status: status)
                                        .transition(
                                            .asymmetric(
                                                insertion: .move(edge: .top).combined(
                                                    with: .opacity
                                                ),
                                                removal: .opacity
                                            )
                                        )
                                }

                                // Show callsign info or error when keyboard is not visible
                                callsignLookupDisplay

                                // Compact fields: State, RSTs, with More expansion
                                compactFieldsSection

                                // Cancel button when editing a QSO
                                if editingQSO != nil {
                                    Button {
                                        cancelEditingCallsign()
                                    } label: {
                                        Text("Cancel Edit")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Cancel editing callsign")
                                }
                            }

                            qsoListSection
                        }
                        .padding()
                        // Add bottom padding when a panel is open so Log QSO button remains accessible
                        .padding(.bottom, isAnyPanelOpen ? 280 : 0)
                    }
                }
            }
            .navigationBarHidden(horizontalSizeClass != .regular)
            .toolbarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSessionSheet) {
                SessionStartSheet(
                    sessionManager: sessionManager,
                    onDismiss: { showSessionSheet = false }
                )
            }
            .sheet(isPresented: $showTitleEditSheet) {
                SessionTitleEditSheet(
                    title: $editingTitle,
                    defaultTitle: sessionManager?.activeSession?.defaultTitle ?? "",
                    onSave: { newTitle in
                        sessionManager?.updateTitle(newTitle.isEmpty ? nil : newTitle)
                        showTitleEditSheet = false
                    },
                    onCancel: {
                        showTitleEditSheet = false
                    }
                )
                .presentationDetents([.height(200)])
            }
            .sheet(isPresented: $showParkEditSheet) {
                SessionParkEditSheet(
                    parkReference: $editingParkReference,
                    userGrid: sessionManager?.activeSession?.myGrid
                        ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid"),
                    onSave: { newPark in
                        sessionManager?.updateParkReference(newPark.isEmpty ? nil : newPark)
                        showParkEditSheet = false
                    },
                    onCancel: {
                        showParkEditSheet = false
                    }
                )
                .presentationDetents([.height(340)])
            }
            .sheet(isPresented: $showNextStopSheet) {
                NextRoveStopSheet(
                    sessionManager: sessionManager,
                    onDismiss: {
                        showNextStopSheet = false
                        refreshSessionQSOs()
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showBandEditSheet) {
                SessionBandEditSheet(
                    currentFrequency: sessionManager?.activeSession?.frequency,
                    currentMode: sessionManager?.activeSession?.mode ?? "CW",
                    onSelectFrequency: { freq in
                        let result = sessionManager?.updateFrequency(freq)
                        if result?.isFirstFrequencySet == true {
                            let band = LoggingSession.bandForFrequency(freq)
                            ToastManager.shared.success(
                                "Frequency set to \(FrequencyFormatter.formatWithUnit(freq)) (\(band))"
                            )
                        }
                        if autoModeSwitch, let suggestedMode = result?.suggestedMode {
                            _ = sessionManager?.updateMode(suggestedMode)
                        }
                        if result?.shouldPromptForSpot == true {
                            qsyNewFrequency = freq
                            showQSYSpotConfirmation = true
                        }
                        showBandEditSheet = false
                    },
                    onCancel: {
                        showBandEditSheet = false
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showModeEditSheet) {
                SessionModeEditSheet(
                    currentMode: sessionManager?.activeSession?.mode ?? "CW",
                    onSelectMode: { newMode in
                        _ = sessionManager?.updateMode(newMode)
                        showModeEditSheet = false
                    },
                    onCancel: {
                        showModeEditSheet = false
                    }
                )
                .presentationDetents([.height(280)])
            }
            .sheet(isPresented: $showRigEditSheet) {
                SessionEquipmentEditSheet(
                    radio: Binding(
                        get: { sessionManager?.activeSession?.myRig },
                        set: { sessionManager?.activeSession?.myRig = $0 }
                    ),
                    antenna: Binding(
                        get: { sessionManager?.activeSession?.myAntenna },
                        set: { sessionManager?.activeSession?.myAntenna = $0 }
                    ),
                    key: Binding(
                        get: { sessionManager?.activeSession?.myKey },
                        set: { sessionManager?.activeSession?.myKey = $0 }
                    ),
                    mic: Binding(
                        get: { sessionManager?.activeSession?.myMic },
                        set: { sessionManager?.activeSession?.myMic = $0 }
                    ),
                    extraEquipment: Binding(
                        get: { sessionManager?.activeSession?.extraEquipment },
                        set: { sessionManager?.activeSession?.extraEquipment = $0 }
                    ),
                    mode: sessionManager?.activeSession?.mode ?? "CW"
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showHiddenQSOsSheet) {
                HiddenQSOsSheet(sessionId: sessionManager?.activeSession?.id)
            }
            .onAppear {
                if sessionManager == nil {
                    sessionManager = LoggingSessionManager(modelContext: modelContext)
                }
                // Load session QSOs after session manager is ready
                refreshSessionQSOs()
                refreshActiveSessions()

                // Fetch POTA spots for nearby frequency detection
                Task {
                    await refreshPOTASpots()
                }
            }
            .task {
                // Periodic refresh of POTA spots (every 60 seconds)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else {
                        break
                    }
                    await refreshPOTASpots()
                }
            }
            .onChange(of: sessionManager?.activeSession?.frequency) { _, _ in
                dismissedWarnings.removeAll()
                // Refresh spots if we don't have any cached yet
                if cachedPOTASpots.isEmpty {
                    Task {
                        await refreshPOTASpots()
                    }
                }
            }
            .onChange(of: sessionManager?.activeSession?.mode) { _, _ in
                dismissedWarnings.removeAll()
                // RST fields stay empty - placeholder shows correct default based on mode
            }
            .onChange(of: sessionManager?.activeSession?.id) { _, _ in
                refreshSessionQSOs()
                refreshActiveSessions()
            }
            .onChange(of: externalSpotSelection) { _, newValue in
                if let selection = newValue {
                    handleSpotSelection(selection)
                    externalSpotSelection = nil
                }
            }
            .overlay(alignment: .bottom) {
                panelOverlays
            }
            .sheet(isPresented: $showHelpSheet) {
                LoggerHelpSheet()
            }
            .sheet(isPresented: $showPOTAUploadPrompt) {
                POTAUploadPromptSheet(
                    parkReference: pendingSessionEndParkRef ?? "",
                    parkName: pendingSessionEndParkName,
                    qsoCount: pendingSessionEndQSOCount,
                    isInMaintenance: pendingSessionEndInMaintenance,
                    maintenanceTimeRemaining: pendingSessionEndMaintenanceRemaining,
                    onUpload: {
                        await uploadPendingPOTAQSOs()
                    },
                    onLater: {
                        showPOTAUploadPrompt = false
                        completeSessionEnd()
                    },
                    onDontAskAgain: {
                        potaUploadPromptDisabled = true
                        showPOTAUploadPrompt = false
                        completeSessionEnd()
                    }
                )
            }
            .sheet(isPresented: $showDeleteSessionSheet) {
                DeleteSessionConfirmationSheet(
                    qsoCount: sessionQSOs.count,
                    onConfirm: {
                        sessionManager?.deleteCurrentSession()
                        showDeleteSessionSheet = false
                    },
                    onCancel: {
                        showDeleteSessionSheet = false
                    }
                )
            }
            .alert("Post QSY Spot?", isPresented: $showQSYSpotConfirmation) {
                Button("No", role: .cancel) {}
                Button("Yes") {
                    Task {
                        await sessionManager?.postQSYSpot()
                    }
                }
            } message: {
                if let freq = qsyNewFrequency {
                    Text("Post a QSY spot to POTA at \(FrequencyFormatter.formatWithUnit(freq))?")
                } else {
                    Text("Post a QSY spot to POTA?")
                }
            }
            .toastContainer()
            .miniTour(.logger, tourState: tourState)
        }
    }

    // MARK: Private

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @AppStorage("userLicenseClass") private var licenseClassRaw: String = LicenseClass.extra
        .rawValue

    @AppStorage("loggerAutoModeSwitch") private var autoModeSwitch = true

    /// QSOs for the current session (manually fetched, not @Query to avoid full-database refresh)
    @State private var sessionQSOs: [QSO] = []

    @State private var sessionManager: LoggingSessionManager?

    @State private var showSessionSheet = false

    /// Active/paused sessions available to continue or finish
    @State private var activeSessions: [LoggingSession] = []
    /// QSO counts for active sessions (keyed by session ID)
    @State private var activeSessionQSOCounts: [UUID: Int] = [:]
    /// Finish confirmation for an active session
    @State private var sessionToFinish: LoggingSession?
    /// Delete confirmation for an active session
    @State private var sessionToDelete: LoggingSession?

    // Input fields
    @State private var callsignInput = ""
    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var showMoreFields = false
    @FocusState private var callsignFieldFocused: Bool

    // Quick entry
    @State private var quickEntryResult: QuickEntryResult?
    @State private var quickEntryTokens: [ParsedToken] = []

    // Expanded fields
    @State private var notes = ""
    @State private var theirPark = ""
    @State private var operatorName = ""
    @State private var theirGrid = ""
    @State private var theirState = ""

    // Callsign lookup
    @State private var lookupResult: CallsignInfo?
    @State private var lookupError: CallsignLookupError?
    @State private var lookupTask: Task<Void, Never>?

    /// All-time QSO count with the current callsign
    @State private var previousQSOCount: Int = 0

    /// Cached POTA duplicate status (computed on callsign change, not every render)
    @State private var cachedPotaDuplicateStatus: POTACallsignStatus?

    // Command panels
    @State private var showRBNPanel = false
    @State private var showMapPanel = false
    @State private var rbnTargetCallsign: String?
    @State private var showSolarPanel = false
    @State private var showWeatherPanel = false
    @State private var showPOTAPanel = false
    @State private var showP2PPanel = false
    @State private var showHelpSheet = false
    @State private var showHiddenQSOsSheet = false
    @State private var showWebSDRPanel = false

    // Session title editing
    @State private var showTitleEditSheet = false
    @State private var editingTitle = ""

    // Session park editing
    @State private var showParkEditSheet = false
    @State private var editingParkReference = ""

    /// Rove
    @State private var showNextStopSheet = false
    /// When set, logger displays QSOs for this park instead of the current active stop
    @State private var viewingParkOverride: String?

    // Session band/mode/rig editing
    @State private var showBandEditSheet = false
    @State private var showModeEditSheet = false
    @State private var showRigEditSheet = false

    /// Session end/delete confirmation
    @State private var showEndSessionConfirmation = false
    @State private var showDeleteSessionSheet = false

    /// POTA upload prompt after session end
    @State private var showPOTAUploadPrompt = false
    @State private var pendingSessionEndParkRef: String?
    @State private var pendingSessionEndParkName: String?
    @State private var pendingSessionEndQSOCount = 0
    @State private var pendingSessionEndQSOs: [QSO] = []
    @State private var pendingSessionEndInMaintenance = false
    @State private var pendingSessionEndMaintenanceRemaining: String?

    /// User preference to disable POTA upload prompt
    @AppStorage("potaUploadPromptDisabled") private var potaUploadPromptDisabled = false

    /// QSO being edited (for tap-to-edit callsign feature)
    @State private var editingQSO: QSO?

    /// QSO pending swipe-to-delete confirmation
    @State private var qsoToDelete: QSO?

    // QSY spot confirmation
    @State private var showQSYSpotConfirmation = false
    @State private var qsyNewFrequency: Double?

    /// POTA spot tracking - stores session frequency before tuning to a spot
    @State private var preSpotFrequency: Double?

    /// Cached POTA activator spots for nearby frequency detection
    @State private var cachedPOTASpots: [POTASpot] = []
    @State private var spotsLastFetched: Date?

    /// License warning
    /// Dismissed warning messages (to avoid re-showing dismissed warnings)
    @State private var dismissedWarnings: Set<String> = []

    /// iPad sidebar: spot selected from sidebar, processed via .onChange
    @Binding private var externalSpotSelection: SpotSelection?

    /// Tour state for mini-tour
    private let tourState: TourState

    /// Callback when session ends with QSOs logged
    private let onSessionEnd: (() -> Void)?

    /// iPad sidebar: intercepts spot commands to switch sidebar tab
    private let onSpotCommand: ((SpotCommandAction) -> Void)?

    // MARK: - Compact Form Fields

    /// Unified field height for consistency
    private let fieldHeight: CGFloat = 36

    /// Deprecated: Use dismissedWarnings
    private var dismissedViolation: String? {
        get { dismissedWarnings.first }
        set {
            if let value = newValue {
                dismissedWarnings.insert(value)
            }
        }
    }

    private var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    /// QSOs to display — during roves, scoped to the viewed or current park stop
    private var displayQSOs: [QSO] {
        guard let session = sessionManager?.activeSession, session.isRove else {
            return sessionQSOs
        }
        let park = (viewingParkOverride ?? session.parkReference)?.uppercased()
        guard let park else {
            return sessionQSOs
        }
        return sessionQSOs.filter { $0.parkReference?.uppercased() == park }
    }

    /// Whether we're viewing a past rove stop (not the active one)
    private var isViewingPastStop: Bool {
        viewingParkOverride != nil
    }

    /// Whether the log button should be enabled
    private var canLog: Bool {
        guard sessionManager?.hasActiveSession == true else {
            return false
        }

        // Determine which callsign to validate
        let callsignToValidate: String
        if let qeResult = quickEntryResult {
            // In quick entry mode, use the parsed callsign
            callsignToValidate = qeResult.callsign
        } else {
            // Normal mode, use the input directly
            guard !callsignInput.isEmpty, callsignInput.count >= 3 else {
                return false
            }
            callsignToValidate = callsignInput.uppercased()
        }

        // Don't allow logging your own callsign
        let myCallsign = sessionManager?.activeSession?.myCallsign.uppercased() ?? ""
        if !myCallsign.isEmpty, callsignToValidate.uppercased() == myCallsign {
            return false
        }

        // Block POTA duplicates on same band (requirement 6a)
        if case .duplicateBand = potaDuplicateStatus {
            return false
        }

        return true
    }

    /// Whether the action button next to the callsign field is enabled
    private var actionButtonEnabled: Bool {
        detectedCommand != nil || canLog
    }

    /// Label for the action button next to the callsign field
    private var actionButtonLabel: String {
        if detectedCommand != nil {
            return "RUN"
        } else if editingQSO != nil {
            return "SAVE"
        }
        return "LOG"
    }

    /// Color for the action button next to the callsign field
    private var actionButtonColor: Color {
        if detectedCommand != nil {
            return .purple
        } else if editingQSO != nil {
            return .orange
        }
        return .green
    }

    /// Accessibility label for the action button
    private var actionButtonAccessibilityLabel: String {
        if detectedCommand != nil {
            return "Run command"
        } else if editingQSO != nil {
            return "Save callsign edit"
        }
        return "Log QSO"
    }

    /// Current mode (for RST default)
    private var currentMode: String {
        sessionManager?.activeSession?.mode ?? "CW"
    }

    /// Whether current mode uses 3-digit RST (CW/digital) vs 2-digit RS (phone)
    private var isCWMode: Bool {
        let mode = currentMode.uppercased()
        let threeDigitModes = [
            "CW", "RTTY", "PSK", "PSK31", "FT8", "FT4", "JT65", "JT9", "DATA", "DIGITAL",
        ]
        return threeDigitModes.contains(mode)
    }

    /// Default RST based on current mode
    private var defaultRST: String {
        isCWMode ? "599" : "59"
    }

    /// Detected command from input (if any)
    private var detectedCommand: LoggerCommand? {
        LoggerCommand.parse(callsignInput)
    }

    /// Whether to show the lookup error banner (when keyboard is not visible)
    private var shouldShowLookupError: Bool {
        lookupError != nil && lookupResult == nil && !callsignFieldFocused && !callsignInput.isEmpty
            && callsignInput.count >= 3 && detectedCommand == nil
    }

    /// Check if the current callsign input would be a duplicate in the current POTA session
    /// Uses cached value computed in onCallsignChanged to avoid expensive filtering on every render
    private var potaDuplicateStatus: POTACallsignStatus? {
        cachedPotaDuplicateStatus
    }

    /// Key for animating POTA status changes
    private var potaDuplicateStatusKey: String {
        switch potaDuplicateStatus {
        case .none: "none"
        case .firstContact: "first"
        case .newBand: "newband"
        case .duplicateBand: "dupe"
        }
    }

    /// Current frequency warning (if any) - convenience property
    private var currentWarning: FrequencyWarning? {
        computeCurrentWarning(spotCount: cachedPOTASpots.count, inputText: callsignInput)
    }

    /// Whether any bottom panel is currently open
    private var isAnyPanelOpen: Bool {
        showRBNPanel || showSolarPanel || showWeatherPanel || showMapPanel || showPOTAPanel
            || showP2PPanel || showWebSDRPanel
    }

    /// Deprecated: Use currentWarning instead
    private var currentViolation: BandPlanViolation? {
        guard let warning = currentWarning else {
            return nil
        }
        // Convert back for compatibility (if needed elsewhere)
        let violationType: BandPlanViolation.ViolationType =
            switch warning.type {
            case .noPrivileges: .noPrivileges
            case .wrongMode: .wrongMode
            case .outOfBand: .outOfBand
            default: .unusualFrequency
            }
        return BandPlanViolation(
            type: violationType,
            message: warning.message,
            suggestion: warning.suggestion
        )
    }

    // MARK: - QSO List

    /// Combined session log entries (QSOs + notes)
    private var sessionLogEntries: [SessionLogEntry] {
        let notes = sessionManager?.parseSessionNotes() ?? []
        return SessionLogEntry.combine(qsos: displayQSOs, notes: notes)
    }

    /// Callsign lookup display (card or error banner)
    @ViewBuilder
    private var callsignLookupDisplay: some View {
        if let info = lookupResult, !callsignFieldFocused || callsignInput.isEmpty {
            LoggerCallsignCard(info: info, previousQSOCount: previousQSOCount)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
        } else if let error = lookupError, shouldShowLookupError {
            CallsignLookupErrorBanner(error: error)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
        }
    }

    /// Panel overlays for RBN, Solar, Weather
    private var panelOverlays: some View {
        VStack {
            if showRBNPanel {
                SwipeToDismissPanel(isPresented: $showRBNPanel) {
                    RBNPanelView(
                        callsign: sessionManager?.activeSession?.myCallsign
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultCallsign")
                            ?? "UNKNOWN",
                        targetCallsign: rbnTargetCallsign
                    ) {
                        showRBNPanel = false
                        rbnTargetCallsign = nil
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showSolarPanel {
                SwipeToDismissPanel(isPresented: $showSolarPanel) {
                    SolarPanelView {
                        showSolarPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showWeatherPanel {
                SwipeToDismissPanel(isPresented: $showWeatherPanel) {
                    WeatherPanelView(
                        grid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
                    ) {
                        showWeatherPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showMapPanel {
                SwipeToDismissPanel(isPresented: $showMapPanel) {
                    SessionMapPanelView(
                        sessionQSOs: sessionQSOs,
                        myGrid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid"),
                        roveStops: sessionManager?.activeSession?.isRove == true
                            ? (sessionManager?.activeSession?.roveStops ?? [])
                            : []
                    ) {
                        showMapPanel = false
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showPOTAPanel {
                SwipeToDismissPanel(isPresented: $showPOTAPanel) {
                    POTASpotsView(
                        userCallsign: sessionManager?.activeSession?.myCallsign,
                        initialBand: sessionManager?.activeSession?.band,
                        initialMode: sessionManager?.activeSession?.mode,
                        onDismiss: { showPOTAPanel = false },
                        onSelectSpot: { spot in
                            handleSpotSelection(.pota(spot))
                            showPOTAPanel = false
                        }
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showP2PPanel {
                SwipeToDismissPanel(isPresented: $showP2PPanel) {
                    P2PPanelView(
                        userCallsign: sessionManager?.activeSession?.myCallsign ?? "",
                        userGrid: sessionManager?.activeSession?.myGrid
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid") ?? "",
                        initialBand: sessionManager?.activeSession?.band,
                        initialMode: sessionManager?.activeSession?.mode,
                        onDismiss: { showP2PPanel = false },
                        onSelectOpportunity: { opportunity in
                            handleSpotSelection(.p2p(opportunity))
                            showP2PPanel = false
                        }
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if showWebSDRPanel, let session = sessionManager {
                SwipeToDismissPanel(isPresented: $showWebSDRPanel) {
                    WebSDRPanelView(
                        webSDRSession: session.webSDRSession,
                        myGrid: session.activeSession?.myGrid,
                        frequencyMHz: session.activeSession?.frequency,
                        mode: session.activeSession?.mode,
                        loggingSessionId: session.activeSession?.id,
                        modelContext: modelContext,
                        onDismiss: { showWebSDRPanel = false }
                    )
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSolarPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showWeatherPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showMapPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showPOTAPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showP2PPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showWebSDRPanel)
    }

    /// Session header - shows active session info or "no session" prompt
    private var sessionHeader: some View {
        Group {
            if let session = sessionManager?.activeSession {
                activeSessionHeader(session)
            } else {
                noSessionHeader
            }
        }
    }

    private var noSessionHeader: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No Active Session")
                        .font(.headline)
                    Text(
                        activeSessions.isEmpty
                            ? "Start a session to begin logging"
                            : "Continue a session or start a new one"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showSessionSheet = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            if !activeSessions.isEmpty {
                activeSessionsList
            }
        }
        .confirmationDialog(
            "Finish Session",
            isPresented: Binding(
                get: { sessionToFinish != nil },
                set: {
                    if !$0 {
                        sessionToFinish = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Finish Session") {
                if let session = sessionToFinish {
                    sessionManager?.finishSession(session)
                    refreshActiveSessions()
                }
            }
            Button("Cancel", role: .cancel) {
                sessionToFinish = nil
            }
        } message: {
            if let session = sessionToFinish {
                Text(
                    "Finish \"\(session.displayTitle)\"? "
                        + "It will move to your Sessions list."
                )
            }
        }
        .alert(
            "Delete Session",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: {
                    if !$0 {
                        sessionToDelete = nil
                    }
                }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    sessionManager?.deleteSession(session)
                    refreshActiveSessions()
                }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            if let session = sessionToDelete {
                let count = activeSessionQSOCounts[session.id] ?? 0
                Text(
                    "Delete \"\(session.displayTitle)\" and hide "
                        + "\(count) QSO(s)? Hidden QSOs will not be "
                        + "synced or counted in statistics."
                )
            }
        }
    }

    private var activeSessionsList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Active Sessions")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(activeSessions, id: \.id) { session in
                ActiveSessionRow(
                    session: session,
                    qsoCount: activeSessionQSOCounts[session.id] ?? 0,
                    onContinue: {
                        sessionManager?.resumeSession(session)
                        refreshSessionQSOs()
                        refreshActiveSessions()
                    },
                    onPause: {
                        sessionManager?.pauseOtherSession(session)
                        refreshActiveSessions()
                    },
                    onFinish: {
                        sessionToFinish = session
                    },
                    onDelete: {
                        sessionToDelete = session
                    }
                )
            }
        }
        .padding()
    }

    // MARK: - Callsign Input

    private var callsignInputSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Text field with clear button
                HStack(spacing: 12) {
                    CallsignTextField(
                        "Callsign or command...",
                        text: $callsignInput,
                        isFocused: $callsignFieldFocused,
                        onSubmit: {
                            // Defer to next run loop to avoid UICollectionView crash
                            // when keyboard dismiss triggers List updates simultaneously
                            DispatchQueue.main.async {
                                handleInputSubmit()
                            }
                        },
                        onCommand: { command in
                            executeCommand(command)
                        }
                    )
                    .foregroundStyle(detectedCommand != nil ? .purple : .primary)
                    .onChange(of: callsignInput) { _, newValue in
                        onCallsignChanged(newValue)
                    }

                    Button {
                        callsignInput = ""
                        lookupResult = nil
                        lookupError = nil
                        quickEntryResult = nil
                        quickEntryTokens = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .opacity(callsignInput.isEmpty ? 0 : 1)
                    .disabled(callsignInput.isEmpty)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(detectedCommand != nil ? Color.purple : Color.clear, lineWidth: 2)
                )

                // Action button to the right of text field (always present)
                Button {
                    if let command = detectedCommand {
                        executeCommand(command)
                        callsignInput = ""
                    } else if quickEntryResult != nil {
                        logQuickEntry()
                    } else {
                        logQSO()
                    }
                } label: {
                    Text(actionButtonLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxHeight: .infinity)
                        .frame(width: 48)
                        .background(actionButtonColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!actionButtonEnabled)
                .opacity(actionButtonEnabled ? 1 : 0.4)
                .accessibilityLabel(actionButtonAccessibilityLabel)
            }

            // Command description badge
            if let command = detectedCommand {
                HStack {
                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(.purple)

                    Spacer()

                    Text("Press Return to execute")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Quick entry preview
            if !quickEntryTokens.isEmpty, detectedCommand == nil {
                QuickEntryPreview(tokens: quickEntryTokens)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Cancel spot button - shown when tuned away from session frequency
            if preSpotFrequency != nil {
                Button {
                    cancelSpot()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                        Text("Cancel Spot")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// Compact RST and State fields with inline More expansion
    private var compactFieldsSection: some View {
        VStack(spacing: 8) {
            // Row 1: State, RST Sent, RST Rcvd, More chevron
            HStack(spacing: 8) {
                // State field
                compactField(
                    label: "State",
                    placeholder: lookupResult?.state ?? "ST",
                    text: $theirState,
                    width: 50
                )

                // RST Sent
                compactField(label: "Sent", placeholder: defaultRST, text: $rstSent, width: 50)
                    .keyboardType(.numberPad)

                // RST Rcvd
                compactField(label: "Rcvd", placeholder: defaultRST, text: $rstReceived, width: 50)
                    .keyboardType(.numberPad)

                Spacer()

                // More fields chevron
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMoreFields.toggle()
                    }
                } label: {
                    Image(systemName: showMoreFields ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: fieldHeight)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Row 2: Expanded fields (Grid, Park, Operator, Notes)
            if showMoreFields {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        compactField(
                            label: "Grid",
                            placeholder: lookupResult?.grid ?? "",
                            text: $theirGrid
                        )
                        compactField(label: "Park", placeholder: "", text: $theirPark)
                    }
                    compactField(
                        label: "Operator",
                        placeholder: lookupResult?.displayName ?? "",
                        text: $operatorName,
                        isMonospaced: false
                    )
                    compactField(
                        label: "Notes",
                        placeholder: "",
                        text: $notes,
                        isMonospaced: false
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var qsoListSection: some View {
        // Only show QSO list when there's an active session
        if sessionManager?.hasActiveSession == true {
            VStack(alignment: .leading, spacing: 8) {
                if let viewingPark = viewingParkOverride {
                    viewingPastStopBanner(viewingPark)
                }

                HStack {
                    Text("Session Log")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(displayQSOs.count) QSOs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if sessionLogEntries.isEmpty {
                    Text("No entries yet")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    let entries = Array(sessionLogEntries.prefix(15))
                    List {
                        ForEach(entries) { entry in
                            switch entry {
                            case let .qso(qso):
                                LoggerQSORow(
                                    qso: qso,
                                    sessionQSOs: displayQSOs,
                                    isPOTASession: sessionManager?.activeSession?
                                        .activationType == .pota,
                                    isRove: sessionManager?.activeSession?.isRove
                                        ?? false,
                                    onQSODeleted: refreshSessionQSOs,
                                    onEditCallsign: { qsoToEdit in
                                        startEditingCallsign(qsoToEdit)
                                    }
                                )
                                .swipeActions(
                                    edge: .trailing,
                                    allowsFullSwipe: false
                                ) {
                                    Button(role: .destructive) {
                                        qsoToDelete = qso
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            case let .note(note):
                                LoggerNoteRow(note: note)
                            }
                        }
                        .listRowInsets(
                            EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.secondary.opacity(0.2))
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(entries.count) * 44)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .alert(
                "Delete QSO",
                isPresented: Binding(
                    get: { qsoToDelete != nil },
                    set: { if !$0 { qsoToDelete = nil } }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let qso = qsoToDelete {
                        qso.isHidden = true
                        try? modelContext.save()
                        refreshSessionQSOs()
                    }
                    qsoToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    qsoToDelete = nil
                }
            } message: {
                if let qso = qsoToDelete {
                    Text("Delete QSO with \(qso.callsign)?")
                }
            }
        }
    }

    private func viewingPastStopBanner(_ parkRef: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.blue)

            Text("Viewing \(ParkReference.split(parkRef).first ?? parkRef)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.blue)

            Spacer()

            Button {
                viewingParkOverride = nil
            } label: {
                Text("Back to Current")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .controlSize(.mini)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func webSDRMiniBadge(session: WebSDRSession) -> some View {
        Button {
            showWebSDRPanel = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                Text(formatWebSDRDuration(session.recordingDuration))
                    .font(.caption.monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    /// Reusable compact field with label above
    private func compactField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        width: CGFloat? = nil,
        isMonospaced: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(isMonospaced ? .subheadline.monospaced() : .subheadline)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .frame(height: fieldHeight)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: width)
        }
    }

    // MARK: - Session Header

    // swiftlint:disable:next function_body_length
    private func activeSessionHeader(_ session: LoggingSession) -> some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    editingTitle = session.customTitle ?? ""
                    showTitleEditSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(session.displayTitle)
                            .font(.headline.monospaced())
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Text(session.formattedDuration)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("\(displayQSOs.count) QSOs")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)

                Button {
                    callsignFieldFocused = false
                    showEndSessionConfirmation = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Session Actions",
                    isPresented: $showEndSessionConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Pause Session") {
                        sessionManager?.pauseSession()
                        refreshActiveSessions()
                    }
                    Button("End Session") {
                        handleEndSession()
                    }
                    Button("Delete Session", role: .destructive) {
                        showDeleteSessionSheet = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if session.frequency == nil, !sessionQSOs.isEmpty {
                        Text(
                            "Pause keeps the session active for later. "
                                + "End keeps your \(sessionQSOs.count) QSOs for sync. "
                                + "QSOs were logged without a frequency and will show as \"Unknown\" band. "
                                + "Delete hides them permanently."
                        )
                    } else {
                        Text(
                            "Pause keeps the session active for later. "
                                + "End keeps your \(sessionQSOs.count) QSOs for sync. "
                                + "Delete hides them permanently."
                        )
                    }
                }
            }

            // Rove bar or standard park + controls
            if session.isRove {
                RoveProgressBar(
                    stops: session.roveStops,
                    currentStopId: session.currentRoveStop?.id,
                    viewingPark: viewingParkOverride,
                    onNextStop: {
                        viewingParkOverride = nil
                        showNextStopSheet = true
                    },
                    onTapStop: { stop in
                        let stopPark = stop.parkReference
                        let activePark = session.parkReference
                        if stopPark == activePark {
                            viewingParkOverride = nil
                        } else {
                            viewingParkOverride = stopPark
                        }
                    }
                )
            }

            HStack {
                if session.activationType == .pota, !session.isRove {
                    parkHeaderView(session)
                }

                freqBandCapsule(session)

                Button {
                    showModeEditSheet = true
                } label: {
                    HStack(spacing: 2) {
                        Text(session.mode)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                equipmentCapsule(session)

                Spacer()

                // Spot comments button for POTA activations
                if session.activationType == .pota,
                   let parkRef = session.parkReference,
                   let commentsService = sessionManager?.spotCommentsService
                {
                    SpotCommentsButton(
                        comments: commentsService.comments,
                        newCount: commentsService.newCommentCount,
                        parkRef: parkRef,
                        onMarkRead: { commentsService.markAllRead() }
                    )
                }
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, session.isRove ? 8 : 16)
        .background(Color(.secondarySystemGroupedBackground))
    }

    /// Park header: tappable ref(s) that open the park editor directly
    @ViewBuilder
    private func parkHeaderView(_ session: LoggingSession) -> some View {
        let parkRef = session.parkReference
        Button {
            editingParkReference = parkRef ?? ""
            showParkEditSheet = true
        } label: {
            parkRefLabels(parkRef)
        }
        .buttonStyle(.plain)
    }

    /// Park reference label(s) — always shows ref numbers
    @ViewBuilder
    private func parkRefLabels(_ parkRef: String?) -> some View {
        if let parkRef, !parkRef.isEmpty {
            let parks = ParkReference.split(parkRef)
            HStack(spacing: 4) {
                ForEach(parks, id: \.self) { park in
                    Text(park)
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        } else {
            Text("No park")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// Merged frequency + band capsule (or "Set Freq" / "Band" when unset)
    @ViewBuilder
    private func freqBandCapsule(_ session: LoggingSession) -> some View {
        if let freq = session.frequency {
            bandCapsule(color: .blue) {
                Text(FrequencyFormatter.format(freq)).fontDesign(.monospaced)
                if let band = session.band {
                    Text(band)
                }
            }
        } else if session.activationType == .pota || session.activationType == .sota {
            bandCapsule(color: .orange) { Text("Set Freq") }
        } else {
            bandCapsule(color: .blue) { Text("Band").foregroundStyle(.secondary) }
        }
    }

    private func bandCapsule(
        color: Color, @ViewBuilder content: () -> some View
    ) -> some View {
        Button { showBandEditSheet = true } label: {
            HStack(spacing: 4) {
                content()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Equipment capsule — shows radio name, equipment count, or placeholder
    private func equipmentCapsule(_ session: LoggingSession) -> some View {
        Button {
            showRigEditSheet = true
        } label: {
            HStack(spacing: 2) {
                Text(equipmentCapsuleLabel(session))
                    .lineLimit(1)
                    .foregroundStyle(hasAnyEquipment(session) ? .primary : .secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func hasAnyEquipment(_ session: LoggingSession) -> Bool {
        [session.myRig, session.myAntenna, session.myKey, session.myMic]
            .contains { $0 != nil && !$0!.isEmpty }
    }

    private func equipmentCapsuleLabel(_ session: LoggingSession) -> String {
        if let rig = session.myRig, !rig.isEmpty {
            let extras = [session.myAntenna, session.myKey, session.myMic]
                .compactMap { $0 }.filter { !$0.isEmpty }.count
            return extras > 0 ? "\(rig) +\(extras)" : rig
        }
        if hasAnyEquipment(session) {
            return "Equipment"
        }
        return "Equip"
    }

    private func formatWebSDRDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Current frequency warning (if any) - includes license violations, activity warnings, and nearby spots
    /// The spotCount parameter forces SwiftUI to re-evaluate when cached spots change
    private func computeCurrentWarning(spotCount: Int, inputText: String) -> FrequencyWarning? {
        // Reference parameters to silence unused parameter warnings
        _ = spotCount
        _ = inputText

        guard let session = sessionManager?.activeSession else {
            return nil
        }

        // Check both the session frequency AND any frequency being typed as a command
        let freq: Double
        if case let .frequency(typedFreq) = detectedCommand {
            // User is typing a frequency command - check that frequency
            freq = typedFreq
        } else if let sessionFreq = session.frequency {
            // Use the session's current frequency
            freq = sessionFreq
        } else {
            return nil
        }

        var warnings = BandPlanService.validateFrequency(
            frequencyMHz: freq,
            mode: session.mode,
            license: userLicenseClass
        )

        // Check for nearby POTA spots
        if let nearbyWarning = checkNearbySpots(frequencyMHz: freq, mode: session.mode) {
            warnings.append(nearbyWarning)
            warnings.sort { $0.priority < $1.priority }
        }

        // Return the highest priority warning not dismissed
        return warnings.first { !dismissedWarnings.contains($0.message) }
    }

    /// Tolerance for nearby spot detection based on mode
    private func spotToleranceKHz(for mode: String) -> Double {
        let normalizedMode = mode.uppercased()
        // CW is narrower, SSB/phone is wider
        if normalizedMode == "CW" {
            return 2.0
        } else if ["SSB", "USB", "LSB", "PHONE", "AM"].contains(normalizedMode) {
            return 3.0
        } else {
            // Digital modes, etc.
            return 3.0
        }
    }

    /// Check if there are POTA spots near the current frequency
    private func checkNearbySpots(frequencyMHz: Double, mode: String) -> FrequencyWarning? {
        let tolerance = spotToleranceKHz(for: mode)
        let freqKHz = frequencyMHz * 1_000

        // Find spots within tolerance
        let nearbySpots = cachedPOTASpots.filter { spot in
            guard let spotFreqKHz = spot.frequencyKHz else {
                return false
            }
            let distanceKHz = abs(spotFreqKHz - freqKHz)
            return distanceKHz <= tolerance
        }

        guard
            let closestSpot = nearbySpots.min(by: { spot1, spot2 in
                guard let freq1 = spot1.frequencyKHz, let freq2 = spot2.frequencyKHz else {
                    return false
                }
                return abs(freq1 - freqKHz) < abs(freq2 - freqKHz)
            })
        else {
            return nil
        }

        // Don't warn about our own spots
        if let myCallsign = sessionManager?.activeSession?.myCallsign,
           closestSpot.activator.uppercased().hasPrefix(myCallsign.uppercased())
        {
            return nil
        }

        // Don't warn about the spot we're actively trying to work
        if !callsignInput.isEmpty,
           closestSpot.activator.uppercased() == callsignInput.uppercased()
        {
            return nil
        }

        return buildNearbySpotWarning(spot: closestSpot, freqKHz: freqKHz, mode: mode)
    }

    /// Build a FrequencyWarning with detailed context for a nearby spot
    private func buildNearbySpotWarning(
        spot: POTASpot,
        freqKHz: Double,
        mode: String
    ) -> FrequencyWarning? {
        guard let spotFreqKHz = spot.frequencyKHz else {
            return nil
        }
        let distanceKHz = abs(spotFreqKHz - freqKHz)
        let distanceStr =
            distanceKHz < 0.1 ? "same frequency" : String(format: "%.1f kHz away", distanceKHz)

        // Build context details
        var details: [String] = [distanceStr]

        // Mode comparison
        let spotMode = spot.mode.uppercased()
        let currentMode = mode.uppercased()
        if spotMode == currentMode {
            details.append("same mode (\(spot.mode))")
        } else {
            details.append("mode: \(spot.mode)")
        }

        // How fresh is the spot
        let timeAgo = spot.timeAgo
        if !timeAgo.isEmpty {
            details.append("spotted \(timeAgo)")
        }

        // Spotter info (RBN vs human)
        if spot.isAutomatedSpot {
            details.append("via RBN")
        } else {
            details.append("by \(spot.spotter)")
        }

        // Location
        if let location = spot.locationDesc, !location.isEmpty {
            details.append(location)
        }

        // Park info for the message
        let parkInfo =
            if let parkName = spot.parkName {
                "\(spot.reference) - \(parkName)"
            } else {
                spot.reference
            }

        return FrequencyWarning(
            type: .spotNearby,
            message: "\(spot.activator) at \(parkInfo)",
            suggestion: details.joined(separator: " • ")
        )
    }

    /// Cancel the current spot and restore session frequency
    private func cancelSpot() {
        if let freq = preSpotFrequency {
            _ = sessionManager?.updateFrequency(freq, isTuningToSpot: true)
            preSpotFrequency = nil
        }
        callsignInput = ""
        notes = ""
        lookupResult = nil
        lookupError = nil
        quickEntryResult = nil
        quickEntryTokens = []
        ToastManager.shared.info("Spot cancelled")
    }

    /// Refresh the session QSOs from SwiftData
    private func refreshSessionQSOs() {
        guard let session = sessionManager?.activeSession else {
            sessionQSOs = []
            return
        }

        let sessionId = session.id
        let predicate = #Predicate<QSO> { qso in
            qso.loggingSessionId == sessionId && !qso.isHidden
        }
        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            sessionQSOs = try modelContext.fetch(descriptor)
        } catch {
            sessionQSOs = []
        }
    }

    /// Refresh the list of active/paused sessions (for the no-session view)
    private func refreshActiveSessions() {
        guard let manager = sessionManager else {
            activeSessions = []
            activeSessionQSOCounts = [:]
            return
        }

        activeSessions = manager.fetchActiveSessions()

        // Load QSO counts for each active session
        var counts: [UUID: Int] = [:]
        for session in activeSessions {
            let sessionId = session.id
            var descriptor = FetchDescriptor<QSO>(
                predicate: #Predicate { $0.loggingSessionId == sessionId && !$0.isHidden }
            )
            descriptor.fetchLimit = 500
            counts[sessionId] = (try? modelContext.fetch(descriptor))?.count ?? 0
        }
        activeSessionQSOCounts = counts
    }

    /// Refresh POTA spots for nearby frequency detection
    private func refreshPOTASpots() async {
        // Only fetch if we have an active session
        guard sessionManager?.hasActiveSession == true else {
            return
        }

        // Throttle fetches to at most once per 30 seconds
        if let lastFetch = spotsLastFetched,
           Date().timeIntervalSince(lastFetch) < 30
        {
            return
        }

        do {
            let client = POTAClient(authService: POTAAuthService())
            let spots = try await client.fetchActiveSpots()
            await MainActor.run {
                cachedPOTASpots = spots
                spotsLastFetched = Date()
            }
        } catch {
            // Silently fail - spots are a nice-to-have
        }
    }

    /// Compute POTA duplicate status - called only when callsign changes
    private func computePotaDuplicateStatus() -> POTACallsignStatus? {
        // Don't show duplicate status when editing an existing QSO
        guard editingQSO == nil else {
            return nil
        }

        guard let session = sessionManager?.activeSession,
              session.activationType == .pota,
              !callsignInput.isEmpty,
              callsignInput.count >= 3,
              detectedCommand == nil
        else {
            return nil
        }

        // Use parsed callsign in quick entry mode, otherwise use raw input
        let callsign: String =
            if let qeResult = quickEntryResult {
                qeResult.callsign.uppercased()
            } else {
                callsignInput.uppercased()
            }
        let currentBand = session.band ?? "Unknown"

        // Find all QSOs with this callsign at the current park
        // During roves, each park is a separate activation — scope to current park
        let currentPark = session.parkReference?.uppercased()
        let matchingQSOs = displayQSOs.filter { qso in
            guard qso.callsign.uppercased() == callsign else {
                return false
            }
            if session.isRove {
                return qso.parkReference?.uppercased() == currentPark
            }
            return true
        }

        if matchingQSOs.isEmpty {
            return .firstContact
        }

        let previousBands = Set(matchingQSOs.map(\.band))

        if previousBands.contains(currentBand) {
            return .duplicateBand(band: currentBand)
        } else {
            return .newBand(previousBands: Array(previousBands).sorted())
        }
    }

    private func handleInputSubmit() {
        // Check if it's a command
        if let command = LoggerCommand.parse(callsignInput) {
            executeCommand(command)
            callsignInput = ""
            quickEntryResult = nil
            quickEntryTokens = []
            return
        }

        // Check for quick entry mode
        if quickEntryResult != nil, canLog {
            logQuickEntry()
            return
        }

        // Otherwise try to log normally
        if canLog {
            logQSO()
        }
    }

    private func executeCommand(_ command: LoggerCommand) {
        switch command {
        case let .frequency(freq): executeFrequencyCommand(freq)
        case let .mode(newMode): executeModeCommand(newMode)
        case let .spot(comment): Task { await postSpot(comment: comment) }
        case let .rbn(callsign): executeRBNCommand(callsign)
        case .p2p: executeP2PCommand()
        case .map: executeMapCommand()
        case let .note(text): executeNoteCommand(text)
        case .manual: executeManualCommand()
        case .checklist: FieldGuideLinker.openChecklists(radioName: sessionManager?.activeSession?.myRig)
        default: executeSheetCommand(command)
        }
    }

    private func executeSheetCommand(_ command: LoggerCommand) {
        switch command {
        case .pota:
            if sessionManager?.activeSession?.isRove == true {
                showNextStopSheet = true
            } else if let onSpotCommand {
                onSpotCommand(.showPOTA)
            } else {
                showPOTAPanel = true
            }
        case .solar: showSolarPanel = true
        case .weather: showWeatherPanel = true
        case .hidden: showHiddenQSOsSheet = true
        case .help: showHelpSheet = true
        case .websdr: showWebSDRPanel = true
        case .band: showBandEditSheet = true
        case .rig: showRigEditSheet = true
        default: break
        }
    }

    private func executeManualCommand() {
        guard let radio = sessionManager?.activeSession?.myRig,
              !radio.isEmpty
        else {
            ToastManager.shared.warning("No radio selected")
            return
        }
        guard FieldGuideLinker.hasManual(for: radio) else {
            ToastManager.shared.warning("No manual found for \(radio)")
            return
        }
        FieldGuideLinker.openManual(for: radio)
    }

    private func executeFrequencyCommand(_ freq: Double) {
        let result = sessionManager?.updateFrequency(freq)

        if result?.isFirstFrequencySet == true {
            let band = LoggingSession.bandForFrequency(freq)
            ToastManager.shared.success(
                "Frequency set to \(FrequencyFormatter.formatWithUnit(freq)) (\(band))"
            )
        } else {
            ToastManager.shared.commandExecuted(
                "FREQ", result: FrequencyFormatter.formatWithUnit(freq)
            )
        }

        // Auto-switch mode based on frequency segment (if enabled)
        if autoModeSwitch, let suggestedMode = result?.suggestedMode {
            _ = sessionManager?.updateMode(suggestedMode)
            ToastManager.shared.commandExecuted("MODE", result: "\(suggestedMode) (auto)")
        }

        // Prompt for QSY spot
        if result?.shouldPromptForSpot == true {
            qsyNewFrequency = freq
            showQSYSpotConfirmation = true
        }
    }

    private func executeModeCommand(_ newMode: String) {
        let shouldPromptForSpot = sessionManager?.updateMode(newMode) ?? false
        ToastManager.shared.commandExecuted("MODE", result: newMode)
        if shouldPromptForSpot {
            qsyNewFrequency = sessionManager?.activeSession?.frequency
            showQSYSpotConfirmation = true
        }
    }

    private func executeRBNCommand(_ callsign: String?) {
        if let onSpotCommand {
            onSpotCommand(.showRBN(callsign: callsign))
        } else {
            rbnTargetCallsign = callsign
            showRBNPanel = true
        }
    }

    private func executeP2PCommand() {
        // P2P only works during POTA activations
        guard sessionManager?.activeSession?.activationType == .pota else {
            ToastManager.shared.error("P2P is only available during POTA activations")
            return
        }

        // Check for user grid
        let myGrid =
            sessionManager?.activeSession?.myGrid
                ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")

        if myGrid == nil || myGrid?.isEmpty == true {
            ToastManager.shared.error("Set your grid in session settings to find P2P opportunities")
            return
        }

        if let onSpotCommand {
            onSpotCommand(.showP2P)
        } else {
            showP2PPanel = true
        }
    }

    /// Shared handler for spot selection from both panels and sidebar
    private func handleSpotSelection(_ selection: SpotSelection) {
        guard sessionManager?.activeSession != nil else {
            ToastManager.shared.warning("Start a session first")
            return
        }

        // Save session frequency before tuning to spot
        preSpotFrequency = sessionManager?.activeSession?.frequency

        switch selection {
        case let .pota(spot):
            callsignInput = spot.activator
            if let freqKHz = spot.frequencyKHz {
                let freqMHz = freqKHz / 1_000.0
                _ = sessionManager?.updateFrequency(freqMHz, isTuningToSpot: true)
            }
            var noteParts: [String] = [spot.reference]
            if let loc = spot.locationDesc {
                let state = loc.components(separatedBy: "-").last ?? loc
                noteParts.append(state)
            }
            if let parkName = spot.parkName {
                noteParts.append(parkName)
            }
            notes = noteParts.joined(separator: " - ")
            ToastManager.shared.info("Loaded \(spot.activator)")

        case let .rbn(spot):
            callsignInput = spot.callsign
            _ = sessionManager?.updateFrequency(spot.frequencyMHz, isTuningToSpot: true)
            ToastManager.shared.info("Loaded \(spot.callsign)")

        case let .p2p(opportunity):
            callsignInput = opportunity.callsign
            _ = sessionManager?.updateFrequency(
                opportunity.frequencyMHz, isTuningToSpot: true
            )
            var noteParts: [String] = ["P2P", opportunity.parkRef]
            if let loc = opportunity.locationDesc {
                let state = loc.components(separatedBy: "-").last ?? loc
                noteParts.append(state)
            }
            if let parkName = opportunity.parkName {
                noteParts.append(parkName)
            }
            notes = noteParts.joined(separator: " - ")
            ToastManager.shared.info(
                "P2P: \(opportunity.callsign) @ \(opportunity.parkRef)"
            )
        }
    }

    private func executeMapCommand() {
        // Check for missing grid configuration
        let myGrid =
            sessionManager?.activeSession?.myGrid
                ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")

        if myGrid == nil || myGrid?.isEmpty == true {
            ToastManager.shared.warning("Your grid is not set - no arcs will be shown")
        } else {
            checkSessionGridWarnings()
        }

        showMapPanel = true
    }

    private func checkSessionGridWarnings() {
        let qsosWithGrid = sessionQSOs.filter {
            $0.theirGrid != nil && !$0.theirGrid!.isEmpty
        }

        if !sessionQSOs.isEmpty, qsosWithGrid.isEmpty {
            ToastManager.shared.warning(
                "No QSOs have grids - add QRZ Callbook in Settings → Data"
            )
        } else if sessionQSOs.count > qsosWithGrid.count {
            let missing = sessionQSOs.count - qsosWithGrid.count
            ToastManager.shared.info(
                "\(missing) QSO\(missing == 1 ? "" : "s") missing grid"
            )
        }
    }

    private func executeNoteCommand(_ text: String) {
        sessionManager?.appendNote(text)
        ToastManager.shared.commandExecuted("NOTE", result: "Added to session log")
    }

    private func postSpot(comment: String? = nil) async {
        guard let session = sessionManager?.activeSession,
              session.activationType == .pota,
              let parkRef = session.parkReference,
              let freq = session.frequency
        else {
            ToastManager.shared.error("SPOT requires active POTA session with frequency")
            return
        }

        let callsign = session.myCallsign
        guard !callsign.isEmpty else {
            ToastManager.shared.error("No callsign configured")
            return
        }

        // Post spot for each park in multi-park activation
        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: POTAAuthService())
        var successCount = 0

        for park in parks {
            do {
                let success = try await potaClient.postSpot(
                    callsign: callsign,
                    reference: park,
                    frequency: freq * 1_000,
                    mode: session.mode,
                    comments: comment
                )
                if success {
                    successCount += 1
                }
            } catch {
                ToastManager.shared.error(
                    "Spot failed for \(park): \(error.localizedDescription)"
                )
            }
        }

        if successCount > 0 {
            let label = parks.count > 1
                ? "\(parks.count) parks" : parks.first ?? parkRef
            if let comment, !comment.isEmpty {
                ToastManager.shared.spotPosted(park: label, comment: comment)
            } else {
                ToastManager.shared.spotPosted(park: label)
            }
        }
    }

    /// Extract the primary callsign from a potentially prefixed/suffixed callsign
    /// e.g., "I/W6JSV/P" -> "W6JSV", "VE3/W6JSV" -> "W6JSV", "W6JSV/M" -> "W6JSV"
    private func extractPrimaryCallsign(_ callsign: String) -> String {
        let parts = callsign.split(separator: "/").map(String.init)

        guard parts.count > 1 else {
            return callsign
        }

        // Common suffixes that indicate the primary is before them
        let knownSuffixes = Set(["P", "M", "MM", "AM", "QRP", "R", "A", "B"])

        // For 2 parts: check if second part is a known suffix or very short (1-2 chars)
        // If so, first part is primary. Otherwise, longer part is likely primary.
        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]

            // If second is a known suffix, first is primary
            if knownSuffixes.contains(second.uppercased()) {
                return first
            }

            // If second is very short (1-2 chars), it's likely a suffix
            if second.count <= 2 {
                return first
            }

            // If first is very short (1-2 chars), it's likely a country prefix
            if first.count <= 2 {
                return second
            }

            // Otherwise, return the longer one (more likely to be the full callsign)
            return first.count >= second.count ? first : second
        }

        // For 3 parts (prefix/call/suffix): middle is primary
        if parts.count == 3 {
            return parts[1]
        }

        // Fallback: return the longest part
        return parts.max(by: { $0.count < $1.count }) ?? callsign
    }

    /// Parse quick entry and determine callsign for lookup
    private func resolveCallsignForLookup(_ callsign: String) -> String {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        if callsign.contains(" ") {
            quickEntryResult = QuickEntryParser.parse(callsign)
            quickEntryTokens = QuickEntryParser.parseTokens(callsign)
        } else {
            quickEntryResult = nil
            quickEntryTokens = []
        }
        return quickEntryResult?.callsign ?? trimmed
    }

    private func onCallsignChanged(_ callsign: String) {
        lookupTask?.cancel()

        // Update cached POTA duplicate status (avoids expensive computation on every render)
        cachedPotaDuplicateStatus = computePotaDuplicateStatus()

        let callsignForLookup = resolveCallsignForLookup(callsign)

        // Don't lookup if too short or looks like a command
        // When input is empty, preserve lookupResult so the QRZ card stays visible
        // after logging (card persists until user starts typing next callsign)
        guard callsignForLookup.count >= 3,
              LoggerCommand.parse(callsignForLookup) == nil
        else {
            if !callsignForLookup.isEmpty {
                lookupResult = nil
            }
            lookupError = nil
            previousQSOCount = 0
            return
        }

        // Extract the primary callsign for lookup (strip prefix/suffix)
        let primaryCallsign = extractPrimaryCallsign(callsignForLookup)

        // Don't lookup if primary is too short
        guard primaryCallsign.count >= 3 else {
            lookupResult = nil
            lookupError = nil
            previousQSOCount = 0
            return
        }

        let service = CallsignLookupService(modelContext: modelContext)
        lookupTask = Task {
            // Small delay to avoid excessive lookups while typing
            try? await Task.sleep(for: .milliseconds(300))

            guard !Task.isCancelled else {
                return
            }

            let result = await service.lookupWithResult(primaryCallsign)
            let count = fetchPreviousQSOCount(for: primaryCallsign)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                lookupResult = result.info
                previousQSOCount = count
                // Only show actionable errors (not "not found" which is normal)
                if result.error == .notFound {
                    lookupError = nil
                } else {
                    lookupError = result.error
                }
            }
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    private func fetchPreviousQSOCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.fetchCount(
                FetchDescriptor<QSO>(
                    predicate: #Predicate<QSO> { qso in
                        qso.callsign == upper
                            && !qso.isHidden
                            && qso.mode != "WEATHER"
                            && qso.mode != "SOLAR"
                            && qso.mode != "NOTE"
                    }
                )
            )) ?? 0
    }

    private func logQSO() {
        guard canLog else {
            return
        }

        // Check if we're editing an existing QSO
        if let qsoToUpdate = editingQSO {
            updateExistingQSOCallsign(qsoToUpdate)
            return
        }

        // Build field values with fallback: form > lookup
        let gridToUse = theirGrid.nonEmpty ?? lookupResult?.grid
        let stateToUse = theirState.nonEmpty ?? lookupResult?.state

        _ = sessionManager?.logQSO(
            callsign: callsignInput,
            rstSent: rstSent.nonEmpty ?? defaultRST,
            rstReceived: rstReceived.nonEmpty ?? defaultRST,
            theirGrid: gridToUse,
            theirParkReference: theirPark.nonEmpty,
            notes: notes.nonEmpty,
            name: lookupResult?.name,
            operatorName: operatorName.nonEmpty ?? lookupResult?.displayName,
            state: stateToUse,
            country: lookupResult?.country,
            qth: lookupResult?.qth,
            theirLicenseClass: lookupResult?.licenseClass
        )

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        viewingParkOverride = nil
        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()
    }

    /// Start editing an existing QSO's callsign
    private func startEditingCallsign(_ qso: QSO) {
        editingQSO = qso
        callsignInput = qso.callsign
        callsignFieldFocused = true
        ToastManager.shared.info("Editing callsign - tap Update to save")
    }

    /// Cancel editing and clear the form
    private func cancelEditingCallsign() {
        editingQSO = nil
        resetFormAfterLog()
    }

    /// Update only the callsign of an existing QSO (preserves timestamp and notes)
    private func updateExistingQSOCallsign(_ qso: QSO) {
        let newCallsign = callsignInput.trimmingCharacters(in: .whitespaces).uppercased()

        guard !newCallsign.isEmpty else {
            ToastManager.shared.error("Callsign cannot be empty")
            return
        }

        qso.callsign = newCallsign

        // Update with new callsign's metadata from lookup (if available)
        if let info = lookupResult {
            qso.name = info.name
            qso.theirGrid = info.grid
            qso.state = info.state
            qso.country = info.country
            qso.qth = info.qth
            qso.theirLicenseClass = info.licenseClass
        } else {
            // No lookup result yet - clear metadata and fetch async
            qso.name = nil
            qso.theirGrid = nil
            qso.state = nil
            qso.country = nil
            qso.qth = nil
            qso.theirLicenseClass = nil

            // Trigger async lookup to populate metadata
            Task {
                await fetchAndUpdateQSOMetadata(qso, callsign: newCallsign)
            }
        }

        try? modelContext.save()

        refreshSessionQSOs()
        resetFormAfterLog()
        editingQSO = nil
        ToastManager.shared.success("Callsign updated")
    }

    /// Fetch callsign metadata and update QSO (called when editing without existing lookup)
    private func fetchAndUpdateQSOMetadata(_ qso: QSO, callsign: String) async {
        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(callsign) else {
            return
        }

        await MainActor.run {
            qso.name = info.name
            qso.theirGrid = info.grid
            qso.state = info.state
            qso.country = info.country
            qso.qth = info.qth
            qso.theirLicenseClass = info.licenseClass
            try? modelContext.save()
            refreshSessionQSOs()
        }
    }

    /// Log a QSO using quick entry data
    private func logQuickEntry() {
        guard let qeResult = quickEntryResult, canLog else {
            return
        }

        // Build field values with fallback chain: quick entry > form > lookup
        let gridToUse = qeResult.theirGrid.nonEmpty ?? theirGrid.nonEmpty ?? lookupResult?.grid
        let stateToUse = qeResult.state.nonEmpty ?? theirState.nonEmpty ?? lookupResult?.state
        let parkToUse = qeResult.theirPark.nonEmpty ?? theirPark.nonEmpty
        let notesToUse = qeResult.notes.nonEmpty ?? notes.nonEmpty

        _ = sessionManager?.logQSO(
            callsign: qeResult.callsign,
            rstSent: qeResult.rstSent ?? rstSent.nonEmpty ?? defaultRST,
            rstReceived: qeResult.rstReceived ?? rstReceived.nonEmpty ?? defaultRST,
            theirGrid: gridToUse,
            theirParkReference: parkToUse,
            notes: notesToUse,
            name: lookupResult?.name,
            operatorName: operatorName.nonEmpty ?? lookupResult?.displayName,
            state: stateToUse,
            country: lookupResult?.country,
            qth: lookupResult?.qth,
            theirLicenseClass: lookupResult?.licenseClass
        )

        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()
    }

    /// Restore frequency if we tuned away for a spot
    private func restorePreSpotFrequency() {
        if let freq = preSpotFrequency {
            _ = sessionManager?.updateFrequency(freq, isTuningToSpot: true)
            preSpotFrequency = nil
        }
    }

    /// Reset form fields without animations after logging
    private func resetFormAfterLog() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            callsignInput = ""
            // Keep lookupResult — card persists until user starts typing next callsign
            lookupError = nil
            previousQSOCount = 0
            cachedPotaDuplicateStatus = nil
            viewingParkOverride = nil
            quickEntryResult = nil
            quickEntryTokens = []
            theirGrid = ""
            theirState = ""
            theirPark = ""
            notes = ""
            operatorName = ""
            rstSent = ""
            rstReceived = ""
            editingQSO = nil
        }
        callsignFieldFocused = true
    }

    private func lookupParkName(_ reference: String?) -> String? {
        guard let ref = reference else {
            return nil
        }
        // For multi-park, look up the first park only
        let firstPark = ParkReference.split(ref).first ?? ref
        return POTAParksCache.shared.nameSync(for: firstPark)
    }

    // MARK: - Session End Handling

    /// Handle end session action - checks for POTA upload prompt first
    private func handleEndSession() {
        guard let session = sessionManager?.activeSession else {
            completeSessionEnd()
            return
        }

        // Check if this is a POTA session with unuploaded QSOs
        if session.activationType == .pota,
           !potaUploadPromptDisabled,
           let parkRef = session.parkReference
        {
            // Find QSOs that need upload to POTA
            let qsosNeedingUpload = sessionQSOs.filter { $0.needsUpload(to: .pota) }

            if !qsosNeedingUpload.isEmpty {
                // Store data for the prompt sheet
                pendingSessionEndParkRef = parkRef
                pendingSessionEndParkName = lookupParkName(parkRef)
                pendingSessionEndQSOCount = qsosNeedingUpload.count
                pendingSessionEndQSOs = qsosNeedingUpload

                // Check maintenance window status
                pendingSessionEndInMaintenance = POTAClient.isInMaintenanceWindow()
                pendingSessionEndMaintenanceRemaining =
                    pendingSessionEndInMaintenance
                        ? POTAClient.formatMaintenanceTimeRemaining() : nil

                // Show the upload prompt (with maintenance warning if applicable)
                showPOTAUploadPrompt = true
                return
            }
        }

        // No POTA upload needed, end session directly
        completeSessionEnd()
    }

    /// Complete the session end after any POTA upload prompt handling
    private func completeSessionEnd() {
        let hadQSOs = !sessionQSOs.isEmpty
        sessionManager?.endSession()
        if hadQSOs {
            onSessionEnd?()
        }

        // Clear pending state
        pendingSessionEndParkRef = nil
        pendingSessionEndParkName = nil
        pendingSessionEndQSOCount = 0
        pendingSessionEndQSOs = []
        pendingSessionEndInMaintenance = false
        pendingSessionEndMaintenanceRemaining = nil
    }

    /// Upload pending POTA QSOs from the upload prompt (supports multi-park)
    private func uploadPendingPOTAQSOs() async -> Bool {
        guard let parkRef = pendingSessionEndParkRef,
              !pendingSessionEndQSOs.isEmpty
        else {
            return false
        }

        let parks = ParkReference.split(parkRef)
        let potaClient = POTAClient(authService: POTAAuthService())
        var allSucceeded = true

        for park in parks {
            do {
                let result = try await potaClient.uploadActivationWithRecording(
                    parkReference: park,
                    qsos: pendingSessionEndQSOs,
                    modelContext: modelContext
                )

                if result.success {
                    for qso in pendingSessionEndQSOs {
                        qso.markSubmittedToPark(park, context: modelContext)
                    }
                    try? modelContext.save()
                } else {
                    allSucceeded = false
                    SyncDebugLog.shared.warning(
                        "POTA upload for \(park): result.success=false, "
                            + "message=\(result.message ?? "nil")",
                        service: .pota
                    )
                }
            } catch {
                allSucceeded = false
                SyncDebugLog.shared.error(
                    "POTA upload for \(park) failed: \(error.localizedDescription)",
                    service: .pota
                )
            }
        }

        return allSucceeded
    }
}

// MARK: - POTACallsignStatus

/// Status of a callsign within a POTA session
enum POTACallsignStatus {
    /// First contact with this callsign
    case firstContact
    /// Contact on a new band (valid for POTA)
    case newBand(previousBands: [String])
    /// Duplicate on the same band (not valid for POTA)
    case duplicateBand(band: String)
}

// MARK: - LoggerNoteRow

/// A row displaying a session note
struct LoggerNoteRow: View {
    let note: SessionNoteEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(note.displayTime)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.purple)

            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

// MARK: - LoggerQSORow

/// A row displaying a logged QSO
struct LoggerQSORow: View {
    // MARK: Internal

    let qso: QSO
    /// All QSOs in the current session (for duplicate detection)
    var sessionQSOs: [QSO] = []
    /// Whether this is a POTA session
    var isPOTASession: Bool = false
    /// Whether this session is a rove (multiple parks)
    var isRove: Bool = false
    /// Callback when QSO is deleted (hidden)
    var onQSODeleted: (() -> Void)?
    /// Callback when callsign is tapped for quick edit
    var onEditCallsign: ((QSO) -> Void)?

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditSheet) {
            QSOEditSheet(qso: qso, onDelete: onQSODeleted)
        }
        .onAppear {
            // Use QSO's stored data if available (from pre-fetch during logging)
            if callsignInfo == nil, qso.name != nil || qso.theirGrid != nil {
                callsignInfo = CallsignInfo(
                    callsign: qso.callsign,
                    name: qso.name,
                    qth: qso.qth,
                    state: qso.state,
                    country: qso.country,
                    grid: qso.theirGrid,
                    licenseClass: qso.theirLicenseClass,
                    source: .qrz
                )
            }
        }
        .task(id: qso.id) {
            await lookupCallsign()
            totalContactCount = fetchTotalContactCount(for: qso.callsign)
        }
    }

    // MARK: Private

    /// Shared UTC time formatter - created once, reused for all rows
    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var callsignInfo: CallsignInfo?
    @State private var showEditSheet = false
    @State private var totalContactCount: Int = 0

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    /// Display name from callsign lookup (prefers nickname), fallback to QSO stored name
    private var displayName: String? {
        callsignInfo?.displayName ?? qso.name?.capitalized
    }

    /// Display location from QSO or callsign lookup
    private var displayLocation: String? {
        if let state = qso.state {
            return state
        }
        if let info = callsignInfo {
            let parts = [info.state, info.country].compactMap { $0 }
            if !parts.isEmpty {
                return parts.joined(separator: ", ")
            }
        }
        return nil
    }

    /// Determine the POTA status of this QSO's callsign
    private var potaStatus: POTACallsignStatus {
        let callsign = qso.callsign.uppercased()
        let thisBand = qso.band

        // Find all previous QSOs with this callsign (before this one)
        // During roves, scope to the same park — each park is a separate activation
        let qsoPark = qso.parkReference?.uppercased()
        let previousQSOs = sessionQSOs.filter { other in
            guard other.callsign.uppercased() == callsign,
                  other.timestamp < qso.timestamp
            else {
                return false
            }
            if isRove {
                return other.parkReference?.uppercased() == qsoPark
            }
            return true
        }

        if previousQSOs.isEmpty {
            return .firstContact
        }

        let previousBands = Set(previousQSOs.map(\.band))

        if previousBands.contains(thisBand) {
            return .duplicateBand(band: thisBand)
        } else {
            return .newBand(previousBands: Array(previousBands).sorted())
        }
    }

    /// Color for the callsign based on POTA status
    private var callsignColor: Color {
        guard isPOTASession else {
            return .green
        }

        switch potaStatus {
        case .firstContact:
            return .green
        case .newBand:
            return .blue
        case .duplicateBand:
            return .orange
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Text(Self.utcTimeFormatter.string(from: qso.timestamp))
                .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: isRegularWidth ? 60 : 50, alignment: .leading)

            HStack(spacing: 4) {
                // Callsign is tappable for quick edit
                Button {
                    onEditCallsign?(qso)
                } label: {
                    Text(qso.callsign)
                        .font(
                            isRegularWidth
                                ? .headline.weight(.semibold).monospaced()
                                : .subheadline.weight(.semibold).monospaced()
                        )
                        .foregroundStyle(callsignColor)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)

                if let emoji = callsignInfo?.combinedEmoji {
                    Text(emoji)
                        .font(.caption)
                }

                // Show POTA status badges
                if isPOTASession {
                    potaStatusBadge
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let name = displayName {
                        Text(name)
                            .font(isRegularWidth ? .subheadline : .caption)
                            .lineLimit(1)
                    }
                    if totalContactCount > 1 {
                        Text("×\(totalContactCount)")
                            .font(isRegularWidth ? .caption.weight(.medium) : .caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let note = callsignInfo?.note, !note.isEmpty {
                    Text(note)
                        .font(isRegularWidth ? .caption : .caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                } else if let location = displayLocation {
                    Text(location)
                        .font(isRegularWidth ? .caption : .caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Frequency or band
                if let freq = qso.frequency {
                    Text(FrequencyFormatter.format(freq))
                        .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(qso.band)
                        .font(isRegularWidth ? .subheadline.monospaced() : .caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("\(qso.rstSent ?? "599")/\(qso.rstReceived ?? "599")")
                    .font(isRegularWidth ? .caption.monospaced() : .caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, isRegularWidth ? 10 : 6)
    }

    /// Badge showing POTA status
    @ViewBuilder
    private var potaStatusBadge: some View {
        switch potaStatus {
        case .firstContact:
            EmptyView()
        case let .newBand(previousBands):
            Text("NEW BAND")
                .font(isRegularWidth ? .caption.weight(.bold) : .caption2.weight(.bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help("Previously worked on: \(previousBands.joined(separator: ", "))")
        case .duplicateBand:
            Text("DUPE")
                .font(isRegularWidth ? .caption.weight(.bold) : .caption2.weight(.bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func lookupCallsign() async {
        // Skip if we already have callsign info from logging or previous lookup
        guard callsignInfo == nil,
              qso.name == nil, qso.theirGrid == nil
        else {
            return
        }

        let service = CallsignLookupService(modelContext: modelContext)
        guard let info = await service.lookup(qso.callsign) else {
            return
        }

        callsignInfo = info

        // Update QSO with enriched data (background fill-in for fast logging)
        var updated = false
        if qso.name == nil, let name = info.name {
            qso.name = name
            updated = true
        }
        if qso.theirGrid == nil, let grid = info.grid {
            qso.theirGrid = grid
            updated = true
        }
        if qso.state == nil, let state = info.state {
            qso.state = state
            updated = true
        }
        if qso.country == nil, let country = info.country {
            qso.country = country
            updated = true
        }
        if qso.qth == nil, let qth = info.qth {
            qso.qth = qth
            updated = true
        }
        if qso.theirLicenseClass == nil, let licenseClass = info.licenseClass {
            qso.theirLicenseClass = licenseClass
            updated = true
        }

        if updated {
            try? modelContext.save()
        }
    }

    /// Count all-time QSOs with a callsign (excludes hidden and metadata modes)
    private func fetchTotalContactCount(for callsign: String) -> Int {
        let upper = callsign.uppercased()
        return
            (try? modelContext.fetchCount(
                FetchDescriptor<QSO>(
                    predicate: #Predicate<QSO> { qso in
                        qso.callsign == upper
                            && !qso.isHidden
                            && qso.mode != "WEATHER"
                            && qso.mode != "SOLAR"
                            && qso.mode != "NOTE"
                    }
                )
            )) ?? 0
    }
}

// MARK: - QSOEditSheet

/// Sheet for editing an existing QSO
struct QSOEditSheet: View {
    // MARK: Internal

    let qso: QSO
    /// Callback when QSO is deleted (hidden)
    var onDelete: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    HStack {
                        Text("Callsign")
                        Spacer()
                        TextField("Callsign", text: $callsign)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    DatePicker(
                        "Time",
                        selection: $timestamp,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Signal Reports") {
                    HStack {
                        Text("Sent")
                        Spacer()
                        TextField("599", text: $rstSent)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Received")
                        Spacer()
                        TextField("599", text: $rstReceived)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                    }
                }

                Section("Station Info") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $name)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Grid")
                        Spacer()
                        TextField("Grid", text: $grid)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Their Park")
                        Spacer()
                        TextField("K-1234", text: $theirPark)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .frame(width: 100)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                if qso.stationProfileName != nil || qso.myGrid != nil {
                    Section("My Station") {
                        if let profileName = qso.stationProfileName {
                            HStack {
                                Text("Station")
                                Spacer()
                                Text(profileName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let myGrid = qso.myGrid {
                            HStack {
                                Text("Grid")
                                Spacer()
                                Text(myGrid)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete QSO")
                            Spacer()
                        }
                    }
                    .confirmationDialog(
                        "Delete QSO?",
                        isPresented: $showDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            hideQSO()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "This QSO will be hidden and won't sync to any services."
                        )
                    }
                }
            }
            .navigationTitle("Edit QSO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadQSOData()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var callsign = ""
    @State private var timestamp = Date()
    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var name = ""
    @State private var grid = ""
    @State private var theirPark = ""
    @State private var notes = ""
    @State private var showDeleteConfirmation = false

    private func loadQSOData() {
        callsign = qso.callsign
        timestamp = qso.timestamp
        rstSent = qso.rstSent ?? "599"
        rstReceived = qso.rstReceived ?? "599"
        name = qso.name ?? ""
        grid = qso.theirGrid ?? ""
        theirPark = qso.theirParkReference ?? ""
        notes = qso.notes ?? ""
    }

    private func saveChanges() {
        qso.callsign = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        qso.timestamp = timestamp
        qso.rstSent = rstSent.isEmpty ? nil : rstSent
        qso.rstReceived = rstReceived.isEmpty ? nil : rstReceived
        qso.name = name.isEmpty ? nil : name
        qso.theirGrid = grid.isEmpty ? nil : grid
        qso.theirParkReference = theirPark.isEmpty ? nil : theirPark
        qso.notes = notes.isEmpty ? nil : notes
        try? modelContext.save()
    }

    private func hideQSO() {
        qso.isHidden = true
        try? modelContext.save()
        dismiss()
        onDelete?()
    }
}

// MARK: - POTAStatusBanner

/// Banner showing POTA duplicate or new band status before logging
struct POTAStatusBanner: View {
    let status: POTACallsignStatus

    var body: some View {
        switch status {
        case .firstContact:
            EmptyView()

        case let .newBand(previousBands):
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Band!")
                        .font(.subheadline.weight(.semibold))
                    Text("Previously worked on \(previousBands.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case let .duplicateBand(band):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate on \(band)")
                        .font(.subheadline.weight(.semibold))
                    Text("Already worked this callsign on this band")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - SwipeToDismissPanel

/// Wrapper that adds swipe-to-dismiss gesture to a panel
struct SwipeToDismissPanel<Content: View>: View {
    // MARK: Internal

    @Binding var isPresented: Bool

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging down
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Dismiss if dragged more than 80 points or with velocity
                        if value.translation.height > 80
                            || value.predictedEndTranslation.height > 150
                        {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }
                        // Reset offset
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
            )
    }

    // MARK: Private

    @State private var dragOffset: CGFloat = 0
}

// MARK: - SessionTitleEditSheet

/// Sheet for editing the session title
struct SessionTitleEditSheet: View {
    // MARK: Internal

    @Binding var title: String

    let defaultTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Session title", text: $title)
                    .font(.title3)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)

                Text("Leave empty to use default: \(defaultTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title)
                    }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }

    // MARK: Private

    @FocusState private var isFocused: Bool
}

// MARK: - SessionParkEditSheet

/// Sheet for editing parks on an active POTA session (supports n-fer)
struct SessionParkEditSheet: View {
    @Binding var parkReference: String

    let userGrid: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ParkEntryField(
                        parkReference: $parkReference,
                        label: "Parks",
                        placeholder: "K-1234",
                        userGrid: userGrid,
                        defaultCountry: "US"
                    )
                } footer: {
                    Text("Add or remove parks for this n-fer activation")
                }
            }
            .navigationTitle("Edit Parks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(parkReference)
                    }
                    .disabled(parkReference.isEmpty)
                }
            }
        }
    }
}

// MARK: - HiddenQSOsSheet

/// Sheet showing hidden (deleted) QSOs for the current session with option to restore
struct HiddenQSOsSheet: View {
    // MARK: Internal

    let sessionId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if hiddenQSOs.isEmpty {
                    ContentUnavailableView(
                        "No Deleted QSOs",
                        systemImage: "checkmark.circle",
                        description: Text("All QSOs in this session are visible")
                    )
                } else {
                    List {
                        ForEach(hiddenQSOs) { qso in
                            HiddenQSORow(
                                qso: qso,
                                onRestore: {
                                    restoreQSO(qso)
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Deleted QSOs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                fetchHiddenQSOs()
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Hidden QSOs for the current session (manually fetched to avoid full table scan)
    @State private var hiddenQSOs: [QSO] = []

    private func fetchHiddenQSOs() {
        guard let sessionId else {
            hiddenQSOs = []
            return
        }

        let predicate = #Predicate<QSO> { qso in
            qso.isHidden && qso.loggingSessionId == sessionId
        }

        let descriptor = FetchDescriptor<QSO>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            hiddenQSOs = try modelContext.fetch(descriptor)
        } catch {
            hiddenQSOs = []
        }
    }

    private func restoreQSO(_ qso: QSO) {
        qso.isHidden = false
        try? modelContext.save()
        // Refresh the list after restoring
        fetchHiddenQSOs()
    }
}

// MARK: - HiddenQSORow

/// A row displaying a hidden QSO with restore button
struct HiddenQSORow: View {
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
}

// MARK: - DeleteSessionConfirmationSheet

/// Sheet requiring user to type "delete" to confirm session deletion
struct DeleteSessionConfirmationSheet: View {
    // MARK: Internal

    let qsoCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.red)

                VStack(spacing: 8) {
                    Text("Delete Session?")
                        .font(.title2.weight(.bold))

                    Text(
                        "This will hide \(qsoCount) QSO\(qsoCount == 1 ? "" : "s") permanently. "
                            + "They will not sync to any services."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type \"delete\" to confirm:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("", text: $confirmationText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isConfirmationValid ? Color.red : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .focused($isTextFieldFocused)
                }

                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        onConfirm()
                    } label: {
                        Text("Delete Session")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(!isConfirmationValid)

                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }

                Spacer()
            }
            .padding()
            .navigationBarHidden(true)
            .onAppear {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Private

    @State private var confirmationText = ""
    @FocusState private var isTextFieldFocused: Bool

    private var isConfirmationValid: Bool {
        confirmationText.lowercased() == "delete"
    }
}

// MARK: - SessionBandEditSheet

/// Sheet for selecting a new band/frequency during an active session.
/// Shows live POTA/RBN spot data with recommended clear frequencies.
struct SessionBandEditSheet: View {
    // MARK: Internal

    let currentFrequency: Double?
    let currentMode: String
    let onSelectFrequency: (Double) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                FrequencyBandView(
                    selectedMode: currentMode,
                    frequency: $frequencyText,
                    detailBand: $bandDetail
                )
            }
            .navigationTitle("Pick Frequency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .sheet(item: $bandDetail) { band in
                BandActivitySheet(
                    suggestion: band,
                    frequency: $frequencyText
                )
            }
            .onChange(of: frequencyText) { _, newValue in
                guard hasInitialized else {
                    return
                }
                if let freq = FrequencyFormatter.parse(newValue) {
                    onSelectFrequency(freq)
                }
            }
            .task {
                if let freq = currentFrequency {
                    frequencyText = FrequencyFormatter.format(freq)
                }
                hasInitialized = true
            }
        }
    }

    // MARK: Private

    @State private var frequencyText = ""
    @State private var bandDetail: BandSuggestion?
    @State private var hasInitialized = false
}

// MARK: - SessionModeEditSheet

/// Sheet for selecting a new mode during an active session
struct SessionModeEditSheet: View {
    // MARK: Internal

    let currentMode: String
    let onSelectMode: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(modeOptions, id: \.self) { mode in
                        Button {
                            onSelectMode(mode)
                        } label: {
                            HStack {
                                Text(mode)
                                    .font(.headline)

                                Spacer()

                                if currentMode.uppercased() == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Select Mode")
                }
            }
            .navigationTitle("Change Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }

    // MARK: Private

    private let modeOptions = ["CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM"]
}

// MARK: - Preview

#Preview {
    LoggerView(tourState: TourState())
        .modelContainer(
            for: [QSO.self, LoggingSession.self],
            inMemory: true
        )
}
