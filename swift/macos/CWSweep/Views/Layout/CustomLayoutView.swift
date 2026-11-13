import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - CustomLayoutView

/// Renders the active layout from LayoutStore using LayoutRenderer.
/// Handles activator session logic when the layout is activator-style.
struct CustomLayoutView: View {
    // MARK: Internal

    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService

    var body: some View {
        if layoutStore.activeLayout.isActivatorStyle {
            ActivatorLayoutWrapper(
                radioManager: radioManager,
                flexDiscovery: flexDiscovery,
                layout: layoutStore.activeLayout
            )
        } else {
            standardLayout
        }
    }

    // MARK: Private

    @Environment(LayoutStore.self) private var layoutStore
    @Environment(SelectionState.self) private var selectionState

    private var standardLayout: some View {
        LayoutRenderer(
            node: layoutStore.activeLayout.root,
            context: PanelContext(
                radioManager: radioManager,
                flexDiscovery: flexDiscovery
            )
        )
        .task {
            selectionState.availablePanes = layoutStore.activeLayout.orderedPanels
            if let first = selectionState.availablePanes.first {
                selectionState.focusedPane = first
            }
        }
        .onChange(of: layoutStore.activeLayoutId) {
            selectionState.availablePanes = layoutStore.activeLayout.orderedPanels
            if let first = selectionState.availablePanes.first {
                selectionState.focusedPane = first
            }
        }
    }
}

// MARK: - ActivatorLayoutWrapper

/// Wraps a layout with activator session logic: cold-start wizard, session header,
/// and activatorEditMode. Preserves the existing ActivatorLayout behavior.
private struct ActivatorLayoutWrapper: View {
    // MARK: Internal

    let radioManager: RadioManager
    let flexDiscovery: FlexDiscoveryService
    let layout: CustomLayout

    var body: some View {
        Group {
            if activeSession != nil {
                VStack(spacing: 0) {
                    ActivationHeader(onSessionChanged: { await loadActiveSession() })
                    Divider()
                    LayoutRenderer(
                        node: layout.root,
                        context: PanelContext(
                            radioManager: radioManager,
                            flexDiscovery: flexDiscovery,
                            activeSession: activeSession
                        )
                    )
                }
            } else {
                ColdStartView(radioManager: radioManager, onSessionStarted: { session in
                    applySessionFrequency(session)
                    Task { await loadActiveSession() }
                })
            }
        }
        .task {
            selectionState.activatorEditMode = true
            selectionState.availablePanes = layout.orderedPanels
            await loadActiveSession()
        }
        .onDisappear {
            selectionState.activatorEditMode = false
            selectionState.availablePanes = []
        }
        .onChange(of: selectionState.logRemovedQSOId) { _, newId in
            guard newId != nil else {
                return
            }
            activeSession?.decrementQSOCount()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @Environment(SelectionState.self) private var selectionState
    @State private var activeSession: LoggingSession?

    private func loadActiveSession() async {
        let descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active" && session.activationTypeRawValue != "casual"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        activeSession = try? modelContext.fetch(descriptor).first
        if let session = activeSession {
            applySessionFrequency(session)
        }
    }

    private func applySessionFrequency(_ session: LoggingSession) {
        if !radioManager.isConnected {
            if let freq = session.frequency, freq > 0 {
                radioManager.frequency = freq
            }
            if !session.mode.isEmpty {
                radioManager.mode = session.mode
            }
        }
    }
}
