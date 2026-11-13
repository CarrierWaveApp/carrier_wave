//
//  WsjtxSettingsView.swift
//  CarrierWave
//
//  Settings → Services → WSJT-X: turn on the UDP listener that logs QSOs
//  WSJT-X broadcasts from another computer, choose the bind host/port, show
//  this phone's addresses to type into WSJT-X, and watch a live feed of
//  decodes and logged QSOs (CAR-282). State lives in the shared
//  `WsjtxIngestService` owned by `WsjtxFieldService`. The feed section and
//  its row helpers live in `WsjtxSettingsView+Feed.swift`.
//

import CarrierWaveData
import SwiftUI

// MARK: - WsjtxServicesRow

/// The Settings → Services row; the caller gates it on the experiment.
struct WsjtxServicesRow: View {
    var body: some View {
        NavigationLink {
            WsjtxSettingsView()
        } label: {
            HStack {
                Text("WSJT-X")
                ExperimentalBadge(feature: .wsjtx)
                Spacer()
                if WsjtxFieldService.shared.ingest.isRunning {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Listening")
                }
            }
        }
    }
}

// MARK: - WsjtxSettingsView

struct WsjtxSettingsView: View {
    // MARK: Internal

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var service: WsjtxIngestService {
        WsjtxFieldService.shared.ingest
    }

    var body: some View {
        List {
            SettingsHeroHeader(
                icon: "dot.radiowaves.left.and.right",
                tint: .blue,
                title: "WSJT-X",
                subtitle: "Log FT8, FT4 and other digital QSOs as you make them. WSJT-X on your "
                    + "computer sends each logged QSO to this phone over your local network."
            )
            listenerSection
            endpointSection
            addressSection
            feedSection
        }
        .navigationTitle("WSJT-X")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hostDraft = service.host
            portDraft = String(service.port)
            addresses = DeviceIPv4.addresses()
        }
    }

    // MARK: Private

    @State private var hostDraft = ""
    @State private var portDraft = ""
    @State private var endpointError: String?
    @State private var addresses: [DeviceIPv4.Address] = []
    @State private var copiedAddress: String?

    @FocusState private var hostFocused: Bool
    @FocusState private var portFocused: Bool

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { service.isEnabled },
            set: { newValue in Task { await service.setEnabled(newValue) } }
        )
    }

    private var listenerSection: some View {
        Section {
            Toggle("Log QSOs from WSJT-X", isOn: enabledBinding)
            statusRow
            if let error = service.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if service.loggedCount > 0 || service.duplicateCount > 0 {
                LabeledContent("This session") {
                    Text("\(service.loggedCount) logged · \(service.duplicateCount) duplicates skipped")
                        .foregroundStyle(.secondary)
                }
            }
            if let status = service.lastStatus {
                LabeledContent("WSJT-X reports") {
                    Text(statusText(status))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Listener")
        } footer: {
            Text(
                "Keep Carrier Wave open while you operate: iOS pauses the listener when the app "
                    + "is in the background, and it picks up again when you return."
            )
        }
    }

    private var endpointSection: some View {
        Section {
            TextField("Host", text: $hostDraft, prompt: Text(WsjtxIngestService.anyHost))
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($hostFocused)
                .onSubmit { commitEndpoint() }
                .onChange(of: hostFocused) { _, focused in
                    if !focused {
                        commitEndpoint()
                    }
                }
            TextField("Port", text: $portDraft, prompt: Text(String(WsjtxIngestService.defaultPort)))
                .keyboardType(.numberPad)
                .focused($portFocused)
                .onSubmit { commitEndpoint() }
                .onChange(of: portFocused) { _, focused in
                    if !focused {
                        commitEndpoint()
                    }
                }
            if let endpointError {
                Text(endpointError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("UDP endpoint")
        } footer: {
            Text(
                "Leave the host at \(WsjtxIngestService.anyHost) to accept QSOs from any computer on your "
                    + "network, or enter one of this phone's addresses below to listen on that network only. "
                    + "Each logged QSO is added once — WSJT-X's repeat broadcasts and its ADIF copy are "
                    + "recognised and skipped."
            )
        }
    }

    private var addressSection: some View {
        Section {
            if addresses.isEmpty {
                Text("Not connected to Wi-Fi")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(addresses) { address in
                    addressRow(address)
                }
            }
        } header: {
            Text("This phone")
        } footer: {
            Text(
                "In WSJT-X open File → Settings → Reporting and set UDP Server to one of these "
                    + "addresses and port \(service.boundPort ?? service.port). Both devices must be on "
                    + "the same network."
            )
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if service.isStarting {
            Label("Starting…", systemImage: "ellipsis.circle")
        } else if service.isRunning {
            Label(
                "Listening on \(service.host):\(service.boundPort ?? service.port)",
                systemImage: "dot.radiowaves.left.and.right"
            )
            .foregroundStyle(.green)
        } else {
            Label("Stopped", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func addressRow(_ address: DeviceIPv4.Address) -> some View {
        Button {
            UIPasteboard.general.string = address.address
            copiedAddress = address.address
        } label: {
            HStack {
                Text(address.address)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(address.interface == "en0" ? "Wi-Fi" : address.interface)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: copiedAddress == address.address ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(copiedAddress == address.address ? "Copied" : "Copy")
            }
        }
    }

    private func statusText(_ status: WsjtxStatusSummary) -> String {
        var parts = [status.frequencyAndMode]
        if !status.dxCall.isEmpty {
            parts.append("DX \(status.dxCall)")
        }
        if status.transmitting {
            parts.append("TX")
        }
        return parts.joined(separator: " · ")
    }

    private func commitEndpoint() {
        let host = hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = WsjtxIngestService.parsePort(portDraft) else {
            endpointError = "Port must be a number between 1 and 65535."
            return
        }
        endpointError = nil
        let effectiveHost = host.isEmpty ? WsjtxIngestService.anyHost : host
        hostDraft = effectiveHost
        portDraft = String(port)
        Task { await service.applyEndpoint(host: effectiveHost, port: port) }
    }
}
