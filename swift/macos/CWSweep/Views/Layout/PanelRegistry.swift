import CarrierWaveData
import SwiftUI

// MARK: - PanelContext

/// Dependencies needed by panels, passed through the layout renderer.
struct PanelContext {
    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService
    var activeSession: LoggingSession?
    /// Live contest state when a contest session is active. Contest panels
    /// (`contestScore`, `contestEntry`, …) render a placeholder when nil so
    /// the layout still shows their slots outside contest mode.
    var contestManager: ContestManager?
    var contestDefinition: ContestDefinition?
}

// MARK: - PanelRegistry

/// Maps PanelIdentifier to concrete SwiftUI views.
/// Uses AnyView to type-erase the 12-branch switch — without this,
/// the recursive LayoutRenderer causes exponential type-checker blowup.
enum PanelRegistry {
    // MARK: Internal

    @MainActor
    static func view(for panel: PanelIdentifier, context: PanelContext) -> AnyView {
        if let view = bandScopePanel(for: panel) {
            return view
        }
        return otherPanel(for: panel, context: context)
    }

    // MARK: Private

    @MainActor
    private static func bandScopePanel(for panel: PanelIdentifier) -> AnyView? {
        switch panel {
        case .bandScope: AnyView(BandScopeContainerView()) // legacy
        case .bandScopeSingle: AnyView(ContestBandScopeView(showSummaryBar: true))
        case .bandScopeHybrid: AnyView(BandScopeHybridPane())
        case .bandScopeStacked: AnyView(StackedBandScopeView())
        case .bandScopeGrid: AnyView(GridBandOverviewView())
        default: nil
        }
    }

    @MainActor
    private static func otherPanel(for panel: PanelIdentifier, context: PanelContext) -> AnyView {
        switch panel {
        case .spotList: AnyView(SpotListView())
        case .qsoLog: qsoLogPanel(context: context)
        case .qsoMap: AnyView(QSOMapView())
        case .cluster: AnyView(ClusterView())
        case .dashboard: AnyView(DashboardView())
        case .waterfall: AnyView(WaterfallPanel(radioManager: context.radioManager))
        case .activationMap: AnyView(ActivationMapPane(sessionId: context.activeSession?.id))
        case .radioControl: radioControlPanel(context: context)
        case .winKeyer: AnyView(KeyerControlView())
        case .dxccTracking: AnyView(DXCCTrackingView())
        case .propagation: AnyView(placeholderPanel(title: "Propagation", icon: "sun.max"))
        case .spaceWeather: AnyView(placeholderPanel(title: "Space Weather", icon: "sparkles"))
        case .spotDetail: AnyView(SpotDetailPane())
        case .jttyTerminal: AnyView(JttyTerminalPanel())
        case .contestScore,
             .contestEntry,
             .contestBandBreakdown,
             .contestRecent:
            contestPanel(panel, context: context)
        case .bandScope,
             .bandScopeSingle,
             .bandScopeHybrid,
             .bandScopeStacked,
             .bandScopeGrid:
            // Handled in `bandScopePanel(for:)`; bandScope cases reach
            // here only if the dispatch table is misconfigured.
            AnyView(EmptyView())
        }
    }

    @MainActor
    private static func contestPanel(_ kind: PanelIdentifier, context: PanelContext) -> AnyView {
        guard let manager = context.contestManager, let definition = context.contestDefinition else {
            return AnyView(ContestPanelPlaceholder(kind: kind))
        }
        switch kind {
        case .contestScore:
            return AnyView(
                ContestScorePanel(manager: manager, definition: definition)
                    .frame(minWidth: 420)
            )
        case .contestEntry:
            // Reuse ParsedEntryView so the contest entry bar is the same
            // single-line quick-entry the rest of the app uses, augmented
            // with contest exchange parsing + dupe/macro chrome.
            return AnyView(
                ParsedEntryView(
                    radioManager: context.radioManager,
                    activeSession: context.activeSession,
                    contestManager: manager,
                    contestDefinition: definition
                )
                .padding()
            )
        case .contestBandBreakdown:
            return AnyView(ContestBandBreakdownPanel(manager: manager, definition: definition))
        case .contestRecent:
            return AnyView(ContestRecentQSOsPanel(manager: manager))
        default:
            return AnyView(EmptyView())
        }
    }

    @MainActor
    private static func qsoLogPanel(context: PanelContext) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                ParsedEntryView(
                    radioManager: context.radioManager,
                    activeSession: context.activeSession,
                    contestManager: context.contestManager,
                    contestDefinition: context.contestDefinition
                )
                .padding()
                Divider()
                QSOLogTableView(sessionId: context.activeSession?.id)
            }
        )
    }

    @MainActor
    private static func radioControlPanel(context: PanelContext) -> AnyView {
        AnyView(
            RadioControlView(
                radioManager: context.radioManager,
                flexDiscovery: context.flexDiscovery
            )
        )
    }

    private static func placeholderPanel(title: String, icon: String) -> some View {
        PlaceholderView(title: title, icon: icon, description: "Available during activations")
    }
}
