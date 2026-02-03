import SwiftUI

// MARK: - CallsignBreakdownView

/// Extracted view showing callsign prefix/base/suffix breakdown
struct CallsignBreakdownView: View {
    let prefix: String
    let baseCallsign: String
    let suffix: String

    var body: some View {
        HStack(spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix.uppercased())
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(baseCallsign.uppercased())
                .font(.caption.monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .clipShape(Capsule())

            if !suffix.isEmpty {
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suffix)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - ActivationSectionView

/// Extracted view for activation type selection
struct ActivationSectionView: View {
    @Binding var activationType: ActivationType
    @Binding var parkReference: String
    @Binding var sotaReference: String

    /// User's grid square for nearby parks
    var userGrid: String?
    /// Default country prefix for park shorthand
    var defaultCountry: String = "US"

    var body: some View {
        Section("Activation Type") {
            Picker("Type", selection: $activationType) {
                ForEach(ActivationType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            if activationType == .pota {
                ParkEntryField(
                    parkReference: $parkReference,
                    label: "Park",
                    placeholder: "1234 or US-1234",
                    userGrid: userGrid,
                    defaultCountry: defaultCountry
                )
            }

            if activationType == .sota {
                HStack {
                    Text("Summit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("W4C/CM-001", text: $sotaReference)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                }
            }
        }
    }
}

// MARK: - FrequencySuggestionsView

/// Extracted view for frequency band suggestions
struct FrequencySuggestionsView: View {
    // MARK: Internal

    let selectedMode: String

    @Binding var frequency: String

    var body: some View {
        let suggestions = LoggingSession.suggestedFrequencies(for: selectedMode)
        let availableBands = Self.sortedBands.filter { suggestions[$0] != nil }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableBands, id: \.self) { band in
                    if let freq = suggestions[band] {
                        bandButton(band: band, freq: freq)
                    }
                }
            }
        }
    }

    // MARK: Private

    private static let sortedBands = [
        "160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
    ]

    private func bandButton(band: String, freq: Double) -> some View {
        let freqString = FrequencyFormatter.format(freq)
        let isSelected = frequency == freqString

        return Button {
            frequency = freqString
        } label: {
            VStack(spacing: 2) {
                Text(band)
                    .font(.caption.weight(.medium))
                Text(freqString)
                    .font(.caption2.monospaced())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : Color(.tertiarySystemGroupedBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SessionStartValidation

/// Validation logic for session start requirements
enum SessionStartValidation {
    static func canStart(
        callsign: String,
        activationType: ActivationType,
        parkReference: String,
        sotaReference: String,
        frequency: Double?
    ) -> Bool {
        guard !callsign.isEmpty, callsign.count >= 3 else {
            return false
        }

        switch activationType {
        case .pota:
            let hasPark = !parkReference.trimmingCharacters(in: .whitespaces).isEmpty
            return frequency != nil && hasPark
        case .sota:
            let hasSummit = !sotaReference.trimmingCharacters(in: .whitespaces).isEmpty
            return frequency != nil && hasSummit
        case .casual:
            return true
        }
    }

    static func disabledReason(
        callsign: String,
        activationType: ActivationType,
        parkReference: String,
        sotaReference: String,
        frequency: Double?
    ) -> String? {
        if callsign.isEmpty || callsign.count < 3 {
            return "Set your callsign in Settings → About Me"
        }

        switch activationType {
        case .pota:
            let hasPark = !parkReference.trimmingCharacters(in: .whitespaces).isEmpty
            if !hasPark, frequency == nil {
                return "POTA requires park reference and frequency"
            } else if !hasPark {
                return "POTA requires park reference"
            } else if frequency == nil {
                return "POTA requires frequency"
            }
        case .sota:
            let hasSummit = !sotaReference.trimmingCharacters(in: .whitespaces).isEmpty
            if !hasSummit, frequency == nil {
                return "SOTA requires summit reference and frequency"
            } else if !hasSummit {
                return "SOTA requires summit reference"
            } else if frequency == nil {
                return "SOTA requires frequency"
            }
        case .casual:
            break
        }

        return nil
    }
}
