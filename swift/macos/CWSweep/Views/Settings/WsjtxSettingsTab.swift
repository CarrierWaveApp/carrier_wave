import CarrierWaveData
import SwiftUI

// MARK: - WsjtxSettingsTab

/// Settings → WSJT-X: enable the UDP listener that logs QSOs WSJT-X
/// broadcasts, choose the bind host/port, and watch a live feed of decodes and
/// logged QSOs (CAR-282). State lives in the shared `WsjtxIngestService`.
struct WsjtxSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            listenerSection
            endpointSection
            feedSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            hostDraft = service.host
            portDraft = String(service.port)
        }
    }

    // MARK: Private

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @Environment(WsjtxIngestService.self) private var service

    @State private var hostDraft = ""
    @State private var portDraft = ""
    @State private var endpointError: String?

    @FocusState private var hostFocused: Bool
    @FocusState private var portFocused: Bool

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { service.isEnabled },
            set: { newValue in Task { await service.setEnabled(newValue) } }
        )
    }

    private var listenerSection: some View {
        Section("Listener") {
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
        }
    }

    private var endpointSection: some View {
        Section {
            TextField("Host", text: $hostDraft, prompt: Text(WsjtxIngestService.loopbackHost))
                .autocorrectionDisabled()
                .focused($hostFocused)
                .onSubmit { commitEndpoint() }
                .onChange(of: hostFocused) { _, focused in
                    if !focused {
                        commitEndpoint()
                    }
                }
            TextField("Port", text: $portDraft, prompt: Text(String(WsjtxIngestService.defaultPort)))
                .autocorrectionDisabled()
                .frame(width: 120)
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
                "In WSJT-X open Settings → Reporting and set UDP Server to this Mac "
                    + "(\(WsjtxIngestService.loopbackHost) when WSJT-X runs here) and the port above. "
                    + "Use \(WsjtxIngestService.anyHost) as the host to accept QSOs from WSJT-X on another "
                    + "computer on your network. Each logged QSO is added once — WSJT-X's repeat "
                    + "broadcasts and its ADIF copy are recognised and skipped."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var feedSection: some View {
        Section {
            if service.recentEvents.isEmpty {
                Text(service.isRunning ? "Waiting for WSJT-X…" : "Turn the listener on to see decodes and logged QSOs.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.recentEvents.reversed()) { event in
                    feedRow(event)
                }
            }
        } header: {
            HStack {
                Text("Live feed")
                Spacer()
                if !service.recentEvents.isEmpty {
                    Button("Clear") { service.clearFeed() }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Rows

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

    private func feedRow(_ event: WsjtxIngestEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: event.date))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: icon(for: event.kind))
                .foregroundStyle(color(for: event.kind))
                .frame(width: 14)
            Text(event.text)
                .font(event.kind == .decode ? .caption.monospaced() : .callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: Helpers

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

    private func icon(for kind: WsjtxIngestEvent.Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .decode: "waveform"
        case .qsoLogged: "checkmark.circle.fill"
        case .duplicate: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: WsjtxIngestEvent.Kind) -> Color {
        switch kind {
        case .info: .secondary
        case .decode: .blue
        case .qsoLogged: .green
        case .duplicate: .orange
        case .error: .red
        }
    }

    private func commitEndpoint() {
        let host = hostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = WsjtxIngestService.parsePort(portDraft) else {
            endpointError = "Port must be a number between 1 and 65535."
            return
        }
        endpointError = nil
        let effectiveHost = host.isEmpty ? WsjtxIngestService.loopbackHost : host
        hostDraft = effectiveHost
        portDraft = String(port)
        Task { await service.applyEndpoint(host: effectiveHost, port: port) }
    }
}
