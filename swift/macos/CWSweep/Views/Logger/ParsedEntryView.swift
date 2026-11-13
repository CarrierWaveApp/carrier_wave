import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - ParsedEntryView

/// Single-line parsed QSO entry field.
/// User types everything into one text field; the parser extracts callsign,
/// frequency, RST, mode, park references, etc. in real time.
struct ParsedEntryView: View {
    // MARK: Internal

    let radioManager: RadioManager
    var activeSession: LoggingSession?
    /// When set, the entry bar parses contest exchanges (using the definition)
    /// and routes Enter to the contest manager instead of inserting a raw QSO.
    /// Nil for non-contest sessions — keeps every other call site unchanged.
    var contestManager: ContestManager?
    var contestDefinition: ContestDefinition?

    @State var entryDXCCEntity: String?
    @State var entryNeededStatus: NeededStatus = .unknown
    @State var callsignInfo: CallsignInfo?
    @State var poloEntry: PoloNotesEntry?
    @State var combinedEmoji: String?
    @State var callsignLookupTask: Task<Void, Never>?
    @Environment(\.modelContext) var modelContext
    @Environment(DXCCLookupService.self) var dxccLookup
    @Environment(DXCCNeededChecker.self) var neededChecker

    @Environment(SelectionState.self) var selectionState

