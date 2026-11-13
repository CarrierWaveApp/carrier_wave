import CarrierWaveCore
import SwiftUI

// MARK: - RemoteSweepRadioPane

//
// Control-surface layout for the Radio sub-screen of the Remote tab.
// Replaces the original Form-with-sections look with a hero VFO display,
// inline tune entry, and an audio shelf — see the redesign rationale in
// `RemoteSweepConnectedView`. The VFO renders via `FrequencyReadout`,
// kept fileprivate to this file because nothing else needs it.
//

struct RemoteSweepRadioPane: View {
    // MARK: Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                serverChip
                vfoBlock
                audioStrip
                tuneStrip
                RemoteStraightKeyPad()
                if let lastError = coordinator.lastError {
                    Text(lastError)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.red.opacity(0.85))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black.ignoresSafeArea())
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { freqFieldFocused = false }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { freqFieldFocused = false }
    }

    // MARK: Private

    @Environment(RemoteSweepCoordinator.self) private var coordinator
    @State private var tuneFreqMHzText: String = ""
    @State private var sending = false
    @AppStorage("remoteSweepAudioVolume") private var audioVolume: Double = 0.7
    @FocusState private var freqFieldFocused: Bool

    private var isTransmitting: Bool {
        coordinator.radioState?.isTransmitting == true
    }

    private var audioFooterText: String {
        if coordinator.audioSubscribed,
           let format = coordinator.audioFormat
        {
            let source = format.sourceLabel.uppercased()
            let codec = format.codec.rawValue.uppercased()
            let kHz = format.sampleRate / 1_000
            return "\(source)  \(codec)  \(kHz) KHZ"
        } else if coordinator.audioSubscribed {
            return "AWAITING SOURCE"
        } else {
            return "TAP TO LISTEN"
        }
    }

    private var parsedFreqHz: UInt64? {
        guard let mhz = Double(tuneFreqMHzText), mhz > 0 else {
            return nil
        }
        return UInt64((mhz * 1_000_000).rounded())
    }

    private var serverChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.9))
                .frame(width: 6, height: 6)
            Text(coordinator.serverName ?? "Connected")
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
            if let version = coordinator.serverVersion {
                Text("·  \(version)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
            txRxIndicator
        }
    }

    private var txRxIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isTransmitting ? Color.red : Color.white.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(isTransmitting ? "TX" : "RX")
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(1)
                .foregroundStyle(isTransmitting ? Color.red : Color.white.opacity(0.55))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.05))
        )
    }

    private var vfoBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            FrequencyReadout(hz: coordinator.radioState?.freqHz)
            HStack(spacing: 10) {
                if let mode = coordinator.radioState?.mode, !mode.isEmpty {
                    Text(mode.uppercased())
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .tracking(1.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.blue)
                }
                if let name = coordinator.radioState?.radioName {
                    Text(name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                } else if coordinator.radioState == nil, !coordinator.radioStateLoading {
                    Text("No radio at Sweep")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                } else if coordinator.radioStateLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(.white.opacity(0.5))
                        Text("Loading…")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
            }
        }
    }

    private var audioStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("RX AUDIO")
            HStack(spacing: 14) {
                speakerButton
                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { audioVolume },
                            set: { newValue in
                                audioVolume = newValue
                                coordinator.audioPlayer.volume = Float(newValue)
                            }
                        ),
                        in: 0 ... 1
                    )
                    .tint(coordinator.audioSubscribed ? Color.blue : .white.opacity(0.25))
                    .disabled(!coordinator.audioSubscribed)
                    HStack(spacing: 8) {
                        Text(audioFooterText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Text("\(Int(audioVolume * 100))%")
                            .font(.system(.caption2, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }

    private var speakerButton: some View {
        Button {
            Task { await toggleAudio() }
        } label: {
            Image(
                systemName: coordinator.audioSubscribed
                    ? "speaker.wave.2.fill"
                    : "speaker.slash.fill"
            )
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 48, height: 48)
            .background(
                Circle().fill(
                    coordinator.audioSubscribed
                        ? Color.blue.opacity(0.22)
                        : Color.white.opacity(0.05)
                )
            )
            .overlay(
                Circle().strokeBorder(
                    coordinator.audioSubscribed
                        ? Color.blue.opacity(0.55)
                        : Color.white.opacity(0.12),
                    lineWidth: 1
                )
            )
            .foregroundStyle(
                coordinator.audioSubscribed
                    ? Color.blue
                    : Color.white.opacity(0.55)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(coordinator.audioSubscribed ? "Mute remote audio" : "Unmute remote audio")
    }

    private var tuneStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TUNE")
            HStack(spacing: 8) {
                TextField("MHz (e.g. 14.074)", text: $tuneFreqMHzText)
                    .keyboardType(.decimalPad)
                    .focused($freqFieldFocused)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                freqFieldFocused
                                    ? Color.blue.opacity(0.55)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                Button(sending ? "…" : "Set") {
                    Task { await sendTune() }
                }
                .disabled(sending || parsedFreqHz == nil)
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(0.35))
    }

    private func toggleAudio() async {
        if coordinator.audioSubscribed {
            await coordinator.unsubscribeAudio()
        } else {
            coordinator.audioPlayer.volume = Float(audioVolume)
            await coordinator.subscribeAudio()
        }
    }

    private func sendTune() async {
        guard let hz = parsedFreqHz else {
            return
        }
        sending = true
        defer { sending = false }
        await coordinator.tune(freqHz: hz)
    }
}

// MARK: - FrequencyReadout

/// Tabular monospaced VFO readout. The MHz.kHz portion dominates; the Hz
/// triplet is rendered smaller and dimmer so the eye lands on the digits
/// that matter most to an operator at a glance. When no radio is reporting
/// state the digits are shown as a faint placeholder, like an off radio's
/// LCD.
private struct FrequencyReadout: View {
    // MARK: Internal

    let hz: UInt64?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(majorText)
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(majorColor)
                .kerning(-1)
            Text(".")
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(separatorColor)
                .padding(.horizontal, 1)
            Text(hzText)
                .font(.system(size: 32, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(hzColor)
                .baselineOffset(4)
            Spacer(minLength: 8)
            Text("MHz")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.35))
                .baselineOffset(8)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    // MARK: Private

    private var hasSignal: Bool {
        hz != nil
    }

    private var majorText: String {
        guard let hz else {
            return "00.000"
        }
        let mhz = hz / 1_000_000
        let kHz = (hz / 1_000) % 1_000
        return String(format: "%2d.%03d", mhz, kHz)
    }

    private var hzText: String {
        guard let hz else {
            return "000"
        }
        return String(format: "%03d", hz % 1_000)
    }

    private var majorColor: Color {
        hasSignal ? .white : .white.opacity(0.18)
    }

    private var hzColor: Color {
        hasSignal ? .white.opacity(0.55) : .white.opacity(0.12)
    }

    private var separatorColor: Color {
        hasSignal ? .white.opacity(0.4) : .white.opacity(0.15)
    }
}
