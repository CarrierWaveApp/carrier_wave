import CarrierWaveData
import SwiftUI

// MARK: - FrequencyStepEditor

/// Rich editor for `.setFrequency(hz:)`. Lets the user enter MHz/kHz/Hz
/// freely; the form mirrors the entered value across units so the
/// underlying step always stores Hz.
struct FrequencyStepEditor: View {
    // MARK: Lifecycle

    init(hz: Binding<UInt64>) {
        _hz = hz
        let mhz = Double(hz.wrappedValue) / 1_000_000
        _textInput = State(initialValue: String(format: "%.6f", mhz))
        _unit = State(initialValue: .mhz)
    }

    // MARK: Internal

    enum FrequencyUnit: String, CaseIterable, Identifiable {
        case hz
        case kHz
        case mhz

        // MARK: Internal

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .hz: "Hz"
            case .kHz: "kHz"
            case .mhz: "MHz"
            }
        }
    }

    @Binding var hz: UInt64

    var body: some View {
        Form {
            Section("Frequency") {
                Picker("Unit", selection: $unit) {
                    ForEach(FrequencyUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: unit) { _, _ in syncTextFromHz() }

                TextField("Value", text: $textInput)
                    .onChange(of: textInput) { _, _ in syncHzFromText() }

                Text(formattedSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Section {
                bandSuggestionsView
            } header: {
                Text("Common Bands")
            }
        }
        .navigationTitle("Set Frequency")
    }

    // MARK: Private

    @State private var textInput: String
    @State private var unit: FrequencyUnit

    private var formattedSummary: String {
        "\(hz) Hz · " + String(format: "%.6f", Double(hz) / 1_000_000) + " MHz"
    }

    private var bandSuggestionsView: some View {
        ForEach(MacroFrequencySuggestion.suggestions, id: \.label) { suggestion in
            Button {
                hz = suggestion.hz
                syncTextFromHz()
            } label: {
                HStack {
                    Text(suggestion.label)
                    Spacer()
                    Text(String(format: "%.3f MHz", Double(suggestion.hz) / 1_000_000))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func syncHzFromText() {
        let cleaned = textInput.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned) else {
            return
        }
        switch unit {
        case .hz: hz = UInt64(value)
        case .kHz: hz = UInt64(value * 1_000)
        case .mhz: hz = UInt64(value * 1_000_000)
        }
    }

    private func syncTextFromHz() {
        switch unit {
        case .hz: textInput = String(hz)
        case .kHz: textInput = String(format: "%.3f", Double(hz) / 1_000)
        case .mhz: textInput = String(format: "%.6f", Double(hz) / 1_000_000)
        }
    }
}

// MARK: - MacroFrequencySuggestion

struct MacroFrequencySuggestion {
    static let suggestions: [MacroFrequencySuggestion] = [
        .init(label: "80m FT8", hz: 3_573_000),
        .init(label: "40m FT8", hz: 7_074_000),
        .init(label: "40m CW QRP", hz: 7_032_000),
        .init(label: "30m FT8", hz: 10_136_000),
        .init(label: "20m FT8", hz: 14_074_000),
        .init(label: "20m CW QRP", hz: 14_060_000),
        .init(label: "17m FT8", hz: 18_100_000),
        .init(label: "15m FT8", hz: 21_074_000),
        .init(label: "12m FT8", hz: 24_915_000),
        .init(label: "10m FT8", hz: 28_074_000),
        .init(label: "6m FT8", hz: 50_313_000),
        .init(label: "2m FM simplex", hz: 146_520_000),
    ]

    let label: String
    let hz: UInt64
}
