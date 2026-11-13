import CarrierWaveCwFfi
import SwiftUI

// MARK: - SDRSettingsTab

/// Configure an external SDR as the waterfall source: the device (SoapySDR,
/// rtl_tcp, test tones), how its spectrum maps to RF (radio IF output such as
/// the K3's 8.215 MHz IF OUT, or the antenna directly), and IF calibration.
struct SDRSettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            Section("SDR Waterfall") {
                Toggle("Use an external SDR for the waterfall", isOn: $draft.enabled)
                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
            deviceSection
            tuningSection
            if draft.tuningKind == .ifTap {
                calibrationSection
            }
            displaySection
            HStack {
                Spacer()
                Button("Revert") { draft = service.settings }
                    .disabled(draft == service.settings)
                Button("Apply") { service.apply(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == service.settings)
            }
        }
        .formStyle(.grouped)
        .onAppear { draft = service.settings }
    }

    // MARK: Private

    @State private var draft = SDRInputSettings.load()
    @State private var soapyDevices: [String] = []
    @State private var soapyMessage: String?
    @State private var isDetecting = false
    @State private var calibrationMessage: String?

    private var service: IQPanadapterService {
        SharedEnvironment.shared.radioManager.iqPanadapter
    }

    private var statusText: String {
        var text = service.status.description
        if service.isPausedForTransmit {
            text += " (paused while transmitting)"
        }
        if let floor = service.noiseFloorDB, service.status == .running {
            text += String(format: " · noise floor %.0f dBFS", floor)
        }
        return text
    }

    private var statusIsError: Bool {
        if case .failed = service.status {
            return true
        }
        return false
    }

    private var deviceSection: some View {
        Section("Device") {
            Picker("Source", selection: $draft.sourceKind) {
                ForEach(SDRInputSettings.SourceKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            switch draft.sourceKind {
            case .soapy:
                soapyFields
            case .rtlTcp:
                rtlTcpFields
            case .tone:
                Text("Synthetic carriers — one sits under the VFO. Useful for checking the display and tap-to-tune.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Sample rate", selection: $draft.sampleRate) {
                ForEach(SDRInputSettings.sampleRateChoices, id: \.self) { rate in
                    Text(Self.formatRate(rate)).tag(rate)
                }
            }
            Toggle("Automatic gain", isOn: $draft.autoGain)
            if !draft.autoGain {
                LabeledContent("Gain") {
                    Slider(value: $draft.gainDB, in: 0 ... 60, step: 1)
                    Text("\(Int(draft.gainDB)) dB")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
            TextField("Frequency offset (Hz, e.g. upconverter)", value: $draft.deviceOffsetHz, format: .number)
        }
    }

    @ViewBuilder
    private var soapyFields: some View {
        HStack {
            TextField("Device args", text: $draft.soapyArgs)
                .autocorrectionDisabled()
            Button(isDetecting ? "Detecting…" : "Detect") { detectSoapyDevices() }
                .disabled(isDetecting)
        }
        ForEach(soapyDevices, id: \.self) { device in
            Button(device) { draft.soapyArgs = device }
                .buttonStyle(.link)
                .font(.caption)
        }
        if let soapyMessage {
            Text(soapyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        Text("Needs `brew install soapysdr` plus the device module (SoapySDRPlay3, soapyrtlsdr, soapyairspyhf).")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var rtlTcpFields: some View {
        TextField("Host", text: $draft.rtlTcpHost)
            .autocorrectionDisabled()
        TextField("Port", value: $draft.rtlTcpPort, format: .number.grouping(.never))
        Picker("Direct sampling", selection: $draft.directSampling) {
            Text("Off").tag(0)
            Text("I branch").tag(1)
            Text("Q branch (HF on RTL-SDR)").tag(2)
        }
    }

    private var tuningSection: some View {
        Section("Frequency mapping") {
            Picker("SDR is connected to", selection: $draft.tuningKind) {
                ForEach(SDRInputSettings.TuningKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            if draft.tuningKind == .ifTap {
                HStack {
                    TextField("IF frequency (Hz)", value: $draft.ifHz, format: .number)
                    Button("Elecraft K3/K3S") { draft.applyK3Preset() }
                }
                Toggle("Spectrum is inverted", isOn: $draft.ifInverted)
                Text("If signals move the wrong way when you tune the radio, toggle this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("The SDR follows the radio's VFO using CAT frequency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("SDR LO offset (Hz, keeps DC spike off the VFO)", value: $draft.loOffsetHz, format: .number)
        }
    }

    private var calibrationSection: some View {
        Section("Calibration") {
            let mode = service.currentMode.isEmpty ? "—" : service.currentMode
            LabeledContent("Current mode", value: mode)
            LabeledContent("Offset for \(mode)") {
                Text("\(Int(service.settings.calibrationHz(forMode: service.currentMode))) Hz")
                    .monospacedDigit()
            }
            Text("Tune the radio exactly onto a steady carrier (WWV, a beacon, a zero-beat CW signal), "
                + "then calibrate. The strongest signal within 5 kHz moves under the VFO marker.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Calibrate on strongest signal") {
                    calibrationMessage = service.calibrateOnStrongestSignal()
                }
                .disabled(service.status != .running)
                Button("Reset") {
                    service.resetCalibration()
                    calibrationMessage = nil
                }
            }
            if let calibrationMessage {
                Text(calibrationMessage)
                    .font(.caption)
            }
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Span", selection: $draft.spanHz) {
                ForEach(SDRInputSettings.spanChoicesHz, id: \.self) { span in
                    Text("\(Int(span / 1_000)) kHz").tag(span)
                }
            }
            Picker("Frame rate", selection: $draft.fps) {
                Text("10 fps").tag(10.0)
                Text("25 fps").tag(25.0)
            }
        }
    }

    private static func formatRate(_ rate: Int) -> String {
        rate >= 1_000_000
            ? String(format: "%.3g MS/s", Double(rate) / 1_000_000)
            : "\(rate / 1_000) kS/s"
    }

    private func detectSoapyDevices() {
        isDetecting = true
        Task {
            let result = await Task.detached { panadapterEnumerateSoapyDevices() }.value
            soapyDevices = result.devices
            if !result.available {
                soapyMessage = result.error ?? "SoapySDR is not available."
            } else if result.devices.isEmpty {
                soapyMessage = "No SoapySDR devices found."
            } else {
                soapyMessage = nil
            }
            isDetecting = false
        }
    }
}
