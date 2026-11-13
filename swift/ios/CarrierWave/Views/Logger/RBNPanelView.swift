// RBN Panel View for Logger
//
// Displays combined RBN and POTA spots for a callsign
// with optional mini-map showing spotter locations.
// Supports both modal panel and persistent sidebar layouts.

import CarrierWaveCwFfi
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RBNDisplayMode

/// Controls whether RBN spots are shown as a modal panel or persistent sidebar
enum RBNDisplayMode {
    /// Modal panel with header, dismiss button, rounded styling, height-limited list
    case panel
    /// Embedded inside another card — panel behavior without card chrome (no bg/shadow/clip)
    case embedded
    /// Persistent sidebar with auto-refresh, friend badges, full-height list
    case sidebar
}

// MARK: - RBNPanelView

struct RBNPanelView: View {
    // MARK: Internal

    let displayMode: RBNDisplayMode
    let callsign: String
    let targetCallsign: String?
    var showsCallsignInHeader: Bool = true
    var onDismiss: (() -> Void)?
    var onSelectSpot: ((UnifiedSpot) -> Void)?

    @State var spots: [UnifiedSpot] = []
    @State var isLoading = true
    @State var errorMessage: String?
    // These @State members are internal (not private): the data-loading
    // extension in RBNPanelView+Data.swift reads and writes them.
    @State var showMap: Bool
    @State var targetGrid: String?
    @State var lookbackMinutes: Int = 30

    /// Target-grid lookup only; spot fetching goes through the Rust engine.
    @State var hamDBClient = HamDBClient()

    var displayCallsign: String {
        targetCallsign ?? callsign
    }

    var isPanel: Bool {
        displayMode == .panel || displayMode == .embedded
    }

    var friendCallsigns: Set<String> {
        FriendsSyncService.shared.acceptedFriendCallsigns
    }

    var body: some View {
        content
            .task {
                await loadData()
            }
            .task(id: displayMode == .sidebar ? "auto-refresh" : "none") {
                guard displayMode == .sidebar else {
                    return
                }
                await autoRefreshLoop()
            }
            .onChange(of: targetCallsign) { _, _ in
                guard displayMode == .sidebar else {
                    return
                }
                Task { await loadData() }
            }
    }

    // MARK: Private

    private var hasMappableSpots: Bool {
        spots.contains { $0.spotterGrid != nil }
    }

    private var lookbackOptions: [(minutes: Int, label: String)] {
        [
            (10, "10 min"),
            (30, "30 min"),
            (60, "1 hour"),
            (120, "2 hours"),
            (360, "6 hours"),
        ]
    }

    private var lookbackLabel: String {
        lookbackOptions.first { $0.minutes == lookbackMinutes }?.label
            ?? "\(lookbackMinutes)m"
    }

    private var spotsCountLabel: String {
        spots.count == 1 ? "1 spot" : "\(spots.count) spots"
    }

    private var panelMinHeight: CGFloat? {
        switch displayMode {
        case .panel: 150
        case .embedded: 80
        case .sidebar: nil
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var content: some View {
        let stack = VStack(spacing: 0) {
            if isPanel {
                panelHeader
            } else {
                sidebarHeader
            }
            Divider()
            spotsContent
        }
        switch displayMode {
        case .panel:
            stack
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        case .embedded:
            stack
        case .sidebar:
            stack
        }
    }

    @ViewBuilder
    private var spotsContent: some View {
        let showLoading = isPanel ? isLoading : (isLoading && spots.isEmpty)
        let showError = isPanel
            ? (errorMessage != nil)
            : (errorMessage != nil && spots.isEmpty)

        if showLoading {
            loadingView
        } else if showError {
            errorView(errorMessage ?? "")
        } else if spots.isEmpty {
            emptyView
        } else {
            spotsList
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 8) {
            if showsCallsignInHeader {
                Text(displayCallsign)
                    .font(.headline.monospaced())
            }

            Text(spotsCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            lookbackPicker

            Spacer()

            if hasMappableSpots {
                mapToggleButton
            }

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Refresh spots")

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close")
            }
        }
        .padding(.vertical, displayMode == .embedded ? 8 : 16)
        .padding(.horizontal, displayMode == .embedded ? 0 : 16)
    }

    // MARK: - Sidebar Header

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            if targetCallsign != nil {
                Text(displayCallsign)
                    .font(.caption.weight(.semibold).monospaced())
            }

            Text(spotsCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            lookbackPicker

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            if hasMappableSpots {
                mapToggleButton
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var lookbackPicker: some View {
        Menu {
            ForEach(lookbackOptions, id: \.minutes) { option in
                Button {
                    lookbackMinutes = option.minutes
                    Task { await loadData() }
                } label: {
                    if lookbackMinutes == option.minutes {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            Text(lookbackLabel)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Time range: \(lookbackLabel)")
    }

    private var mapToggleButton: some View {
        Button {
            showMap.toggle()
        } label: {
            Image(systemName: showMap ? "list.bullet" : "map")
                .font(.system(size: isPanel ? 16 : 14))
                .frame(minWidth: isPanel ? 44 : nil, minHeight: isPanel ? 44 : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Toggle map view")
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading spots...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: panelMinHeight, maxHeight: isPanel ? nil : .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots for \(displayCallsign)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if targetCallsign == nil {
                Text("Start transmitting to be spotted!")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: panelMinHeight, maxHeight: isPanel ? nil : .infinity)
    }

    @ViewBuilder
    private var spotsList: some View {
        if showMap {
            SpotsMiniMapView(
                spots: spots,
                targetCallsign: displayCallsign,
                targetGrid: targetGrid
            )
            .frame(height: 200)
        } else {
            spotsListContent
        }
    }

    private var spotsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(spots) { spot in
                    if isPanel {
                        spotRow(spot)
                    } else {
                        Button {
                            onSelectSpot?(spot)
                        } label: {
                            spotRow(spot)
                        }
                        .buttonStyle(.plain)
                    }
                    if spot.id != spots.last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .frame(maxHeight: isPanel ? 250 : .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadData() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: panelMinHeight, maxHeight: isPanel ? nil : .infinity)
    }
}

// MARK: - RBNPanelView + Init Helpers

extension RBNPanelView {
    /// Convenience init for panel mode (backwards compatible)
    init(
        callsign: String,
        targetCallsign: String?,
        showsCallsignInHeader: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) {
        displayMode = .panel
        self.callsign = callsign
        self.targetCallsign = targetCallsign
        self.showsCallsignInHeader = showsCallsignInHeader
        self.onDismiss = onDismiss
        onSelectSpot = nil
        _showMap = State(initialValue: true)
    }

    /// Convenience init for embedded mode (inside another card, no card chrome)
    init(
        embeddedCallsign: String,
        targetCallsign: String?,
        showsCallsignInHeader: Bool = true
    ) {
        displayMode = .embedded
        callsign = embeddedCallsign
        self.targetCallsign = targetCallsign
        self.showsCallsignInHeader = showsCallsignInHeader
        onDismiss = nil
        onSelectSpot = nil
        _showMap = State(initialValue: true)
    }

    /// Convenience init for sidebar mode
    init(
        sidebarCallsign: String,
        targetCallsign: String?,
        onSelectSpot: @escaping (UnifiedSpot) -> Void
    ) {
        displayMode = .sidebar
        callsign = sidebarCallsign
        self.targetCallsign = targetCallsign
        onDismiss = nil
        self.onSelectSpot = onSelectSpot
        _showMap = State(initialValue: false)
    }
}

#Preview {
    RBNPanelView(callsign: "W1AW", targetCallsign: nil) {}
        .padding()
}
