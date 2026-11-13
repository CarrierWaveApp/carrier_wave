import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsTabView

/// Top-level container for the Sessions tab.
/// Switches between idle view (sessions list) and active logger
/// based on whether a logging session is active.
///
/// When the operator role is `.hunter` and a Hunter Log is configured, the
/// idle path is the Hunter Log itself (not the intent grid). Hunters never
/// start sessions — surfacing the intent grid as their default landing wastes
/// a tap on every visit. The Sessions intent grid remains one tap away via a
/// toolbar button on the Hunter Log.
struct SessionsTabView: View {
    // MARK: Internal

    let tourState: TourState
    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let qrzClient: QRZClient?
    var isInNavigationContext: Bool = false
    @Binding var pendingHunterSpot: [String: Any]?
    @Binding var pendingSpotlightSessionID: UUID?
    var onSessionStateChange: ((Bool) -> Void)?

    @Environment(\.modelContext) var modelContext
    @Environment(\.locationSessionService) var locationService

    @AppStorage(OperatorRole.storageKey) var operatorRoleRaw = ""

    var body: some View {
        Group {
            if sessionManager?.hasActiveSession == true {
                LoggerContainerView(
                    tourState: tourState,
                    sessionManager: sessionManager,
                    onSessionEnd: nil
                )
            } else if shouldDefaultToHunterLog,
                      let manager = hunterLogManager
            {
                hunterDefaultContent(manager: manager)
            } else {
                SessionsIntentView(
                    sessionManager: $sessionManager,
                    potaClient: potaClient,
                    potaAuth: potaAuth,
                    tourState: tourState,
                    qrzClient: qrzClient,
                    isInNavigationContext: isInNavigationContext,
                    pendingHunterSpot: $pendingHunterSpot,
                    pendingSpotlightSessionID: $pendingSpotlightSessionID,
                    activityLogManager: $hunterLogManager
                )
            }
        }
        .onAppear {
            if sessionManager == nil {
                sessionManager = LoggingSessionManager(
                    modelContext: modelContext,
                    locationService: locationService,
                    potaAuthService: potaAuth
                )
            }
            if hunterLogManager == nil {
                hunterLogManager = ActivityLogManager(
                    modelContext: modelContext,
                    locationService: locationService
                )
            } else {
                // SessionsIntentView keeps its own ActivityLogManager. When
                // the user creates a Hunter Log via the setup sheet there,
                // our hunterLogManager's `activeLog` stays nil until we
                // refresh — which gates `shouldDefaultToHunterLog`.
                hunterLogManager?.loadActiveLog()
            }
        }
        .onChange(of: sessionManager?.hasActiveSession) { _, hasSession in
            onSessionStateChange?(hasSession ?? false)
            // When a session is started from the Sessions intent sheet (opened
            // from the Hunter Log toolbar), dismiss the sheet so the active
            // LoggerContainerView takes over the tab.
            if hasSession == true, showSessionsIntentSheet {
                showSessionsIntentSheet = false
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveWatchStartSession)
        ) { notification in
            handleWatchStartSession(notification)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didStartSessionExternally)
        ) { _ in
            sessionManager?.loadActiveSession()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didRequestHunterLog)
        ) { _ in
            handleHunterLogDeepLink()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didRequestResumeSession)
        ) { _ in
            handleResumeSessionDeepLink()
        }
        .fullScreenCover(isPresented: $showHunterLogCover) {
            if let manager = hunterLogManager {
                NavigationStack {
                    ActivityLogView(manager: manager)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showHunterLogCover = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showHunterLogSetupSheet) {
            ActivityLogSetupSheet(manager: hunterLogManager)
        }
        .sheet(isPresented: $showSessionsIntentSheet) {
            NavigationStack {
                SessionsIntentView(
                    sessionManager: $sessionManager,
                    potaClient: potaClient,
                    potaAuth: potaAuth,
                    tourState: tourState,
                    qrzClient: qrzClient,
                    isInNavigationContext: true,
                    pendingHunterSpot: .constant(nil),
                    pendingSpotlightSessionID: $pendingSpotlightSessionID,
                    activityLogManager: $hunterLogManager
                )
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showSessionsIntentSheet = false }
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var sessionManager: LoggingSessionManager?
    @State private var hunterLogManager: ActivityLogManager?
    @State private var showHunterLogCover = false
    @State private var showHunterLogSetupSheet = false
    @State private var showSessionsIntentSheet = false

    /// Snapshot of `pendingHunterSpot` captured once when the hunter-default
    /// content first appears (or when a new spot arrives). The binding itself
    /// is cleared immediately so a later body re-eval doesn't re-deliver the
    /// same spot to `QuickLogSection.applyInitialSpot`. Stored locally so the
    /// snapshot survives the binding clear within the same SwiftUI tick.
    @State private var hunterDefaultPendingSpot: [String: Any]?

    /// True when the user has explicitly chosen `.hunter` AND has a configured
    /// Hunter Log to land on. Unset / mixed / other roles continue to land on
    /// the intent grid by default.
    private var shouldDefaultToHunterLog: Bool {
        OperatorRole(rawValue: operatorRoleRaw) == .hunter
            && hunterLogManager?.activeLog != nil
    }

    /// Hunter Log wrapped in its own NavigationStack with a toolbar item that
    /// surfaces the Sessions intent grid as a sheet. The pendingHunterSpot
    /// dictionary is captured into `hunterDefaultPendingSpot` on first
    /// delivery — the binding is then cleared so a tab switch or re-render
    /// doesn't re-apply the same spot to `QuickLogSection.applyInitialSpot`,
    /// which is otherwise idempotent on `initialSpotInfo`.
    @ViewBuilder
    private func hunterDefaultContent(manager: ActivityLogManager) -> some View {
        let content = ActivityLogView(
            manager: manager,
            pendingSpotUserInfo: hunterDefaultPendingSpot
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSessionsIntentSheet = true
                } label: {
                    Label("Sessions", systemImage: "list.bullet.rectangle.portrait")
                }
                .accessibilityLabel("Open Sessions intent")
            }
        }
        .onAppear {
            consumePendingHunterSpot()
        }
        .onChange(of: pendingHunterSpot?["callsign"] as? String) { _, _ in
            consumePendingHunterSpot()
        }

        if isInNavigationContext {
            content
        } else {
            NavigationStack {
                content
            }
        }
    }

    /// Capture the incoming spot into local state, then clear the binding so
    /// the QuickLogSection sees the new value exactly once.
    private func consumePendingHunterSpot() {
        guard let spot = pendingHunterSpot,
              spot["callsign"] is String
        else {
            return
        }
        hunterDefaultPendingSpot = spot
        pendingHunterSpot = nil
    }

    /// Hunt-widget deep link handler — surfaces the Hunter Log over whatever
    /// the Sessions tab is currently showing (active session or idle/intent).
    /// Falls back to the setup sheet if no Hunter Log is configured yet.
    private func handleHunterLogDeepLink() {
        guard hunterLogManager?.activeLog != nil else {
            showHunterLogSetupSheet = true
            return
        }
        // No need to cover when the Hunter Log is already the default surface
        // for a hunter — the tab is already there.
        if shouldDefaultToHunterLog {
            return
        }
        showHunterLogCover = true
    }

    /// Home's hero Resume row: reopen the most recent open session instead
    /// of leaving the user on the idle intent screen. Resuming flips
    /// `hasActiveSession`, which swaps this tab to the live LoggerView.
    private func handleResumeSessionDeepLink() {
        guard let manager = sessionManager, !manager.hasActiveSession else {
            return // live logger already showing (or tab not mounted yet)
        }
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate {
                $0.statusRawValue == "active" || $0.statusRawValue == "paused"
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let session = (try? modelContext.fetch(descriptor))?.first else {
            return
        }
        manager.resumeSession(session)
    }

    private func handleWatchStartSession(_ notification: Notification) {
        guard let request = notification.userInfo?["request"]
            as? WatchStartSessionRequest,
            sessionManager?.hasActiveSession != true
        else {
            return
        }
        let type = ActivationType(rawValue: request.activationType) ?? .casual
        sessionManager?.startSession(
            myCallsign: request.myCallsign,
            mode: request.mode,
            frequency: request.frequency,
            activationType: type,
            parkReference: request.parkReference
        )
    }
}
