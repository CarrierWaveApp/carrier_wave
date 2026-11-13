import CarrierWaveData
import SwiftUI

// MARK: - SatelliteRotatorSheet

/// Rotator & trackers: sweep the LAN for CSN S.A.T. trackers, WA4MCM PSR-100
/// rotors and `rotctld` servers (or add one by address), link one, watch its
/// reported az/el against the selected satellite's target, and turn Follow on
/// to let the antenna move. Everything drives `SatelliteRotatorService.shared`.
struct SatelliteRotatorSheet: View {
    // MARK: Internal

    let model: SatelliteTrackerModel

    var body: some View {
        NavigationStack {
            Form {
                trackersSection
                RotatorSection(model: model, service: service)
                if service.rotator.isConnected {
                    Section {
                        RotatorManualControls(
                            rotator: service.rotator,
                            target: service.desiredTarget,
                            targetSource: service.desiredTargetSource
                        )
                    } header: {
                        Text("Manual control")
                    } footer: {
                        Text("Jogging or going to a position turns Follow off; turn it back on to resume tracking.")
                    }
                }
            }
            .navigationTitle("Rotator & Trackers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var service = SatelliteRotatorService.shared
    @State private var manualHost = ""
    @State private var isIdentifying = false
    @State private var identifyFailedHost: String?

    private var discovery: TrackerDiscoveryService {
        service.discovery
    }

    private var trimmedManualHost: String {
        manualHost.trimmingCharacters(in: .whitespaces)
    }

    private var trackersSection: some View {
        Section {
            Toggle("Detect trackers automatically", isOn: Binding(
                get: { service.autoDetect.isEnabled },
                set: { service.autoDetect.isEnabled = $0 }
            ))
            scanRow
            if discovery.discovered.isEmpty, !discovery.isScanning, discovery.lastScanAt != nil {
                Text("No trackers found")
                    .foregroundStyle(.secondary)
            }
            ForEach(discovery.discovered) { tracker in
                trackerRow(tracker)
            }
            manualAddRow
        } header: {
            Text("Trackers on this network")
        } footer: {
            trackersFooter
        }
    }

    private var scanRow: some View {
        HStack {
            if discovery.isScanning {
                ProgressView()
                Text("Scanning…")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await discovery.scan() }
                } label: {
                    Label(
                        discovery.lastScanAt == nil ? "Scan network" : "Scan again",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var manualAddRow: some View {
        HStack(spacing: 8) {
            TextField("Address or network (192.168.20.0/24)", text: $manualHost)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(addManual)
            if isIdentifying {
                ProgressView()
            } else {
                Button("Add", action: addManual)
                    .buttonStyle(.bordered)
                    .disabled(trimmedManualHost.isEmpty)
            }
        }
        if let failed = identifyFailedHost {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing answered at \(failed). Add it anyway as:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(TrackerKind.allCases) { kind in
                        Button(kind.shortLabel) {
                            discovery.addManual(host: failed, kind: kind)
                            identifyFailedHost = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        if !discovery.extraNetworks.isEmpty {
            ForEach(discovery.extraNetworks, id: \.self) { cidr in
                HStack {
                    Label(cidr, systemImage: "network")
                        .font(.caption)
                        .monospacedDigit()
                    Spacer()
                    Button("Stop sweeping") {
                        discovery.removeNetwork(cidr)
                    }
                    .font(.caption)
                }
            }
        }
        if !service.autoDetect.ignoredHosts.isEmpty {
            Button("Stop ignoring \(service.autoDetect.ignoredHosts.count) device(s)") {
                service.autoDetect.clearIgnored()
            }
            .font(.caption)
        }
    }

    private var trackersFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = discovery.lastError {
                Text(error)
                    .foregroundStyle(.red)
            }
            if discovery.scannedNetworks.isEmpty {
                Text(
                    "Sweeps every Wi-Fi/Ethernet subnet this device is on for a S.A.T. (rotctld 4533 + web UI), "
                        + "a PSR-100 (web UI :8080, UDP 2390) or a rotctld server. "
                        + "Add a unit by address (or its network as 192.168.20.0/24) if it lives on another VLAN; it is remembered and swept automatically from then on."
                )
            } else {
                Text("Swept \(discovery.scannedNetworks.joined(separator: ", "))"
                    + (discovery.lastScanAt.map { " · \($0.formatted(.relative(presentation: .named)))" } ?? ""))
            }
        }
    }

    private func trackerRow(_ tracker: DiscoveredTracker) -> some View {
        let isLinked = service.rotator.endpoint == tracker.endpoint
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tracker.name)
                    .font(.body.weight(.semibold))
                Text(tracker.detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            TrackerKindBadge(kind: tracker.kind)
            if isLinked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Connected")
            } else {
                Button("Connect") {
                    Task { await service.connect(to: tracker.endpoint, model: model) }
                }
                .buttonStyle(.bordered)
                .disabled(service.rotator.state == .connecting)
            }
        }
    }

    /// Probe the address and let the device say what it is; only when
    /// nothing answers do we offer to add it by type. A network such as
    /// "192.168.20.0/24" is added to every future sweep instead.
    private func addManual() {
        let host = trimmedManualHost
        guard !host.isEmpty, !isIdentifying else {
            return
        }
        if host.contains("/") {
            if discovery.addNetwork(host) != nil {
                manualHost = ""
                identifyFailedHost = nil
                Task { await service.autoDetect.sweepNow() }
            } else {
                identifyFailedHost = host
            }
            return
        }
        isIdentifying = true
        identifyFailedHost = nil
        Task {
            let found = await discovery.identify(host: host)
            isIdentifying = false
            if found != nil {
                manualHost = ""
            } else {
                identifyFailedHost = host
            }
        }
    }
}

// MARK: - TrackerKindBadge

/// Compact kind chip on a discovered-tracker row, in the app's capsule
/// badge convention.
private struct TrackerKindBadge: View {
    let kind: TrackerKind

    var body: some View {
        Text(kind.shortLabel)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - RotatorSection

/// The linked rotator: state, reported vs target az/el, pointing error,
/// Follow toggle, Park/Stop, elevation floor, web UI link, disconnect/forget.
private struct RotatorSection: View {
    // MARK: Internal

    let model: SatelliteTrackerModel
    let service: SatelliteRotatorService

    var body: some View {
        Section {
            if let endpoint = rotator.endpoint {
                linkedRows(endpoint)
            } else if let saved = rotator.savedEndpoint {
                savedRows(saved)
            } else {
                Text("Connect a tracker above to drive it from the selected satellite.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Rotator")
        } footer: {
            if rotator.endpoint != nil {
                Text(
                    "Follow sends the selected satellite's az/el once a second while it is up, and parks the "
                        + "antenna at the rise azimuth five minutes before the next pass."
                )
            }
        }
    }

    // MARK: Private

    private var rotator: RotatorController {
        service.rotator
    }

    private var stateColor: Color {
        switch rotator.state {
        case .disconnected: .secondary
        case .connecting: .orange
        case .idle: .primary
        case .following: .green
        case .error: .red
        }
    }

    private var followBinding: Binding<Bool> {
        Binding(
            get: { service.isFollowing },
            set: { enabled in
                if enabled {
                    service.start(model: model)
                    Task { await rotator.startFollowing() }
                } else {
                    rotator.stopFollowing()
                }
            }
        )
    }

    private var minElevationBinding: Binding<Double> {
        Binding(
            get: { rotator.minElevationDeg },
            set: { rotator.minElevationDeg = $0 }
        )
    }

    /// The pointing Follow would send right now, with where it comes from.
    private var desiredTargetRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Satellite")
                Spacer()
                Text(service.desiredTarget
                    .map { String(format: "%03.0f° / %.0f°", $0.azimuthDeg, $0.elevationDeg) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(service.desiredTarget == nil ? .secondary : .primary)
            }
            Text(service.desiredTargetSource)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func linkedRows(_ endpoint: TrackerEndpoint) -> some View {
        LabeledContent("Unit", value: "\(endpoint.kind.displayName) · \(endpoint.host)")
        LabeledContent("Protocol", value: endpoint.protocolKind.displayName)
        LabeledContent("Status") {
            Text(rotator.state.label)
                .foregroundStyle(stateColor)
        }
        positionRow("Reported", rotator.position)
        positionRow("Commanded", rotator.commandedTarget)
        desiredTargetRow
        if let error = rotator.pointingErrorDeg {
            LabeledContent("Pointing error", value: String(format: "%.1f°", error))
        }
        Toggle("Follow satellite", isOn: followBinding)
            .disabled(!rotator.isConnected || model.selectedNoradID == nil)
        Stepper(value: minElevationBinding, in: 0 ... 45, step: 1) {
            LabeledContent("Minimum elevation", value: String(format: "%.0f°", rotator.minElevationDeg))
        }
        if let url = endpoint.webURL {
            Link(destination: url) {
                Label("Open web UI", systemImage: "safari")
            }
        }
        if let error = rotator.lastError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
        }
        Button("Disconnect") {
            Task { await service.disconnect() }
        }
        Button("Forget rotator", role: .destructive) {
            Task { await service.disconnect() }
            rotator.forgetSaved()
        }
    }

    @ViewBuilder
    private func savedRows(_ saved: TrackerEndpoint) -> some View {
        LabeledContent("Saved", value: "\(saved.kind.displayName) · \(saved.host)")
        Button("Reconnect") {
            Task { await service.connect(to: saved, model: model) }
        }
        Button("Forget rotator", role: .destructive) {
            rotator.forgetSaved()
        }
    }

    private func positionRow(_ title: String, _ position: RotatorPosition?) -> some View {
        LabeledContent(title) {
            Text(position.map { String(format: "%03.0f° / %.0f°", $0.azimuthDeg, $0.elevationDeg) } ?? "—")
                .monospacedDigit()
        }
    }
}
