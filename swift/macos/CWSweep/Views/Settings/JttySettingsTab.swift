import AppKit
import SwiftUI

/// Settings → JTTY: the modem toggle and helper install, the radio's audio
/// devices, tone/profile/PTT options, and the F1–F8 macro templates.
struct JttySettingsTab: View {
    // MARK: Internal

    var body: some View {
        Form {
            modemSection
            audioSection
            operatingSection
            macrosSection
            helperLogSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refreshDevices)
    }

    // MARK: Private

    @Environment(JttyService.self) private var service

    @State private var inputs: [MacAudioDevice] = []
    @State private var outputs: [MacAudioDevice] = []
    @State private var customPathDraft = ""
    @State private var toneDraft = ""

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { service.isEnabled },
            set: { newValue in Task { await service.setEnabled(newValue) } }
        )
    }

    private var modemSection: some View {
        Section {
            Toggle("Enable the JTTY modem", isOn: enabledBinding)
                .disabled(!service.isHelperInstalled && !service.isEnabled)
            LabeledContent("Status") {
                Text(service.sidecarStatus.label)
                    .foregroundStyle(service.sidecarStatus.isRunning ? .green : .secondary)
            }
            if let audioError = service.audioError {
                Label(audioError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            helperRow
        } header: {
            Text("Modem")
        } footer: {
            Text(
                "JTTY is WSJT-X 3.2's keyboard-to-keyboard contest mode (4-GFSK, 1.9 s frames, ~125 Hz wide, "
                    + "no time slots). Decoding and encoding run in the separate jtty-sidecar helper "
                    + "(GPLv3, source at \(JttySidecarRelease.sourceURL.absoluteString)), downloaded once and "
                    + "verified against a pinned checksum. JTTY is still a release candidate; a new WSJT-X may "
                    + "change the protocol until it ships."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var helperRow: some View {
        HStack {
            if service.isHelperInstalled, let url = service.helperURL {
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .controlSize(.small)
            } else {
                Text("The helper (\(JttySidecarRelease.version), macOS universal) is not installed.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if case .installing = service.sidecarStatus {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(service.isHelperInstalled ? "Reinstall" : "Install helper") {
                    Task { await service.installHelper() }
                }
                .controlSize(.small)
                .disabled(service.isRunning)
            }
        }
        HStack {
            TextField("Custom helper path (optional)", text: $customPathDraft)
                .autocorrectionDisabled()
                .onSubmit(commitCustomPath)
            Button("Choose…", action: chooseHelper)
                .controlSize(.small)
        }
        .onAppear { customPathDraft = service.customHelperPath ?? "" }
    }

    private var audioSection: some View {
        @Bindable var service = service
        return Section {
            Picker("Receive audio from", selection: $service.inputDeviceUID) {
                Text("System default input").tag(String?.none)
                ForEach(inputs) { device in
                    Text(device.name).tag(String?.some(device.uid))
                }
            }
            Picker("Transmit audio to", selection: $service.outputDeviceUID) {
                Text("System default output").tag(String?.none)
                ForEach(outputs) { device in
                    Text(device.name).tag(String?.some(device.uid))
                }
            }
            HStack {
                Button("Refresh devices", action: refreshDevices)
                    .controlSize(.small)
                Button("Apply to running modem") { service.restartAudio() }
                    .controlSize(.small)
                    .disabled(!service.isRunning)
            }
        } header: {
            Text("Audio")
        } footer: {
            Text(
                "Pick the radio's USB audio codec for both directions. Input must be 32-bit float (any sample rate); it is converted to 12 kHz for the decoder."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var operatingSection: some View {
        @Bindable var service = service
        return Section("Operating") {
            HStack {
                TextField("Tone frequency (Hz)", text: $toneDraft)
                    .frame(width: 220)
                    .onSubmit(commitTone)
                Text("Lowest tone when transmitting; preferred receive channel. WSJT-X defaults to 1500.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { toneDraft = String(Int(service.toneFrequency)) }
            Picker("Exchange profile", selection: $service.profile) {
                ForEach(JttyExchangeProfile.allCases) { profile in
                    Text(profile.label).tag(profile)
                }
            }
            Toggle("Key the radio's PTT when transmitting", isOn: $service.autoPTT)
            Text("Off: transmit audio only and let the radio's VOX or an external interface key it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var macrosSection: some View {
        @Bindable var service = service
        return Section {
            ForEach(0 ..< JttyMacroExpander.slotCount, id: \.self) { slot in
                HStack {
                    Text("F\(slot + 1)")
                        .frame(width: 28, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    TextField("", text: $service.macros[slot])
                        .font(.body.monospaced())
                }
            }
            Button("Reset to WSJT-X defaults") {
                service.macros = JttyMacroExpander.defaultTemplates
            }
            .controlSize(.small)
        } header: {
            Text("Function keys")
        } footer: {
            Text(
                "%M my call · %H his call · %Q queued call · %E exchange (599 nnn, or the exchange field for Field Day / RTTY Roundup) · %N serial · %G grid. The WSJT-X defaults pack into single compact frames; free text costs one frame per five characters."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var helperLogSection: some View {
        if !service.helperLog.isEmpty {
            Section("Helper log") {
                ForEach(Array(service.helperLog.suffix(12).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func refreshDevices() {
        let devices = MacAudioDevices.all()
        inputs = devices.filter(\.hasInput)
        outputs = devices.filter(\.hasOutput)
    }

    private func commitCustomPath() {
        let trimmed = customPathDraft.trimmingCharacters(in: .whitespaces)
        service.customHelperPath = trimmed.isEmpty ? nil : trimmed
    }

    private func chooseHelper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a jtty-sidecar executable"
        if panel.runModal() == .OK, let url = panel.url {
            customPathDraft = url.path
            commitCustomPath()
        }
    }

    private func commitTone() {
        guard let value = Double(toneDraft.trimmingCharacters(in: .whitespaces)), (300 ... 2_800).contains(value) else {
            toneDraft = String(Int(service.toneFrequency))
            return
        }
        service.toneFrequency = value
    }
}
