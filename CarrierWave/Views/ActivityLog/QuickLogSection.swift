import CarrierWaveCore
import SwiftUI
import UIKit

// MARK: - QuickLogSection

/// Manual callsign entry section for the Activity Log.
/// Mirrors the Logger's callsign input + compact fields layout.
struct QuickLogSection: View {
    // MARK: Internal

    @Binding var currentMode: String
    @Binding var currentFrequency: Double?

    let spotCallsigns: [String]
    let contactCounts: [String: Int]
    let onLog: (QuickLogData) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Log")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            callsignRow

            // Callsign suggestions (SCP + spots)
            if !suggestions.isEmpty, detectedCommand == nil {
                SCPSuggestionsView(
                    suggestions: suggestions,
                    contactCounts: contactCounts,
                    spotCallsigns: Set(spotCallsigns.map { $0.uppercased() })
                ) { selected in
                    callsignInput = selected
                }
                .padding(.top, 4)
            }

            fieldsRow

            // Show quick entry preview if multi-token input
            if !parsedTokens.isEmpty {
                quickEntryPreview
            }
        }
        .onChange(of: callsignInput) { _, newValue in
            suggestions = CallsignSuggestionProvider.suggestions(
                for: newValue,
                spotCallsigns: spotCallsigns,
                contactCounts: contactCounts
            )
        }
    }

    // MARK: Private

    @State private var callsignInput = ""
    @State private var rstSent = ""
    @State private var rstReceived = ""
    @State private var suggestions: [String] = []
    @FocusState private var callsignFocused: Bool

    @ScaledMetric(relativeTo: .subheadline) private var fieldHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .subheadline) private var rstFieldWidth: CGFloat = 50

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

    private var isInputEmpty: Bool {
        callsignInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var detectedCommand: LoggerCommand? {
        LoggerCommand.parse(callsignInput)
    }

    // MARK: - Callsign Row (matches Logger callsignInputSection)

    private var callsignRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                CallsignTextField(
                    "Callsign or quick entry...",
                    text: $callsignInput,
                    isFocused: $callsignFocused,
                    fontSize: 15,
                    showCommands: true,
                    onSubmit: { logFromInput() },
                    onCommand: { command in executeCommand(command) }
                )

                Button {
                    callsignInput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .opacity(callsignInput.isEmpty ? 0 : 1)
                .disabled(callsignInput.isEmpty)
                .accessibilityLabel("Clear callsign")
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                logFromInput()
            } label: {
                Text("LOG")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity)
                    .frame(width: 48)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isInputEmpty)
            .opacity(isInputEmpty ? 0.4 : 1)
            .accessibilityLabel("Log QSO")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Fields Row (matches Logger compactFieldsSection)

    private var fieldsRow: some View {
        HStack(spacing: 8) {
            compactField(label: "Sent", placeholder: defaultRST, text: $rstSent, width: rstFieldWidth)
                .keyboardType(.numberPad)
            compactField(label: "Rcvd", placeholder: defaultRST, text: $rstReceived, width: rstFieldWidth)
                .keyboardType(.numberPad)
            Spacer()
            bandModeLabel
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var bandModeLabel: some View {
        let band = currentFrequency.map {
            LoggingSession.bandForFrequency($0)
        } ?? "No band"
        return Text("\(band) \(currentMode)")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
    }

    // MARK: - Quick Entry Preview

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

    // MARK: - Compact Field (matches Logger compactField)

    private func compactField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        width: CGFloat? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.subheadline.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 8)
                .frame(height: max(fieldHeight, 44))
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: width)
        }
    }

    // MARK: - Token Colors

    private func tokenColor(for type: TokenType) -> Color {
        switch type {
        case .callsign: .blue
        case .rstSent,
             .rstReceived: .green
        case .park: .orange
        case .grid: .purple
        case .state: .cyan
        case .frequency: .teal
        case .band: .indigo
        case .notes: .gray
        }
    }

    // MARK: - Logging

    private func logFromInput() {
        let trimmed = callsignInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return
        }

        // Check for commands first
        if let command = LoggerCommand.parse(trimmed) {
            executeCommand(command)
            callsignInput = ""
            return
        }

        var data = QuickLogData()

        // Try quick entry parse first
        if let result = QuickEntryParser.parse(trimmed) {
            data.callsign = result.callsign

            // Single RST applies to both sent and received
            if result.rstSent == nil, let rst = result.rstReceived {
                data.rstSent = rst
                data.rstReceived = rst
            } else {
                data.rstSent = result.rstSent ?? effectiveRST(rstSent)
                data.rstReceived = result.rstReceived ?? effectiveRST(rstReceived)
            }

            data.theirParkReference = result.theirPark
            data.theirGrid = result.theirGrid
            data.state = result.state
            data.notes = result.notes
            data.frequency = result.frequency ?? currentFrequency
            data.band = result.band ?? currentFrequency.map {
                LoggingSession.bandForFrequency($0)
            } ?? "Unknown"
        } else {
            // Single callsign
            data.callsign = trimmed.uppercased()
            data.rstSent = effectiveRST(rstSent)
            data.rstReceived = effectiveRST(rstReceived)
            data.frequency = currentFrequency
            data.band = currentFrequency.map {
                LoggingSession.bandForFrequency($0)
            } ?? "Unknown"
        }

        data.mode = currentMode

        onLog(data)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Reset form
        callsignInput = ""
        rstSent = ""
        rstReceived = ""
    }

    private func executeCommand(_ command: LoggerCommand) {
        switch command {
        case let .frequency(freq):
            currentFrequency = freq
        case let .mode(newMode):
            currentMode = newMode
        default:
            // Other commands (SPOT, RBN, etc.) not applicable in activity log
            break
        }
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
    var notes: String?
}
