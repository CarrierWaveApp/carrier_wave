import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ParsedEntryView

/// Single-line parsed QSO entry field.
/// User types everything into one text field; the parser extracts callsign,
/// frequency, RST, mode, park references, etc. in real time.
/// When a contest is active, also runs ContestExchangeParser and checks dupes.
struct ParsedEntryView: View {
    // MARK: Internal

    let radioManager: RadioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Entry field
            HStack {
                if contestManager.isActive {
                    Text("QSO #\(contestManager.currentSerial)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Callsign RST Freq Mode Park...", text: $entryText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($isEntryFocused)
                    .onSubmit { logQSO() }
                    .onChange(of: entryText) { _, newValue in
                        parseEntry(newValue)
                    }
                    .onKeyPress(.escape) {
                        clearEntry()
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        recallHistory(direction: .up)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        recallHistory(direction: .down)
                        return .handled
                    }

                if contestManager.isActive, let dupeStatus {
                    DupeIndicator(status: dupeStatus)
                }

                Button("Log") { logQSO() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(parsedResult == nil)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            )

            // Parsed field summary
            if !entryText.isEmpty {
                ParsedFieldSummary(
                    result: parsedResult,
                    radioManager: radioManager,
                    contestResult: contestManager.isActive ? contestParseResult : nil,
                    dupeStatus: contestManager.isActive ? dupeStatus : nil
                )
            }
        }
        .onAppear {
            isEntryFocused = true
        }
        .onChange(of: selectionState.requestEntryFocus) { _, newValue in
            if newValue {
                isEntryFocused = true
                selectionState.requestEntryFocus = false
            }
        }
        .onChange(of: selectionState.pendingSpotEntry) { _, newValue in
            if let entry = newValue {
                entryText = entry
                selectionState.pendingSpotEntry = nil
                isEntryFocused = true
            }
        }
    }

    // MARK: Private

    private enum HistoryDirection { case up, down }

    private struct ContestFields {
        var name: String?
        var serialSent: Int?
        var serialReceived: Int?
        var exchangeSent: String?
        var exchangeReceived: String?
    }

    @State private var entryText = ""
    @State private var parsedResult: QuickEntryResult?
    @State private var contestParseResult: ContestParseResult?
    @State private var dupeStatus: DupeStatus?
    @State private var dupeCheckTask: Task<Void, Never>?
    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @Environment(\.modelContext) private var modelContext
    @Environment(ContestManager.self) private var contestManager
    @Environment(SelectionState.self) private var selectionState
    @FocusState private var isEntryFocused: Bool

    private var currentCallsign: String {
        (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign)) ?? ""
    }

    private func parseEntry(_ text: String) {
        guard !text.isEmpty else {
            parsedResult = nil
            contestParseResult = nil
            dupeStatus = nil
            return
        }
        let result = QuickEntryParser.parse(text)
        parsedResult = result

        if contestManager.isActive, let definition = contestManager.definition, let result {
            parseContestExchange(text: text, result: result, definition: definition)
        } else {
            contestParseResult = nil
            dupeStatus = nil
        }
    }

    private func parseContestExchange(
        text: String,
        result: QuickEntryResult,
        definition: ContestDefinition
    ) {
        let extraTokens = extractUnmatchedTokens(text: text, result: result)

        contestParseResult = ContestExchangeParser.parse(
            tokens: extraTokens,
            definition: definition
        )

        dupeCheckTask?.cancel()
        dupeCheckTask = Task {
            let band = result.band ?? BandUtilities.deriveBand(
                from: radioManager.frequency * 1_000
            ) ?? "Unknown"
            let status = await contestManager.checkDupe(
                callsign: result.callsign,
                band: band
            )
            if !Task.isCancelled {
                dupeStatus = status
            }
        }
    }

    private func extractUnmatchedTokens(
        text: String,
        result: QuickEntryResult
    ) -> [String] {
        let allTokens = text.split(separator: " ").map(String.init)
        let matched: [String?] = [
            result.frequency.map { String(format: "%.3f", $0) },
            result.rstSent, result.rstReceived,
            result.theirPark, result.theirGrid,
            result.band, result.state,
        ]
        let matchedUpper = Set(matched.compactMap { $0?.uppercased() })
        return allTokens.dropFirst().filter { !matchedUpper.contains($0.uppercased()) }
    }

