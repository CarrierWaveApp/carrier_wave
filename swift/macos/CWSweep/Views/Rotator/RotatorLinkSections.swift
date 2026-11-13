import CarrierWaveData
import SwiftUI

// MARK: - RotatorStatusRows

/// Station-rotator rows shared by the Rotator panel (inside a `GroupBox`) and
/// Settings → Trackers (inside a `Section`): endpoint, link state, reported
/// position, connect / park / stop / forget, and the minimum-elevation slider.
struct RotatorStatusRows: View {
    // MARK: Internal

    var body: some View {
        if let endpoint = rotator.endpoint ?? rotator.savedEndpoint {
            LabeledContent(endpoint.kind.displayName) {
                Text("\(endpoint.host) · \(endpoint.protocolKind.displayName)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            LabeledContent("Link") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(RotatorStateStyle.color(for: rotator.state))
                        .frame(width: 8, height: 8)
                    Text(rotator.state.label)
                }
            }
            if let position = rotator.position {
                LabeledContent("Reported position") {
                    Text(String(format: "AZ %05.1f°  EL %04.1f°", position.azimuthDeg, position.elevationDeg))
                        .monospacedDigit()
                }
            }
            if let error = rotator.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                if rotator.isConnected {
                    Button("Disconnect") {
                        Task { await rotator.disconnect() }
                    }
                    Button("Park") {
                        Task { await rotator.park() }
                    }
                    Button("Stop") {
                        Task { await rotator.stop() }
                    }
                } else {
                    Button("Connect") {
                        Task { await rotator.connect(to: endpoint) }
                    }
                    .disabled(rotator.state == .connecting)
                }
                Spacer()
                if let web = endpoint.webURL {
                    Link("Open web UI", destination: web)
                }
                Button("Forget", role: .destructive) {
                    Task {
                        await rotator.disconnect()
                        rotator.forgetSaved()
                    }
                }
            }
            LabeledContent("Minimum elevation") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { rotator.minElevationDeg },
                            set: { rotator.minElevationDeg = $0 }
                        ),
                        in: 0 ... 20,
                        step: 1
                    )
                    Text("\(Int(rotator.minElevationDeg))°")
                        .monospacedDigit()
                }
            }
        } else {
            Text("No rotator chosen. Scan the network below, or add one by address.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    private let rotator = SharedEnvironment.shared.rotatorController
}

// MARK: - RotatorStateStyle

enum RotatorStateStyle {
    static func color(for state: RotatorController.State) -> Color {
        switch state {
        case .following: .green
        case .idle: .blue
        case .connecting: .orange
        case .error: .red
        case .disconnected: .secondary
        }
    }
}

// MARK: - TrackerDiscoveryRows

/// "Trackers on this network" rows: auto-detect toggle, ignored hosts, the
/// scan result list with Use / Connected, and the last scan error. The Scan
/// button and the swept-networks footer are the container's job
/// (`TrackerDiscoveryScanButton`, `TrackerDiscoveryFooter`).
struct TrackerDiscoveryRows: View {
    // MARK: Internal

    var body: some View {
        Toggle("Detect trackers automatically", isOn: Binding(
            get: { detector.isEnabled },
            set: { detector.isEnabled = $0 }
        ))
        if !detector.ignoredHosts.isEmpty {
            LabeledContent("Ignored") {
                HStack {
                    Text(detector.ignoredHosts.sorted().joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Stop ignoring") {
                        detector.clearIgnored()
                    }
                    .controlSize(.small)
                }
            }
        }
        if discovery.discovered.isEmpty, !discovery.isScanning {
            Text(discovery.lastScanAt == nil
                ? "Scan to look for trackers on your network."
                : "Nothing found. Both units must be on the same Wi-Fi/LAN as this Mac "
                + "(S.A.T.: Hamlib port 4533 · PSR-100 Mk2: web UI on 8080).")
                .foregroundStyle(.secondary)
        }
        ForEach(discovery.discovered) { tracker in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name)
                        .font(.body.weight(.medium))
                    Text(tracker.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                if rotator.endpoint?.host == tracker.host, rotator.isConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Use") {
                        Task { await rotator.connect(to: tracker.endpoint) }
                    }
                }
            }
        }
        if let error = discovery.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: Private

    private let detector = SharedEnvironment.shared.trackerAutoDetector
    private let discovery = SharedEnvironment.shared.trackerDiscovery
    private let rotator = SharedEnvironment.shared.rotatorController
}

// MARK: - TrackerDiscoveryScanButton

