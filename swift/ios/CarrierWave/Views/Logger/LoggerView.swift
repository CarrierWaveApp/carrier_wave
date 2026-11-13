import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CompactField

/// Focus tracking for compact form fields (RST, State, Grid, etc.)
/// so they can be explicitly defocused when returning focus to the callsign field.
enum CompactField: Hashable {
    case state
    case rstSent
    case rstReceived
    case grid
    case park
    case summit
    case aoaCode
    case operatorName
    case notes
}

// MARK: - LoggerView

/// Main logging view for QSO entry
struct LoggerView: View {
    // MARK: Lifecycle

    init(
        tourState: TourState,
        sessionManager: LoggingSessionManager? = nil,
        onSessionEnd: (() -> Void)? = nil,
        onSpotCommand: ((SpotCommandAction) -> Void)? = nil,
        pendingSpotSelection: Binding<SpotSelection?>? = nil
    ) {
        self.tourState = tourState
        externalSessionManager = sessionManager
        self.onSessionEnd = onSessionEnd
        self.onSpotCommand = onSpotCommand
        _externalSpotSelection = pendingSpotSelection ?? .constant(nil)
    }

    // MARK: Internal

    /// The bottom panels the logger can surface. Only one shows at a time.
    enum Panel {
        case rbn
        case solar
        case weather
        case map
        case pota
        case p2p
        case webSDR
        case radio
    }

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.modelContext) var modelContext
    @Environment(\.locationSessionService) var locationService
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// QSOs for the current session (manually fetched via FetchDescriptor to avoid full-database refresh)
    @State var sessionQSOs: [QSO] = []

    /// All QSOs for the current UTC day (across all sessions) — used for duplicate detection.
    /// Dupe = same callsign + band + UTC day. POTA additionally scopes by park.
    @State var utcDayQSOs: [QSO] = []

    @State var sessionManager: LoggingSessionManager?

    @State var showSessionSheet = false

    // Input fields
    @State var callsignInput = ""
    @FocusState var callsignFieldFocused: Bool
    @FocusState var compactFieldFocus: CompactField?
    @State var showWebSDRPanel = false
    @State var showRadioPanel = false
    /// End session multi-step flow
    @State var showEndSessionFlow = false
    @State var endSessionActivityItem: ActivityItem?
    /// QSO being edited (for tap-to-edit callsign feature)
    @State var editingQSO: QSO?

    /// FT8 session manager (created when session mode is FT8)
    @State var ft8Manager: FT8SessionManager?

    /// FT8 setup wizard presentation
    @State var showFT8SetupWizard = false
    @AppStorage("ft8SetupComplete") var ft8SetupComplete = false

    /// QSO pending swipe-to-delete confirmation
    @State var qsoToDelete: QSO?

    /// Whether the command bar has scrolled off the top of the screen
    @State var commandBarPinned = false

    /// Cached POTA activator spots for nearby frequency detection
    @State var cachedPOTASpots: [POTASpot] = []
    /// POTA spots matching the current callsign input (P2P enrichment)
    @State var potaSpotMatches: [POTASpot] = []
    /// Park reference from matched POTA spot (for P2P enrichment display)
    @State var spotMatchPark: String?

    /// Cached SOTA activator spots — used for S2S enrichment (auto-fill
    /// the contacted station's summit ref when a callsign matches a
    /// current spot). Mirrors `SOTASpotsCache.shared` for fast SwiftUI reads.
    @State var cachedSOTASpots: [SOTASpot] = []
    /// Dismissed warning messages (to avoid re-showing dismissed warnings)
    @State var dismissedWarnings: Set<String> = []

    /// Spot-vs-QSO callsign mismatches (near-misses within edit distance 2)
    @State var spotMismatches: [SpotContactMismatch] = []
    /// Whether the user permanently dismissed the mismatch banner for this session
    @State var spotMismatchesDismissed = false

    /// Callsign → contact count for weighting suggestions
    @State var suggestionContactCounts: [String: Int] = [:]
    /// SCP (Super Check Partial) suggestions for the current callsign input
    @State var scpSuggestions: [String] = []
    /// Whether the current callsign is a known callsign in the SCP database
    @State var scpCallsignKnown: Bool?
    /// SCP did-you-mean confirmation
    @State var showSCPDidYouMean = false
    @State var scpDidYouMeanSuggestions: [(callsign: String, distance: Int)] = []

    @AppStorage("userLicenseClass") var licenseClassRaw: String = LicenseClass.extra
        .rawValue

    @AppStorage("loggerAutoModeSwitch") var autoModeSwitch = true
    @AppStorage("loggerKeepLookupAfterLog") var keepLookupAfterLog = true
    @AppStorage("loggerHideFieldEntryForm") var hideFieldEntryForm = false
    /// Simple Logging Mode: mutes situational chips in the session header so the
    /// logger stays focused on the contact being worked. Set in Appearance settings.
    @AppStorage("loggerSimpleMode") var loggerSimpleMode = false
    @AppStorage("rstParseOrder") var rstParseOrderRaw = RSTOrder.receivedFirst.rawValue

    @State var rstSent = ""
    @State var rstReceived = ""
    @State var showMoreFields = false

    // Quick entry
    @State var quickEntryResult: QuickEntryResult?
    @State var quickEntryMultiResults: [QuickEntryResult]?
    @State var quickEntryTokens: [ParsedToken] = []

    // Expanded fields
    @State var notes = ""
    @State var theirPark = ""
    /// SOTA summit reference for the contacted station (S2S — required for SOTA QSOs)
    @State var theirSummit = ""
    /// Last value the S2S enrichment auto-wrote into `theirSummit`. Used so
    /// we only clear sticky auto-fills when the user types a new callsign
    /// that doesn't match a SOTA spot — a hand-typed value (where
    /// `theirSummit != autoFilledSummit`) is preserved.
    @State var autoFilledSummit: String?
    @State var operatorName = ""
    @State var theirGrid = ""
    @State var theirState = ""
    @State var aoaCode = ""

    // Contest
    @State var contestManager: ContestManager?
    @State var contestExchangeValues: [String: String] = [:]
    /// Field name → value last written by enrichment prefill. Used to
    /// distinguish auto-filled values from user-typed ones so we can clear
    /// only the auto-fills when the callsign is cleared.
    @State var prefilledContestFields: [String: String] = [:]

    // Callsign lookup
    @State var lookupResult: CallsignInfo?
    @State var lookupError: CallsignLookupError?
    @State var lookupTask: Task<Void, Never>?

    // Multi-callsign lookup (for multi-op contacts)
    @State var multiLookupResults: [MultiCallsignLookupState] = []
    @State var selectedMultiLookupIndex: Int = 0

    /// Last callsign(s) sent to lookup — skip redundant lookups when only metadata tokens change
    @State var lastLookedUpCallsigns: [String] = []

    /// Network health
    @State var networkHealthDismissed = false

    /// All-time QSO count with the current callsign
    @State var previousQSOCount: Int = 0

    /// Cached duplicate status (computed on callsign change, not every render)
    @State var cachedDuplicateStatus: CallsignDuplicateStatus?

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
    @State var showSpaceWeatherSheet = false
    @State var showOperatorsSheet = false

    // Controls bar scroll fade
    @State var chipContentWidth: CGFloat = 0
    @State var chipScrollOffset: CGFloat = 0
    @State var chipScrollViewWidth: CGFloat = 0

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

    // CW Keyer
    @State var cwSlotEditorID: Int?
    @State var showCWSlotEditor = false

    // QRQ Crew spot
    @State var showQRQCrewSpotSheet = false
    @State var pendingQRQCrewSpot: QRQCrewSpotInfo?

    /// QSY Log confirmation (from qsy://log URI)
    @State var pendingQSYLog: QSYLogConfirmation?

    /// POTA spot tracking - stores session frequency before tuning to a spot
    @State var preSpotFrequency: Double?
    @State var spotsLastFetched: Date?

    /// iPad sidebar: spot selected from sidebar, processed via .onChange
    @Binding var externalSpotSelection: SpotSelection?

    /// External session manager passed from parent (SessionsTabView).
    /// When set, LoggerView uses this instead of creating its own.
    let externalSessionManager: LoggingSessionManager?

    /// Tour state for mini-tour
    let tourState: TourState

    /// Callback when session ends with QSOs logged
    let onSessionEnd: (() -> Void)?

    /// iPad sidebar: intercepts spot commands to switch sidebar tab
    let onSpotCommand: ((SpotCommandAction) -> Void)?

    // MARK: - Compact Form Fields

    /// Unified field height for consistency
    let fieldHeight: CGFloat = 36

    // MARK: - Stored Properties (internal for cross-file extensions)

    var acceptedFriends: [Friendship] {
        FriendsSyncService.shared.acceptedFriends
    }

    var rstParseOrder: RSTOrder {
        RSTOrder(rawValue: rstParseOrderRaw) ?? .receivedFirst
    }

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

    /// Duplicate status for the current callsign input (same callsign + band + UTC day).
    /// Uses cached value computed in onCallsignChanged to avoid expensive filtering on every render.
    var duplicateStatus: CallsignDuplicateStatus? {
        cachedDuplicateStatus
    }

    /// Whether any bottom panel is currently open
    var isAnyPanelOpen: Bool {
        showRBNPanel || showSolarPanel || showWeatherPanel || showMapPanel || showPOTAPanel
            || showP2PPanel || showWebSDRPanel
    }

    // MARK: - QSO List

    /// Combined session log entries (QSOs, notes, and boundary markers)
    var sessionLogEntries: [SessionLogEntry] {
        let notes = sessionManager?.parseSessionNotes() ?? []
        let parkRef = sessionManager?.activeSession?.parkReference
        let longitude = parkRef.flatMap { POTAParksCache.shared.parkSync(for: $0)?.longitude }
        return SessionLogEntry.combineWithBoundaries(
            qsos: displayQSOs, notes: notes, parkLongitude: longitude
        )
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

            applyPebbleHandlers(applyEventHandlers(applySheetModifiers(mainContent)))
                .overlay(alignment: .bottom) {
                    panelOverlays
                }
                .toastContainer()
                .sheet(isPresented: $showFT8SetupWizard) {
                    FT8SetupWizardView(isPresented: $showFT8SetupWizard)
                        .interactiveDismissDisabled()
                }
        }
    }

    /// Show a single panel (or `nil` to close all). Keeps panels mutually
    /// exclusive so they never stack on top of one another — previously each
    /// panel had its own independent flag and several could pile up at once.
    func present(_ panel: Panel?) {
        showRBNPanel = panel == .rbn
        showSolarPanel = panel == .solar
        showWeatherPanel = panel == .weather
        showMapPanel = panel == .map
        showPOTAPanel = panel == .pota
        showP2PPanel = panel == .p2p
        showWebSDRPanel = panel == .webSDR
        showRadioPanel = panel == .radio
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
