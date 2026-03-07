import CarrierWaveCore
import CarrierWaveData
import SwiftUI

// MARK: - RadioPaletteView + Command Summary

extension RadioPaletteView {
    func commandSummary(_ command: RadioCommand) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let named = command.namedCommand {
                namedCommandSummary(named)
            }
            if let freq = command.frequencyMHz {
                summaryRow("Frequency", FrequencyFormatter.formatWithUnit(freq))
            }
            if let mode = command.mode {
                let resolved = RadioCommandParser.resolveMode(mode, frequencyMHz: command.frequencyMHz)
                if resolved != mode {
                    summaryRow("Mode", "\(mode) (\(resolved))")
                } else {
                    summaryRow("Mode", mode)
                }
            }
            if let split = command.splitDirective {
                summaryRow("Split", split.description)
            }
        }
    }

    func namedCommandSummary(_ cmd: NamedCommand) -> some View {
        Group {
            switch cmd {
            case let .lookup(callsign):
                summaryRow("Action", "Look up \(callsign)")
            case let .spot(callsign, freq):
                spotSummary(callsign: callsign, freq: freq)
            case let .setPark(ref):
                summaryRow("Action", "Set POTA park to \(ref)")
            case let .setSummit(ref):
                summaryRow("Action", "Set SOTA summit to \(ref)")
            case let .setPower(watts):
                summaryRow("Action", "Set power to \(watts)W")
            case .sendCQ:
                sendCQSummary
            case let .setSpeed(wpm):
                speedSummary(wpm: wpm)
            case let .setContestMode(mode):
                contestModeSummary(mode: mode)
            case let .findCall(callsign):
                findCallSummary(callsign: callsign)
            case let .lastQSOs(count):
                lastQSOsSummary(count: count)
            case .sessionCount:
                sessionCountSummary
            }
        }
    }

    // MARK: - Summary Helpers

    func spotSummary(callsign: String, freq: Double?) -> some View {
        Group {
            summaryRow("Action", "Spot \(callsign)")
            if let freqKHz = freq {
                summaryRow("Frequency", FrequencyFormatter.formatWithUnit(freqKHz / 1_000))
            } else {
                summaryRow("Frequency", "Current radio frequency")
            }
            if !clusterManager.isConnected {
                summaryRow("Warning", "Cluster not connected")
            }
        }
    }

    var sendCQSummary: some View {
        Group {
            summaryRow("Action", "Send CQ macro (F1)")
            if !winKeyerManager.isConnected {
                summaryRow("Warning", "WinKeyer not connected")
            }
        }
    }

    func speedSummary(wpm: Int) -> some View {
        Group {
            summaryRow("Action", "Set CW speed to \(wpm) WPM")
            if winKeyerManager.isConnected {
                summaryRow("Current", "\(winKeyerManager.speed) WPM")
            } else {
                summaryRow("Warning", "WinKeyer not connected")
            }
        }
    }

    func contestModeSummary(mode: ContestModeValue) -> some View {
        let label = mode == .run ? "RUN (CQ)" : "Search & Pounce"
        return Group {
            summaryRow("Action", "Set contest mode: \(label)")
            if !contestManager.isActive {
                summaryRow("Warning", "No contest active")
            }
        }
    }

    func findCallSummary(callsign: String) -> some View {
        let results = fetchMatchingQSOs(callsign: callsign)
        return Group {
            summaryRow("Action", "Search log for \(callsign)")
            if results.isEmpty {
                summaryRow("Result", "No QSOs found")
            } else {
                summaryRow("Found", "\(results.count) QSO\(results.count == 1 ? "" : "s")")
                ForEach(results.prefix(5)) { qso in
                    qsoResultRow(qso)
                }
            }
        }
    }

    func lastQSOsSummary(count: Int) -> some View {
        let results = fetchRecentQSOs(count: count)
        return Group {
            summaryRow("Action", "Last \(count) QSOs")
            ForEach(results) { qso in
                qsoResultRow(qso)
            }
            if results.isEmpty {
                summaryRow("Result", "No QSOs in log")
            }
        }
    }

    var sessionCountSummary: some View {
        let count = fetchSessionQSOCount()
        return Group {
            summaryRow("Action", "Session QSO count")
            summaryRow("Count", "\(count)")
        }
    }

    func qsoResultRow(_ qso: QSOSearchResult) -> some View {
        HStack {
            Text(qso.callsign)
                .font(.caption.weight(.medium).monospacedDigit())
                .frame(width: 70, alignment: .trailing)
            Text("\(qso.band) \(qso.mode)")
                .font(.caption.monospacedDigit())
            Text(qso.timestamp, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
        }
    }
}