    @State var entryText = ""
    /// When non-nil, we're editing an existing QSO instead of creating a new one.
    @State var editingQSOId: UUID?
    @State var parsedResult: QuickEntryResult?
    /// Contest exchange parsed from the entry line (named fields keyed by
    /// `ContestExchangeField.name`). Only populated when contest mode is on.
    @State var parsedContestFields: [String: String] = [:]
    @State var parsedContestSerial: Int?
    @State var parsedContestRSTReceived: String?
    /// Last live dupe/mult check result for the currently-typed callsign.
    @State var liveDupe: ContestDupeStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Entry field
            HStack {
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

                Button("Log") { logQSO() }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(!canLog)

                if radioManager.isConnected, radioManager.frequency > 0 {
                    Divider()
                        .frame(height: 16)
                    RadioFrequencyBadge(radioManager: radioManager)
                }
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
                    dxccEntity: entryDXCCEntity,
                    neededStatus: entryNeededStatus,
                    callsignInfo: callsignInfo,
                    poloEntry: poloEntry,
                    combinedEmoji: combinedEmoji
                )
            }

            // Contest-mode chrome: exchange summary, dupe/mult banner, CW macros.
            contestExtras
        }
        .onAppear {
            if !vimEngine.isEnabled {
                isEntryFocused = true
            }
        }
        .onChange(of: isEntryFocused) { _, focused in
            if focused, vimEngine.isEnabled, vimEngine.mode != .entry {
                vimEngine.mode = .entry
            }
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
        .onChange(of: selectionState.editingQSOId) { _, newId in
            guard let newId else {
                return
            }
            selectionState.editingQSOId = nil
            populateForEdit(qsoId: newId)
        }
        .onChange(of: vimEngine.mode) { oldMode, newMode in
            if newMode == .entry {
                isEntryFocused = true
                // Move cursor to end after focus (avoid selecting all text)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                        let end = editor.string.count
                        editor.setSelectedRange(NSRange(location: end, length: 0))
                    }
                }
            } else if oldMode == .entry, !vimEngine.shouldLogEntry {
                // Escape exits without logging — clear entry
                editingQSOId = nil
                clearEntry()
                isEntryFocused = false
            } else if oldMode == .entry {
                // Return logged — logQSO already cleared, just unfocus
                isEntryFocused = false
            }
        }
        .onChange(of: vimEngine.shouldLogEntry) { _, shouldLog in
            if shouldLog {
                logQSO()
                vimEngine.shouldLogEntry = false
            }
        }
    }

    func clearEntry() {
        entryText = ""
        editingQSOId = nil
        parsedResult = nil
        parsedContestFields = [:]
        parsedContestSerial = nil
        parsedContestRSTReceived = nil
        liveDupe = nil
        selectionState.entryInProgress = false
        selectionState.entryCallsignGrid = nil
        clearCallsignLookup()
    }

    // MARK: Private

    private enum HistoryDirection { case up, down }

    @State private var history: [String] = []
    @State private var historyIndex: Int?
    @Environment(VimEngine.self) private var vimEngine
    @FocusState private var isEntryFocused: Bool

    private var canLog: Bool {
        parsedResult != nil || extractLeadingCallsign(entryText) != nil
    }

    private var currentCallsign: String {
        (try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign)) ?? ""
    }

    private func logQSO() {
        if let editId = editingQSOId {
            updateExistingQSO(id: editId)
        } else if let manager = contestManager, let definition = contestDefinition {
            logContestQSO(manager: manager, definition: definition)
        } else {
            insertNewQSO()
        }
    }

    private func insertNewQSO() {
        // Guard against multiple invocations (onSubmit + keyboardShortcut + vim signal)
        let currentText = entryText
        guard !currentText.isEmpty else {
            return
        }

        let callsign = parsedResult?.callsign.uppercased() ?? extractLeadingCallsign(currentText)
        guard let callsign else {
            return
        }

        let session = activeSession
        let result = parsedResult

        // Clear immediately to prevent re-entry from parallel paths
        history.append(currentText)
        historyIndex = nil
        clearEntry()

        let frequency = result?.frequency ?? radioManager.frequency
        let mode = radioManager.mode.isEmpty ? "CW" : radioManager.mode
        let band = result?.band ?? BandUtilities.deriveBand(
            from: frequency * 1_000
        ) ?? "Unknown"

        // Resolve park from explicit entry or spot cache
        let theirPark = result?.theirPark ?? selectionState.spotParkCache[callsign]

        let qso = QSO(
            callsign: callsign,
            band: band,
            mode: mode.uppercased(),
            frequency: frequency > 0 ? frequency : nil,
            timestamp: Date(),
            rstSent: result?.rstSent ?? (mode == "SSB" ? "59" : "599"),
            rstReceived: result?.rstReceived ?? (mode == "SSB" ? "59" : "599"),
            myCallsign: session?.myCallsign ?? currentCallsign,
            myGrid: session?.myGrid,
            theirGrid: result?.theirGrid,
            parkReference: session?.parkReference,
            theirParkReference: theirPark,
            importSource: .logger
        )

        if let session {
            qso.loggingSessionId = session.id
            qso.cloudDirtyFlag = true
            qso.modifiedAt = Date()
        }

        modelContext.insert(qso)
        session?.incrementQSOCount()
        try? CwStoreSeams.save(modelContext, qsos: [qso], sessions: session.map { [$0] } ?? [])
        QueryFacade.mirrorQSO(qso)
        selectionState.logInsertedQSORow = QSOTableRow(from: qso)
        enrichQSOInBackground(qso)
    }

    private func updateExistingQSO(id: UUID) {
        let currentText = entryText
        guard !currentText.isEmpty else {
            return
        }
        let callsign = parsedResult?.callsign.uppercased() ?? extractLeadingCallsign(currentText)
        guard let callsign else {
            return
        }

        let result = parsedResult
        editingQSOId = nil
        history.append(currentText)
        historyIndex = nil
        clearEntry()

        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == id }, limit: 1
        )
        guard let qso = try? modelContext.boundedFetch(descriptor).first else {
            return
        }

        let frequency = result?.frequency ?? radioManager.frequency
        let mode = radioManager.mode.isEmpty ? "CW" : radioManager.mode
        qso.callsign = callsign
        qso.frequency = frequency > 0 ? frequency : nil
        qso.mode = mode.uppercased()
        qso.band = result?.band ?? BandUtilities.deriveBand(from: frequency * 1_000) ?? qso.band
        qso.rstSent = result?.rstSent ?? qso.rstSent
        qso.rstReceived = result?.rstReceived ?? qso.rstReceived
        qso.theirGrid = result?.theirGrid ?? qso.theirGrid
        qso.theirParkReference = result?.theirPark
            ?? selectionState.spotParkCache[callsign] ?? qso.theirParkReference
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        try? CwStoreSeams.save(modelContext, qsos: [qso])
        selectionState.logUpdatedQSORow = QSOTableRow(from: qso)
        enrichQSOInBackground(qso)
    }

    private func populateForEdit(qsoId: UUID) {
        let descriptor = BoundedDescriptor<QSO>(
            predicate: #Predicate { $0.id == qsoId }, limit: 1
        )
        guard let qso = try? modelContext.boundedFetch(descriptor).first else {
            return
        }
        editingQSOId = qsoId
        var tokens: [String] = [qso.callsign]
        if let freq = qso.frequency {
            tokens.append(String(format: "%.3f", freq))
        }
        tokens.append(qso.mode)
        if let rst = qso.rstReceived {
            tokens.append("\(rst)R")
        }
        if let rst = qso.rstSent {
            tokens.append("\(rst)S")
        }
        if let park = qso.theirParkReference {
            tokens.append(park)
        }
        if let grid = qso.theirGrid {
            tokens.append(grid)
        }
        entryText = tokens.joined(separator: " ")
        parseEntry(entryText)
        isEntryFocused = true
    }

    private func recallHistory(direction: HistoryDirection) {
        guard !history.isEmpty else {
            return
        }
        switch direction {
        case .up:
            let newIndex = historyIndex.map { max(0, $0 - 1) } ?? (history.count - 1)
            historyIndex = newIndex
            entryText = history[newIndex]
        case .down:
            guard let index = historyIndex else {
                return
            }
            let next = index + 1
            if next >= history.count {
                historyIndex = nil; entryText = ""
            } else {
                historyIndex = next; entryText = history[next]
            }
        }
    }
}

// MARK: - RadioFrequencyBadge

/// Compact live frequency/mode indicator for the entry bar.
private struct RadioFrequencyBadge: View {
    let radioManager: RadioManager

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text(String(format: "%.3f", radioManager.frequency))
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
            Text(radioManager.mode)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(String(format: "%.3f", radioManager.frequency)) MHz, \(radioManager.mode)"
        )
    }
}