    private func logQSO() {
        guard let result = parsedResult else {
            return
        }

        let frequency = result.frequency ?? radioManager.frequency
        let mode = radioManager.mode.isEmpty ? "CW" : radioManager.mode
        let band = result.band ?? BandUtilities.deriveBand(
            from: frequency * 1_000
        ) ?? "Unknown"

        let contest = buildContestFields()

        let qso = QSO(
            callsign: result.callsign.uppercased(),
            band: band,
            mode: mode.uppercased(),
            frequency: frequency > 0 ? frequency : nil,
            timestamp: Date(),
            rstSent: result.rstSent ?? (mode == "SSB" ? "59" : "599"),
            rstReceived: result.rstReceived ?? (mode == "SSB" ? "59" : "599"),
            myCallsign: currentCallsign,
            myGrid: nil,
            theirGrid: result.theirGrid,
            parkReference: nil,
            theirParkReference: result.theirPark,
            importSource: .logger,
            contestName: contest.name,
            contestSerialSent: contest.serialSent,
            contestSerialReceived: contest.serialReceived,
            contestExchangeSent: contest.exchangeSent,
            contestExchangeReceived: contest.exchangeReceived
        )

        if let session = contestManager.activeSession {
            qso.loggingSessionId = session.id
            session.incrementQSOCount()
        }

        modelContext.insert(qso)
        registerContestQSO(qso, contest: contest)

        history.append(entryText)
        historyIndex = nil
        clearEntry()
    }

    private func buildContestFields() -> ContestFields {
        var fields = ContestFields()
        guard contestManager.isActive, let definition = contestManager.definition else {
            return fields
        }
        fields.name = definition.id

        if let contestParse = contestParseResult {
            let parts = definition.exchange.fields.compactMap { field -> String? in
                field.type == .rst ? nil : contestParse.fields[field.id]
            }
            fields.exchangeReceived = parts.joined(separator: " ")
            fields.serialReceived = contestParse.serialReceived
        }

        let sentParts = definition.exchange.fields.compactMap(\.defaultValue)
        fields.exchangeSent = sentParts.joined(separator: " ")
        return fields
    }

    private func registerContestQSO(_ qso: QSO, contest: ContestFields) {
        guard contestManager.isActive else {
            return
        }
        Task {
            let serialSent = await contestManager.nextSerial()
            qso.contestSerialSent = serialSent

            let snapshot = QSOContestSnapshot(
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp,
                rstSent: qso.rstSent ?? "599",
                rstReceived: qso.rstReceived ?? "599",
                exchangeSent: contest.exchangeSent ?? "",
                exchangeReceived: contest.exchangeReceived ?? "",
                serialSent: serialSent,
                serialReceived: contest.serialReceived,
                country: qso.country,
                dxcc: qso.dxcc,
                cqZone: contestParseResult?.fields["cqZone"].flatMap { Int($0) },
                ituZone: contestParseResult?.fields["ituZone"].flatMap { Int($0) },
                state: contestParseResult?.fields["state"],
                arrlSection: contestParseResult?.fields["section"],
                county: contestParseResult?.fields["county"]
            )
            await contestManager.logContestQSO(snapshot)
        }
    }

    private func clearEntry() {
        entryText = ""
        parsedResult = nil
        contestParseResult = nil
        dupeStatus = nil
    }

    private func recallHistory(direction: HistoryDirection) {
        guard !history.isEmpty else {
            return
        }
        switch direction {
        case .up:
            if let index = historyIndex {
                let newIndex = max(0, index - 1)
                historyIndex = newIndex
                entryText = history[newIndex]
            } else {
                historyIndex = history.count - 1
                entryText = history[history.count - 1]
            }
        case .down:
            if let index = historyIndex {
                let newIndex = index + 1
                if newIndex >= history.count {
                    historyIndex = nil
                    entryText = ""
                } else {
                    historyIndex = newIndex
                    entryText = history[newIndex]
                }
            }
        }
    }
}

// MARK: - DupeIndicator

struct DupeIndicator: View {
    let status: DupeStatus

    var body: some View {
        switch status {
        case let .newMultiplier(value, _):
            Label {
                Text("NEW MULT \(value)")
                    .font(.caption.bold())
            } icon: {
                Image(systemName: "star.fill")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .systemGreen), in: Capsule())
            .accessibilityLabel("New multiplier: \(value)")
        case .newStation:
            Text("NEW")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .systemTeal), in: Capsule())
                .accessibilityLabel("New station")
        case .dupe:
            Label {
                Text("DUPE")
                    .font(.caption.bold())
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .systemRed), in: Capsule())
            .accessibilityLabel("Duplicate contact")
        }
    }
}
