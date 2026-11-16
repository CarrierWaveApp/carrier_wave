import SwiftUI

// MARK: - RadioPowerRow

/// "Radio Power" row at the top of the USB Serial box: detects the CH340
/// power switch, pulses it to turn the radio on, and sends `PS0;` to turn a
/// connected Elecraft off.
struct RadioPowerRow: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "power")
                    .foregroundStyle(iconColor)
                Text("Radio Power")
                    .font(.headline)
                if power.status == .chooseDevice || power.candidates.count > 1 {
                    devicePicker
                }
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
                .disabled(power.isBusy || power.powerPortPath == nil || !hasCandidate)
                Button("Power Off") {
                    Task { await power.powerOff(radioManager: radioManager) }
                }
                .disabled(power.isBusy || power.elecraftSessionId(radioManager: radioManager) == nil)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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

    private var statusText: String {
        switch power.status {
        case .idle: "Looking for the power switch…"
        case .notFound: "Power switch not found (CH340 USB adapter)."
        case .chooseDevice: "Several CH340 adapters found. Choose the power switch."
        case .found: "Power switch found on \(power.powerPortPath ?? "?")."
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
                Text(path.replacingOccurrences(of: "/dev/cu.", with: "")).tag(path)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 200)
    }

    private func detect() {
        portMonitor.refreshPorts()
        power.detect(radioManager: radioManager)
    }
}
