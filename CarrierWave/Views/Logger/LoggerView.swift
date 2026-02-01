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

                    // License warning banner
                    if let violation = currentViolation {
                        LicenseWarningBanner(violation: violation) {
                            dismissedViolation = violation.message
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

                                qsoFormSection

                                alwaysVisibleFieldsSection

                                if showMoreFields, hasMoreFields {
                                    moreFieldsSection
                                        .transition(
                                            .asymmetric(
                                                insertion: .move(edge: .top).combined(
                                                    with: .opacity
                                                ),
                                                removal: .opacity
                                            )
                                        )
                                }

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
            }

            .onChange(of: sessionManager?.activeSession?.frequency) { _, _ in
                dismissedViolation = nil
            }
            .onChange(of: sessionManager?.activeSession?.mode) { _, _ in
                dismissedViolation = nil
                // RST fields stay empty - placeholder shows correct default based on mode
            }
            .onChange(of: sessionManager?.activeSession?.id) { _, _ in
                refreshSessionQSOs()
            }
            .overlay(alignment: .bottom) {
                panelOverlays
            }
            .alert("Logger Commands", isPresented: $showHelpAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(LoggerCommand.helpText)
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

    // Always visible field settings
    @AppStorage("loggerShowNotes") private var showNotesAlways = false
    @AppStorage("loggerShowTheirGrid") private var showTheirGridAlways = false
    @AppStorage("loggerShowTheirPark") private var showTheirParkAlways = false
    @AppStorage("loggerShowOperator") private var showOperatorAlways = false

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

    // Expanded fields
    @State private var notes = ""
    @State private var theirPark = ""
    @State private var operatorName = ""
    @State private var theirGrid = ""

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
    @State private var showHelpAlert = false
    @State private var showHiddenQSOsSheet = false

    // Session title editing
    @State private var showTitleEditSheet = false
    @State private var editingTitle = ""

    /// Session end/delete confirmation
    @State private var showEndSessionConfirmation = false
    @State private var showDeleteSessionSheet = false

    // QSY spot confirmation
    @State private var showQSYSpotConfirmation = false
    @State private var qsyNewFrequency: Double?

    /// License warning
    @State private var dismissedViolation: String?

    /// Tour state for mini-tour
    private let tourState: TourState

    /// Callback when session ends with QSOs logged
    private let onSessionEnd: (() -> Void)?

    private var userLicenseClass: LicenseClass {
        LicenseClass(rawValue: licenseClassRaw) ?? .extra
    }

    /// QSOs for the current session only
    private var displayQSOs: [QSO] {
        sessionQSOs
    }

    /// Whether the log button should be enabled
    private var canLog: Bool {
        guard sessionManager?.hasActiveSession == true,
              !callsignInput.isEmpty,
              callsignInput.count >= 3
        else {
            return false
        }

        // Don't allow logging your own callsign
        let myCallsign = sessionManager?.activeSession?.myCallsign.uppercased() ?? ""
        if !myCallsign.isEmpty, callsignInput.uppercased() == myCallsign {
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

    /// Whether any fields are configured to always be visible
    private var hasAlwaysVisibleFields: Bool {
        showNotesAlways || showTheirGridAlways || showTheirParkAlways || showOperatorAlways
    }

    /// Whether there are any fields left to show in "More Fields"
    private var hasMoreFields: Bool {
        !showNotesAlways || !showTheirGridAlways || !showTheirParkAlways || !showOperatorAlways
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

    /// Current band plan violation (if any)
    private var currentViolation: BandPlanViolation? {
        guard let session = sessionManager?.activeSession,
              let freq = session.frequency
        else {
            return nil
        }

        let violation = BandPlanService.validate(
            frequencyMHz: freq,
            mode: session.mode,
            license: userLicenseClass
        )

        // Don't show if user dismissed this specific violation
        if let violation, violation.message == dismissedViolation {
            return nil
        }

        return violation
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
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showRBNPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSolarPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showWeatherPanel)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showMapPanel)
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
                // Icon changes based on whether input is a command
                if let command = detectedCommand {
                    Image(systemName: command.icon)
                        .foregroundStyle(.purple)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }

                TextField("Callsign or command...", text: $callsignInput)
                    .font(.title3.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(detectedCommand != nil ? .purple : .primary)
                    .focused($callsignFieldFocused)
                    .onSubmit {
                        // Defer to next run loop to avoid UICollectionView crash
                        // when keyboard dismiss triggers List updates simultaneously
                        DispatchQueue.main.async {
                            handleInputSubmit()
                        }
                    }
                    .onChange(of: callsignInput) { _, newValue in
                        onCallsignChanged(newValue)
                    }

                if !callsignInput.isEmpty {
                    Button {
                        callsignInput = ""
                        lookupResult = nil
                        lookupError = nil
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
        }
    }

    // MARK: - QSO Form

    private var qsoFormSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(defaultRST, text: $rstSent)
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Rcvd")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(defaultRST, text: $rstReceived)
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .keyboardType(.numberPad)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Only show "More" button if there are fields not marked as always visible
            if hasMoreFields {
                Button {
                    withAnimation {
                        showMoreFields.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showMoreFields ? "chevron.up" : "chevron.down")
                        Text(showMoreFields ? "Less" : "More")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    /// Fields configured to always be visible (shown below RST)
    @ViewBuilder
    private var alwaysVisibleFieldsSection: some View {
        if hasAlwaysVisibleFields {
            VStack(spacing: 12) {
                // Grid and Park in a row if both visible
                if showTheirGridAlways || showTheirParkAlways {
                    HStack(spacing: 12) {
                        if showTheirGridAlways {
                            theirGridField
                        }
                        if showTheirParkAlways {
                            theirParkField
                        }
                    }
                }

                if showOperatorAlways {
                    operatorField
                }

                if showNotesAlways {
                    notesField
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var moreFieldsSection: some View {
        VStack(spacing: 12) {
            // Grid and Park in a row (only if not always visible)
            if !showTheirGridAlways || !showTheirParkAlways {
                HStack(spacing: 12) {
                    if !showTheirGridAlways {
                        theirGridField
                    }
                    if !showTheirParkAlways {
                        theirParkField
                    }
                }
            }

            if !showOperatorAlways {
                operatorField
            }

            if !showNotesAlways {
                notesField
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Reusable Field Views

    private var theirGridField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Their Grid")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(lookupResult?.grid ?? "", text: $theirGrid)
                .font(.subheadline.monospaced())
                .textInputAutocapitalization(.characters)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var theirParkField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Their Park")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("", text: $theirPark)
                .font(.subheadline.monospaced())
                .textInputAutocapitalization(.characters)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var operatorField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Operator")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(lookupResult?.displayName ?? "Operator name", text: $operatorName)
                .font(.subheadline)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Notes...", text: $notes, axis: .vertical)
                .font(.subheadline)
                .lineLimit(2 ... 4)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
                logQSO()
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
                                    == .pota
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
                if let parkName = lookupParkName(session.parkReference) {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
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

        let callsign = callsignInput.uppercased()
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
            return
        }

        // Otherwise try to log
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
        case .solar: showSolarPanel = true
        case .weather: showWeatherPanel = true
        case .map: executeMapCommand()
        case .hidden: showHiddenQSOsSheet = true
        case .help: showHelpAlert = true
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

        // Don't lookup if too short or looks like a command
        guard trimmed.count >= 3,
              LoggerCommand.parse(trimmed) == nil
        else {
            lookupResult = nil
            lookupError = nil
            return
        }

        // Extract the primary callsign for lookup (strip prefix/suffix)
        let primaryCallsign = extractPrimaryCallsign(trimmed)

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

        // Use manually entered grid, or fall back to grid from callsign lookup
        let gridToUse: String? =
            if !theirGrid.isEmpty {
                theirGrid
            } else {
                lookupResult?.grid
            }

        _ = sessionManager?.logQSO(
            callsign: callsignInput,
            rstSent: rstSent.isEmpty ? defaultRST : rstSent,
            rstReceived: rstReceived.isEmpty ? defaultRST : rstReceived,
            theirGrid: gridToUse,
            theirParkReference: theirPark.isEmpty ? nil : theirPark,
            notes: notes.isEmpty ? nil : notes,
            name: lookupResult?.name,
            operatorName: operatorName.isEmpty ? lookupResult?.displayName : operatorName,
            state: lookupResult?.state,
            country: lookupResult?.country,
            qth: lookupResult?.qth,
            theirLicenseClass: lookupResult?.licenseClass
        )

        // Refresh the QSO list with the new entry
        refreshSessionQSOs()

        // Reset form without animations for instant feedback
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            callsignInput = ""
            lookupResult = nil
            lookupError = nil
            cachedPotaDuplicateStatus = nil
            theirGrid = ""
            theirPark = ""
            notes = ""
            operatorName = ""
            rstSent = ""
            rstReceived = ""
        }

        // Immediately focus callsign field for next QSO
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

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditSheet) {
            QSOEditSheet(qso: qso)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    HStack {
                        Text("Callsign")
                        Spacer()
                        Text(qso.callsign)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Time")
                        Spacer()
                        Text(qso.timestamp, format: .dateTime)
                            .foregroundStyle(.secondary)
                    }
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
                        hideQSO()
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
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var name = ""
    @State private var grid = ""
    @State private var theirPark = ""
    @State private var notes = ""

    private func loadQSOData() {
        rstSent = qso.rstSent ?? "599"
        rstReceived = qso.rstReceived ?? "599"
        name = qso.name ?? ""
        grid = qso.theirGrid ?? ""
        theirPark = qso.theirParkReference ?? ""
        notes = qso.notes ?? ""
    }

    private func saveChanges() {
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
