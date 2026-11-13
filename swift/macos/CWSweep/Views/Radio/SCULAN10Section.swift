import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SCULAN10Section")

// MARK: - SCULAN10Section

/// Yaesu SCU-LAN10 (UDP) connection section. Holds host + credentials inline;
/// no separate settings tab. The protocol is YaesuProtocolHandler regardless
/// of which Yaesu radio is wired into the SCU-LAN10, so no model picker.
struct SCULAN10Section: View {
    // MARK: Internal

    let radioManager: RadioManager

    @Binding var connectionError: String?

    var body: some View {
        GroupBox("Yaesu SCU-LAN10") {
            VStack(alignment: .leading, spacing: 8) {
                credentialsForm
                Divider()
                connectionRow
                if radioManager.isConnected {
                    audioRow
                }
                if !radioManager.connectionLog.isEmpty {
                    connectionLogView
                }
                if radioManager.isConnected {
                    debugInfo
                }
            }
            .padding(8)
        }
        .padding(.horizontal)
    }

    // MARK: Private

    @AppStorage("sculan10Host") private var sculan10Host = ""
    @AppStorage("sculan10Port") private var sculan10Port = 50_000
    @AppStorage("sculan10Username") private var sculan10Username = ""
    @AppStorage("sculan10Password") private var sculan10Password = ""
    @AppStorage("sculan10AudioMuted") private var sculan10AudioMuted = true
    @AppStorage("sculan10AudioVolume") private var sculan10AudioVolume: Double = 0.7
    @State private var isConnecting = false

    /// SCU-LAN10 always speaks Yaesu CAT — the model is purely cosmetic for
    /// the connection log. Pick the first known SCU-LAN10 model and reuse it.
    private var connectionModel: RadioModel {
        RadioModel.knownModels.first { $0.protocolType == .scuLan10 }
            ?? RadioModel.knownModels[0]
    }

    private var credentialsForm: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("Host").frame(width: 80, alignment: .trailing)
                TextField("192.168.1.50", text: $sculan10Host)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Port").frame(width: 80, alignment: .trailing)
                Stepper("\(sculan10Port)", value: $sculan10Port, in: 49_990 ... 50_009)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GridRow {
                Text("Username").frame(width: 80, alignment: .trailing)
                TextField("", text: $sculan10Username)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Password").frame(width: 80, alignment: .trailing)
                SecureField("", text: $sculan10Password)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .font(.caption)
    }

    private var connectionRow: some View {
        HStack {
            Image(systemName: radioManager.isConnected ? "wifi" : "wifi.slash")
                .foregroundStyle(radioManager.isConnected ? .green : .secondary)
            Text(sculan10Host.isEmpty ? "Enter host above" : sculan10Host)
                .font(.body)
            Spacer()
            if radioManager.isConnected {
                Button("Disconnect") {
                    Task { await radioManager.disconnectAll() }
                }
                .tint(.red)
            } else if isConnecting {
                Button("Cancel") { isConnecting = false }
                    .foregroundStyle(.secondary)
            } else {
                Button("Connect") {
                    Task { await connectWithRetry() }
                }
                .disabled(sculan10Host.isEmpty || sculan10Username.isEmpty)
            }
        }
    }

    private var connectionLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(
                        Array(radioManager.connectionLog.enumerated()),
                        id: \.offset
                    ) { idx, entry in
                        Text(entry)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .id(idx)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
            .onChange(of: radioManager.connectionLog.count) { _, count in
                withAnimation {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private var audioRow: some View {
        HStack(spacing: 8) {
            Button {
                sculan10AudioMuted.toggle()
                applyAudioGain()
            } label: {
                Image(
                    systemName: sculan10AudioMuted
                        ? "speaker.slash.fill"
                        : "speaker.wave.2.fill"
                )
                .font(.body)
                .frame(width: 22)
                .foregroundStyle(sculan10AudioMuted ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .help(sculan10AudioMuted ? "Unmute RX audio" : "Mute RX audio")

            Slider(
                value: $sculan10AudioVolume,
                in: 0 ... 1
            )
            .disabled(sculan10AudioMuted)
            .onChange(of: sculan10AudioVolume) { _, _ in applyAudioGain() }

            Text("\(Int(sculan10AudioVolume * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .onAppear { applyAudioGain() }
    }

    @ViewBuilder
    private var debugInfo: some View {
        if let stats = radioManager.sculan10DebugStats {
            SCULAN10DebugView(
                stats: stats,
                store: radioManager.waterfallStore,
                pendingLines: radioManager.sculan10Waterfall.pendingLineCount
            )
        }
    }

    private func applyAudioGain() {
        let gain = sculan10AudioMuted ? 0 : Float(sculan10AudioVolume)
        radioManager.sculan10AudioPlayer.volume = gain
    }

    private func connectWithRetry() async {
        guard !sculan10Host.isEmpty, !sculan10Username.isEmpty else {
            connectionError = "Enter host and credentials"
            return
        }
        isConnecting = true
        connectionError = nil
        radioManager.connectionLog.removeAll()
        defer { isConnecting = false }

        for attempt in 1 ... 3 {
            guard isConnecting else {
                return
            }
            do {
                _ = try await radioManager.connectSCULAN10(
                    host: sculan10Host,
                    port: UInt16(sculan10Port),
                    username: sculan10Username,
                    password: sculan10Password,
                    model: connectionModel
                )
                return
            } catch {
                logger.warning("Attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < 3, isConnecting {
                    radioManager.appendConnectionLog("Retry in 2s (\(error.localizedDescription))…")
                    try? await Task.sleep(for: .seconds(2))
                } else {
                    connectionError = error.localizedDescription
                }
            }
        }
    }
}
