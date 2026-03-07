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
            }
            .task {
                clusterManager.spotAggregator = spotAggregator
                spotAggregator.userCallsign = myCallsign
                spotAggregator.userGrid = myGrid
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
                await radioManager.autoConnect(
                    ports: ports,
                    defaultRadioModel: defaultRadioModel,
                    defaultBaudRate: defaultBaudRate
                )
                await winKeyerManager.autoConnect(ports: ports)
            }
            .onChange(of: myCallsign) { _, newValue in
                spotAggregator.userCallsign = newValue
            }
            .onChange(of: myGrid) { _, newValue in
                spotAggregator.userGrid = newValue
            }
            // Global keyboard shortcuts
            .keyboardShortcut("1", modifiers: .command) { activeRole = .contester }
            .keyboardShortcut("2", modifiers: .command) { activeRole = .hunter }
            .keyboardShortcut("3", modifiers: .command) { activeRole = .activator }
            .keyboardShortcut("4", modifiers: .command) { activeRole = .dxer }
            .keyboardShortcut("5", modifiers: .command) { activeRole = .casual }
    }

    // MARK: Private

    @State private var selectedItem: SidebarItem? = .logger
    @State private var activeRole: OperatingRole = .casual
    @State private var showInspector = false
    @State private var showCommandPalette = false
    @State private var showRadioPalette = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.modelContext) private var modelContext
    @State private var radioManager = RadioManager()
    @State private var portMonitor = SerialPortMonitor()
    @State private var spotAggregator = SpotAggregator()
    @State private var clusterManager = ClusterManager()
    @State private var contestManager = ContestManager()
    @State private var interopManager = InteropManager()
    @State private var tuneInManager = TuneInManager()
    @State private var selectionState = SelectionState()
    @State private var winKeyerManager = WinKeyerManager()
    @State private var showContestSetup = false
    @AppStorage("myCallsign") private var myCallsign = ""
    @AppStorage("myGrid") private var myGrid = ""
    @AppStorage("defaultRadioModel") private var defaultRadioModel = "ic7300"
    @AppStorage("defaultBaudRate") private var defaultBaudRate = 19_200
    @State private var locationResolver = LocationGridResolver()

    private var cloudSyncService = CloudSyncService.shared

    // MARK: - View Composition

    private var configuredView: some View {
        coreLayout
            .environment(radioManager)
            .environment(portMonitor)
            .environment(spotAggregator)
            .environment(clusterManager)
            .environment(contestManager)
            .environment(interopManager)
            .environment(tuneInManager)
            .environment(selectionState)
            .environment(winKeyerManager)
            // CloudSyncService is a singleton accessed directly by views
            .focusedSceneValue(\.toggleInspector, ToggleInspectorAction {
                showInspector.toggle()
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
            .focusedSceneValue(\.disconnectRadio, DisconnectRadioAction {
                Task { await radioManager.disconnectAll() }
            })
            .focusedSceneValue(\.showContestSetup, ShowContestSetupAction {
                showContestSetup = true
            })
            .focusedSceneValue(\.contestManager, contestManager)
            .focusedSceneValue(\.tuneInManager, tuneInManager)
            .focusedSceneValue(\.disconnectSDR, DisconnectSDRAction {
                Task { await tuneInManager.stop() }
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
                        activeRole: activeRole,
                        radioManager: radioManager
                    )

                    StatusBarView(radioManager: radioManager)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    Divider()
                    InspectorView()
                        .frame(width: 300)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showInspector)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if selectedItem == .logger {
                    RolePicker(activeRole: $activeRole)
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                RadioToolbarItem(radioManager: radioManager)

                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .accessibilityLabel("Toggle Inspector")
                .help("Toggle Inspector")
            }
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView()
        }
        .sheet(isPresented: $showRadioPalette) {
            RadioPaletteView()
        }
        .sheet(isPresented: $showContestSetup) {
            ContestSetupView(contestManager: contestManager)
        }
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

// MARK: - RolePicker

struct RolePicker: View {
    @Binding var activeRole: OperatingRole

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OperatingRole.allCases) { role in
                Button {
                    activeRole = role
                } label: {
                    Image(systemName: role.icon)
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(activeRole == role ? .primary : .secondary)
                .background(
                    activeRole == role
                        ? RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                        : nil
                )
                .help(role.displayName)

                if role != OperatingRole.allCases.last {
                    Divider().frame(height: 16).padding(.horizontal, 2)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.bar, in: RoundedRectangle(cornerRadius: 6))
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
