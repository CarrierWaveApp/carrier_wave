import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - SessionsIntentView

/// Intent-first landing screen for the Sessions tab.
///
/// 2×2 grid of verb-first cards (Activate, Hunt, Casual, Contest) so the
/// primary task — *start operating* — is the most prominent thing on screen.
/// Active/paused sessions appear in a secondary "Continue" strip, and
/// completed session history is embedded below via `SessionsView` to avoid
/// duplication.
///
/// Graduated from `.sessionIntentPicker` in v1.93.0 (CAR-276 PR2). The
/// previous `SessionsIdleView` was retired in the same release.
struct SessionsIntentView: View {
    // MARK: Internal

    static let dismissedTemplatesKey = "dismissedSessionTemplateKeys"

    @Binding var sessionManager: LoggingSessionManager?
    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let tourState: TourState
    let qrzClient: QRZClient?
    var isInNavigationContext: Bool = false

    @Binding var pendingHunterSpot: [String: Any]?
    @Binding var pendingSpotlightSessionID: UUID?

    @Environment(\.modelContext) var modelContext
    @Environment(\.locationSessionService) var locationService

    /// Shared with `SessionsTabView` (which also hosts the Hunter Log as the
    /// hunter-role default landing and the deep-link cover). One manager means
    /// QSOs logged through any of those surfaces update the Hunter Log card
    /// here; a second instance would hold its own stale `todayQSOCount`.
    @Binding var activityLogManager: ActivityLogManager?

    // Internal access so the +Actions extension in a sibling file can
    // read/write these. Swift `private`/`fileprivate` only reach within
    // the declaring file; cross-file extensions need `internal`.
    @State var activeSessions: [LoggingSession] = []
    @State var activeSessionQSOCounts: [UUID: Int] = [:]
    @State var recentTemplates: [SessionTemplate] = []
    @State var savedTemplates: [SavedSessionTemplate] = []
    @State var selectedSavedTemplate: SavedSessionTemplate?
    @State var sessionToFinish: LoggingSession?
    @State var sessionToDelete: LoggingSession?
    @State var showSessionSheet = false
    @State var showingActivityLogSetup = false
    @State var navigateToHunterLog = false
    @State var loggerTourManager: LoggerTourManager?
    @State var hasRefreshedProfile = false
    @State var spotlightSession: LoggingSession?
    @State var dismissedTemplateKeys: Set<String> = []
    /// Non-nil signals the next `SessionStartSheet` presentation is a contest
    /// start. Empty string = no last-used contest (sheet auto-presents
    /// picker); non-empty = pre-load that contest definition by id.
    @State var sessionStartContestIntent: String?
    /// Which tailored wizard the next sheet uses; set by the intent actions.
    @State var sessionOperationType: SessionOperationType = .activation

    // MARK: - Header Assembly

    @AppStorage(OperatorRole.storageKey) var operatorRoleRaw = ""

    var body: some View {
        if isInNavigationContext {
            sessionsIntentContent
        } else {
            NavigationStack {
                sessionsIntentContent
            }
        }
    }

