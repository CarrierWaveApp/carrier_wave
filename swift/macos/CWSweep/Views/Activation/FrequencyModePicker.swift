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

    private static let modes = ["CW", "SSB", "FM", "FT8", "FT4"]

    /// Band ordering for display
    private static let bandOrder = [
        "160m", "80m", "60m", "40m", "30m", "20m",
        "17m", "15m", "12m", "10m", "6m",
        "2m", "1.25m", "70cm", "33cm", "23cm",
    ]

    /// US (ARRL) VHF/UHF calling frequencies, merged over `BandPlan`'s HF
    /// tables. Kept here rather than in `BandPlan` so iOS suggestions don't
    /// change.
    private static let vhfFrequencies: [String: [String: Double]] = [
        "CW": ["2m": 144.050, "1.25m": 222.100, "70cm": 432.100, "33cm": 902.100, "23cm": 1_296.100],
        "SSB": ["2m": 144.200, "1.25m": 222.100, "70cm": 432.100, "33cm": 903.100, "23cm": 1_296.100],
        "FM": ["1.25m": 223.500, "33cm": 927.500, "23cm": 1_294.500],
        "FT8": ["2m": 144.174, "70cm": 432.174, "23cm": 1_296.174],
        "FT4": ["2m": 144.170],
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
        let base = switch mode {
        case "SSB": BandPlan.ssbCallingFrequencies
        case "FM": BandPlan.fmFrequencies
        case "FT8": BandPlan.ft8Frequencies
        case "FT4": BandPlan.ft4Frequencies
        default: BandPlan.cwCallingFrequencies
        }
        return base.merging(Self.vhfFrequencies[mode] ?? [:]) { hf, _ in hf }
    }

    private func normalizeMode(_ mode: String) -> String {
        let upper = mode.uppercased()
        if ["USB", "LSB", "AM"].contains(upper) {
            return "SSB"
        }
        if Self.modes.contains(upper) {
            return upper
        }
        return "CW"
    }
}
