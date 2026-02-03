// swiftlint:disable file_length type_body_length
import SwiftData
import SwiftUI

// MARK: - LoggerView

/// Main logging view for QSO entry
struct LoggerView: View {
    // MARK: Lifecycle

    init(tourState: TourState, onSessionEnd: (() -> Void)? = nil) {
        self.tourState = tourState
        self.onSessionEnd = onSessionEnd
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    sessionHeader

                    // Spot monitoring summary (always visible when session active)
                    if let manager = sessionManager {
                        SpotSummaryView(monitoringService: manager.spotMonitoringService)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Frequency warning banner (license violations + activity warnings)
                    if let warning = currentWarning {
                        FrequencyWarningBanner(warning: warning) {
                            dismissedWarning = warning.message
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

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

                                logButtonSection
                            }

                            qsoListSection
                        }
                        .padding()
                    }
                }
            }
            .navigationBarHidden(true)
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
                .presentationDetents([.height(280)])
            }
            .sheet(isPresented: $showHiddenQSOsSheet) {
                HiddenQSOsSheet(sessionId: sessionManager?.activeSession?.id)
            }
            .onAppear {
                if sessionManager == nil {
                    sessionManager = LoggingSessionManager(modelContext: modelContext)
                }
                // Auto-start session if skip wizard is enabled and no active session
                // Read directly from UserDefaults to avoid @AppStorage observation overhead
                let defaults = UserDefaults.standard
                let skipWizard = defaults.bool(forKey: "loggerSkipWizard")
                let defaultCallsign = defaults.string(forKey: "loggerDefaultCallsign") ?? ""

                if skipWizard,
                   sessionManager?.hasActiveSession != true,
                   !defaultCallsign.isEmpty
                {
                    let defaultMode = defaults.string(forKey: "loggerDefaultMode") ?? "CW"
                    let defaultGrid = defaults.string(forKey: "loggerDefaultGrid") ?? ""
                    let defaultActivationType =
                        defaults.string(forKey: "loggerDefaultActivationType") ?? "casual"
                    let defaultParkReference =
                        defaults.string(forKey: "loggerDefaultParkReference") ?? ""

                    let activationType = ActivationType(rawValue: defaultActivationType) ?? .casual
                    let parkRef = activationType == .pota ? defaultParkReference : nil
                    sessionManager?.startSession(
                        myCallsign: defaultCallsign,
                        mode: defaultMode,
                        frequency: nil,
                        activationType: activationType,
                        parkReference: parkRef,
                        sotaReference: nil,
                        myGrid: defaultGrid.isEmpty ? nil : defaultGrid
                    )
                }

                // Load session QSOs after session manager is ready
                refreshSessionQSOs()

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
                dismissedWarning = nil
            }
            .onChange(of: sessionManager?.activeSession?.mode) { _, _ in
                dismissedWarning = nil
                // RST fields stay empty - placeholder shows correct default based on mode
            }
            .onChange(of: sessionManager?.activeSession?.id) { _, _ in
                refreshSessionQSOs()
            }
            .overlay(alignment: .bottom) {
                panelOverlays
            }
            .sheet(isPresented: $showHelpSheet) {
                LoggerHelpSheet()
            }
            .confirmationDialog(
                "End Session",
                isPresented: $showEndSessionConfirmation,
                titleVisibility: .visible
            ) {
                Button("End Session") {
                    let hadQSOs = !displayQSOs.isEmpty
                    sessionManager?.endSession()
                    if hadQSOs {
                        onSessionEnd?()
                    }
                }
                Button("Delete Session", role: .destructive) {
                    showDeleteSessionSheet = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "End keeps your \(displayQSOs.count) QSOs for sync. "
                        + "Delete hides them permanently."
                )
            }
            .sheet(isPresented: $showDeleteSessionSheet) {
                DeleteSessionConfirmationSheet(
                    qsoCount: displayQSOs.count,
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
            .safeAreaInset(edge: .bottom) {
                if callsignFieldFocused {
                    VStack(spacing: 0) {
                        compactCallsignLookupDisplay
                        numberRowAccessory
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            .miniTour(.logger, tourState: tourState)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @AppStorage("userLicenseClass") private var licenseClassRaw: String = LicenseClass.extra
        .rawValue

    @AppStorage("loggerAutoModeSwitch") private var autoModeSwitch = true

    /// QSOs for the current session (manually fetched, not @Query to avoid full-database refresh)
    @State private var sessionQSOs: [QSO] = []

    @State private var sessionManager: LoggingSessionManager?

    @State private var showSessionSheet = false

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

    // Session title editing
    @State private var showTitleEditSheet = false
    @State private var editingTitle = ""

    // Session park editing
    @State private var showParkEditSheet = false
    @State private var editingParkReference = ""

    /// Session end/delete confirmation
    @State private var showEndSessionConfirmation = false
    @State private var showDeleteSessionSheet = false

    // QSY spot confirmation
    @State private var showQSYSpotConfirmation = false
    @State private var qsyNewFrequency: Double?

    /// POTA spot tracking - stores session frequency before tuning to a spot
    @State private var preSpotFrequency: Double?

    /// Cached POTA activator spots for nearby frequency detection
    @State private var cachedPOTASpots: [POTASpot] = []
    @State private var spotsLastFetched: Date?

    /// License warning
    /// Dismissed warning message (to avoid re-showing the same warning)
    @State private var dismissedWarning: String?

    /// Tour state for mini-tour
    private let tourState: TourState

    /// Callback when session ends with QSOs logged
    private let onSessionEnd: (() -> Void)?

    // MARK: - Compact Form Fields

    /// Unified field height for consistency
    private let fieldHeight: CGFloat = 36

    /// Deprecated: Use dismissedWarning
    private var dismissedViolation: String? {
        get { dismissedWarning }
        set { dismissedWarning = newValue }
    }

    private var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    /// QSOs for the current session only
    private var displayQSOs: [QSO] {
        sessionQSOs
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

    /// Current frequency warning (if any) - includes license violations, activity warnings, and nearby spots
    private var currentWarning: FrequencyWarning? {
        guard let session = sessionManager?.activeSession,
              let freq = session.frequency
        else {
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
        return warnings.first { $0.message != dismissedWarning }
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
        if let info = lookupResult, !callsignFieldFocused {
            LoggerCallsignCard(info: info)
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

    /// Compact callsign lookup display for keyboard accessory area
    @ViewBuilder
    private var compactCallsignLookupDisplay: some View {
        if let info = lookupResult {
            CompactCallsignBar(info: info)
        } else if let error = lookupError,
                  !callsignInput.isEmpty,
                  callsignInput.count >= 3,
                  detectedCommand == nil
        {
            CompactLookupErrorBar(error: error)
        }
    }

    // MARK: - Number Row Accessory

    private var numberRowAccessory: some View {
        HStack(spacing: 8) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "."], id: \.self) { char in
                Button {
                    callsignInput.append(char)
                } label: {
                    Text(char)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Button {
                callsignFieldFocused = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 40)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
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
                            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
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
                            // Save session frequency before tuning to spot
                            preSpotFrequency = sessionManager?.activeSession?.frequency

                            // Auto-fill form fields from spot
                            callsignInput = spot.activator

                            if let freqKHz = spot.frequencyKHz {
                                let freqMHz = freqKHz / 1_000.0
                                _ = sessionManager?.updateFrequency(freqMHz)
                            }

                            // Build notes from park info
                            var noteParts: [String] = [spot.reference]
                            if let loc = spot.locationDesc {
                                let state = loc.components(separatedBy: "-").last ?? loc
                                noteParts.append(state)
                            }
                            if let parkName = spot.parkName {
                                noteParts.append(parkName)
                            }
                            notes = noteParts.joined(separator: " - ")

                            showPOTAPanel = false
                            ToastManager.shared.info("Loaded \(spot.activator)")
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
                            // Save session frequency before tuning to spot
                            preSpotFrequency = sessionManager?.activeSession?.frequency

                            // Auto-fill form fields from opportunity
                            callsignInput = opportunity.callsign

                            _ = sessionManager?.updateFrequency(opportunity.frequencyMHz)

                            // Build notes from park info (P2P format)
                            var noteParts: [String] = ["P2P", opportunity.parkRef]
                            if let loc = opportunity.locationDesc {
                                let state = loc.components(separatedBy: "-").last ?? loc
                                noteParts.append(state)
                            }
                            if let parkName = opportunity.parkName {
                                noteParts.append(parkName)
                            }
                            notes = noteParts.joined(separator: " - ")

                            showP2PPanel = false
                            ToastManager.shared.info(
                                "P2P: \(opportunity.callsign) @ \(opportunity.parkRef)"
                            )
                        }
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("No Active Session")
                    .font(.headline)
                Text("Start a session to begin logging")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showSessionSheet = true
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Callsign Input

    private var callsignInputSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon only shown for commands
                if let command = detectedCommand {
                    Image(systemName: command.icon)
                        .foregroundStyle(.purple)
                        .transition(.scale.combined(with: .opacity))
                }

                CallsignTextField(
                    "Callsign or command...",
                    text: $callsignInput,
                    isFocused: $callsignFieldFocused
                ) {
                    // Defer to next run loop to avoid UICollectionView crash
                    // when keyboard dismiss triggers List updates simultaneously
                    DispatchQueue.main.async {
                        handleInputSubmit()
                    }
                }
                .foregroundStyle(detectedCommand != nil ? .purple : .primary)
                .onChange(of: callsignInput) { _, newValue in
                    onCallsignChanged(newValue)
                }

                if !callsignInput.isEmpty {
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
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(detectedCommand != nil ? Color.purple : Color.clear, lineWidth: 2)
            )

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

    // MARK: - Log Button

    @ViewBuilder
    private var logButtonSection: some View {
        if let command = detectedCommand {
            // Show "Run Command" button when a command is detected
            Button {
                executeCommand(command)
                callsignInput = ""
            } label: {
                HStack {
                    Image(systemName: command.icon)
                    Text("Run Command")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        } else {
            // Show "Log QSO" button normally
            Button {
                // Use quick entry if we have parsed results, otherwise normal log
                if quickEntryResult != nil {
                    logQuickEntry()
                } else {
                    logQSO()
                }
            } label: {
                Text("Log QSO")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!canLog)
        }
    }

    @ViewBuilder
    private var qsoListSection: some View {
        // Only show QSO list when there's an active session
        if sessionManager?.hasActiveSession == true {
            VStack(alignment: .leading, spacing: 8) {
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
                    ForEach(sessionLogEntries.prefix(15)) { entry in
                        switch entry {
                        case let .qso(qso):
                            LoggerQSORow(
                                qso: qso,
                                sessionQSOs: displayQSOs,
                                isPOTASession: sessionManager?.activeSession?.activationType
                                    == .pota,
                                onQSODeleted: refreshSessionQSOs
                            )
                        case let .note(note):
                            LoggerNoteRow(note: note)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
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

                Text("\(displayQSOs.count) QSOs")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)

                Button {
                    showEndSessionConfirmation = true
                } label: {
                    Text("END")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            HStack {
                if session.activationType == .pota {
                    Button {
                        editingParkReference = session.parkReference ?? ""
                        showParkEditSheet = true
                    } label: {
                        HStack(spacing: 2) {
                            if let parkName = lookupParkName(session.parkReference) {
                                Text(parkName)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                            } else if let ref = session.parkReference {
                                Text(ref)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.green)
                            } else {
                                Text("No park")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let freq = session.frequency {
                    Text(FrequencyFormatter.formatWithUnit(freq))
                        .font(.caption.monospaced())
                }

                if let band = session.band {
                    Text(band)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Capsule())
                }

                Text(session.mode)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())

                Text(session.formattedDuration)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .clipShape(Capsule())

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
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
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

        guard let spotFreqKHz = closestSpot.frequencyKHz else {
            return nil
        }
        let distanceKHz = abs(spotFreqKHz - freqKHz)
        let distanceStr =
            distanceKHz < 0.1 ? "same frequency" : String(format: "%.1f kHz away", distanceKHz)

        let parkInfo =
            if let parkName = closestSpot.parkName {
                "\(closestSpot.reference) - \(parkName)"
            } else {
                closestSpot.reference
            }

        return FrequencyWarning(
            type: .spotNearby,
            message: "\(closestSpot.activator) spotted at \(closestSpot.frequency) kHz",
            suggestion: "\(distanceStr) • \(parkInfo)"
        )
    }

    /// Cancel the current spot and restore session frequency
    private func cancelSpot() {
        if let freq = preSpotFrequency {
            _ = sessionManager?.updateFrequency(freq)
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

        // Find all QSOs with this callsign in the current session
        let matchingQSOs = displayQSOs.filter { $0.callsign.uppercased() == callsign }

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
        case .pota: showPOTAPanel = true
        case .p2p: executeP2PCommand()
        case .solar: showSolarPanel = true
        case .weather: showWeatherPanel = true
        case .map: executeMapCommand()
        case .hidden: showHiddenQSOsSheet = true
        case .help: showHelpSheet = true
        case let .note(text): executeNoteCommand(text)
        }
    }

    private func executeFrequencyCommand(_ freq: Double) {
        let result = sessionManager?.updateFrequency(freq)
        ToastManager.shared.commandExecuted("FREQ", result: FrequencyFormatter.formatWithUnit(freq))

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
        rbnTargetCallsign = callsign
        showRBNPanel = true
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

        showP2PPanel = true
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

        do {
            let potaClient = POTAClient(authService: POTAAuthService())
            let success = try await potaClient.postSpot(
                callsign: callsign,
                reference: parkRef,
                frequency: freq * 1_000, // Convert MHz to kHz
                mode: session.mode,
                comments: comment
            )
            if success {
                if let comment, !comment.isEmpty {
                    ToastManager.shared.spotPosted(park: parkRef, comment: comment)
                } else {
                    ToastManager.shared.spotPosted(park: parkRef)
                }
            }
        } catch {
            ToastManager.shared.error("Spot failed: \(error.localizedDescription)")
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

    private func onCallsignChanged(_ callsign: String) {
        lookupTask?.cancel()

        // Update cached POTA duplicate status (avoids expensive computation on every render)
        cachedPotaDuplicateStatus = computePotaDuplicateStatus()

        let trimmed = callsign.trimmingCharacters(in: .whitespaces).uppercased()

        // Check for quick entry mode (input contains spaces)
        let isQuickEntry = callsign.contains(" ")
        if isQuickEntry {
            quickEntryResult = QuickEntryParser.parse(callsign)
            quickEntryTokens = QuickEntryParser.parseTokens(callsign)
        } else {
            quickEntryResult = nil
            quickEntryTokens = []
        }

        // Determine the callsign to look up
        let callsignForLookup: String =
            if let qeResult = quickEntryResult {
                // In quick entry mode, use the parsed callsign
                qeResult.callsign
            } else {
                trimmed
            }

        // Don't lookup if too short or looks like a command
        guard callsignForLookup.count >= 3,
              LoggerCommand.parse(callsignForLookup) == nil
        else {
            lookupResult = nil
            lookupError = nil
            return
        }

        // Extract the primary callsign for lookup (strip prefix/suffix)
        let primaryCallsign = extractPrimaryCallsign(callsignForLookup)

        // Don't lookup if primary is too short
        guard primaryCallsign.count >= 3 else {
            lookupResult = nil
            lookupError = nil
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

            await MainActor.run {
                lookupResult = result.info
                // Only show actionable errors (not "not found" which is normal)
                if result.error == .notFound {
                    lookupError = nil
                } else {
                    lookupError = result.error
                }
            }
        }
    }

    private func logQSO() {
        guard canLog else {
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

        refreshSessionQSOs()
        restorePreSpotFrequency()
        resetFormAfterLog()
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
            _ = sessionManager?.updateFrequency(freq)
            preSpotFrequency = nil
        }
    }

    /// Reset form fields without animations after logging
    private func resetFormAfterLog() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            callsignInput = ""
            lookupResult = nil
            lookupError = nil
            cachedPotaDuplicateStatus = nil
            quickEntryResult = nil
            quickEntryTokens = []
            theirGrid = ""
            theirState = ""
            theirPark = ""
            notes = ""
            operatorName = ""
            rstSent = ""
            rstReceived = ""
        }
        callsignFieldFocused = true
    }

    private func lookupParkName(_ reference: String?) -> String? {
        guard let ref = reference else {
            return nil
        }
        // Use the POTA parks cache if available
        return POTAParksCache.shared.nameSync(for: ref)
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
    /// Callback when QSO is deleted (hidden)
    var onQSODeleted: (() -> Void)?

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

    @Environment(\.modelContext) private var modelContext

    @State private var callsignInfo: CallsignInfo?
    @State private var showEditSheet = false

    /// Display name from QSO or callsign lookup
    private var displayName: String? {
        qso.name ?? callsignInfo?.name
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
        let previousQSOs = sessionQSOs.filter {
            $0.callsign.uppercased() == callsign && $0.timestamp < qso.timestamp
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
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 4) {
                Text(qso.callsign)
                    .font(.subheadline.weight(.semibold).monospaced())
                    .foregroundStyle(callsignColor)
                    .fixedSize(horizontal: true, vertical: false)

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
                if let name = displayName {
                    Text(name)
                        .font(.caption)
                        .lineLimit(1)
                }
                if let note = callsignInfo?.note, !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                } else if let location = displayLocation {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // Frequency or band
                if let freq = qso.frequency {
                    Text(FrequencyFormatter.format(freq))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(qso.band)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text("\(qso.rstSent ?? "599")/\(qso.rstReceived ?? "599")")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    /// Badge showing POTA status
    @ViewBuilder
    private var potaStatusBadge: some View {
        switch potaStatus {
        case .firstContact:
            EmptyView()
        case let .newBand(previousBands):
            Text("NEW BAND")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .help("Previously worked on: \(previousBands.joined(separator: ", "))")
        case .duplicateBand:
            Text("DUPE")
                .font(.caption2.weight(.bold))
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
                Text("This QSO will be hidden and won't sync to any services.")
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

/// Sheet for editing the park reference on an active POTA session
struct SessionParkEditSheet: View {
    // MARK: Internal

    @Binding var parkReference: String

    let userGrid: String?
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ParkEntryField(
                    parkReference: $parkReference,
                    label: "Park Reference",
                    placeholder: "K-1234",
                    userGrid: userGrid,
                    defaultCountry: "US"
                )

                Text("Change the park for this activation session")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Park")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Normalize the park reference (e.g., "4571" -> "US-4571")
                        let normalized = normalizeParkReference(parkReference)
                        onSave(normalized)
                    }
                    .disabled(parkReference.isEmpty)
                }
            }
        }
    }

    // MARK: Private

    /// Normalize park reference by looking it up and returning the full reference
    private func normalizeParkReference(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces).uppercased()
        if let park = POTAParksCache.shared.lookupPark(trimmed, defaultCountry: "US") {
            return park.reference
        }
        // If lookup fails, still try to add prefix for numeric-only input
        if trimmed.allSatisfy(\.isNumber) {
            return "US-\(trimmed)"
        }
        return trimmed
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

                Spacer()

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
            }
            .padding()
            .navigationBarHidden(true)
            .onAppear {
                isTextFieldFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    @State private var confirmationText = ""
    @FocusState private var isTextFieldFocused: Bool

    private var isConfirmationValid: Bool {
        confirmationText.lowercased() == "delete"
    }
}

// MARK: - Preview

#Preview {
    LoggerView(tourState: TourState())
        .modelContainer(
            for: [QSO.self, LoggingSession.self],
            inMemory: true
        )
}
