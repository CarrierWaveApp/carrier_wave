import CarrierWaveCore
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

// MARK: - SessionStartValidation

/// Validation logic for session start requirements
enum SessionStartValidation {
    static func canStart(
        callsign: String,
        activationType: ActivationType,
        parkReference: String,
        sotaReference: String,
        frequency _: Double?
    ) -> Bool {
        guard !callsign.isEmpty, callsign.count >= 3 else {
            return false
        }

        switch activationType {
        case .pota:
            return !parkReference.trimmingCharacters(in: .whitespaces).isEmpty
        case .sota:
            return !sotaReference.trimmingCharacters(in: .whitespaces).isEmpty
        case .casual:
            return true
        }
    }

    static func disabledReason(
        callsign: String,
        activationType: ActivationType,
        parkReference: String,
        sotaReference: String,
        frequency _: Double?
    ) -> String? {
        if callsign.isEmpty || callsign.count < 3 {
            return "Set your callsign in Settings → About Me"
        }

        switch activationType {
        case .pota:
            if parkReference.trimmingCharacters(in: .whitespaces).isEmpty {
                return "POTA requires park reference"
            }
        case .sota:
            if sotaReference.trimmingCharacters(in: .whitespaces).isEmpty {
                return "SOTA requires summit reference"
            }
        case .casual:
            break
        }

        return nil
    }
}
