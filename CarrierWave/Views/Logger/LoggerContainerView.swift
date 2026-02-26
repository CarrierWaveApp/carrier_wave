import SwiftData
import SwiftUI

// MARK: - LoggerContainerView

/// Wrapper that provides a two-pane layout on iPad (logger + spots sidebar)
/// and the standard single-column logger on iPhone.
struct LoggerContainerView: View {
    // MARK: Internal

    let tourState: TourState
    let sessionManager: LoggingSessionManager?
    let onSessionEnd: (() -> Void)?

    var body: some View {
        Group {
            if (lockedSizeClass ?? horizontalSizeClass) == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .onAppear {
            if lockedSizeClass == nil {
                lockedSizeClass = horizontalSizeClass
            }
        }
        .task {
            await refreshSessionInfo()
        }
        .task(id: "session-poll") {
            await sessionPollLoop()
        }
    }

    // MARK: Private

    /// Locked layout mode — set once on first appearance, never changes.
    /// Prevents size class transitions (e.g., rotation on iPhone Max)
    /// from destroying the entire view hierarchy and resetting @State.
    @State private var lockedSizeClass: UserInterfaceSizeClass?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    // Sidebar state
    @State private var sidebarTab: SidebarTab = .hunt
    @State private var rbnTargetCallsign: String?
    @State private var pendingSpotSelection: SpotSelection?

    // Session info for sidebar (refreshed periodically)
    @State private var sessionCallsign: String?
    @State private var sessionGrid: String?
    @State private var sessionBand: String?
    @State private var sessionMode: String?
    @State private var isPOTAActivation = false

    // Map data for sidebar
    @State private var sessionQSOs: [QSO] = []
    @State private var roveStops: [RoveStop] = []

    // Resizable sidebar — GestureState for flicker-free live dragging
    @AppStorage("iPadSidebarWidth") private var persistedSidebarWidth: Double = 340
    @GestureState private var dragOffset: CGFloat = 0

    // MARK: - Layouts

    private var effectiveSidebarWidth: CGFloat {
        let raw = CGFloat(persistedSidebarWidth) - dragOffset
        return min(max(raw, 280), 600)
    }

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            LoggerView(
                tourState: tourState,
                sessionManager: sessionManager,
                onSessionEnd: onSessionEnd,
                onSpotCommand: handleSpotCommand,
                pendingSpotSelection: $pendingSpotSelection
            )

            dragHandle

            LoggerSpotsSidebarView(
                selectedTab: $sidebarTab,
                rbnTargetCallsign: $rbnTargetCallsign,
                userCallsign: sessionCallsign,
                userGrid: sessionGrid,
                isPOTAActivation: isPOTAActivation,
                currentBand: sessionBand,
                currentMode: sessionMode,
                sessionQSOs: sessionQSOs,
                roveStops: roveStops,
                onSelectSpot: { selection in
                    pendingSpotSelection = selection
                }
            )
            .frame(width: effectiveSidebarWidth)
        }
    }

    private var iPhoneLayout: some View {
        LoggerView(
            tourState: tourState,
            sessionManager: sessionManager,
            onSessionEnd: onSessionEnd
        )
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Rectangle()
            .fill(dragOffset != 0 ? Color.accentColor : Color(.separator))
            .frame(width: 4)
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating($dragOffset) { value, state, transaction in
                        transaction.disablesAnimations = true
                        state = value.translation.width
                    }
                    .onEnded { value in
                        let newWidth = CGFloat(persistedSidebarWidth) - value.translation.width
                        persistedSidebarWidth = Double(min(max(newWidth, 280), 600))
                    }
            )
    }

    // MARK: - Spot Command Handler

    private func handleSpotCommand(_ action: SpotCommandAction) {
        switch action {
        case .showHunt:
            sidebarTab = .hunt
        case let .showRBN(callsign):
            rbnTargetCallsign = callsign
            sidebarTab = .mySpots
        case .showP2P:
            sidebarTab = .p2p
        case .showMap:
            sidebarTab = .map
        }
    }

    // MARK: - Session Info

    private func refreshSessionInfo() async {
        let container = modelContext.container
        let context = ModelContext(container)

        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let session = try? context.fetch(descriptor).first {
            sessionCallsign = session.myCallsign
            sessionGrid = session.myGrid
            sessionBand = session.band
            sessionMode = session.mode
            isPOTAActivation = session.isPOTA
            roveStops = session.roveStops
            // Session state tracked by SessionsTabView

            // Fetch QSOs for the map sidebar tab
            refreshSessionQSOs(sessionId: session.id, context: context)
        } else {
            sessionCallsign = UserDefaults.standard.string(
                forKey: "loggerDefaultCallsign"
            )
            sessionGrid = UserDefaults.standard.string(
                forKey: "loggerDefaultGrid"
            )
            sessionBand = nil
            sessionMode = nil
            isPOTAActivation = false
            sessionQSOs = []
            roveStops = []
            // Session state tracked by SessionsTabView
        }
    }

    private func refreshSessionQSOs(sessionId: UUID, context: ModelContext) {
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.loggingSessionId == sessionId && !qso.isHidden
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500

        sessionQSOs = (try? context.fetch(descriptor)) ?? []
    }

    private func sessionPollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else {
                return
            }
            await refreshSessionInfo()
        }
    }
}