    @ViewBuilder
    var intentHeader: some View {
        if OperatorRole(rawValue: operatorRoleRaw) == nil {
            operatorRolePromptSection
        }

        if let candidate = quickStartCandidate {
            Section {
                QuickStartCard(
                    title: "Same as Last Session",
                    subtitle: quickStartSubtitle(for: candidate),
                    onTap: { quickStartFromLastSession() }
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }

        Section {
            IntentGrid(
                onActivate: { startActivate() },
                onHunt: { startHunt() },
                onCasual: { startCasual() },
                onContest: { startContest() },
                activateSubtitle: ProgramAvailability.activateSubtitle()
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        if !activeSessions.isEmpty {
            continueSection
        }

        if let manager = activityLogManager, manager.activeLog != nil {
            hunterLogStatusSection(manager: manager)
        }

        if !recentTemplates.isEmpty || !savedTemplates.isEmpty {
            quickStartSection
        }
    }

    // MARK: Private

    // MARK: - Sessions Intent Content

    private var sessionsIntentContent: some View {
        SessionsView(
            potaClient: potaClient,
            potaAuth: potaAuth,
            tourState: tourState,
            qrzClient: qrzClient,
            sessionManager: sessionManager,
            isEmbedded: true,
            activeSessionsHeader: {
                AnyView(intentHeader)
            }
        )
        .toastContainer()
        .navigationTitle("Sessions")
        .sheet(isPresented: $showSessionSheet) {
            SessionStartSheet(
                sessionManager: sessionManager,
                onDismiss: {
                    showSessionSheet = false
                    selectedSavedTemplate = nil
                    sessionStartContestIntent = nil
                    sessionOperationType = .activation
                },
                initialTemplate: selectedSavedTemplate,
                initialContestId: sessionStartContestIntent,
                operationType: sessionOperationType
            )
        }
        .sheet(isPresented: $showingActivityLogSetup) {
            ActivityLogSetupSheet(manager: activityLogManager)
        }
        .fullScreenCover(item: $loggerTourManager) { manager in
            LoggerTourOverlay(tourManager: manager)
        }
        .navigationDestination(isPresented: $navigateToHunterLog) {
            if let manager = activityLogManager {
                ActivityLogView(
                    manager: manager,
                    pendingSpotUserInfo: pendingHunterSpot
                )
                .onDisappear { pendingHunterSpot = nil }
            }
        }
        .navigationDestination(item: $spotlightSession) { session in
            SessionDetailView(session: session)
        }
        .finishSessionDialog(
            session: $sessionToFinish,
            sessionManager: sessionManager,
            onRefresh: { refreshActiveSessions() }
        )
        .deleteSessionDialog(
            session: $sessionToDelete,
            qsoCounts: activeSessionQSOCounts,
            sessionManager: sessionManager,
            onRefresh: { refreshActiveSessions() }
        )
        .onChange(of: pendingHunterSpot?["callsign"] as? String) { _, callsign in
            guard callsign != nil else {
                return
            }
            guard activityLogManager?.activeLog != nil else {
                ToastManager.shared.warning("Set up Hunter Log first")
                pendingHunterSpot = nil
                return
            }
            navigateToHunterLog = true
        }
        .task {
            if activityLogManager == nil {
                activityLogManager = ActivityLogManager(
                    modelContext: modelContext,
                    locationService: locationService
                )
            }
            // `loadActiveLog` defers today's stats; the Hunter Log card reads
            // `todayQSOCount` directly, so populate it here or it shows
            // "No contacts yet today" until the Hunter Log view is opened.
            activityLogManager?.refreshTodayStats()
            if pendingHunterSpot != nil, activityLogManager?.activeLog != nil {
                navigateToHunterLog = true
            }
            refreshActiveSessions()
            loadRecentTemplates()
        }
        .task(id: hasRefreshedProfile) {
            guard !hasRefreshedProfile else {
                return
            }
            hasRefreshedProfile = true
            activityLogManager?.refreshCurrentProfile()
        }
        .task(id: pendingSpotlightSessionID) {
            await consumePendingSpotlightSession()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didLogQSO)
        ) { _ in
            refreshActiveSessions()
            activityLogManager?.refreshTodayStats()
        }
    }

    // MARK: - Continue Section

    private var continueSection: some View {
        Section {
            ForEach(activeSessions, id: \.id) { session in
                ActiveSessionRow(
                    session: session,
                    qsoCount: activeSessionQSOCounts[session.id] ?? 0,
                    onContinue: { sessionManager?.resumeSession(session) },
                    onPause: {
                        sessionManager?.pauseOtherSession(session)
                        refreshActiveSessions()
                    },
                    onFinish: { sessionToFinish = session },
                    onDelete: { sessionToDelete = session }
                )
            }
        } header: {
            Text("Continue")
        }
    }

    // MARK: - Quick Start (Recent + Saved)

    private var quickStartSection: some View {
        Section {
            ForEach(recentTemplates) { template in
                Button {
                    startFromTemplate(template)
                } label: {
                    QuickStartRow(
                        icon: template.activationType.icon,
                        title: template.title,
                        subtitle: template.subtitle
                            .map { "\($0) \u{00B7} \(template.count)×" } ?? "\(template.count)×"
                    )
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        dismissTemplate(template)
                    } label: {
                        Label("Dismiss", systemImage: "trash")
                    }
                }
            }
            ForEach(savedTemplates) { template in
                Button {
                    startFromSavedTemplate(template)
                } label: {
                    QuickStartRow(
                        icon: template.activationType.icon,
                        title: template.name,
                        subtitle: template.subtitle
                    )
                }
                .foregroundStyle(.primary)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteSavedTemplate(template)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("Quick Start")
        }
    }

    // MARK: - Hunter Log Status

    private func hunterLogStatusSection(manager: ActivityLogManager) -> some View {
        Section {
            NavigationLink {
                ActivityLogView(manager: manager)
            } label: {
                HunterLogStatusRow(
                    todayQSOCount: manager.todayQSOCount,
                    todayBandCount: manager.todayBands.count
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Hunter Log")
        }
    }
}

// MARK: - HunterLogStatusRow

/// Compact Hunter Log presence indicator for the intent view. The full stat
/// card lives inside `ActivityLogView`; here we only advertise that a log
/// exists so the main screen stays focused on starting, not reviewing.
private struct HunterLogStatusRow: View {
    let todayQSOCount: Int
    let todayBandCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "binoculars.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hunter Log active")
                    .font(.subheadline.weight(.medium))
                if todayQSOCount > 0 {
                    Text("\(todayQSOCount) today \u{00B7} \(todayBandCount) band\(todayBandCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No contacts yet today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - QuickStartRow

private struct QuickStartRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.secondary)
        }
    }
}
