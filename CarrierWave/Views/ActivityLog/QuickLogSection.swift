import CarrierWaveCore
import SwiftUI

// MARK: - QuickLogSection

/// Manual callsign entry section for the Activity Log.
/// Supports quick entry parsing (e.g., "AJ7CM 579 US-0189").
struct QuickLogSection: View {
    // MARK: Internal

    let currentMode: String
    let currentFrequency: Double?
    let onLog: (QuickLogData) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Log")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Callsign...", text: $callsignInput)
                    .font(.subheadline.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onSubmit { logFromInput() }

                rstField(label: "Snt", text: $rstSent)
                rstField(label: "Rcv", text: $rstReceived)

                Button {
                    logFromInput()
                } label: {
                    Text("Log")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(callsignInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Show quick entry preview if multi-token input
            if !parsedTokens.isEmpty {
                quickEntryPreview
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Private

    @State private var callsignInput = ""
    @State private var rstSent = ""
    @State private var rstReceived = ""

    private var defaultRST: String {
        let mode = currentMode.uppercased()
        if mode == "SSB" || mode == "USB" || mode == "LSB" || mode == "FM" || mode == "AM" {
            return "59"
        }
        return "599"
    }

    private var parsedTokens: [ParsedToken] {
        let trimmed = callsignInput.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains(" ") else {
            return []
        }
        return QuickEntryParser.parseTokens(trimmed)
    }

    private var quickEntryPreview: some View {
        HStack(spacing: 4) {
            ForEach(Array(parsedTokens.enumerated()), id: \.offset) { _, token in
                Text(token.text)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(tokenColor(for: token.type).opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    private func rstField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(defaultRST, text: text)
                .font(.caption.monospaced())
                .frame(width: 40, height: 36)
                .multilineTextAlignment(.center)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .keyboardType(.numberPad)
        }
    }

    private func tokenColor(for type: TokenType) -> Color {
        switch type {
        case .callsign: .blue
        case .rstSent,
             .rstReceived: .green
        case .park: .orange
        case .grid: .purple
        case .state: .cyan
        case .notes: .gray
        }
    }

    private func logFromInput() {
        let trimmed = callsignInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }

        var data = QuickLogData()

        // Try quick entry parse first
        if let result = QuickEntryParser.parse(trimmed) {
            data.callsign = result.callsign
            data.rstSent = result.rstSent ?? effectiveRST(rstSent)
            data.rstReceived = result.rstReceived ?? effectiveRST(rstReceived)
            data.theirParkReference = result.theirPark
            data.theirGrid = result.theirGrid
            data.state = result.state
        } else {
            // Single callsign
            data.callsign = trimmed.uppercased()
            data.rstSent = effectiveRST(rstSent)
            data.rstReceived = effectiveRST(rstReceived)
        }

        data.mode = currentMode
        data.frequency = currentFrequency
        data.band = currentFrequency.map {
            LoggingSession.bandForFrequency($0)
        } ?? "Unknown"

        onLog(data)

        // Reset form
        callsignInput = ""
        rstSent = ""
        rstReceived = ""
    }

    private func effectiveRST(_ value: String) -> String {
        value.isEmpty ? defaultRST : value
    }
}

// MARK: - QuickLogData

/// Data collected from the quick log form
struct QuickLogData {
    var callsign: String = ""
    var band: String = "Unknown"
    var mode: String = "CW"
    var frequency: Double?
    var rstSent: String = "599"
    var rstReceived: String = "599"
    var theirParkReference: String?
    var theirGrid: String?
    var state: String?
}
