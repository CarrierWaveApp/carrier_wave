import CarrierWaveData
import SwiftUI

// MARK: - MacroStepKindPicker

/// Grouped picker the editor shows when the user taps "Add Step". Groups
/// step kinds by intent — Frequency, Mode, Power, PTT, CW, Delay,
/// Read+Wait, Vendor Command, Raw Bytes — so beginners aren't
/// overwhelmed.
struct MacroStepKindPicker: View {
    // MARK: Internal

    let availableCapabilities: RadioMacroCapabilities
    let onSelect: (RadioMacroStep.Kind) -> Void

    var body: some View {
        List {
            ForEach(MacroStepGroup.allCases, id: \.rawValue) { group in
                Section {
                    ForEach(group.kinds, id: \.rawValue) { kind in
                        Button {
                            onSelect(kind)
                        } label: {
                            row(for: kind)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
        .navigationTitle("Add Step")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    private func row(for kind: RadioMacroStep.Kind) -> some View {
        let sample = RadioMacroStep.defaultStep(for: kind)
        return HStack(spacing: 10) {
            Image(systemName: sample.iconName)
                .foregroundStyle(sample.iconTint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName)
                    .font(.body)
                Text(kind.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if kind.warnsAboutSafety {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: - MacroStepGroup

enum MacroStepGroup: String, CaseIterable {
    case radio
    case ptt
    case cw
    case flow
    case advanced

    // MARK: Internal

    var title: String {
        switch self {
        case .radio: "Radio Control"
        case .ptt: "Transmit Control"
        case .cw: "CW Keying"
        case .flow: "Flow Control"
        case .advanced: "Advanced"
        }
    }

    var kinds: [RadioMacroStep.Kind] {
        switch self {
        case .radio: [.setFrequency, .setMode, .setPowerWatts]
        case .ptt: [.setPTT]
        case .cw: [.sendCW]
        case .flow: [.delay, .waitUntil, .assert, .readField]
        case .advanced: [.vendorCommand, .rawBytes]
        }
    }
}

// MARK: - RadioMacroStep.Kind UI helpers

extension RadioMacroStep.Kind {
    var displayName: String {
        switch self {
        case .delay: "Wait (delay)"
        case .setFrequency: "Set Frequency"
        case .setMode: "Set Mode"
        case .setPowerWatts: "Set Power"
        case .setPTT: "Press / Release PTT"
        case .sendCW: "Send CW"
        case .vendorCommand: "Vendor Command"
        case .rawBytes: "Raw Bytes"
        case .readField: "Read Field"
        case .waitUntil: "Wait Until"
        case .assert: "Assert"
        }
    }

    var detail: String {
        switch self {
        case .delay: "Pause for a fixed duration."
        case .setFrequency: "Tune the radio to a frequency in Hz."
        case .setMode: "Switch CW / SSB / FM / digital mode."
        case .setPowerWatts: "Adjust the transmitter power."
        case .setPTT: "Key or unkey the transmitter."
        case .sendCW: "Send Morse text with the keyer."
        case .vendorCommand: "Send a named command from the catalog."
        case .rawBytes: "Send opaque protocol bytes. Unsafe — bypasses checks."
        case .readField: "Read a live value from the radio into a context variable."
        case .waitUntil: "Block until a context expression becomes true."
        case .assert: "Fail the macro if the expression is false."
        }
    }

    var warnsAboutSafety: Bool {
        switch self {
        case .setPTT,
             .rawBytes,
             .sendCW: true
        default: false
        }
    }
}
