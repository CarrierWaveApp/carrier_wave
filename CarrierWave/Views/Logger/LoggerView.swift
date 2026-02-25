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

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.modelContext) var modelContext

    /// QSOs for the current session (manually fetched, not @Query to avoid full-database refresh)
    @State var sessionQSOs: [QSO] = []

    /// All QSOs for the current UTC day (across all sessions) — used for POTA duplicate detection
    /// POTA groups contacts by band + park + UTC day, not by session
    @State var utcDayQSOs: [QSO] = []

    @State var sessionManager: LoggingSessionManager?

    @State var showSessionSheet = false

    // Input fields
    @State var callsignInput = ""
    @FocusState var callsignFieldFocused: Bool
    @State var showWebSDRPanel = false
    /// Session end/delete confirmation
    @State var showEndSessionConfirmation = false
    /// QSO being edited (for tap-to-edit callsign feature)
    @State var editingQSO: QSO?

    /// FT8 session manager (created when session mode is FT8)
    @State var ft8Manager: FT8SessionManager?

    /// FT8 setup wizard presentation
    @State var showFT8SetupWizard = false
    @AppStorage("ft8SetupComplete") var ft8SetupComplete = false

    /// QSO pending swipe-to-delete confirmation
    @State var qsoToDelete: QSO?

    /// Cached POTA activator spots for nearby frequency detection
    @State var cachedPOTASpots: [POTASpot] = []
    /// License warning
    /// Dismissed warning messages (to avoid re-showing dismissed warnings)
    @State var dismissedWarnings: Set<String> = []

    // MARK: - Stored Properties (internal for cross-file extensions)

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    var acceptedFriends: [Friendship]

    @AppStorage("userLicenseClass") var licenseClassRaw: String = LicenseClass.extra
        .rawValue

    @AppStorage("loggerAutoModeSwitch") var autoModeSwitch = true
    @AppStorage("loggerKeepLookupAfterLog") var keepLookupAfterLog = true
    @AppStorage("loggerHideFieldEntryForm") var hideFieldEntryForm = false

    /// Active/paused sessions available to continue or finish
    @State var activeSessions: [LoggingSession] = []
    /// QSO counts for active sessions (keyed by session ID)
    @State var activeSessionQSOCounts: [UUID: Int] = [:]
    /// Finish confirmation for an active session
    @State var sessionToFinish: LoggingSession?
    /// Delete confirmation for an active session
    @State var sessionToDelete: LoggingSession?

    @State var rstSent = ""
    @State var rstReceived = ""
    @State var showMoreFields = false

    // Quick entry
    @State var quickEntryResult: QuickEntryResult?
    @State var quickEntryTokens: [ParsedToken] = []

    // Expanded fields
    @State var notes = ""
    @State var theirPark = ""
    @State var operatorName = ""
    @State var theirGrid = ""
    @State var theirState = ""

    // Callsign lookup
    @State var lookupResult: CallsignInfo?
    @State var lookupError: CallsignLookupError?
    @State var lookupTask: Task<Void, Never>?

    /// All-time QSO count with the current callsign
    @State var previousQSOCount: Int = 0

    /// Cached POTA duplicate status (computed on callsign change, not every render)
    @State var cachedPotaDuplicateStatus: POTACallsignStatus?

    // Command panels
    @State var showRBNPanel = false
    @State var showMapPanel = false
    @State var rbnTargetCallsign: String?
    @State var showSolarPanel = false
    @State var showWeatherPanel = false
    @State var showPOTAPanel = false
    @State var showP2PPanel = false
    @State var showHelpSheet = false
    @State var showHiddenQSOsSheet = false

    // Session title editing
    @State var showTitleEditSheet = false
    @State var editingTitle = ""

    // Session park editing
    @State var showParkEditSheet = false
    @State var editingParkReference = ""

    /// Rove
    @State var showNextStopSheet = false
    /// When set, logger displays QSOs for this park instead of the current active stop
    @State var viewingParkOverride: String?

    // Session band/mode/rig editing
    @State var showBandEditSheet = false
    @State var showModeEditSheet = false
    @State var showRigEditSheet = false

    @State var showDeleteSessionSheet = false

    /// POTA upload prompt after session end
    @State var showPOTAUploadPrompt = false
    @State var pendingSessionEndParkRef: String?
    @State var pendingSessionEndParkName: String?
    @State var pendingSessionEndQSOCount = 0
    @State var pendingSessionEndQSOs: [QSO] = []
    @State var pendingSessionEndRoveStops: [RoveUploadSummary] = []
    @State var pendingSessionEndInMaintenance = false
    @State var pendingSessionEndMaintenanceRemaining: String?

    /// User preference to disable POTA upload prompt
    @AppStorage("potaUploadPromptDisabled") var potaUploadPromptDisabled = false

    // QSY spot confirmation
    @State var showQSYSpotConfirmation = false
    @State var qsyNewFrequency: Double?
    /// Deferred QSY prompt: stored when a sheet dismissal would swallow the alert
    @State var pendingQSYFrequency: Double?

    /// POTA spot tracking - stores session frequency before tuning to a spot
    @State var preSpotFrequency: Double?
    @State var spotsLastFetched: Date?

    /// iPad sidebar: spot selected from sidebar, processed via .onChange
    @Binding var externalSpotSelection: SpotSelection?

    /// Tour state for mini-tour
    let tourState: TourState

    /// Callback when session ends with QSOs logged
    let onSessionEnd: (() -> Void)?

    /// iPad sidebar: intercepts spot commands to switch sidebar tab
    let onSpotCommand: ((SpotCommandAction) -> Void)?

    // MARK: - Compact Form Fields

    /// Unified field height for consistency
    let fieldHeight: CGFloat = 36

    /// Whether to use the landscape two-pane layout
    var isLandscapeWithSession: Bool {
        verticalSizeClass == .compact && sessionManager?.hasActiveSession == true
    }

    /// QSOs to display — during roves, scoped to the viewed or current park stop
    var displayQSOs: [QSO] {
        guard let session = sessionManager?.activeSession, session.isRove else {
            return sessionQSOs
        }
        let park = (viewingParkOverride ?? session.parkReference)?.uppercased()
        guard let park else {
            return sessionQSOs
        }
        return sessionQSOs.filter { $0.parkReference?.uppercased() == park }
    }

    /// Check if the current callsign input would be a duplicate in the current POTA session
    /// Uses cached value computed in onCallsignChanged to avoid expensive filtering on every render
    var potaDuplicateStatus: POTACallsignStatus? {
        cachedPotaDuplicateStatus
    }

    /// Whether any bottom panel is currently open
    var isAnyPanelOpen: Bool {
        showRBNPanel || showSolarPanel || showWeatherPanel || showMapPanel || showPOTAPanel
            || showP2PPanel || showWebSDRPanel
    }

    // MARK: - QSO List

    /// Combined session log entries (QSOs + notes)
    var sessionLogEntries: [SessionLogEntry] {
        let notes = sessionManager?.parseSessionNotes() ?? []
        return SessionLogEntry.combine(qsos: displayQSOs, notes: notes)
    }

    var body: some View {
        NavigationStack {
            let mainContent = ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if isLandscapeWithSession {
                    landscapeTwoPaneLayout
                } else {
                    portraitLayout
                }
            }
            .navigationBarHidden(horizontalSizeClass != .regular)
            .toolbarTitleDisplayMode(.inline)

            applyEventHandlers(applySheetModifiers(mainContent))
                .overlay(alignment: .bottom) {
                    panelOverlays
                }
                .toastContainer()
                .miniTour(.logger, tourState: tourState)
        }
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
