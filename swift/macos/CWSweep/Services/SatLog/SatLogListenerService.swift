// S.A.T. log listener service
//
// UI-facing facade for the CSN Technologies S.A.T. satellite-tracker log
// listener (CAR-343). Owns settings (enabled / transport / port, persisted in
// UserDefaults), the `SatLogListener` socket actor, and the parse → ingest
// hand-off onto the main actor. Configure the S.A.T.'s "QSO LOG IP" to this
// Mac's LAN address and `port`; every QSO it logs arrives as an ADIF record.

import CarrierWaveCore
import CarrierWaveData
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.jsvana.CWSweep", category: "SatLog")

// MARK: - SatLogReceivedRecord

/// One record seen by the listener, for the Settings "Recent records" list.
struct SatLogReceivedRecord: Identifiable, Sendable {
    enum Outcome: Sendable, Equatable {
        case logged
        case duplicate
        case skipped(String)
        case failed(String)
    }

    let id = UUID()
    let receivedAt: Date
    let callsign: String
    let band: String
    let mode: String
    let satName: String?
    let bandRx: String?
    let sender: String
    let outcome: Outcome

    /// e.g. "AO-91 · 2m/70cm FM"
    var summary: String {
        var parts: [String] = []
        if let satName {
            parts.append(satName)
        }
        let bands = bandRx.map { "\(band)/\($0)" } ?? band
        parts.append("\(bands) \(mode)")
        return parts.joined(separator: " · ")
    }
}

// MARK: - SatLogListenerService

@MainActor
@Observable
final class SatLogListenerService {
    // MARK: Lifecycle

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Keys.enabled)
        transport = defaults.string(forKey: Keys.transport)
            .flatMap(SatLogTransport.init(rawValue:)) ?? .udp
        let storedPort = defaults.integer(forKey: Keys.port)
        port = (1 ... Int(UInt16.max)).contains(storedPort) ? UInt16(storedPort) : Self.defaultPort
    }

    // MARK: Internal

    /// The S.A.T. manual documents no fixed port — the user types whatever
    /// their logger listens on. 2333 is the WSJT-X → N1MM "logged ADIF" UDP
    /// port, the closest thing to a convention for bare ADIF over UDP.
    static let defaultPort: UInt16 = 2_333
    static let maxRecentRecords = 25

    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var receivedCount = 0
    private(set) var recentRecords: [SatLogReceivedRecord] = []

    /// Set at launch (`CWSweepApp`); records arriving before then are reported
    /// as failed rather than dropped silently.
    var modelContainer: ModelContainer?

    /// Station callsign fallback when a record has no STATION_CALLSIGN and no
    /// session is active. Overridable for tests.
    var myCallsignProvider: @MainActor () -> String = {
        let keychain = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign)
        return keychain ?? UserDefaults.standard.string(forKey: "myCallsign") ?? ""
    }

    /// Post-insert hook (Rust-store mirror, log table row push). Wired by
    /// `SharedEnvironment`; nil in tests.
    var didLogQSO: (@MainActor (QSO) -> Void)?

    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    var transport: SatLogTransport {
        didSet {
            defaults.set(transport.rawValue, forKey: Keys.transport)
            restartIfRunning()
        }
    }

    var port: UInt16 {
        didSet {
            defaults.set(Int(port), forKey: Keys.port)
            restartIfRunning()
        }
    }

    func startIfEnabled() {
        if isEnabled {
            start()
        }
    }

    /// Bind the listener with the current transport/port. Idempotent.
    func start() {
        guard listener == nil else {
            return
        }
        lastError = nil
        let newListener = SatLogListener(transport: transport, port: port) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        listener = newListener
        Task {
            do {
                try await newListener.start()
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.listener = nil
                    self.isRunning = false
                }
            }
        }
    }

    func stop() {
        guard let current = listener else {
            return
        }
        listener = nil
        isRunning = false
        Task { await current.stop() }
    }

    /// Parse and log raw ADIF record strings. Internal so tests can drive the
    /// pipeline without a socket.
    func handleRawRecords(_ raw: [String], sender: String) {
        let parser = ADIFParser()
        for text in raw {
            receivedCount += 1
            guard let record = (try? parser.parse(text))?.first else {
                logger.warning("S.A.T. record from \(sender, privacy: .public) missing CALL/BAND/MODE — ignored")
                remember(callsign: "?", band: "?", mode: "?", satName: nil, bandRx: nil, sender: sender,
                         outcome: .failed("Missing CALL, BAND or MODE"))
                continue
            }
            ingest(record, sender: sender)
        }
    }

    // MARK: Private

    private enum Keys {
        static let enabled = "satLog.enabled"
        static let transport = "satLog.transport"
        static let port = "satLog.port"
    }

    private let defaults: UserDefaults
    private var listener: SatLogListener?

    private func restartIfRunning() {
        guard listener != nil else {
            return
        }
        stop()
        start()
    }

    private func handle(_ event: SatLogListenerEvent) {
        switch event {
        case let .ready(boundPort):
            isRunning = true
            lastError = nil
            let name = transport.rawValue
            logger.info("S.A.T. listener ready on \(name, privacy: .public) \(boundPort)")
        case let .waiting(message):
            lastError = message
        case let .failed(message):
            isRunning = false
            listener = nil
            lastError = message
        case let .records(raw, sender):
            handleRawRecords(raw, sender: sender)
        }
    }

    private func ingest(_ record: ADIFRecord, sender: String) {
        let bandRx = ADIFParser.extractField("BAND_RX", from: record.rawADIF)
        func note(_ outcome: SatLogReceivedRecord.Outcome) {
            remember(callsign: record.callsign, band: record.band, mode: record.mode,
                     satName: record.satName, bandRx: bandRx, sender: sender, outcome: outcome)
        }

        guard let container = modelContainer else {
            note(.failed("Log store not ready"))
            return
        }
        let ingestor = SatLogIngestor(context: container.mainContext)
        do {
            let outcome = try ingestor.ingest(
                record,
                myCallsign: myCallsignProvider(),
                session: ingestor.activeSession()
            )
            switch outcome {
            case let .logged(qso):
                didLogQSO?(qso)
                NotificationCenter.default.post(
                    name: .didLogQSO, object: nil, userInfo: ["callsign": qso.callsign]
                )
                note(.logged)
            case .duplicate:
                note(.duplicate)
            case .skippedMetadata:
                note(.skipped("Metadata pseudo-mode"))
            }
        } catch {
            logger.error("S.A.T. ingest failed: \(error.localizedDescription, privacy: .public)")
            note(.failed(error.localizedDescription))
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func remember(
        callsign: String, band: String, mode: String, satName: String?, bandRx: String?,
        sender: String, outcome: SatLogReceivedRecord.Outcome
    ) {
        let entry = SatLogReceivedRecord(
            receivedAt: Date(), callsign: callsign, band: band, mode: mode,
            satName: satName, bandRx: bandRx, sender: sender, outcome: outcome
        )
        recentRecords.insert(entry, at: 0)
        if recentRecords.count > Self.maxRecentRecords {
            recentRecords.removeLast(recentRecords.count - Self.maxRecentRecords)
        }
    }
}
