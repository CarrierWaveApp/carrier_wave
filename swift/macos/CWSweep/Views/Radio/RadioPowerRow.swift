import SwiftUI

// MARK: - RadioPowerRow

/// "Radio Power" row at the top of the USB Serial box: detects the CH340
/// power switch, pulses it to turn the radio on, and sends `PS0;` to turn a
/// connected Elecraft off.
struct RadioPowerRow: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if power.status != .notFound {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow {
                        fieldLabel("Power switch")
                        devicePicker
                    }
                    GridRow {
                        fieldLabel("Radio port")
                        radioPicker
                    }
                }
                .padding(.leading, 24)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .padding(.leading, 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .task { detect() }
    }

    // MARK: Private

    @Environment(SerialPortMonitor.self) private var portMonitor
    @State private var power = RadioPowerController()

    private var hasCandidate: Bool {
        guard let path = power.powerPortPath else {
            return false
        }
        return power.candidates.contains(path)
    }

    /// Power is usable only when the switch and the radio's port are both set
    /// and present.
    private var isPaired: Bool {
        hasCandidate && power.radioPort(in: portMonitor.availablePorts) != nil
    }

    private var pairingText: String {
        guard power.radioPortPath != nil else {
            return " Choose the radio's USB port to enable Power On."
        }
        guard let radio = power.radioPort(in: portMonitor.availablePorts) else {
            return " The radio's USB port isn't plugged in."
        }
        return " Paired with \(portLabel(radio.path))."
    }

    private var statusText: String {
        switch power.status {
        case .idle: "Looking for the power switch…"
        case .notFound: "Power switch not found (CH340 USB adapter)."
        case .chooseDevice: "Several CH340 adapters found. Choose the power switch."
        case .found: "Power switch found on \(power.powerPortPath.map(portLabel) ?? "?")." + pairingText
        case .poweringOn: "Powering on…"
        case .connecting: "Waiting for the radio to boot, then connecting…"
        case let .done(message): message
        case .poweringOff: "Powering off…"
        case let .error(message): message
        }
    }

    private var statusColor: Color {
        switch power.status {
        case .error: .red
        case .done: .green
        default: .secondary
        }
    }

    private var iconColor: Color {
        switch power.status {
        case .notFound,
             .error: .red
        case .found,
             .done: .green
        case .idle,
             .chooseDevice: .secondary
        default: .orange
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "power")
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text("Radio Power")
                .font(.headline)
            Spacer()
            if power.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Detect") {
                detect()
            }
            .disabled(power.isBusy)
            Button("Power On") {
                Task {
                    await power.powerOn(radioManager: radioManager, ports: portMonitor.availablePorts)
                }
            }
            .disabled(power.isBusy || !isPaired)
            Button("Power Off") {
                Task { await power.powerOff(radioManager: radioManager) }
            }
            .disabled(power.isBusy || power.elecraftSessionId(radioManager: radioManager) == nil)
        }
    }

    private var devicePicker: some View {
        Picker("Switch", selection: Binding(
            get: { power.powerPortPath ?? "" },
            set: { newValue in
                power.powerPortPath = newValue
                detect()
            }
        )) {
            Text("Choose…").tag("")
            ForEach(power.candidates, id: \.self) { path in
                Text(portLabel(path)).tag(path)
            }
        }
        .labelsHidden()
        .frame(width: 180)
    }

    private var radioPicker: some View {
        let choices = power.radioPortChoices(in: portMonitor.availablePorts)
        let selected = power.radioPortPath ?? ""
        let missing = !selected.isEmpty && !choices.contains { $0.path == selected }
        return Picker("Radio port", selection: Binding(
            get: { selected },
            set: { power.radioPortPath = $0.isEmpty ? nil : $0 }
        )) {
            Text("Choose…").tag("")
            ForEach(choices) { port in
                Text(portLabel(port.path)).tag(port.path)
            }
            if missing {
                Text("Not plugged in").tag(selected)
            }
        }
        .labelsHidden()
        .frame(width: 180)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    /// The port's nickname when one is set, otherwise its short device name.
    private func portLabel(_ path: String) -> String {
        let short = path.replacingOccurrences(of: "/dev/cu.", with: "")
        guard let port = portMonitor.availablePorts.first(where: { $0.path == path }),
              let nickname = portMonitor.nickname(for: port)
        else {
            return short
        }
        return nickname
    }

    private func detect() {
        portMonitor.refreshPorts()
        power.detect(radioManager: radioManager)
    }
}
