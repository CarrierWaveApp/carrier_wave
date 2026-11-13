import CarrierWaveData
import Foundation
import SwiftData

// MARK: - Session, persistence, rescore, export

/// Split out from `ContestManager.swift` to stay under the 500-line file
/// budget. Contains session resume/create, QSO record building +
/// persistence, Cabrillo export, and the supporting `ContestQSOEntry` /
/// `ContestLoggedQSO` value types.
extension ContestManager {
    /// Resume the most recent in-progress session for this contest, or create a
    /// new one. Returns the existing (non-hidden) QSOs to load into the engine.
    func resumeOrCreateSession(definition: ContestDefinition) -> [QSO] {
        guard let modelContext else {
            session = nil
            return []
        }
        let contestID: String? = definition.id
        var descriptor = FetchDescriptor<LoggingSession>(
            predicate: #Predicate { $0.contestId == contestID },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let existing = (try? modelContext.fetch(descriptor))?.first, canResume(existing) {
            session = existing
            return fetchSessionQSOs(existing)
        }
        makeSession(definition: definition)
        return []
    }

    /// Soft-delete a logged QSO and rescore the session from scratch.
    func deleteQSO(_ qsoID: UUID) async {
        guard let modelContext else {
            return
        }
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.id == qsoID })
        descriptor.fetchLimit = 1
        guard let qso = (try? modelContext.fetch(descriptor))?.first else {
            return
        }
        qso.isHidden = true
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        try? CwStoreSeams.save(modelContext, qsos: [qso])
        await rescoreFromSession()
    }

    /// Generate a Cabrillo 3.0 log from the persisted session QSOs.
    func cabrilloText(clubName: String?, email: String?) -> String? {
        guard let definition, let session, let modelContext else {
            return nil
        }
        let sessionID: UUID? = session.id
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.loggingSessionId == sessionID })
        descriptor.fetchLimit = 100_000
        let qsos = (try? modelContext.fetch(descriptor)) ?? []
        let context = CabrilloExportService.Context(
            categoryID: categoryID,
            overlayCategoryID: overlayCategoryID,
            powerClass: powerClass,
            operators: session.contestOperator.map { [$0] } ?? [],
            clubName: clubName,
            email: email
        )
        return CabrilloExportService().generate(
            session: session,
            qsos: qsos,
            definition: definition,
            score: score,
            context: context
        )
    }

    var cabrilloFilename: String {
        let call = session?.contestOperator ?? myCallsign
        let base = call.isEmpty ? "log" : call.replacingOccurrences(of: "/", with: "-")
        return "\(base)_\(definition?.id ?? "contest").cbr"
    }

    /// Encode the received exchange (serial + named fields) into the single
    /// `contestExchangeReceived` string blob stored on `QSO`. Field order
    /// follows the contest definition so the blob reads naturally.
    func encodedReceivedExchange(entry: ContestQSOEntry) -> String? {
        var parts: [String] = []
        if let serial = entry.serialReceived {
            parts.append(String(serial))
        }
        let receivedOrder = definition?.exchange.received ?? []
        let consumedNames: Set = ["rst", "serial"]
        for field in receivedOrder where !consumedNames.contains(field.name) {
            if let value = entry.receivedFields[field.name], !value.isEmpty {
                parts.append(value)
            }
        }
        for (name, value) in entry.receivedFields
            where !consumedNames.contains(name)
            && !receivedOrder.contains(where: { $0.name == name })
            && !value.isEmpty
        {
            parts.append(value)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: Building records / persistence

    func makeRecord(entry: ContestQSOEntry, serialSent: Int, entity: DXCCEntity?) -> ContestQSORecord {
        let sent = ["rst": entry.rstSent, "serial": String(format: "%03d", serialSent)]
        var received = entry.receivedFields
        received["rst"] = entry.rstReceived
        if let serialReceived = entry.serialReceived {
            received["serial"] = String(serialReceived)
        }
        return ContestQSORecord(
            callsign: entry.callsign,
            band: entry.band,
            mode: entry.mode,
            timestamp: Date(),
            sentExchange: sent,
            receivedExchange: received,
            serialSent: serialSent,
            serialReceived: entry.serialReceived,
            theirCountry: entity?.name,
            theirContinent: entity?.continent,
            theirCQZone: entity?.cqZone,
            theirITUZone: entity?.ituZone
        )
    }

    func persist(entry: ContestQSOEntry, serialSent: Int, country: String?) -> UUID? {
        guard let modelContext, let session, let definition else {
            return nil
        }
        let qso = QSO(
            callsign: entry.callsign,
            band: entry.band,
            mode: entry.mode,
            frequency: entry.frequencyMHz,
            timestamp: Date(),
            rstSent: entry.rstSent,
            rstReceived: entry.rstReceived,
            myCallsign: session.myCallsign,
            importSource: .logger,
            country: country,
            contestName: definition.id,
            contestSerialSent: serialSent,
            contestSerialReceived: entry.serialReceived,
            contestExchangeSent: String(serialSent),
            contestExchangeReceived: encodedReceivedExchange(entry: entry)
        )
        qso.loggingSessionId = session.id
        qso.cloudDirtyFlag = true
        qso.modifiedAt = Date()
        modelContext.insert(qso)
        session.incrementQSOCount()
        try? CwStoreSeams.save(modelContext, qsos: [qso], sessions: [session])
        return qso.id
    }

    func recordFromQSO(_ qso: QSO) -> ContestQSORecord {
        let entity = dxcc?.lookup(qso.callsign)
        var received: [String: String] = [:]
        if let rst = qso.rstReceived {
            received["rst"] = rst
        }
        if let exchange = qso.contestExchangeReceived, !exchange.isEmpty {
            received["serial"] = exchange
        }
        return ContestQSORecord(
            callsign: qso.callsign,
            band: qso.band,
            mode: qso.mode,
            timestamp: qso.timestamp,
            receivedExchange: received,
            serialSent: qso.contestSerialSent,
            serialReceived: qso.contestSerialReceived,
            theirCountry: entity?.name,
            theirContinent: entity?.continent,
            theirCQZone: entity?.cqZone,
            theirITUZone: entity?.ituZone
        )
    }

    func rescoreFromSession() async {
        guard let engine, let session else {
            return
        }
        let qsos = fetchSessionQSOs(session)
        await engine.rescore(qsos.map { recordFromQSO($0) })
        applyExisting(qsos)
        await refreshScore()
        currentSerial = await engine.currentSerial()
        recomputeConstraints()
    }

    func recomputeConstraints() {
        guard let definition else {
            return
        }
        offTimeSummary = OffTimeTracker.summarize(
            qsoTimestamps: qsoTimestamps,
            sessionStart: sessionStart,
            categoryID: categoryID,
            rules: definition.operatingConstraints?.offTime
        )
        bandChangeSummary = BandChangeTracker.summarize(
            qsos: bandTimeline,
            categoryID: categoryID,
            rules: definition.operatingConstraints?.bandChanges
        )
    }

    // MARK: Private helpers

    func makeSession(definition: ContestDefinition) {
        guard let modelContext else {
            session = nil
            return
        }
        let bands = definition.bands.count == 1 ? definition.bands.first : "ALL"
        let newSession = LoggingSession(
            myCallsign: myCallsign,
            startedAt: sessionStart,
            mode: definition.modes.first ?? "CW",
            contestId: definition.id,
            contestCategory: categoryID,
            contestOverlayCategory: overlayCategoryID,
            contestPower: powerClass,
            contestBands: bands,
            contestOperator: myCallsign.isEmpty ? nil : myCallsign
        )
        modelContext.insert(newSession)
        try? CwStoreSeams.save(modelContext, sessions: [newSession])
        session = newSession
    }

    func canResume(_ candidate: LoggingSession) -> Bool {
        guard candidate.endedAt == nil else {
            return false
        }
        if let occurrence = activeOccurrence {
            return candidate.startedAt >= occurrence.start && candidate.startedAt <= occurrence.end
        }
        return Date().timeIntervalSince(candidate.startedAt) < 48 * 3_600
    }

    func fetchSessionQSOs(_ loggingSession: LoggingSession) -> [QSO] {
        guard let modelContext else {
            return []
        }
        let sessionID: UUID? = loggingSession.id
        var descriptor = FetchDescriptor<QSO>(predicate: #Predicate { $0.loggingSessionId == sessionID })
        descriptor.fetchLimit = 100_000
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all
            .filter { !$0.isHidden && $0.contestName != nil }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func applyExisting(_ qsos: [QSO]) {
        let sorted = qsos.sorted { $0.timestamp < $1.timestamp }
        qsoTimestamps = sorted.map(\.timestamp)
        bandTimeline = sorted.map { (band: $0.band, timestamp: $0.timestamp) }
        recentQSOs = sorted.reversed().prefix(50).map { qso in
            ContestLoggedQSO(
                callsign: qso.callsign,
                band: qso.band,
                prefix: ContestCallsign.wpxPrefix(qso.callsign),
                serialSent: qso.contestSerialSent,
                status: .newStation,
                timestamp: qso.timestamp,
                qsoID: qso.id
            )
        }
    }
}

// MARK: - ContestQSOEntry

/// Operator-entered exchange for a single contest QSO, before scoring.
struct ContestQSOEntry {
    var callsign: String
    var band: String
    var mode: String
    var rstSent: String
    var rstReceived: String
    var serialReceived: Int?
    var frequencyMHz: Double?
    /// Parsed received-exchange fields keyed by `ContestExchangeField.name`
    /// (e.g. `"cq_zone": "5"`, `"section": "WMA"`). Flows into the engine's
    /// `receivedExchange` map for multiplier/condition evaluation and is
    /// joined into the QSO's `contestExchangeReceived` blob for Cabrillo.
    var receivedFields: [String: String] = [:]
}

// MARK: - ContestLoggedQSO

/// Display row for the operating view's recent-QSO list.
struct ContestLoggedQSO: Identifiable {
    // MARK: Lifecycle

    init(
        callsign: String,
        band: String,
        prefix: String,
        serialSent: Int?,
        status: ContestDupeStatus,
        timestamp: Date,
        qsoID: UUID?
    ) {
        self.callsign = callsign
        self.band = band
        self.prefix = prefix
        self.serialSent = serialSent
        self.status = status
        self.timestamp = timestamp
        self.qsoID = qsoID
    }

    init(record: ContestQSORecord, status: ContestDupeStatus, prefix: String, qsoID: UUID?) {
        self.init(
            callsign: record.callsign,
            band: record.band,
            prefix: prefix,
            serialSent: record.serialSent,
            status: status,
            timestamp: record.timestamp,
            qsoID: qsoID
        )
    }

    // MARK: Internal

    let id = UUID()
    let callsign: String
    let band: String
    let prefix: String
    let serialSent: Int?
    let status: ContestDupeStatus
    let timestamp: Date
    let qsoID: UUID?
}
