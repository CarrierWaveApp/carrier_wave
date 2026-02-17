import SwiftData
import SwiftUI

// MARK: - LoggerContainerView

/// Wrapper that provides a two-pane layout on iPad (logger + spots sidebar)
/// and the standard single-column logger on iPhone.
struct LoggerContainerView: View {
    // MARK: Internal

    let tourState: TourState
    let onSessionEnd: (() -> Void)?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    // Sidebar state
    @State private var sidebarTab: SidebarTab = .pota
    @State private var rbnTargetCallsign: String?
    @State private var pendingSpotSelection: SpotSelection?

    // Session info for sidebar (refreshed periodically)
    @State private var sessionCallsign: String?
    @State private var sessionGrid: String?
    @State private var sessionBand: String?
    @State private var sessionMode: String?
    @State private var isPOTAActivation = false

    // MARK: - Layouts

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            LoggerView(
                tourState: tourState,
                onSessionEnd: onSessionEnd,
                onSpotCommand: handleSpotCommand,
                pendingSpotSelection: $pendingSpotSelection
            )

            Divider()

            LoggerSpotsSidebarView(
                selectedTab: $sidebarTab,
                rbnTargetCallsign: $rbnTargetCallsign,
                userCallsign: sessionCallsign,
                userGrid: sessionGrid,
                isPOTAActivation: isPOTAActivation,
                currentBand: sessionBand,
                currentMode: sessionMode,
                onSelectSpot: { selection in
                    pendingSpotSelection = selection
                }
            )
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
        }
    }

    private var iPhoneLayout: some View {
        LoggerView(
            tourState: tourState,
            onSessionEnd: onSessionEnd
        )
    }

    // MARK: - Spot Command Handler

    private func handleSpotCommand(_ action: SpotCommandAction) {
        switch action {
        case .showPOTA:
            sidebarTab = .pota
        case let .showRBN(callsign):
            rbnTargetCallsign = callsign
            sidebarTab = .mySpots
        case .showP2P:
            sidebarTab = .p2p
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
            isPOTAActivation = session.activationType == .pota
        } else {
            // Fallback to defaults when no active session
            sessionCallsign = UserDefaults.standard.string(
                forKey: "loggerDefaultCallsign"
            )
            sessionGrid = UserDefaults.standard.string(
                forKey: "loggerDefaultGrid"
            )
            sessionBand = nil
            sessionMode = nil
            isPOTAActivation = false
        }
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
