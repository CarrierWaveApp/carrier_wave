import CarrierWaveData
import UIKit

// MARK: - Contest Lifecycle and QSO Logging

extension LoggerView {
    /// Initialize contest manager when a contest session is active
    func initContestManagerIfNeeded() {
        guard let session = sessionManager?.activeSession,
              session.isContest,
              let contestId = session.contestId,
              contestManager == nil
        else {
            return
        }

        let manager = ContestManager()
        contestManager = manager

        Task {
            guard let definition = await ContestDefinitions.definition(id: contestId) else {
                return
            }
            let existing = buildContestRecords(from: sessionQSOs)
            let myStation = buildMyStation(for: session)
            await manager.startContest(
                definition: definition,
                session: session,
                myStation: myStation,
                existingQSOs: existing
            )
        }
    }

    /// Check dupe status when callsign changes in contest mode
    func checkContestDupe(_ callsign: String) {
        guard let manager = contestManager, manager.isActive,
              !callsign.isEmpty,
              let session = sessionManager?.activeSession
        else {
            return
        }

        let band = session.frequency.flatMap {
            LoggingSession.bandForFrequency($0)
        } ?? "Unknown"
        let mode = session.mode

        Task {
            _ = await manager.checkDupe(callsign: callsign, band: band, mode: mode)
        }
    }

    /// Register a QSO with the contest engine after logging
    func registerContestQSO(
        _ qso: QSO,
        exchangeReceived: String
    ) {
        guard let manager = contestManager, manager.isActive,
              let session = sessionManager?.activeSession,
              let definition = manager.definition
        else {
            return
        }

        let received = parseExchange(exchangeReceived, into: definition)
        let sent = parseExchange(qso.contestExchangeSent ?? "", into: definition, useSent: true)
        let record = ContestQSORecord(
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            timestamp: qso.timestamp,
            sentExchange: sent,
            receivedExchange: received,
            serialSent: qso.contestSerialSent,
            serialReceived: qso.contestSerialReceived,
            theirCountry: qso.country
        )

        Task {
            await manager.logContestQSO(record, session: session)
        }
    }

    /// Build contest records from existing QSOs for engine initialization
    func buildContestRecords(from qsos: [QSO]) -> [ContestQSORecord] {
        guard let manager = contestManager, let definition = manager.definition else {
            return []
        }
        return qsos.filter(\.isContestQSO).map { qso in
            let received = parseExchange(qso.contestExchangeReceived ?? "", into: definition)
            let sent = parseExchange(qso.contestExchangeSent ?? "", into: definition, useSent: true)
            return ContestQSORecord(
                callsign: qso.callsign,
                band: qso.band,
                mode: qso.mode,
                timestamp: qso.timestamp,
                sentExchange: sent,
                receivedExchange: received,
                serialSent: qso.contestSerialSent,
                serialReceived: qso.contestSerialReceived,
                theirCountry: qso.country
            )
        }
    }

    /// Build the contest exchange string from form field values
    func buildContestExchange() -> String {
        guard let definition = contestManager?.definition else {
            return ""
        }
        let parts = definition.exchange.received.compactMap { field -> String? in
            guard field.type != .signalReport else {
                return nil
            }
            return contestExchangeValues[field.name]?.nonEmpty
        }
        return parts.joined(separator: " ")
    }

    /// Build the sent exchange string (from session config defaults + autofill)
    func buildSentExchange() -> String {
        guard let definition = contestManager?.definition,
              let session = sessionManager?.activeSession
        else {
            return ""
        }
        let myStation = buildMyStation(for: session)

        var parts: [String] = []
        for field in definition.exchange.sent {
            switch field.type {
            case .signalReport:
                continue
            case .serialNumber:
                if let serial = contestManager?.currentSerial {
                    parts.append(String(serial))
                }
            default:
                if let source = field.autofill,
                   let value = myStation.autofillValue(for: source)
                {
                    parts.append(value)
                } else if let defaultValue = field.defaultValue?.stringValue {
                    parts.append(defaultValue)
                }
            }
        }
        return parts.joined(separator: " ")
    }

    /// Clear contest exchange fields after logging
    func resetContestFields() {
        contestExchangeValues = [:]
        prefilledContestFields = [:]
        contestManager?.lastDupeStatus = nil
    }

    /// Tear down contest manager when session ends
    func teardownContestManager() {
        contestManager?.endContest()
        contestManager = nil
        contestExchangeValues = [:]
        prefilledContestFields = [:]
    }

    // MARK: - Helpers

    private func parseExchange(
        _ raw: String,
        into definition: ContestDefinition,
        useSent: Bool = false
    ) -> [String: String] {
        let tokens = raw.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else {
            return [:]
        }
        let fields = useSent ? definition.exchange.sent : definition.exchange.received
        var out: [String: String] = [:]
        var cursor = 0
        for field in fields where field.type != .signalReport {
            guard cursor < tokens.count else {
                break
            }
            out[field.name] = tokens[cursor]
            cursor += 1
        }
        return out
    }

    private func buildMyStation(for session: LoggingSession) -> MyStationContext {
        MyStationContext(
            callsign: session.contestOperator ?? session.myCallsign,
            grid: session.myGrid,
            power: session.contestPower,
            classLabel: nil,
            name: nil
        )
    }
}
