import CarrierWaveCore
import SwiftUI

// MARK: - FrequencyModePicker

/// Compact frequency and mode picker for the activation wizard.
/// Works with or without a radio — sets radioManager.frequency/mode directly.
struct FrequencyModePicker: View {
    // MARK: Internal

    @Environment(RadioManager.self) var radioManager

    var body: some View {
        VStack(spacing: 4) {
            modePicker
            frequencyPicker
        }
    }

    // MARK: Private

    private static let modes = ["CW", "SSB", "FT8", "FT4"]

    /// Band ordering for display
    private static let bandOrder = [
        "160m", "80m", "60m", "40m", "30m", "20m",
        "17m", "15m", "12m", "10m", "6m",
    ]

    @State private var selectedMode = "CW"

    private var frequenciesForMode: [(label: String, freq: Double)] {
        let dict = frequencyDict(for: selectedMode)
        return Self.bandOrder.compactMap { band in
            guard let freq = dict[band] else {
                return nil
            }
            return (band, freq)
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("", selection: $selectedMode) {
            ForEach(Self.modes, id: \.self) { mode in
                Text(mode).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedMode) { _, newMode in
            radioManager.mode = newMode
            applyDefaultFrequency(for: newMode)
        }
        .onAppear {
            if !radioManager.mode.isEmpty {
                selectedMode = normalizeMode(radioManager.mode)
            }
        }
    }

    // MARK: - Frequency Picker

    private var frequencyPicker: some View {
        Picker("", selection: Binding(
            get: { radioManager.frequency },
            set: { radioManager.frequency = $0 }
        )) {
            if radioManager.frequency <= 0 {
                Text("Select frequency").tag(Double(0))
            }
            ForEach(frequenciesForMode, id: \.freq) { item in
                Text("\(FrequencyFormatter.format(item.freq)) (\(item.label))")
                    .tag(item.freq)
            }
        }
        .labelsHidden()
    }

    // MARK: - Helpers

    private func applyDefaultFrequency(for mode: String) {
        let currentBand = BandUtilities.deriveBand(from: radioManager.frequency * 1_000) ?? "20m"
        if let freq = frequencyDict(for: mode)[currentBand] {
            radioManager.frequency = freq
        }
    }

    private func frequencyDict(for mode: String) -> [String: Double] {
        switch mode {
        case "CW": BandPlan.cwCallingFrequencies
        case "SSB": BandPlan.ssbCallingFrequencies
        case "FT8": BandPlan.ft8Frequencies
        case "FT4": BandPlan.ft4Frequencies
        default: BandPlan.cwCallingFrequencies
        }
    }

    private func normalizeMode(_ mode: String) -> String {
        let upper = mode.uppercased()
        if ["USB", "LSB", "AM", "FM"].contains(upper) {
            return "SSB"
        }
        if Self.modes.contains(upper) {
            return upper
        }
        return "CW"
    }
}
