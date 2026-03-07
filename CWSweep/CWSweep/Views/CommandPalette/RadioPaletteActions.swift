import CarrierWaveCore
import CarrierWaveData
import SwiftData
import SwiftUI

// MARK: - RadioPaletteView + Actions

extension RadioPaletteView {
    func executeCommand() {
        // Handle `>` bridge to app palette
        if searchText.hasPrefix(">") {
            dismiss()
            onSwitchToAppPalette?()
            return
        }

        let expanded = RadioCommandParser.expandAliases(searchText, aliases: RadioAliasStore.load())
        let (command, _) = RadioCommandParser.parse(expanded)
        guard !command.isEmpty else {
            dismiss()
            return
        }

        let input = searchText.trimmingCharacters(in: .whitespaces)
        if !input.isEmpty {
            RadioPaletteHistory.add(input)
        }

        Task {
            await applyCommand(command)
        }
        dismiss()
    }

    func applyCommand(_ command: RadioCommand) async {
        if let named = command.namedCommand {
            await applyNamedCommand(named)
            return
        }
        if let freq = command.frequencyMHz {
            try? await radioManager.tuneToFrequency(freq)
        }
        if let mode = command.mode {
            let resolved = RadioCommandParser.resolveMode(mode, frequencyMHz: command.frequencyMHz)
            try? await radioManager.setMode(resolved)
        }
        if let split = command.splitDirective {
            await applySplit(split)
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

        case let .setSpeed(wpm):
            await winKeyerManager.setSpeed(UInt8(clamping: wpm))

        case let .setContestMode(mode):
            contestManager.toggleToMode(mode)

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
        let context = KeyerContext(
            myCall: myCallsign,
            hisCall: "",
            serial: contestManager.currentSerial,
            exchange: "",
            frequency: radioManager.frequency
        )
        let message = await contestManager.keyerService.expandedMessage(slot: 1, context: context)
        await winKeyerManager.sendText(message)
    }

    func updateActiveSession(_ update: (LoggingSession) -> Void) {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let session = try? modelContext.fetch(descriptor).first else {
            return
        }
        update(session)
        try? modelContext.save()
    }

    func applySplit(_ split: SplitDirective) async {
        switch split {
        case let .up(kHz):
            try? await radioManager.setXIT(true)
            try? await radioManager.setXITOffset(Int(kHz * 1_000))
        case let .down(kHz):
            try? await radioManager.setXIT(true)
            try? await radioManager.setXITOffset(Int(-kHz * 1_000))
        case let .explicitFrequency(kHz):
            try? await radioManager.setXIT(true)
            let currentKHz = radioManager.frequency * 1_000
            let offsetHz = Int((kHz - currentKHz) * 1_000)
            try? await radioManager.setXITOffset(offsetHz)
        case .off:
            try? await radioManager.clearRITXIT()
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

    /// Fetch QSO count for the active session
    func fetchSessionQSOCount() -> Int {
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate<LoggingSession> { session in
                session.statusRawValue == "active"
            },
            sortBy: [SortDescriptor(\LoggingSession.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let session = try? modelContext.fetch(descriptor).first else {
            return 0
        }
        return session.qsoCount
    }

    /// Search log for QSOs matching a callsign
    func fetchMatchingQSOs(callsign: String) -> [QSOSearchResult] {
        let upper = callsign.uppercased()
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                qso.callsign.localizedStandardContains(upper)
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        guard let qsos = try? modelContext.fetch(descriptor) else {
            return []
        }
        return qsos.map { QSOSearchResult(from: $0) }
    }

    /// Fetch the most recent N QSOs
    func fetchRecentQSOs(count: Int) -> [QSOSearchResult] {
        let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]
        var descriptor = FetchDescriptor<QSO>(
            predicate: #Predicate<QSO> { qso in
                !qso.isHidden && !qso.callsign.isEmpty
            },
            sortBy: [SortDescriptor(\QSO.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = count + 10
        guard let qsos = try? modelContext.fetch(descriptor) else {
            return []
        }
        return qsos
            .filter { !metadataModes.contains($0.mode) }
            .prefix(count)
            .map { QSOSearchResult(from: $0) }
    }
}

// MARK: - QSOSearchResult

/// Lightweight snapshot for displaying QSO search results in the palette
struct QSOSearchResult: Identifiable, Sendable {
    // MARK: Lifecycle

    init(from qso: QSO) {
        id = qso.id
        callsign = qso.callsign
        timestamp = qso.timestamp
        band = qso.band
        mode = qso.mode
    }

    // MARK: Internal

    let id: UUID
    let callsign: String
    let timestamp: Date
    let band: String
    let mode: String
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
