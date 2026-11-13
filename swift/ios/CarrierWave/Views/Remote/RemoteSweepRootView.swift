import CarrierWaveCore
import SwiftUI

// MARK: - RemoteSweepRootView

//
// Top-level screen for the Remote tab. Routes between discovery, pairing, and
// the connected radio/spots experience based on the coordinator state.

struct RemoteSweepRootView: View {
    // MARK: Internal

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Remote")
                .toolbar {
                    if coordinator.connectionState == .connected {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Disconnect") {
                                Task { await coordinator.disconnect() }
                            }
                        }
                    }
                }
        }
        .task {
            discovery.start()
            multipeer.start()
        }
        .onDisappear {
            discovery.stop()
            multipeer.stop()
        }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @State private var discovery = RemoteSweepDiscovery()
    @State private var multipeer = MultipeerSweepBrowser()

    @ViewBuilder
    private var content: some View {
        switch coordinator.connectionState {
        case .idle:
            RemoteSweepDiscoveryView(discovery: discovery, multipeer: multipeer)
        case .connecting:
            ProgressView("Connecting…")
                .frame(maxHeight: .infinity)
        case .awaitingPairing:
            RemoteSweepPairingView()
        case .connected:
            RemoteSweepConnectedView()
        case let .error(message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(message)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await coordinator.disconnect() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - RemoteSweepDiscoveryView

struct RemoteSweepDiscoveryView: View {
    // MARK: Internal

    let discovery: RemoteSweepDiscovery
    let multipeer: MultipeerSweepBrowser

    var body: some View {
        List {
            Section {
                if discovery.discovered.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Looking for CW Sweep on this network…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(discovery.discovered) { sweep in
                        Button {
                            Task { await coordinator.connect(to: sweep) }
                        } label: {
                            sweepRow(name: sweep.name, subtitle: "Local network")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Sweeps on the network")
            } footer: {
                if let error = discovery.lastError {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("On your Mac, open CW Sweep → Settings → Remote and start the server.")
                }
            }

            Section {
                if discovery.debugLog.isEmpty {
                    Text("No discovery events yet")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(discovery.debugLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Discovery diagnostics")
            }

            Section {
                if multipeer.discovered.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Searching nearby (Bluetooth + Wi-Fi)…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(multipeer.discovered) { sweep in
                        Button {
                            Task { await coordinator.connectMultipeer(to: sweep, via: multipeer) }
                        } label: {
                            sweepRow(name: sweep.displayName, subtitle: "Nearby (no Wi-Fi needed)")
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Nearby Sweeps")
            } footer: {
                if let error = multipeer.lastError {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Lets Field reach a Mac on the same Apple ID with no shared Wi-Fi router.")
                }
            }
        }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator

    private func sweepRow(name: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - RemoteSweepPairingView

struct RemoteSweepPairingView: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section {
                Text("Enter the 6-digit code shown in CW Sweep → Settings → Remote on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Pairing code", text: $code)
                    .keyboardType(.numberPad)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onChange(of: code) { _, newValue in
                        let trimmed = String(newValue.filter(\.isNumber).prefix(6))
                        if trimmed != newValue {
                            code = trimmed
                        }
                        if trimmed.count == 6 {
                            Task { await submit() }
                        }
                    }
            }

            if let server = coordinator.serverName {
                Section("Connecting to") {
                    Text(server)
                }
            }

            if let error = coordinator.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }

            Section {
                Button("Cancel") {
                    Task { await coordinator.disconnect() }
                }
                .foregroundStyle(.red)
            }
        }
        .onAppear { focused = true }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @State private var code: String = ""
    @State private var submitting = false
    @FocusState private var focused: Bool

    private func submit() async {
        guard !submitting, code.count == 6 else {
            return
        }
        submitting = true
        defer { submitting = false }
        await coordinator.submitPairingCode(code)
    }
}
