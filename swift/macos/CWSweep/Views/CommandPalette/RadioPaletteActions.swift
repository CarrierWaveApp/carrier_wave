import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RadioPaletteView + Actions

extension RadioPaletteView {
    /// Strip a leading slot prefix ("a ", "b ", "A ", "B ") if present and
    /// return the remainder + the resolved slot. Slot tokens with no
    /// trailing argument (e.g. "a" by itself) are not recognized as
    /// prefixes — only `a <command>` triggers the path.
    private func extractSlotPrefix(_ raw: String) -> (slot: RadioSlot?, rest: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2,
              let slot = RadioSlot(rawValue: parts[0].lowercased())
        else {
            return (nil, raw)
        }
        return (slot, String(parts[1]))
    }

    func executeCommand() {
        // Handle `>` bridge to app palette
        if searchText.hasPrefix(">") {
            dismiss()
            onSwitchToAppPalette?()
            return
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        // Slot focus / swap shortcuts evaluated before parsing because they
        // never hand off to RadioCommandParser.
        if trimmed.lowercased() == "swap" {
            Task { await radioManager.swapFrequencies(.a, .b) }
            dismiss()
            return
        }
        if trimmed.lowercased().hasPrefix("focus ") {
            let token = trimmed.dropFirst("focus ".count).trimmingCharacters(in: .whitespaces)
            if let slot = RadioSlot(rawValue: token.lowercased()) {
                radioManager.setFocusedSlot(slot)
            }
            dismiss()
            return
        }

        if trimmed.lowercased().hasPrefix("profile ") {
            dispatchProfileCommand(name: String(trimmed.dropFirst("profile ".count)))
            dismiss()
            return
        }

        if let intentName = intentPrefixStripped(trimmed) {
            dispatchIntentCommand(name: intentName)
            dismiss()
            return
        }

        if trimmed.uppercased().hasPrefix("SPOT") {
            dispatchSpotCommand(trimmed: trimmed)
            dismiss()
            return
        }

        executeRadioCommand()
        dismiss()
    }

    /// Tail of `executeCommand` after all keyword prefixes are dispatched —
    /// parses the input as a raw radio command (freq / mode / split / aliases)
    /// and routes it to `applyCommand`.
    private func executeRadioCommand() {
        let (slot, body) = extractSlotPrefix(searchText)
        let expanded = RadioCommandParser.expandAliases(body, aliases: RadioAliasStore.load())
        let (command, _) = RadioCommandParser.parse(expanded)
        guard !command.isEmpty else {
            return
        }

        let input = searchText.trimmingCharacters(in: .whitespaces)
        if !input.isEmpty {
            RadioPaletteHistory.add(input)
        }

        Task { await applyCommand(command, slot: slot) }
    }

    /// `SPOT [comment]` self-spot dispatch. Pulled out of `executeCommand`
    /// for body-length compliance.
    private func dispatchSpotCommand(trimmed: String) {
        let comment = trimmed.count > 4
            ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            : nil
        spotNow?(comment: comment.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `profile <name>` dispatch: `readback` runs the codec-over-serial harness,
    /// any other name resolves against `RadioStateProfile.builtIn(named:)`.
    func dispatchProfileCommand(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "readback" {
            Task { await RadioProfileReadbackRunner.run(on: radioManager) }
            return
        }
        if let profile = RadioStateProfile.builtIn(named: trimmed) {
            Task { await RadioProfileRunner.run(profile: profile, on: radioManager) }
        }
    }

    /// `operate <intent>` / `op <intent>` dispatch: resolves the intent, runs
    /// the planner against live radio state, and opens the existing macro
    /// run window with both the synthesized spec and the pre-computed diff.
    func dispatchIntentCommand(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard let intent = RadioIntent(rawValue: trimmed) else {
            return
        }
        Task { await OperateIntentRunner.run(intent: intent, on: radioManager) }
    }

    /// Recognize both `operate <name>` and the short `op <name>` form, return
    /// the bare intent name. Returns nil when the input isn't an intent
    /// command (so the caller falls through to ordinary radio commands).
    func intentPrefixStripped(_ trimmed: String) -> String? {
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("operate ") {
            return String(trimmed.dropFirst("operate ".count))
        }
        if lowered.hasPrefix("op ") {
            return String(trimmed.dropFirst("op ".count))
        }
        return nil
    }

    func applyCommand(_ command: RadioCommand, slot: RadioSlot? = nil) async {
        if let named = command.namedCommand {
            await applyNamedCommand(named)
            return
        }
        if let freq = command.frequencyMHz {
            await radioManager.tuneToFrequency(freq, slot: slot)
        }
        if let mode = command.mode {
            let resolved = RadioCommandParser.resolveMode(mode, frequencyMHz: command.frequencyMHz)
            await radioManager.setMode(resolved, slot: slot)
        }
        if let split = command.splitDirective {
            await applySplit(split, slot: slot)
        }
    }

    func applyNamedCommand(_ cmd: NamedCommand) async {
        switch cmd {
        case .lookup:
            break

        case let .spot(callsign, frequencyKHz):
            await applySpotCommand(callsign: callsign, frequencyKHz: frequencyKHz)

        case let .setPark(reference):
            updateActiveSession { $0.parkReference = reference }

        case let .setSummit(reference):
            updateActiveSession { $0.sotaReference = reference }

        case .setPower:
            break

        case .sendCQ:
            await applySendCQ()

        case let .sendCW(text):
            await radioManager.sendCW(text, fallback: winKeyerManager)

        case let .setSpeed(wpm):
            await radioManager.setCWSpeed(wpm, fallback: winKeyerManager)

        case .setContestMode:
            break

        case .findCall,
             .lastQSOs,
             .sessionCount:
            // Informational commands — results shown in palette UI, no side effects
            break
        }
    }

    func applySpotCommand(callsign: String, frequencyKHz: Double?) async {
        guard clusterManager.isConnected else {
            return
        }
        let freq = frequencyKHz ?? (radioManager.frequency * 1_000)
        let spotCmd = "DX \(String(format: "%.1f", freq)) \(callsign)"
        clusterManager.sendCommand(spotCmd)
    }

    func applySendCQ() async {
        let message = "CQ CQ CQ DE \(myCallsign) \(myCallsign) K"
        await radioManager.sendCW(message, fallback: winKeyerManager)
    }

    func updateActiveSession(_ update: (LoggingSession) -> Void) {
        guard let session = PaletteQSOQueries.activeSession(in: modelContext) else {
            return
        }
        update(session)
        try? CwStoreSeams.save(modelContext, sessions: [session])
    }

    func applySplit(_ split: SplitDirective, slot: RadioSlot? = nil) async {
        switch split {
        case let .up(kHz):
            await radioManager.setXIT(true, slot: slot)
            await radioManager.setXITOffset(Int(kHz * 1_000), slot: slot)
        case let .down(kHz):
            await radioManager.setXIT(true, slot: slot)
            await radioManager.setXITOffset(Int(-kHz * 1_000), slot: slot)
        case let .explicitFrequency(kHz):
            await radioManager.setXIT(true, slot: slot)
            let baseFreq = slot.flatMap { radioManager.slotStates[$0]?.frequency } ?? radioManager.frequency
            let currentKHz = baseFreq * 1_000
            let offsetHz = Int((kHz - currentKHz) * 1_000)
            await radioManager.setXITOffset(offsetHz, slot: slot)
        case .off:
            await radioManager.clearRITXIT(slot: slot)
        }
    }

    func navigateHistory(direction: HistoryDirection) {
        guard !recentCommands.isEmpty else {
            return
        }

        switch direction {
        case .up:
            if let current = historyIndex {
                historyIndex = min(current + 1, recentCommands.count - 1)
            } else {
                historyIndex = 0
            }
        case .down:
            if let current = historyIndex {
                if current <= 0 {
                    historyIndex = nil
                    searchText = ""
                    return
                }
                historyIndex = current - 1
            }
        }

        if let idx = historyIndex, idx < recentCommands.count {
            searchText = recentCommands[idx]
        }
    }

    /// Fetch QSO count for the active session (0 when no session is active).
    /// Shared with vim `:count` via `PaletteQSOQueries`.
    func fetchSessionQSOCount() -> Int {
        PaletteQSOQueries.sessionQSOCount(in: modelContext) ?? 0
    }

    /// Search log for QSOs matching a callsign. Shared with vim `:find`.
    func fetchMatchingQSOs(callsign: String) -> [QSOSearchResult] {
        PaletteQSOQueries.matchingQSOs(callsign: callsign, in: modelContext)
    }

    /// Fetch the most recent N QSOs. Shared with vim `:last`.
    func fetchRecentQSOs(count: Int) -> [QSOSearchResult] {
        PaletteQSOQueries.recentQSOs(count: count, in: modelContext)
    }
}

// MARK: - RadioAliasStore

/// UserDefaults-backed store for custom command aliases
enum RadioAliasStore {
    // MARK: Internal

    static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func save(_ aliases: [String: String]) {
        UserDefaults.standard.set(aliases, forKey: key)
    }

    static func add(alias: String, expansion: String) {
        var aliases = load()
        aliases[alias.uppercased()] = expansion
        save(aliases)
    }

    static func remove(alias: String) {
        var aliases = load()
        aliases.removeValue(forKey: alias.uppercased())
        save(aliases)
    }

    // MARK: Private

    private static let key = "radioPaletteAliases"
}
