import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CommandRowItem + Hunter Log

extension CommandRowItem {
    /// Command-row buttons the Hunter Log can actually run. There is no
    /// session behind the hunter quick log, so the activation-only items
    /// (SPOT, HUNT, P2P, S2S) are left out rather than shown as dead buttons.
    static let hunterLogItems: Set<CommandRowItem> = [.rbn, .solar, .weather, .map, .manual, .help]
}

// MARK: - HunterPanel

/// Panels the Hunter Log presents from the command row or a typed command.
enum HunterPanel: Equatable {
    case rbn(targetCallsign: String?)
    case solar
    case weather
    case map
}

// MARK: - HunterPanelState

/// Which panel the Hunter Log is showing. Mirrors `LoggerView.present(_:)`:
/// panels are mutually exclusive, so presenting one closes the others.
@MainActor
@Observable
final class HunterPanelState {
    // MARK: Internal

    var panel: HunterPanel?

    /// Today's hunter QSOs for the map panel, fetched (bounded) when it opens.
    var mapQSOs: [QSO] = []

    /// The hunter's own callsign for the RBN panel.
    static func callsign(for manager: ActivityLogManager) -> String {
        if let call = manager.activeLog?.myCallsign, !call.isEmpty {
            return call
        }
        return UserDefaults.standard.string(forKey: "loggerDefaultCallsign") ?? "UNKNOWN"
    }

    /// The hunter's grid: the log's current grid (profile or GPS), else the
    /// logger default. `nil` when neither is set.
    static func grid(for manager: ActivityLogManager) -> String? {
        let grid = manager.activeLog?.currentGrid
            ?? UserDefaults.standard.string(forKey: "loggerDefaultGrid")
        return (grid?.isEmpty ?? true) ? nil : grid
    }

    /// Present the panel for a quick-log command. RBN, SOLAR, WX and MAP open
    /// an overlay; MANUAL deep-links into CW Field Guide for the profile's rig.
    func handle(_ command: LoggerCommand, manager: ActivityLogManager) {
        switch command {
        case let .rbn(callsign):
            present(.rbn(targetCallsign: callsign))
        case .solar:
            present(.solar)
        case .weather:
            present(.weather)
        case .map:
            mapQSOs = manager.fetchRecentQSOs(limit: 500)
            if Self.grid(for: manager) == nil {
                ToastManager.shared.warning("Your grid is not set - no arcs will be shown")
            }
            present(.map)
        case .manual:
            openManual(manager: manager)
        default:
            break
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            panel = nil
        }
    }

    // MARK: Private

    private func present(_ next: HunterPanel) {
        withAnimation(.easeOut(duration: 0.2)) {
            panel = next
        }
    }

    /// Mirrors `LoggerView.executeManualCommand`, sourcing the rig from the
    /// active station profile instead of a session.
    private func openManual(manager: ActivityLogManager) {
        guard let radio = manager.currentProfile?.rig, !radio.isEmpty else {
            ToastManager.shared.warning("No radio selected")
            return
        }
        guard FieldGuideLinker.hasManual(for: radio) else {
            ToastManager.shared.warning("No manual found for \(radio)")
            return
        }
        FieldGuideLinker.openManual(for: radio)
    }
}

// MARK: - HunterPanelOverlays

/// Bottom-anchored RBN / Solar / Weather / Map panels for the Hunter Log —
/// the same panel views `LoggerView+Layout.panelOverlays` hosts during an
/// activation, fed from the hunter log instead of a session.
struct HunterPanelOverlays: View {
    // MARK: Internal

    let state: HunterPanelState
    let manager: ActivityLogManager

    var body: some View {
        VStack {
            switch state.panel {
            case let .rbn(target):
                panel {
                    RBNPanelView(
                        callsign: HunterPanelState.callsign(for: manager),
                        targetCallsign: target
                    ) {
                        state.dismiss()
                    }
                }
            case .solar:
                panel {
                    SolarPanelView {
                        state.dismiss()
                    }
                }
            case .weather:
                panel {
                    WeatherPanelView(grid: HunterPanelState.grid(for: manager)) {
                        state.dismiss()
                    }
                }
            case .map:
                panel {
                    SessionMapPanelView(
                        sessionQSOs: state.mapQSOs,
                        myGrid: HunterPanelState.grid(for: manager)
                    ) {
                        state.dismiss()
                    }
                }
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: Private

    private var isPresented: Binding<Bool> {
        Binding(
            get: { state.panel != nil },
            set: { shown in
                if !shown {
                    state.panel = nil
                }
            }
        )
    }

    private func panel(@ViewBuilder _ content: @escaping () -> some View) -> some View {
        SwipeToDismissPanel(isPresented: isPresented, content: content)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