struct TrackerDiscoveryScanButton: View {
    // MARK: Internal

    var body: some View {
        HStack {
            if discovery.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Button(discovery.isScanning ? "Scanning…" : "Scan") {
                Task { await discovery.scan() }
            }
            .disabled(discovery.isScanning)
        }
    }

    // MARK: Private

    private let discovery = SharedEnvironment.shared.trackerDiscovery
}

// MARK: - TrackerDiscoveryFooter

struct TrackerDiscoveryFooter: View {
    // MARK: Internal

    var body: some View {
        if !discovery.scannedNetworks.isEmpty {
            Text("Swept \(discovery.scannedNetworks.joined(separator: ", ")). "
                + "CSN S.A.T. answers Hamlib rotctld on 4533; the PSR-100 Mk2 shows its web UI on :8080 "
                + "and answers EasyComm/GS-232 probes on UDP 2390.")
        }
    }

    // MARK: Private

    private let discovery = SharedEnvironment.shared.trackerDiscovery
}

// MARK: - TrackerManualAddRows

/// "Add by address or network" rows: the address field + Add, the
/// nothing-answered fallback with type / protocol pickers, and the
/// extra-network chips. Owns the identify flow.
struct TrackerManualAddRows: View {
    // MARK: Internal

    static let footer = "For a unit on another network or VLAN (e.g. 192.168.20.89, or 192.168.20.0/24 to sweep the "
        + "whole network). Addresses are probed and the type worked out from how the device answers; its network "
        + "is remembered and swept automatically from then on."

    var body: some View {
        LabeledContent("Address") {
            HStack {
                TextField(
                    "Address or network",
                    text: $manualHost,
                    prompt: Text("192.168.20.89 or 192.168.20.0/24")
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospaced()
                .onSubmit(identifyManual)
                if isIdentifying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Add") {
                        identifyManual()
                    }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        if let failed = identifyFailedHost {
            HStack {
                Text("Nothing answered at \(failed). Add it anyway as")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $manualKind) {
                    ForEach(TrackerKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .onChange(of: manualKind) { _, kind in
                    manualProtocol = kind.defaultProtocol
                }
                Picker("", selection: $manualProtocol) {
                    ForEach(RotatorProtocolKind.allCases) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                .labelsHidden()
                Button("Add anyway") {
                    discovery.addManual(host: failed, kind: manualKind, protocolKind: manualProtocol)
                    identifyFailedHost = nil
                    manualHost = ""
                }
            }
        }
        if !discovery.extraNetworks.isEmpty {
            LabeledContent("Also sweeping") {
                HStack(spacing: 6) {
                    ForEach(discovery.extraNetworks, id: \.self) { cidr in
                        HStack(spacing: 2) {
                            Text(cidr)
                                .monospacedDigit()
                            Button {
                                discovery.removeNetwork(cidr)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Stop sweeping \(cidr)")
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: Private

    @State private var manualHost = ""
    @State private var isIdentifying = false
    @State private var identifyFailedHost: String?
    @State private var manualKind: TrackerKind = .csnSAT
    @State private var manualProtocol: RotatorProtocolKind = .hamlibRotctl

    private let detector = SharedEnvironment.shared.trackerAutoDetector
    private let discovery = SharedEnvironment.shared.trackerDiscovery

    /// Ask the device what it is instead of making the operator choose. A
    /// network ("192.168.20.0/24") is added to every future sweep instead.
    private func identifyManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !isIdentifying else {
            return
        }
        if host.contains("/") {
            if discovery.addNetwork(host) != nil {
                manualHost = ""
                identifyFailedHost = nil
                Task { await detector.sweepNow() }
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

// MARK: - RotatorStatusSection

/// Settings → Trackers form section wrapping `RotatorStatusRows`.
struct RotatorStatusSection: View {
    var body: some View {
        Section("Station rotator") {
            RotatorStatusRows()
        }
    }
}

// MARK: - TrackerDiscoverySections

/// Settings → Trackers form sections wrapping the discovery and add rows.
struct TrackerDiscoverySections: View {
    var body: some View {
        Section {
            TrackerDiscoveryRows()
        } header: {
            HStack {
                Text("Trackers on this network")
                Spacer()
                TrackerDiscoveryScanButton()
            }
        } footer: {
            TrackerDiscoveryFooter()
        }
        Section {
            TrackerManualAddRows()
        } header: {
            Text("Add by address or network")
        } footer: {
            Text(TrackerManualAddRows.footer)
        }
    }
}
