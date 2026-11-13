import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - WorkspaceView

/// Root workspace view with NavigationSplitView: Sidebar | Content | Inspector
struct WorkspaceView: View {
    // MARK: Internal

    var body: some View {
        configuredView
            .onAppear {
                portMonitor.startMonitoring()
                flexDiscovery.startListening()
            }
            .task {
                if sessionManager == nil {
                    sessionManager = MacSessionManager(modelContext: modelContext)
                }
                sessionManager?.refresh()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didChangeLoggingSession)
            ) { _ in
                sessionManager?.refresh()
            }
            .task {
                vimEngine.executor = VimActionExecutor(
                    selectionState: selectionState,
                    radioManager: radioManager,
                    spotAggregator: spotAggregator,
                    winKeyer: winKeyerManager,
                    spotService: spotService,
                    modelContext: modelContext
                )
                clusterManager.spotAggregator = spotAggregator
                spotAggregator.userCallsign = myCallsign
                spotAggregator.userGrid = myGrid

                // Load DXCC entity database and wire into spot enrichment
                await dxccLookup.loadIfNeeded()
                spotAggregator.dxccLookup = dxccLookup

                // Load worked entities for needed indicators
                await neededChecker.loadWorkedEntities(
                    container: modelContext.container
                )
                spotAggregator.neededChecker = neededChecker

                // Load SKCC roster so spots are enriched with member badges.
                Task.detached(priority: .background) {
                    await SKCCMembershipStore.shared.ensureLoaded()
                }

                spotAggregator.startPolling()

                // Auto-detect grid from device location if not set
                if myGrid.isEmpty {
                    if let grid = await locationResolver.resolveGrid() {
                        myGrid = grid
                        spotAggregator.userGrid = grid
                    }
                }

                // Auto-reconnect to last-used devices by fingerprint
                let ports = portMonitor.availablePorts
                await radioManager.autoConnect(ports: ports)
                await winKeyerManager.autoConnect(ports: ports)
            }
            .onChange(of: myCallsign) { _, newValue in
                spotAggregator.userCallsign = newValue
            }
            .onChange(of: myGrid) { _, newValue in
                spotAggregator.userGrid = newValue
            }
            .onChange(of: showCommandPalette) { _, newValue in
                vimEngine.isPaletteActive = newValue
            }
            .onChange(of: showRadioPalette) { _, newValue in
                vimEngine.isPaletteActive = newValue
            }
            // Vim search: update filter live as user types in search mode
            .onChange(of: vimEngine.searchText) { _, newText in
                guard vimEngine.mode == .search else {
                    return
                }
                selectionState.vimFilterResult = newText.isEmpty ? nil : VimFilterParser.parse(newText)
            }
            // Vim search: clear filter when escaping search mode (searchText will be "")
            .onChange(of: vimEngine.mode) { oldMode, newMode in
                if oldMode == .search, newMode == .normal, vimEngine.searchText.isEmpty {
                    selectionState.vimFilterResult = nil
                }
                if showVimHelp {
                    showVimHelp = false
                }
            }
            .onChange(of: vimEngine.shouldShowHelp) { _, newValue in
                if newValue {
                    showVimHelp = true
                    vimEngine.shouldShowHelp = false
                }
            }
            .onChange(of: vimModeEnabled) { _, newValue in
                vimEngine.isEnabled = newValue
            }
            // Vim requests that need workspace state; handlers are shared with the palette.
            .modifier(VimWorkspaceBridge(
                selectionState: selectionState,
                onNavigate: { selectedItem = $0 },
                onSetRole: applyRole,
                onToggleInspector: { vimInspectorVisible.toggle() },
                onDeleteQSO: deleteSelectedQSO
            ))
            // Global keyboard shortcuts for layout switching
            .keyboardShortcut("1", modifiers: .command) { switchToLayout(index: 0) }
            .keyboardShortcut("2", modifiers: .command) { switchToLayout(index: 1) }
            .keyboardShortcut("3", modifiers: .command) { switchToLayout(index: 2) }
    }

    // MARK: Private

    @State private var selectedItem: SidebarItem? = .logger
    @State private var showCommandPalette = false
    @State private var showRadioPalette = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(RadioManager.self) private var radioManager
    @Environment(SerialPortMonitor.self) private var portMonitor
    @Environment(SpotAggregator.self) private var spotAggregator
    @Environment(DXCCLookupService.self) private var dxccLookup
    @Environment(DXCCNeededChecker.self) private var neededChecker
    @Environment(ClusterManager.self) private var clusterManager
    @Environment(LayoutStore.self) private var layoutStore
    @Environment(SelectionState.self) private var selectionState
    @Environment(WinKeyerManager.self) private var winKeyerManager
    @State private var flexDiscovery = FlexDiscoveryService()
    @State private var sessionManager: MacSessionManager?
    @Environment(POTASpotService.self) private var spotService
    @State private var showImportADIF = false
    @State private var showExportADIF = false
    @State private var showVimHelp = false
    @State private var showLayoutEditor = false
    @State private var vimInspectorVisible = false
    @AppStorage("myCallsign") private var myCallsign = ""
    @AppStorage("myGrid") private var myGrid = ""
    @AppStorage("vimModeEnabled") private var vimModeEnabled = false
    @State private var locationResolver = LocationGridResolver()
    @Environment(VimEngine.self) private var vimEngine

    // MARK: - View Composition

    private var configuredView: some View {
        coreLayout
            .overlay(alignment: .bottom) {
                if vimEngine.isEnabled,
                   vimEngine.mode == .command || vimEngine.mode == .search
                {
                    VimCommandLine()
                }
            }
            .overlay {
                if showVimHelp {
                    VimHelpOverlay(mode: vimEngine.mode)
                        .onTapGesture { showVimHelp = false }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusEntryField)) { _ in
                selectedItem = .logger
                selectionState.requestEntryFocus = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSatellites)) { _ in
                selectedItem = .satellites
            }
            .trackerDetectedAlert()
            .focusedSceneValue(\.toggleInspector, ToggleInspectorAction {
                if selectionState.selectedQSOId != nil {
                    selectionState.selectedQSOId = nil
                }
            })
            .focusedSceneValue(\.showCommandPalette, ShowCommandPaletteAction {
                showCommandPalette = true
            })
            .focusedSceneValue(\.showRadioPalette, ShowRadioPaletteAction {
                showRadioPalette = true
            })
            .focusedSceneValue(\.radioManager, radioManager)
            .focusedSceneValue(\.spotAggregator, spotAggregator)
            .focusedSceneValue(\.refreshSpots, RefreshSpotsAction {
                Task { await spotAggregator.refresh() }
            })
            .focusedSceneValue(\.toggleCluster, ToggleClusterAction {
                if clusterManager.isConnected {
                    clusterManager.disconnect()
                }
            })
            .focusedSceneValue(\.connectRadio, ConnectRadioAction {
                // Connection setup lives in the Radio section
                selectedItem = .radio
            })
            .focusedSceneValue(\.disconnectRadio, DisconnectRadioAction {
                Task { await radioManager.disconnectAll() }
            })
            .focusedSceneValue(\.openQSOEntry, OpenQSOEntryAction {
                openQSOEntryWindow()
            })
            .focusedSceneValue(\.showImportADIF, ShowImportADIFAction {
                showImportADIF = true
            })
            .focusedSceneValue(\.showExportADIF, ShowExportADIFAction {
                showExportADIF = true
            })
            // Self-spot entry point shared by the radio palette's `SPOT [comment]`,
            // the Activation menu's "Spot Now", and vim `:spot [comment]`.
            .focusedSceneValue(\.spotNow, SpotNowAction { comment in
                Task { try? await spotService.postCurrentSpot(overrideComment: comment) }
            })
    }

    private var coreLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedItem: $selectedItem)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ContentAreaView(
                        selectedItem: selectedItem ?? .logger,
                        radioManager: radioManager,
                        flexDiscovery: flexDiscovery
                    )

                    StatusBarView(radioManager: radioManager)
                }
                .frame(minWidth: 800, maxWidth: .infinity, maxHeight: .infinity)

                if vimInspectorVisible ||
                    (!vimEngine
                        .isEnabled && (selectionState.selectedQSOId != nil || selectionState.selectedSpot != nil))
                {
                    Divider()
                    InspectorView()
                        .frame(width: 280)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vimInspectorVisible)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if selectedItem == .logger {
                    LayoutPicker(layoutStore: layoutStore, showEditor: $showLayoutEditor)
                    if let sessionManager {
                        SessionToolbarControl(sessionManager: sessionManager)
                    }
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                RadioToolbarItem(radioManager: radioManager)
            }
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(
                onSwitchToRadioPalette: {
                    showCommandPalette = false
                    showRadioPalette = true
                },
                onSelectSidebarItem: { item in
                    selectedItem = item
                },
                onSetRole: { role in
                    applyRole(role)
                },
                onSwitchLayout: { layout in
                    layoutStore.setActiveLayout(layout)
                },
                onToggleInspector: {
                    if selectionState.selectedQSOId != nil {
                        selectionState.selectedQSOId = nil
                    }
                },
                hasActiveSession: sessionManager?.activeSession != nil,
                onEndSession: {
                    if let session = sessionManager?.activeSession {
                        sessionManager?.finishSession(session)
                    }
                },
                onPauseSession: {
                    sessionManager?.pauseSession()
                }
            )
        }
        .sheet(isPresented: $showRadioPalette) {
            RadioPaletteView(onSwitchToAppPalette: {
                showRadioPalette = false
                showCommandPalette = true
            })
        }
        .sheet(isPresented: $showImportADIF) {
            ADIFImportSheet()
        }
        .sheet(isPresented: $showLayoutEditor) {
            LayoutEditorView(layoutStore: layoutStore)
        }
        .sheet(isPresented: $showExportADIF) {
            ADIFExportSheet()
        }
    }

    private func openQSOEntryWindow() {
        openWindow(id: "qso-entry")
    }

    private func switchToLayout(index: Int) {
        let layouts = layoutStore.allLayouts
        guard index < layouts.count else {
            return
        }
        layoutStore.setActiveLayout(layouts[index])
    }

    /// Role → layout preset. Shared by the command palette's role rows and
    /// the vim `:role <name>` command.
    private func applyRole(_ role: OperatingRole) {
        switch role {
        case .hunter:
            layoutStore.setActiveLayout(CustomLayout.hunterPreset)
        case .activator:
            layoutStore.setActiveLayout(CustomLayout.activatorPreset)
        }
    }

    private func deleteSelectedQSO() {
        guard let qsoId = selectionState.selectedQSOId,
              CwStoreSeams.hideQSO(id: qsoId, in: modelContext)
        else {
            return
        }
        selectionState.logRemovedQSOId = qsoId
        selectionState.selectedQSOId = nil
    }
}

// MARK: - Keyboard Shortcut Extension

extension View {
    func keyboardShortcut(
        _ key: KeyEquivalent,
        modifiers: EventModifiers = .command,
        action: @escaping () -> Void
    ) -> some View {
        background(
            Button("") { action() }
                .keyboardShortcut(key, modifiers: modifiers)
                .hidden()
                .accessibilityHidden(true)
        )
    }
}

// MARK: - RadioToolbarItem

struct RadioToolbarItem: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        if radioManager.isConnected {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text(formatFrequency(radioManager.frequency))
                    .monospacedDigit()
                Text(radioManager.mode)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        } else {
            Label("No Radio", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private func formatFrequency(_ mhz: Double) -> String {
        guard mhz > 0 else {
            return "—"
        }
        return String(format: "%.3f MHz", mhz)
    }
}
