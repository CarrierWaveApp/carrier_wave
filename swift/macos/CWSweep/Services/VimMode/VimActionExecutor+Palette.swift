import CarrierWaveCore
import CarrierWaveData
import Foundation

// MARK: - Command palette parity (CAR-211)

/// `:` commands that mirror command-palette actions which previously had no
/// vim equivalent. Each one routes through the same code path the palette
/// uses (`RadioManager` tune/mode, `ServerSyncService`, `PaletteQSOQueries`,
/// or a `SelectionState` request consumed by `WorkspaceView`) so behaviour
/// is identical whichever surface the operator reaches for.
extension VimActionExecutor {
    // MARK: Internal

    func executeRadioControlCommand(_ command: VimCommand) -> String? {
        switch command {
        case let .tuneFrequency(mhz):
            Task { await radioManager.tuneToFrequency(mhz) }
            return "Tune: \(String(format: "%.3f", mhz)) MHz"
        case let .setMode(mode):
            let current = radioManager.frequency > 0 ? radioManager.frequency : nil
            let resolved = RadioCommandParser.resolveMode(mode, frequencyMHz: current)
            Task { await radioManager.setMode(resolved) }
            return "Mode: \(resolved)"
        default:
            return nil
        }
    }

    func executeNavigationCommand(_ command: VimCommand) -> String? {
        switch command {
        case let .navigate(item):
            selectionState.vimNavigateTo = item
            return "Show: \(item.displayName)"
        case .syncNow:
            Task { await ServerSyncService.shared.syncPending() }
            return "Syncing\u{2026}"
        case .toggleInspector:
            return executeOpenInspector()
        case let .setRole(role):
            selectionState.vimSetRole = role
            return "Role: \(role.displayName)"
        default:
            return nil
        }
    }

    func executeInfoCommand(_ command: VimCommand) -> String? {
        switch command {
        case let .findCall(callsign):
            return describeFind(callsign)
        case let .lastQSOs(count):
            return describeLast(count)
        case .sessionCount:
            guard let count = PaletteQSOQueries.sessionQSOCount(in: modelContext) else {
                return "No active session"
            }
            return "Session: \(count) QSO\(count == 1 ? "" : "s")"
        default:
            return nil
        }
    }

    // MARK: Private

    /// Status-line cap for `:last` — the echo is a single line.
    private static let lastQSOsDisplayCap = 10

    private func describeFind(_ callsign: String) -> String {
        let results = PaletteQSOQueries.matchingQSOs(callsign: callsign, in: modelContext)
        guard let newest = results.first else {
            return "\(callsign): no QSOs"
        }
        let count = results.count >= PaletteQSOQueries.findLimit
            ? "\(PaletteQSOQueries.findLimit)+"
            : "\(results.count)"
        let plural = results.count == 1 ? "" : "s"
        let when = newest.timestamp.formatted(date: .abbreviated, time: .shortened)
        return "\(callsign): \(count) QSO\(plural), last \(when)"
    }

    private func describeLast(_ requested: Int) -> String {
        let count = min(requested, Self.lastQSOsDisplayCap)
        let results = PaletteQSOQueries.recentQSOs(count: count, in: modelContext)
        guard !results.isEmpty else {
            return "No QSOs in log"
        }
        let rows = results.map { qso in
            let stamp = qso.timestamp.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
            return "\(qso.callsign) \(qso.band) \(qso.mode) \(stamp)"
        }
        return rows.joined(separator: "  |  ")
    }
}
