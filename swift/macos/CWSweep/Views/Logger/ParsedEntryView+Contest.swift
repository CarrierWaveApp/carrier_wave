import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ParsedEntryView + Contest

/// Contest-aware add-ons for `ParsedEntryView`: parses the active contest's
/// exchange fields from the same single-line entry, surfaces a live dupe /
/// new-mult banner, attaches the CW macro bar when applicable, and routes
/// the Enter key through `ContestManager.logQSO` instead of inserting a
/// plain QSO. Lives in its own extension to keep the main entry view file
/// under the 500-line cap.
extension ParsedEntryView {
    // MARK: - Public surface used by the main view

    /// Compact chrome shown under the parsed-field summary whenever the entry
    /// is operating in contest mode. Empty view otherwise.
    @ViewBuilder
    var contestExtras: some View {
        if let manager = contestManager, let definition = contestDefinition {
            VStack(alignment: .leading, spacing: 6) {
                contestExchangeSummary(definition: definition)
                if let liveDupe, !entryText.isEmpty {
                    contestBanner(for: liveDupe)
                }
                if contestMode(definition: definition) == "CW" {
                    ContestMacroBar(
                        manager: manager,
                        callsign: contestCallsign() ?? ""
                    )
                    .padding(.horizontal, -12)
                }
            }
        }
    }

    /// Parse contest exchange tokens out of the entry line. Called from
    /// `parseEntry` after the standard quick-entry parser has run.
    func contestParseIfNeeded(text: String, leadingCallsign: String?) {
        guard let definition = contestDefinition else {
            parsedContestFields = [:]
            parsedContestSerial = nil
            parsedContestRSTReceived = nil
            liveDupe = nil
            return
        }
        let tokens = exchangeTokens(text: text, leadingCallsign: leadingCallsign)
        let parsed = ContestExchangeParser.parse(tokens: tokens, definition: definition)
        parsedContestFields = parsed.fields
        parsedContestSerial = parsed.serialReceived
        parsedContestRSTReceived = parsed.fields["rst"]
        Task { await refreshLiveDupe(definition: definition) }
    }

    /// Build a `ContestQSOEntry` from the parsed state and dispatch it to the
    /// active `ContestManager`. Mirrors what the standalone `ContestEntryBar`
    /// used to do.
    func logContestQSO(manager: ContestManager, definition: ContestDefinition) {
        guard let call = contestCallsign(), !call.isEmpty else {
            return
        }
        let mode = contestMode(definition: definition)
        let band = contestBand(definition: definition)
        let defaultReport = mode == "CW" ? "599" : "59"
        let rstSent = parsedResult?.rstSent ?? defaultReport
        let rstReceived = parsedContestRSTReceived ?? parsedResult?.rstReceived ?? defaultReport

        let frequencyMHz: Double? = {
            if radioManager.isConnected, radioManager.frequency > 0 {
                return radioManager.frequency
            }
            return parsedResult?.frequency
        }()

        let entry = ContestQSOEntry(
            callsign: call,
            band: band,
            mode: mode,
            rstSent: rstSent,
            rstReceived: rstReceived,
            serialReceived: parsedContestSerial,
            frequencyMHz: frequencyMHz,
            receivedFields: receivedFieldsExcludingRSTSerial()
        )

        clearEntry()
        Task { _ = await manager.logQSO(entry) }
    }

    // MARK: - Helpers

    private func exchangeTokens(text: String, leadingCallsign: String?) -> [String] {
        let raw = text
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map(String.init)
        guard !raw.isEmpty else {
            return []
        }
        // Drop the first token if it matches the detected callsign; otherwise
        // assume the operator hasn't typed an exchange yet.
        if let leadingCallsign,
           raw.first?.uppercased() == leadingCallsign.uppercased()
        {
            return Array(raw.dropFirst())
        }
        return Array(raw.dropFirst())
    }

    private func contestCallsign() -> String? {
        if let parsed = parsedResult?.callsign, !parsed.isEmpty {
            return parsed.uppercased()
        }
        return extractLeadingCallsign(entryText)
    }

    private func contestMode(definition: ContestDefinition) -> String {
        if radioManager.isConnected, !radioManager.mode.isEmpty {
            return radioManager.mode.uppercased()
        }
        return definition.modes.first ?? "CW"
    }

    private func contestBand(definition: ContestDefinition) -> String {
        if radioManager.isConnected, radioManager.frequency > 0,
           let band = BandUtilities.deriveBand(from: radioManager.frequency * 1_000)
        {
            return band
        }
        return parsedResult?.band ?? definition.bands.first ?? "20m"
    }

    private func receivedFieldsExcludingRSTSerial() -> [String: String] {
        var copy = parsedContestFields
        copy.removeValue(forKey: "rst")
        copy.removeValue(forKey: "serial")
        return copy
    }

    private func refreshLiveDupe(definition: ContestDefinition) async {
        guard let manager = contestManager else {
            return
        }
        guard let call = contestCallsign(), call.count >= 3 else {
            await MainActor.run { liveDupe = nil }
            return
        }
        let band = contestBand(definition: definition)
        let mode = contestMode(definition: definition)
        let status = await manager.checkDupe(callsign: call, band: band, mode: mode)
        await MainActor.run { liveDupe = status }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func contestExchangeSummary(definition: ContestDefinition) -> some View {
        let chips = exchangeChips(definition: definition)
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                    contestChip(label: chip.label, value: chip.value)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func exchangeChips(definition: ContestDefinition) -> [(label: String, value: String)] {
        definition.exchange.received.compactMap { field -> (String, String)? in
            let value: String? = parsedContestFields[field.name]
                ?? defaultValue(for: field, definition: definition)
            guard let value, !value.isEmpty else {
                return nil
            }
            return (field.label, value)
        }
    }

    private func defaultValue(for field: ContestExchangeField, definition: ContestDefinition) -> String? {
        if field.type == .signalReport {
            return contestMode(definition: definition) == "CW" ? "599" : "59"
        }
        return field.defaultValue?.stringValue
    }

    private func contestChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private func contestBanner(for status: ContestDupeStatus) -> some View {
        switch status {
        case .dupe:
            bannerLabel(
                text: "DUPE — already worked",
                color: .red,
                icon: "exclamationmark.triangle.fill"
            )
        case let .newMultiplier(_, value):
            bannerLabel(
                text: "NEW MULT — \(value)",
                color: .green,
                icon: "star.fill"
            )
        case .newStation:
            bannerLabel(
                text: "New station",
                color: .secondary,
                icon: "checkmark.circle"
            )
        }
    }

    private func bannerLabel(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}
